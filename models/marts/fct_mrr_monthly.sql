-- Paid MRR per customer x product x month-end. Only paid lines drive MRR; movements are computed per customer
-- (fct_customer_monthly) and per customer x category (rpt_category_monthly).
select
    client_id                              as customer_id,
    product_id,
    month_end_date,
    cast(sum(mrr_eur) as decimal(24, 10))  as mrr_eur
from {{ ref('int_mrr_order_months') }}
where is_paid_line
group by client_id, product_id, month_end_date
