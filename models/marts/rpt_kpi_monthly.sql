-- KPI framework: one row per reporting month with the 10 KPIs and the MRR bridge.
-- KPIs are computed over all months first, so year-over-year and 12-month retention have their base,
-- and only then filtered to the reporting window.
{%- set first_complete_base_month = "last_day(add_months(date'" ~ var('reporting_start_month') ~ "', -1))" %}

with customer_months as (

    select * from {{ ref('fct_customer_monthly') }}

),

dates as (

    select month_end_date, is_reporting_month from {{ ref('dim_date') }}

),

monthly as (

    select
        month_end_date,
        sum(opening_mrr_eur)                                               as opening_mrr_eur,
        sum(new_mrr_eur)                                                   as new_mrr_eur,
        sum(expansion_mrr_eur)                                             as expansion_mrr_eur,
        sum(reactivation_mrr_eur)                                          as reactivation_mrr_eur,
        sum(contraction_mrr_eur)                                           as contraction_mrr_eur,
        sum(churn_mrr_eur)                                                 as churn_mrr_eur,
        sum(mrr_eur)                                                       as mrr_eur,
        count_if(opening_mrr_eur > 0)                                      as opening_customers,
        count_if(is_active)                                                as active_customers,
        count_if(is_churned)                                               as churned_customers,
        count_if(is_new_logo)                                              as new_logos,
        count_if(is_cross_sold)                                            as cross_sold_customers,
        avg(case when is_active then paid_category_count end)              as avg_categories_per_customer
    from customer_months
    group by month_end_date

),

paid_customer_months as (

    select customer_id, month_end_date, mrr_eur
    from customer_months
    where mrr_eur > 0

),

-- 12-month retention base: customers paying 12 months ago and what they pay today.
-- GRR caps each customer at their old MRR, so expansion cannot hide churn.
retention as (

    select
        last_day(add_months(base.month_end_date, 12))                    as month_end_date,
        sum(base.mrr_eur)                                                 as base_mrr_12m_ago_eur,
        sum(coalesce(current_month.mrr_eur, 0))                           as base_current_mrr_eur,
        sum(least(coalesce(current_month.mrr_eur, 0), base.mrr_eur))      as base_retained_mrr_eur
    from paid_customer_months as base
    left join paid_customer_months as current_month
        on base.customer_id = current_month.customer_id
       and current_month.month_end_date = last_day(add_months(base.month_end_date, 12))
    group by 1

),

all_months as (

    select
        dates.month_end_date,
        dates.is_reporting_month,
        coalesce(monthly.opening_mrr_eur, 0)                     as opening_mrr_eur,
        coalesce(monthly.new_mrr_eur, 0)                         as new_mrr_eur,
        coalesce(monthly.expansion_mrr_eur, 0)                   as expansion_mrr_eur,
        coalesce(monthly.reactivation_mrr_eur, 0)                as reactivation_mrr_eur,
        coalesce(monthly.contraction_mrr_eur, 0)                 as contraction_mrr_eur,
        coalesce(monthly.churn_mrr_eur, 0)                       as churn_mrr_eur,
        coalesce(monthly.mrr_eur, 0)                             as mrr_eur,
        coalesce(monthly.opening_customers, 0)                   as opening_customers,
        coalesce(monthly.active_customers, 0)                    as active_customers,
        coalesce(monthly.churned_customers, 0)                   as churned_customers,
        coalesce(monthly.new_logos, 0)                           as new_logos,
        coalesce(monthly.cross_sold_customers, 0)                as cross_sold_customers,
        monthly.avg_categories_per_customer,
        retention.base_mrr_12m_ago_eur,
        retention.base_current_mrr_eur,
        retention.base_retained_mrr_eur,
        lag(coalesce(monthly.mrr_eur, 0), 12) over (order by dates.month_end_date) as mrr_12m_ago_eur
    from dates
    left join monthly
        on dates.month_end_date = monthly.month_end_date
    left join retention
        on dates.month_end_date = retention.month_end_date

),

kpis as (

    select
        *,
        -- Comparisons 12 months back need a complete base month (the month before the reporting window or later).
        last_day(add_months(month_end_date, -12)) >= {{ first_complete_base_month }} as has_complete_12m_base
    from all_months

)

select
    month_end_date,

    -- MRR bridge: opening + new + expansion + reactivation - contraction - churn = MRR
    opening_mrr_eur,
    new_mrr_eur,
    expansion_mrr_eur,
    reactivation_mrr_eur,
    contraction_mrr_eur,
    churn_mrr_eur,

    -- KPI 1: MRR (closing)
    mrr_eur,
    -- KPI 2: MRR growth year over year
    case when has_complete_12m_base
        then cast(100 * (mrr_eur / nullif(mrr_12m_ago_eur, 0) - 1) as double) end              as mrr_growth_yoy_pct,
    -- KPI 3: Net new MRR
    new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur
        - contraction_mrr_eur - churn_mrr_eur                                                   as net_new_mrr_eur,
    -- KPI 4 and 5: trailing 12-month revenue retention
    case when has_complete_12m_base
        then cast(100 * base_current_mrr_eur / nullif(base_mrr_12m_ago_eur, 0) as double) end  as net_revenue_retention_pct,
    case when has_complete_12m_base
        then cast(100 * base_retained_mrr_eur / nullif(base_mrr_12m_ago_eur, 0) as double) end as gross_revenue_retention_pct,
    -- KPI 6: Customer churn rate (same churn rule as the MRR bridge)
    cast(100 * churned_customers / nullif(opening_customers, 0) as double)                     as customer_churn_rate_pct,
    -- Revenue churn: MRR lost to churn and contraction as a share of opening MRR.
    cast(100 * (churn_mrr_eur + contraction_mrr_eur) / nullif(opening_mrr_eur, 0) as double)   as revenue_churn_rate_pct,
    -- KPI 7: Active paying customers
    active_customers,
    -- KPI 8: New logos
    new_logos,
    -- KPI 9: ARPU
    cast(mrr_eur / nullif(active_customers, 0) as decimal(18, 4))                              as arpu_eur,
    -- KPI 10: Cross-sell rate (paid categories only)
    cast(100 * cross_sold_customers / nullif(active_customers, 0) as double)                   as cross_sell_rate_pct,
    -- Depth of cross-sell: paid product categories per active customer.
    cast(avg_categories_per_customer as double)                                                as avg_categories_per_customer
from kpis
where is_reporting_month
