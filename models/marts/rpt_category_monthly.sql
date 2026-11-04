-- Category performance: one row per product category per reporting month.
-- Movements are at customer x product grain, so a product swap within a category shows as churn plus new.
with product_months as (

    select
        mrr.*,
        products.product_category
    from {{ ref('fct_mrr_monthly') }} as mrr
    inner join {{ ref('dim_product') }} as products
        on mrr.product_id = products.product_id

),

dates as (

    select month_end_date from {{ ref('dim_date') }}
    where is_reporting_month

),

categories as (

    select distinct product_category from {{ ref('dim_product') }}

),

monthly as (

    select
        product_category,
        month_end_date,
        sum(opening_mrr_eur)                                        as opening_mrr_eur,
        sum(churn_mrr_eur)                                          as churn_mrr_eur,
        sum(mrr_eur)                                                as mrr_eur,
        count(distinct case when mrr_eur > 0 then customer_id end)  as active_customers
    from product_months
    group by product_category, month_end_date

)

-- Full category x month spine, so every category has a row in every reporting month.
select
    dates.month_end_date,
    categories.product_category,
    coalesce(monthly.mrr_eur, 0)                                                     as mrr_eur,
    coalesce(monthly.active_customers, 0)                                            as active_customers,
    -- Share of last month's category MRR lost to customers who stopped paying for a product.
    cast(100 * monthly.churn_mrr_eur / nullif(monthly.opening_mrr_eur, 0) as double) as gross_mrr_churn_rate_pct
from categories
cross join dates
left join monthly
    on categories.product_category = monthly.product_category
   and dates.month_end_date = monthly.month_end_date
