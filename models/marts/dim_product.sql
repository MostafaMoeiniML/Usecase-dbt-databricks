select
    product_id,
    product_desc        as product_name,
    product_subcat_desc as product_subcategory,
    product_cat_desc    as product_category
from {{ ref('stg_products') }}
