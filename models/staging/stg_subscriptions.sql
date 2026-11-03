with source as (

    select * except (_rescued_data)
    from {{ source('bronze', 'subscriptions') }}

),

cleaned as (

    select
        trim(subscription_id)                                 as subscription_id,
        try_cast(nullif(trim(creation_date), 'NULL') as date) as creation_date,
        try_cast(nullif(trim(start_date), 'NULL') as date)    as start_date,
        try_cast(nullif(trim(expire_date), 'NULL') as date)   as expire_date,
        nullif(trim(status), 'NULL')                          as status,
        nullif(trim(product_code), 'NULL')                    as product_code
    from source

)

select
    *,
    -- start_date before creation_date is common (backdated / transferred subscriptions), so we do not flag it.
    coalesce(
        start_date is null
        or expire_date is null
        or creation_date is null
        or expire_date < start_date,
        false
    ) as is_invalid_date
from cleaned
