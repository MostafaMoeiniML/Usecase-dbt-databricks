with source as (

    select
        product_id,
        product_code,
        product_desc,
        product_subgroup_desc,
        product_group_desc,
        product_subcat_desc,
        `product_cat_desc,,,,` as product_cat_desc
    from {{ source('bronze', 'products') }}

),

-- A misaligned row has its first three fields merged into product_id ("id;code;desc"),
-- and every following value shifted two columns to the left. We split product_id
-- and move the other values back to their correct position.
realigned as (

    select
        product_id like '%;%' as is_repaired_row,

        case when product_id like '%;%' then split_part(product_id, ';', 1) else product_id            end as product_id,
        case when product_id like '%;%' then split_part(product_id, ';', 2) else product_code          end as product_code,
        case when product_id like '%;%' then split_part(product_id, ';', 3) else product_desc          end as product_desc,
        case when product_id like '%;%' then product_code                   else product_subgroup_desc end as product_subgroup_desc,
        case when product_id like '%;%' then product_desc                   else product_group_desc    end as product_group_desc,
        case when product_id like '%;%' then product_subgroup_desc          else product_subcat_desc   end as product_subcat_desc,
        case when product_id like '%;%' then product_group_desc             else product_cat_desc      end as product_cat_desc
    from source

),

-- Remove stray quotes and the trailing commas that the broken CSV header left on the values.
cleaned as (

    select
        {%- for col in ['product_id', 'product_code', 'product_desc', 'product_subgroup_desc',
                        'product_group_desc', 'product_subcat_desc', 'product_cat_desc'] %}
        nullif(trim(regexp_replace(replace({{ col }}, '"', ''), ',+$', '')), 'NULL') as {{ col }},
        {%- endfor %}
        is_repaired_row
    from realigned

)

select * from cleaned
