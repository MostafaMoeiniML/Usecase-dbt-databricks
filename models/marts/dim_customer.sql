-- One row per customer. The first paid month is the first month-end with paid MRR in the extract.
with customers as (

    select * from {{ ref('stg_customers') }}

),

first_paid_months as (

    select client_id, min(month_end_date) as first_paid_month
    from {{ ref('int_mrr_order_months') }}
    where is_paid_line
    group by client_id

)

select
    customers.client_id                    as customer_id,
    customers.client_country               as customer_country,
    customers.segment                      as customer_segment,
    customers.join_date,
    first_paid_months.first_paid_month
from customers
left join first_paid_months
    on customers.client_id = first_paid_months.client_id
