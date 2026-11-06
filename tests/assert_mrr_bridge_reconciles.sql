-- For every month at customer level: opening + new + expansion + reactivation - contraction - churn = closing,
-- opening equals the previous month's closing, and closing equals paid MRR in int_mrr_order_months.
with bridge as (

    select
        month_end_date,
        sum(opening_mrr_eur)        as opening_mrr_eur,
        sum(new_mrr_eur)            as new_mrr_eur,
        sum(expansion_mrr_eur)      as expansion_mrr_eur,
        sum(reactivation_mrr_eur)   as reactivation_mrr_eur,
        sum(contraction_mrr_eur)    as contraction_mrr_eur,
        sum(churn_mrr_eur)          as churn_mrr_eur,
        sum(mrr_eur)                as closing_mrr_eur
    from {{ ref('fct_customer_monthly') }}
    group by month_end_date

),

source_mrr as (

    select month_end_date, sum(mrr_eur) as source_mrr_eur
    from {{ ref('int_mrr_order_months') }}
    where is_paid_line
    group by month_end_date

),

checks as (

    select
        bridge.*,
        coalesce(previous_bridge.closing_mrr_eur, 0) as previous_closing_mrr_eur,
        coalesce(source_mrr.source_mrr_eur, 0)       as source_mrr_eur
    from bridge
    left join bridge as previous_bridge
        on previous_bridge.month_end_date = last_day(add_months(bridge.month_end_date, -1))
    left join source_mrr
        on bridge.month_end_date = source_mrr.month_end_date

)

select *
from checks
where abs(opening_mrr_eur + new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur
          - contraction_mrr_eur - churn_mrr_eur - closing_mrr_eur) > 0.01
   or abs(opening_mrr_eur - previous_closing_mrr_eur) > 0.01
   or abs(closing_mrr_eur - source_mrr_eur) > 0.01
