-- Category performance: one row per product category per reporting month.
-- Movements are computed per customer x category x month, so a customer who swaps one product for another
-- in the same category stays in that category instead of showing as churn plus new.
with product_months as (

    select
        mrr.customer_id,
        mrr.month_end_date,
        mrr.mrr_eur,
        products.product_category
    from {{ ref('fct_mrr_monthly') }} as mrr
    inner join {{ ref('dim_product') }} as products
        on mrr.product_id = products.product_id
    where mrr.mrr_eur > 0

),

-- Paid MRR per customer x category x month: all products of the customer in that category summed.
paid_category_months as (

    select
        customer_id,
        product_category,
        month_end_date,
        cast(sum(mrr_eur) as decimal(24, 10)) as mrr_eur
    from product_months
    group by customer_id, product_category, month_end_date

),

-- The month after a paid month without paid MRR in the category gets an explicit 0 row, so churned MRR shows up.
churn_category_months as (

    select
        current_month.customer_id,
        current_month.product_category,
        last_day(add_months(current_month.month_end_date, 1)) as month_end_date,
        cast(0 as decimal(24, 10))                            as mrr_eur
    from paid_category_months as current_month
    left anti join paid_category_months as next_month
        on current_month.customer_id = next_month.customer_id
       and current_month.product_category = next_month.product_category
       and next_month.month_end_date = last_day(add_months(current_month.month_end_date, 1))

),

all_category_months as (

    select * from paid_category_months
    union all
    select * from churn_category_months

),

with_opening as (

    select
        all_category_months.*,
        coalesce(previous_month.mrr_eur, 0) as opening_mrr_eur,
        -- The earliest row is always a paid month, because churn rows only follow a paid month.
        min(all_category_months.month_end_date) over (
            partition by all_category_months.customer_id, all_category_months.product_category
        ) as first_paid_month
    from all_category_months
    left join paid_category_months as previous_month
        on all_category_months.customer_id = previous_month.customer_id
       and all_category_months.product_category = previous_month.product_category
       and previous_month.month_end_date = last_day(add_months(all_category_months.month_end_date, -1))

),

-- Same movement rules as the customer-level model, applied within one category.
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
    from with_opening

),

customer_category_movements as (

    select
        customer_id,
        product_category,
        month_end_date,
        mrr_eur,
        opening_mrr_eur,
        movement_type,
        case when movement_type = 'new'          then mrr_eur - opening_mrr_eur else 0 end as new_mrr_eur,
        case when movement_type = 'expansion'    then mrr_eur - opening_mrr_eur else 0 end as expansion_mrr_eur,
        case when movement_type = 'reactivation' then mrr_eur - opening_mrr_eur else 0 end as reactivation_mrr_eur,
        case when movement_type = 'contraction'  then opening_mrr_eur - mrr_eur else 0 end as contraction_mrr_eur,
        case when movement_type = 'churn'        then opening_mrr_eur - mrr_eur else 0 end as churn_mrr_eur
    from classified

),

monthly as (

    select
        product_category,
        month_end_date,
        sum(opening_mrr_eur)       as opening_mrr_eur,
        sum(new_mrr_eur)           as new_mrr_eur,
        sum(expansion_mrr_eur)     as expansion_mrr_eur,
        sum(reactivation_mrr_eur)  as reactivation_mrr_eur,
        sum(contraction_mrr_eur)   as contraction_mrr_eur,
        sum(churn_mrr_eur)         as churn_mrr_eur,
        sum(mrr_eur)               as mrr_eur,
        count_if(mrr_eur > 0)      as active_customers
    from customer_category_movements
    group by product_category, month_end_date

),

dates as (

    select month_end_date from {{ ref('dim_date') }}
    where is_reporting_month

),

categories as (

    select distinct product_category from {{ ref('dim_product') }}

),

-- Full category x month spine, so every category has a row in every reporting month.
category_months as (

    select
        dates.month_end_date,
        categories.product_category,
        coalesce(monthly.opening_mrr_eur, 0)       as opening_mrr_eur,
        coalesce(monthly.new_mrr_eur, 0)           as new_mrr_eur,
        coalesce(monthly.expansion_mrr_eur, 0)     as expansion_mrr_eur,
        coalesce(monthly.reactivation_mrr_eur, 0)  as reactivation_mrr_eur,
        coalesce(monthly.contraction_mrr_eur, 0)   as contraction_mrr_eur,
        coalesce(monthly.churn_mrr_eur, 0)         as churn_mrr_eur,
        coalesce(monthly.mrr_eur, 0)               as mrr_eur,
        coalesce(monthly.active_customers, 0)      as active_customers
    from categories
    cross join dates
    left join monthly
        on categories.product_category = monthly.product_category
       and dates.month_end_date = monthly.month_end_date

)

select
    month_end_date,
    product_category,
    mrr_eur,
    active_customers,
    -- Revenue churn, as in rpt_kpi_monthly: category MRR lost to churn and contraction / opening category MRR.
    cast(100 * (churn_mrr_eur + contraction_mrr_eur) / nullif(opening_mrr_eur, 0) as double) as revenue_churn_rate_pct
from category_months
