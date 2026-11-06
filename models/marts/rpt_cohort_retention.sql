-- Cohort retention for new logos: how many customers of each cohort still pay, and how much of the cohort's
-- starting MRR they still bring, at fixed months after their first paid month.
-- Cohorts start the month after the reporting window opens: customers paying in the first month may have started earlier.
{%- set first_cohort_month = "last_day(add_months(date'" ~ var('reporting_start_month') ~ "', 1))" %}
{%- set last_month = "date'" ~ var('reporting_end_month') ~ "'" %}

with cohort_members as (

    select
        customer_id,
        month_end_date as cohort_month,
        mrr_eur        as start_mrr_eur
    from {{ ref('fct_customer_monthly') }}
    where is_new_logo
      and month_end_date between {{ first_cohort_month }} and {{ last_month }}

),

cohorts as (

    select
        cohort_month,
        count(*)            as cohort_customers,
        sum(start_mrr_eur)  as cohort_start_mrr_eur
    from cohort_members
    group by cohort_month

),

checkpoints as (

    select explode(array(0, 1, 3, 6, 12, 24)) as months_since_start

),

member_checkpoints as (

    select
        cohort_members.customer_id,
        cohort_members.cohort_month,
        checkpoints.months_since_start,
        last_day(add_months(cohort_members.cohort_month, checkpoints.months_since_start)) as checkpoint_month
    from cohort_members
    cross join checkpoints

),

-- Customers who stopped paying have no active row at the checkpoint and count as 0.
member_results as (

    select
        member_checkpoints.cohort_month,
        member_checkpoints.months_since_start,
        member_checkpoints.checkpoint_month,
        count_if(customer_months.is_active)              as active_customers,
        coalesce(sum(customer_months.mrr_eur), 0)        as mrr_eur
    from member_checkpoints
    left join {{ ref('fct_customer_monthly') }} as customer_months
        on member_checkpoints.customer_id = customer_months.customer_id
       and member_checkpoints.checkpoint_month = customer_months.month_end_date
       and customer_months.is_active
    group by member_checkpoints.cohort_month, member_checkpoints.months_since_start, member_checkpoints.checkpoint_month

),

-- A checkpoint after the reporting window is not yet observable: NULL, not 0.
results as (

    select
        cohort_month,
        months_since_start,
        case when checkpoint_month <= {{ last_month }} then active_customers end as retained_customers,
        case when checkpoint_month <= {{ last_month }} then mrr_eur end          as retained_mrr_eur
    from member_results

)

select
    cohorts.cohort_month,
    results.months_since_start,
    cohorts.cohort_customers,
    results.retained_customers,
    cast(100 * results.retained_customers / cohorts.cohort_customers as double)            as customer_retention_pct,
    cast(cohorts.cohort_start_mrr_eur as decimal(24, 10))                                  as cohort_start_mrr_eur,
    cast(results.retained_mrr_eur as decimal(24, 10))                                      as retained_mrr_eur,
    cast(100 * results.retained_mrr_eur / nullif(cohorts.cohort_start_mrr_eur, 0) as double) as mrr_retention_pct
from cohorts
inner join results
    on cohorts.cohort_month = results.cohort_month
