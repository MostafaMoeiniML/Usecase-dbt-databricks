with eligible_lines as (

    select
        order_line_id,
        client_id,
        product_id,
        subscription_id,
        order_date,
        period_end_date,
        duration_months,
        mrr_eur,
        is_paid_line
    from {{ ref('int_orders_enriched') }}
    where is_mrr_eligible

),

-- Candidate month-ends: the end of the order month and the following duration_months month-ends.
candidate_months as (

    select
        eligible_lines.*,
        last_day(add_months(order_date, month_offset)) as month_end_date
    from eligible_lines
    lateral view explode(sequence(0, duration_months)) offsets as month_offset

),

-- MRR is an end-of-month snapshot: a line counts in month M when it is active on the last day of M,
-- i.e. order_date <= month_end_date < period_end_date. This gives exactly duration_months month-ends per line.
active_months as (

    select *
    from candidate_months
    where month_end_date >= order_date
      and month_end_date < period_end_date

)

select
    order_line_id,
    month_end_date,
    client_id,
    product_id,
    subscription_id,
    row_number() over (partition by order_line_id order by month_end_date) as month_number,
    duration_months,
    mrr_eur,
    is_paid_line
from active_months
