-- Category performance: one row per product category per reporting month.
-- Movements are at client x product grain, so a product swap within a category shows as churn plus new.
with product_months as (

    select
        mrr.*,
        products.product_cat_desc
    from {{ ref('fct_mrr_monthly') }} as mrr
    inner join {{ ref('dim_product') }} as products
        on mrr.product_id = products.product_id

),

dates as (

    select month_end_date, is_reporting_month from {{ ref('dim_date') }}

),

categories as (

    select distinct product_cat_desc from {{ ref('dim_product') }}

),

monthly as (

    select
        product_cat_desc,
        month_end_date,
        sum(previous_mrr_eur)                                     as opening_mrr_eur,
        sum(new_mrr_eur)                                          as new_mrr_eur,
        sum(expansion_mrr_eur)                                    as expansion_mrr_eur,
        sum(reactivation_mrr_eur)                                 as reactivation_mrr_eur,
        sum(contraction_mrr_eur)                                  as contraction_mrr_eur,
        sum(churn_mrr_eur)                                        as churn_mrr_eur,
        sum(mrr_eur)                                              as mrr_eur,
        count(distinct case when mrr_eur > 0 then client_id end)  as active_customers
    from product_months
    group by product_cat_desc, month_end_date

),

-- Full category x month spine, so the 12-month lag always points to the same calendar month.
spine as (

    select
        categories.product_cat_desc,
        dates.month_end_date,
        dates.is_reporting_month,
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
        on categories.product_cat_desc = monthly.product_cat_desc
       and dates.month_end_date = monthly.month_end_date

),

with_history as (

    select
        *,
        lag(mrr_eur, 12) over (partition by product_cat_desc order by month_end_date) as mrr_12m_ago_eur,
        sum(mrr_eur) over (partition by month_end_date)                               as total_mrr_eur
    from spine

)

select
    month_end_date,
    product_cat_desc,
    opening_mrr_eur,
    new_mrr_eur,
    expansion_mrr_eur,
    reactivation_mrr_eur,
    contraction_mrr_eur,
    churn_mrr_eur,
    mrr_eur,
    new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur
        - contraction_mrr_eur - churn_mrr_eur                                          as net_new_mrr_eur,
    active_customers,
    cast(mrr_eur / nullif(active_customers, 0) as decimal(18, 4))                     as arpu_eur,
    cast(100 * mrr_eur / nullif(total_mrr_eur, 0) as double)                          as share_of_mrr_pct,
    cast(100 * churn_mrr_eur / nullif(opening_mrr_eur, 0) as double)                  as gross_mrr_churn_rate_pct,
    -- Year-over-year growth needs a complete base month (the month before the reporting window or later).
    case
        when last_day(add_months(month_end_date, -12))
             >= last_day(add_months(date'{{ var("reporting_start_month") }}', -1))
            then cast(100 * (mrr_eur / nullif(mrr_12m_ago_eur, 0) - 1) as double)
    end                                                                                as mrr_growth_yoy_pct
from with_history
where is_reporting_month
