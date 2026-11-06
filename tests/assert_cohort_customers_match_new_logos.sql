-- Each cohort must hold exactly the new logos of its month in rpt_kpi_monthly, and every month from the
-- second reporting month onwards must have a cohort (6 checkpoints each).
with cohorts as (

    select cohort_month, max(cohort_customers) as cohort_customers, count(*) as checkpoints
    from {{ ref('rpt_cohort_retention') }}
    group by cohort_month

),

expected as (

    select month_end_date, new_logos
    from {{ ref('rpt_kpi_monthly') }}
    where month_end_date > date'{{ var("reporting_start_month") }}'

)

select
    coalesce(cohorts.cohort_month, expected.month_end_date) as month_end_date,
    cohorts.cohort_customers,
    expected.new_logos,
    cohorts.checkpoints
from cohorts
full outer join expected
    on cohorts.cohort_month = expected.month_end_date
where cohorts.cohort_month is null
   or expected.month_end_date is null
   or cohorts.cohort_customers <> expected.new_logos
   or cohorts.checkpoints <> 6
