with source as (

    select * except (_rescued_data)
    from {{ source('bronze', 'customers') }}

),

cleaned as (

    select
        trim(client_id)                                   as client_id,
        nullif(trim(client_country), 'NULL')              as client_country,
        try_cast(nullif(trim(join_date), 'NULL') as date) as join_date,
        nullif(trim(segment), 'NULL')                     as segment
    from source

)

select
    *,
    join_date is null as is_missing_join_date,
    -- Registry / EUROMNT accounts are internal registry accounts, not real customers.
    coalesce(client_id like '%-EUROMNT' or segment = 'Registry', false) as is_internal
from cleaned
