-- Paid MRR per client x month-end, with customer-level movements and KPI flags.
with paid_product_months as (

    select * from {{ ref('fct_mrr_monthly') }}
    where mrr_eur > 0

),

products as (

    select product_id, product_cat_desc from {{ ref('dim_product') }}

),

customers as (

    select client_id, join_date, cohort_month from {{ ref('dim_customer') }}

),

paid_months as (

    select
        paid_product_months.client_id,
        paid_product_months.month_end_date,
        cast(sum(paid_product_months.mrr_eur) as decimal(24, 10)) as mrr_eur,
        count(distinct paid_product_months.product_id)            as paid_product_count,
        count(distinct products.product_cat_desc)                 as paid_category_count
    from paid_product_months
    inner join products
        on paid_product_months.product_id = products.product_id
    group by paid_product_months.client_id, paid_product_months.month_end_date

),

-- Placeholder (0.01) lines are free bundled products: tracked for adoption, not for MRR or cross-sell.
free_bundled_months as (

    select distinct client_id, month_end_date
    from {{ ref('int_mrr_order_months') }}
    where not is_paid_line

),

-- The month after a paid month without paid MRR gets an explicit 0 row, so churned MRR shows up as a movement.
churn_months as (

    select
        current_month.client_id,
        last_day(add_months(current_month.month_end_date, 1)) as month_end_date,
        cast(0 as decimal(24, 10))                            as mrr_eur,
        0                                                     as paid_product_count,
        0                                                     as paid_category_count
    from paid_months as current_month
    left anti join paid_months as next_month
        on current_month.client_id = next_month.client_id
       and next_month.month_end_date = last_day(add_months(current_month.month_end_date, 1))

),

all_months as (

    select * from paid_months
    union all
    select * from churn_months

),

with_context as (

    select
        all_months.*,
        coalesce(previous_month.mrr_eur, 0) as previous_mrr_eur,
        customers.cohort_month,
        customers.join_date,
        max(case when all_months.mrr_eur > 0 then all_months.month_end_date end) over (
            partition by all_months.client_id order by all_months.month_end_date
            rows between unbounded preceding and 1 preceding
        ) as last_paid_month_before,
        min(case when all_months.mrr_eur > 0 then all_months.month_end_date end) over (
            partition by all_months.client_id order by all_months.month_end_date
            rows between 1 following and unbounded following
        ) as next_paid_month_after
    from all_months
    left join paid_months as previous_month
        on all_months.client_id = previous_month.client_id
       and previous_month.month_end_date = last_day(add_months(all_months.month_end_date, -1))
    left join customers
        on all_months.client_id = customers.client_id

),

classified as (

    select
        *,
        case
            when previous_mrr_eur = 0 and month_end_date = cohort_month then 'new'
            when previous_mrr_eur = 0                                     then 'reactivation'
            when mrr_eur = 0                                              then 'churn'
            when mrr_eur > previous_mrr_eur                               then 'expansion'
            when mrr_eur < previous_mrr_eur                               then 'contraction'
            else 'unchanged'
        end as movement_type
    from with_context

),

-- Length of the inactive spell around a churn or reactivation, in month-ends without paid MRR.
-- On a churn row it counts until the customer returns (NULL if never); on a reactivation row since the last paid month.
with_inactive_months as (

    select
        *,
        case
            when movement_type = 'churn'
                then cast(round(months_between(next_paid_month_after, month_end_date)) as int)
            when movement_type = 'reactivation'
                then cast(round(months_between(month_end_date, last_paid_month_before)) as int) - 1
        end as inactive_months
    from classified

)

select
    with_inactive_months.client_id,
    with_inactive_months.month_end_date,
    with_inactive_months.mrr_eur,
    with_inactive_months.previous_mrr_eur,
    with_inactive_months.mrr_eur - with_inactive_months.previous_mrr_eur as mrr_change_eur,
    with_inactive_months.movement_type,
    case when movement_type = 'new'          then mrr_eur - previous_mrr_eur else 0 end as new_mrr_eur,
    case when movement_type = 'expansion'    then mrr_eur - previous_mrr_eur else 0 end as expansion_mrr_eur,
    case when movement_type = 'reactivation' then mrr_eur - previous_mrr_eur else 0 end as reactivation_mrr_eur,
    case when movement_type = 'contraction'  then previous_mrr_eur - mrr_eur else 0 end as contraction_mrr_eur,
    case when movement_type = 'churn'        then previous_mrr_eur - mrr_eur else 0 end as churn_mrr_eur,

    mrr_eur > 0                      as is_active,
    movement_type = 'new'            as is_new,
    -- 'new' only means first paid month in the extract; a new logo also joined within 12 months of that month.
    coalesce(
        movement_type = 'new' and months_between(cohort_month, join_date) <= 12,
        false
    )                                as is_new_logo,
    movement_type = 'churn'          as is_churned,
    movement_type = 'reactivation'   as is_reactivated,
    -- Churn KPI with a 1-month grace period: a customer who is back at the next month-end has not churned.
    coalesce(movement_type = 'churn' and (inactive_months is null or inactive_months > 1), false)
                                     as is_churned_after_grace,
    coalesce(movement_type = 'reactivation' and inactive_months > 1, false)
                                     as is_reactivated_after_grace,
    inactive_months,
    -- Upper bound: returns after ~12 or ~24 inactive months match one or two renewal periods missing from the extract.
    coalesce(
        movement_type in ('churn', 'reactivation')
        and (inactive_months between 11 and 13 or inactive_months between 23 and 25),
        false
    )                                as is_probable_data_gap,

    paid_product_count,
    paid_category_count,
    paid_category_count > 1          as is_cross_sold,
    free_bundled_months.client_id is not null as has_free_bundled_product,

    cohort_month,
    cast(round(months_between(with_inactive_months.month_end_date, cohort_month)) as int) as months_since_cohort
from with_inactive_months
left join free_bundled_months
    on with_inactive_months.client_id = free_bundled_months.client_id
   and with_inactive_months.month_end_date = free_bundled_months.month_end_date
