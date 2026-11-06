-- Checkpoints after the reporting window must have no values; checkpoints inside it must all have values.
select *
from {{ ref('rpt_cohort_retention') }}
where (
        last_day(add_months(cohort_month, months_since_start)) > date'{{ var("reporting_end_month") }}'
        and (retained_customers is not null or retained_mrr_eur is not null
             or customer_retention_pct is not null or mrr_retention_pct is not null)
      )
   or (
        last_day(add_months(cohort_month, months_since_start)) <= date'{{ var("reporting_end_month") }}'
        and (retained_customers is null or retained_mrr_eur is null)
      )
