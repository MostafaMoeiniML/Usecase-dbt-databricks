-- Every MRR-eligible order line must be active at exactly duration_months month-ends.
select
    orders.order_line_id,
    orders.duration_months,
    count(months.month_end_date) as active_month_ends
from {{ ref('int_orders_enriched') }} as orders
left join {{ ref('int_mrr_order_months') }} as months
    on orders.order_line_id = months.order_line_id
where orders.is_mrr_eligible
group by orders.order_line_id, orders.duration_months
having count(months.month_end_date) <> orders.duration_months
