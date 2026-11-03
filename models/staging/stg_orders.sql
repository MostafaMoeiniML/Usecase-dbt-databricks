{%- set raw_columns = [
    'client_id', 'ordercode', 'renewcode', 'orderdate', 'expiredate', 'subscription_id',
    'product_id', 'quantity', 'productprice', 'currency', 'duration_months', 'flag_recurring'
] -%}

with source as (

    select * except (_rescued_data)
    from {{ source('bronze', 'orders') }}

),

-- Bronze contains exact duplicate rows. We remove them on the raw values, before any cleaning,
-- so the number of removed rows reconciles exactly to Bronze. This is the only place rows are dropped.
deduplicated as (

    select distinct * from source

),

-- Orders have no natural key (ordercode + renewcode is not unique). After dedupe every row is
-- distinct on all raw columns, so a hash of all of them is a unique surrogate key.
keyed as (

    select
        {{ dbt_utils.generate_surrogate_key(raw_columns) }} as order_line_id,
        *
    from deduplicated

),

cleaned as (

    select
        order_line_id,
        trim(client_id)                                     as client_id,
        trim(ordercode)                                     as ordercode,
        nullif(trim(renewcode), 'NULL')                     as renewcode,
        try_cast(nullif(trim(orderdate), 'NULL') as date)   as order_date,
        try_cast(nullif(trim(expiredate), 'NULL') as date)  as expire_date,
        nullif(trim(subscription_id), 'NULL')               as subscription_id,
        nullif(trim(product_id), 'NULL')                    as product_id,
        -- Numbers arrive as decimal strings ('12.000000000'), so we cast via DECIMAL first.
        cast(try_cast(quantity as decimal(18, 6)) as int)               as quantity,
        cast(try_cast(productprice as decimal(18, 6)) as decimal(18, 2)) as product_price_eur,
        nullif(trim(currency), 'NULL')                                  as currency,
        cast(try_cast(duration_months as decimal(18, 6)) as int)        as duration_months_source,
        cast(try_cast(flag_recurring as decimal(18, 6)) as int) = 1     as is_recurring
    from keyed

),

with_duration as (

    select
        *,
        -- Assumption: when the delivered duration is 0 we derive it from the billing period,
        -- rounding up so any partial month counts as one month.
        case
            when duration_months_source > 0 then duration_months_source
            when expire_date > order_date then cast(ceil(months_between(expire_date, order_date)) as int)
        end as duration_months
    from cleaned

)

select
    order_line_id,
    client_id,
    ordercode,
    renewcode,
    order_date,
    expire_date,
    subscription_id,
    product_id,
    quantity,
    product_price_eur,
    currency,
    duration_months_source,
    duration_months,
    is_recurring,

    coalesce(product_price_eur < 0, false)     as is_credit,
    coalesce(product_price_eur = 0.01, false)  as is_placeholder_price,
    coalesce(
        order_date is null
        or expire_date is null
        or expire_date < order_date,
        false
    )                                          as is_invalid_date,
    coalesce(duration_months_source = 0 and duration_months is not null, false) as is_duration_derived,
    duration_months is null                    as is_invalid_duration,
    subscription_id is not null                as has_subscription_id
from with_duration
