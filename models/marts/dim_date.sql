-- Month-end calendar covering every month in the facts, plus one month for the final churn rows.
with bounds as (

    select
        min(month_end_date)                              as first_month_end,
        last_day(add_months(max(month_end_date), 1))     as last_month_end
    from {{ ref('int_mrr_order_months') }}

),

month_ends as (

    select last_day(add_months(first_month_end, month_offset)) as month_end_date
    from bounds
    lateral view explode(
        sequence(0, cast(months_between(last_month_end, first_month_end) as int))
    ) offsets as month_offset

)

select
    month_end_date,
    year(month_end_date)                                            as year,
    date_format(month_end_date, 'yyyy-MM')                          as year_month,
    -- Reporting window from dbt vars (see dbt_project.yml for why these months).
    month_end_date between date'{{ var("reporting_start_month") }}'
                       and date'{{ var("reporting_end_month") }}'   as is_reporting_month
from month_ends
