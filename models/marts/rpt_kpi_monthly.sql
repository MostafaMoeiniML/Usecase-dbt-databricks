-- KPI framework: one row per reporting month with the 10 KPIs and 3 supplementary diagnostics.
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
        sum(previous_mrr_eur)                                             as opening_mrr_eur,
        sum(new_mrr_eur)                                                  as new_mrr_eur,
        sum(expansion_mrr_eur)                                            as expansion_mrr_eur,
        sum(reactivation_mrr_eur)                                         as reactivation_mrr_eur,
        sum(contraction_mrr_eur)                                          as contraction_mrr_eur,
        sum(churn_mrr_eur)                                                as churn_mrr_eur,
        sum(mrr_eur)                                                      as mrr_eur,
        count_if(previous_mrr_eur > 0)                                    as opening_customers,
        count_if(is_active)                                               as active_customers,
        count_if(is_churned_after_grace)                                  as churned_customers,
        count_if(is_churned_after_grace and not is_probable_data_gap)     as churned_customers_excl_data_gap,
        count_if(is_churned_after_grace and not is_contradicted_by_subscription) as churned_customers_excl_contradicted,
        count_if(is_new_logo)                                             as new_logos,
        count_if(is_cross_sold)                                           as cross_sold_customers
    from customer_months
    group by month_end_date

),

paid_customer_months as (

    select client_id, month_end_date, mrr_eur
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
        on base.client_id = current_month.client_id
       and current_month.month_end_date = last_day(add_months(base.month_end_date, 12))
    group by 1

),

-- Lines longer than 12 months run off before the end of the window; tracked to explain the 2022 slowdown.
multi_year_lines as (

    select month_end_date, sum(mrr_eur) as mrr_lines_over_12m_eur
    from {{ ref('int_mrr_order_months') }}
    where is_paid_line and duration_months > 12
    group by month_end_date

),

all_months as (

    select
        dates.month_end_date,
        dates.is_reporting_month,
        coalesce(monthly.opening_mrr_eur, 0)                  as opening_mrr_eur,
        coalesce(monthly.new_mrr_eur, 0)                      as new_mrr_eur,
        coalesce(monthly.expansion_mrr_eur, 0)                as expansion_mrr_eur,
        coalesce(monthly.reactivation_mrr_eur, 0)             as reactivation_mrr_eur,
        coalesce(monthly.contraction_mrr_eur, 0)              as contraction_mrr_eur,
        coalesce(monthly.churn_mrr_eur, 0)                    as churn_mrr_eur,
        coalesce(monthly.mrr_eur, 0)                          as mrr_eur,
        coalesce(monthly.opening_customers, 0)                as opening_customers,
        coalesce(monthly.active_customers, 0)                 as active_customers,
        coalesce(monthly.churned_customers, 0)                as churned_customers,
        coalesce(monthly.churned_customers_excl_data_gap, 0)  as churned_customers_excl_data_gap,
        coalesce(monthly.churned_customers_excl_contradicted, 0) as churned_customers_excl_contradicted,
        coalesce(monthly.new_logos, 0)                        as new_logos,
        coalesce(monthly.cross_sold_customers, 0)             as cross_sold_customers,
        retention.base_mrr_12m_ago_eur,
        retention.base_current_mrr_eur,
        retention.base_retained_mrr_eur,
        coalesce(multi_year_lines.mrr_lines_over_12m_eur, 0)  as mrr_lines_over_12m_eur,
        lag(coalesce(monthly.mrr_eur, 0), 1)  over (order by dates.month_end_date) as mrr_1m_ago_eur,
        lag(coalesce(monthly.mrr_eur, 0), 12) over (order by dates.month_end_date) as mrr_12m_ago_eur
    from dates
    left join monthly
        on dates.month_end_date = monthly.month_end_date
    left join retention
        on dates.month_end_date = retention.month_end_date
    left join multi_year_lines
        on dates.month_end_date = multi_year_lines.month_end_date

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

    -- MRR bridge components
    opening_mrr_eur,
    new_mrr_eur,
    expansion_mrr_eur,
    reactivation_mrr_eur,
    contraction_mrr_eur,
    churn_mrr_eur,

    -- KPI 1: MRR (closing)
    mrr_eur,
    -- KPI 2: MRR growth
    cast(100 * (mrr_eur / nullif(mrr_1m_ago_eur, 0) - 1) as double)                       as mrr_growth_mom_pct,
    case when has_complete_12m_base
        then cast(100 * (mrr_eur / nullif(mrr_12m_ago_eur, 0) - 1) as double) end          as mrr_growth_yoy_pct,
    -- KPI 3: Net new MRR
    new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur
        - contraction_mrr_eur - churn_mrr_eur                                               as net_new_mrr_eur,
    -- KPI 4 and 5: trailing 12-month revenue retention
    case when has_complete_12m_base
        then cast(100 * base_current_mrr_eur / nullif(base_mrr_12m_ago_eur, 0) as double) end  as nrr_pct,
    case when has_complete_12m_base
        then cast(100 * base_retained_mrr_eur / nullif(base_mrr_12m_ago_eur, 0) as double) end as grr_pct,
    -- KPI 6: Customer churn rate (1-month grace)
    cast(100 * churned_customers / nullif(opening_customers, 0) as double)                 as customer_churn_rate_pct,
    -- KPI 7: Active paying customers
    active_customers,
    -- KPI 8: New logos
    new_logos,
    -- KPI 9: ARPU
    cast(mrr_eur / nullif(active_customers, 0) as decimal(18, 4))                          as arpu_eur,
    -- KPI 10: Cross-sell rate (paid categories only)
    cast(100 * cross_sold_customers / nullif(active_customers, 0) as double)               as cross_sell_rate_pct,

    -- Supplementary diagnostics
    cast((new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur)
         / nullif(contraction_mrr_eur + churn_mrr_eur, 0) as double)                        as quick_ratio,
    cast(100 * churned_customers_excl_data_gap / nullif(opening_customers, 0) as double)   as customer_churn_rate_excl_data_gap_pct,
    -- Churn excluding events contradicted by a still-running paid subscription: a lower-bound estimate.
    cast(100 * churned_customers_excl_contradicted / nullif(opening_customers, 0) as double) as churn_rate_excl_contradicted_pct,
    mrr_lines_over_12m_eur,

    -- Counts behind the rates
    opening_customers,
    churned_customers,
    churned_customers_excl_data_gap,
    churned_customers_excl_contradicted,
    cross_sold_customers,
    base_mrr_12m_ago_eur
from kpis
where is_reporting_month
