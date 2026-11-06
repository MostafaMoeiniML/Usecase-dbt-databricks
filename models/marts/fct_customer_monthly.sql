-- Paid MRR per customer x month-end, with customer-level movements and KPI flags.
with paid_product_months as (

    select * from {{ ref('fct_mrr_monthly') }}
    where mrr_eur > 0

),

products as (

    select product_id, product_category from {{ ref('dim_product') }}

),

customers as (

    select customer_id, join_date, first_paid_month from {{ ref('dim_customer') }}

),

paid_months as (

    select
        paid_product_months.customer_id,
        paid_product_months.month_end_date,
        cast(sum(paid_product_months.mrr_eur) as decimal(24, 10)) as mrr_eur,
        count(distinct products.product_category)                 as paid_category_count
    from paid_product_months
    inner join products
        on paid_product_months.product_id = products.product_id
    group by paid_product_months.customer_id, paid_product_months.month_end_date

),

-- The month after a paid month without paid MRR gets an explicit 0 row, so churned MRR shows up as a movement.
churn_months as (

    select
        current_month.customer_id,
        last_day(add_months(current_month.month_end_date, 1)) as month_end_date,
        cast(0 as decimal(24, 10))                            as mrr_eur,
        0                                                     as paid_category_count
    from paid_months as current_month
    left anti join paid_months as next_month
        on current_month.customer_id = next_month.customer_id
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
        coalesce(previous_month.mrr_eur, 0) as opening_mrr_eur,
        customers.first_paid_month,
        customers.join_date
    from all_months
    left join paid_months as previous_month
        on all_months.customer_id = previous_month.customer_id
       and previous_month.month_end_date = last_day(add_months(all_months.month_end_date, -1))
    left join customers
        on all_months.customer_id = customers.customer_id

),

classified as (

    select
        *,
        case
            when opening_mrr_eur = 0 and month_end_date = first_paid_month then 'new'
            when opening_mrr_eur = 0                                         then 'reactivation'
            when mrr_eur = 0                                                 then 'churn'
            when mrr_eur > opening_mrr_eur                                   then 'expansion'
            when mrr_eur < opening_mrr_eur                                   then 'contraction'
            else 'unchanged'
        end as movement_type
    from with_context

)

select
    classified.customer_id,
    classified.month_end_date,
    classified.mrr_eur,
    classified.opening_mrr_eur,
    classified.movement_type,
    case when movement_type = 'new'          then mrr_eur - opening_mrr_eur else 0 end as new_mrr_eur,
    case when movement_type = 'expansion'    then mrr_eur - opening_mrr_eur else 0 end as expansion_mrr_eur,
    case when movement_type = 'reactivation' then mrr_eur - opening_mrr_eur else 0 end as reactivation_mrr_eur,
    case when movement_type = 'contraction'  then opening_mrr_eur - mrr_eur else 0 end as contraction_mrr_eur,
    case when movement_type = 'churn'        then opening_mrr_eur - mrr_eur else 0 end as churn_mrr_eur,

    mrr_eur > 0                      as is_active,
    -- 'new' only means first paid month in the extract; a new logo also joined within 12 months of that month.
    coalesce(
        movement_type = 'new' and months_between(first_paid_month, join_date) <= 12,
        false
    )                                as is_new_logo,
    -- Churned: paid MRR at the previous month-end, none at this one (same rule as churn in the MRR bridge).
    movement_type = 'churn'          as is_churned,

    paid_category_count,
    paid_category_count > 1          as is_cross_sold
from classified
