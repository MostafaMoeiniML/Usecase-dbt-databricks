with customers as (

    select * from {{ ref('stg_customers') }}

),

paid_product_months as (

    select
        months.client_id,
        months.product_id,
        months.month_end_date,
        sum(months.mrr_eur) as mrr_eur
    from {{ ref('int_mrr_order_months') }} as months
    where months.is_paid_line
    group by months.client_id, months.product_id, months.month_end_date

),

-- Cohort = first month-end with paid MRR.
cohorts as (

    select client_id, min(month_end_date) as cohort_month
    from paid_product_months
    group by client_id

),

-- First category bought = category of the highest-MRR paid product in the cohort month (ties: alphabetical).
first_category as (

    select
        paid_product_months.client_id,
        products.product_cat_desc,
        row_number() over (
            partition by paid_product_months.client_id
            order by paid_product_months.mrr_eur desc, products.product_cat_desc, products.product_id
        ) as category_rank
    from paid_product_months
    inner join cohorts
        on paid_product_months.client_id = cohorts.client_id
       and paid_product_months.month_end_date = cohorts.cohort_month
    inner join {{ ref('stg_products') }} as products
        on paid_product_months.product_id = products.product_id

)

select
    customers.client_id,
    customers.client_country,
    customers.segment,
    customers.join_date,
    customers.is_internal,
    cohorts.cohort_month is not null      as has_paid_mrr,
    cohorts.cohort_month,
    first_category.product_cat_desc       as first_product_cat_desc
from customers
left join cohorts
    on customers.client_id = cohorts.client_id
left join first_category
    on customers.client_id = first_category.client_id
   and first_category.category_rank = 1
