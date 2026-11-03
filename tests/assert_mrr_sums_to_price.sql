-- Spreading must not create or lose revenue: the MRR of a paid line summed over its month-ends equals its price.
-- Placeholder lines must sum to 0. We allow EUR 0.0001 for decimal rounding.
select
    orders.order_line_id,
    orders.product_price_eur,
    orders.is_paid_line,
    sum(months.mrr_eur) as total_mrr_eur
from {{ ref('int_orders_enriched') }} as orders
left join {{ ref('int_mrr_order_months') }} as months
    on orders.order_line_id = months.order_line_id
where orders.is_mrr_eligible
group by orders.order_line_id, orders.product_price_eur, orders.is_paid_line
having abs(
    coalesce(sum(months.mrr_eur), 0)
    - case when orders.is_paid_line then orders.product_price_eur else 0 end
) > 0.0001
