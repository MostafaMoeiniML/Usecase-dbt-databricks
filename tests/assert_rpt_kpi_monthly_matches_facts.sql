-- rpt_kpi_monthly must cover exactly the reporting months, and its MRR, bridge and active customers
-- must equal the totals in fct_customer_monthly.
with expected as (

    select
        dates.month_end_date,
        coalesce(sum(facts.mrr_eur), 0)          as mrr_eur,
        coalesce(sum(facts.opening_mrr_eur), 0) as opening_mrr_eur,
        coalesce(count_if(facts.is_active), 0)   as active_customers
    from {{ ref('dim_date') }} as dates
    left join {{ ref('fct_customer_monthly') }} as facts
        on dates.month_end_date = facts.month_end_date
    where dates.is_reporting_month
    group by dates.month_end_date

)

select
    coalesce(expected.month_end_date, report.month_end_date) as month_end_date,
    expected.mrr_eur          as expected_mrr_eur,
    report.mrr_eur            as report_mrr_eur,
    expected.active_customers as expected_active_customers,
    report.active_customers   as report_active_customers
from expected
full outer join {{ ref('rpt_kpi_monthly') }} as report
    on expected.month_end_date = report.month_end_date
where expected.month_end_date is null
   or report.month_end_date is null
   or abs(expected.mrr_eur - report.mrr_eur) > 0.01
   or abs(expected.opening_mrr_eur - report.opening_mrr_eur) > 0.01
   or abs(report.opening_mrr_eur + report.net_new_mrr_eur - report.mrr_eur) > 0.01
   or expected.active_customers <> report.active_customers
