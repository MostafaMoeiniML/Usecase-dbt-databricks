-- The reporting window must be exactly the 47 month-ends from 2019-01 to 2022-11.
select
    count(*)            as reporting_months,
    min(month_end_date) as first_reporting_month,
    max(month_end_date) as last_reporting_month
from {{ ref('dim_date') }}
where is_reporting_month
having count(*) <> 47
    or min(month_end_date) <> date'2019-01-31'
    or max(month_end_date) <> date'2022-11-30'
