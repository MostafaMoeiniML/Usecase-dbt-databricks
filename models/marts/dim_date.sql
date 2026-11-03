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
    trunc(month_end_date, 'MM')                                     as month_start_date,
    year(month_end_date)                                            as year,
    quarter(month_end_date)                                         as quarter,
    concat(year(month_end_date), '-Q', quarter(month_end_date))     as year_quarter,
    month(month_end_date)                                           as month_number,
    date_format(month_end_date, 'MMMM')                             as month_name,
    date_format(month_end_date, 'yyyy-MM')                          as year_month,
    -- Reporting window: before 2019 expired periods are missing from the extract (ramp-up),
    -- from 2022-12 renewals expiring after 2023 are missing (run-off).
    month_end_date between date'2019-01-31' and date'2022-11-30'    as is_reporting_month
from month_ends
