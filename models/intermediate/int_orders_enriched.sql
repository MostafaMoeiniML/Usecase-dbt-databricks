with orders as (

    select * from {{ ref('stg_orders') }}

),

products as (

    select product_id, product_code
    from {{ ref('stg_products') }}

),

subscriptions as (

    select subscription_id, product_code
    from {{ ref('stg_subscriptions') }}

),

customers as (

    select client_id, is_internal
    from {{ ref('stg_customers') }}

),

-- A subscription should belong to one client and one product. We flag subscriptions whose order lines disagree.
subscription_conflicts as (

    select
        subscription_id,
        count(distinct client_id) > 1 or count(distinct product_id) > 1 as has_subscription_conflict
    from orders
    where subscription_id is not null
    group by subscription_id

),

joined as (

    select
        orders.*,
        products.product_code,
        -- MRR period: order_date up to (not including) order_date + duration_months.
        add_months(orders.order_date, orders.duration_months)                  as period_end_date,
        orders.subscription_id is not null and subscriptions.subscription_id is null as has_unknown_subscription,
        coalesce(products.product_code <> subscriptions.product_code, false)  as has_product_mismatch,
        coalesce(subscription_conflicts.has_subscription_conflict, false)      as has_subscription_conflict,
        coalesce(customers.is_internal, false)                                as is_internal_client
    from orders
    left join products
        on orders.product_id = products.product_id
    left join subscriptions
        on orders.subscription_id = subscriptions.subscription_id
    left join subscription_conflicts
        on orders.subscription_id = subscription_conflicts.subscription_id
    left join customers
        on orders.client_id = customers.client_id

),

eligibility as (

    select
        *,
        -- Orders are the source of truth, so mismatches and conflicts are flagged but do not exclude a line.
        is_recurring
            and not is_credit
            and not is_invalid_date
            and not is_invalid_duration
            and not is_internal_client as is_mrr_eligible
    from joined

)

select
    *,
    -- Placeholder prices (0.01) mark free or bundled products: they stay eligible but add no revenue.
    is_mrr_eligible and not is_placeholder_price as is_paid_line,
    case
        when is_mrr_eligible and not is_placeholder_price
            then cast(product_price_eur / duration_months as decimal(24, 10))
        when is_mrr_eligible
            then cast(0 as decimal(24, 10))
    end as mrr_eur
from eligibility
