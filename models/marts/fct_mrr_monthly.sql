-- Paid MRR per customer x product x month-end, with MRR movements. Only paid lines drive MRR.
with paid_months as (

    select
        client_id as customer_id,
        product_id,
        month_end_date,
        cast(sum(mrr_eur) as decimal(24, 10)) as mrr_eur
    from {{ ref('int_mrr_order_months') }}
    where is_paid_line
    group by client_id, product_id, month_end_date

),

-- The month after a paid month without paid MRR gets an explicit 0 row, so churned MRR shows up as a movement.
churn_months as (

    select
        current_month.customer_id,
        current_month.product_id,
        last_day(add_months(current_month.month_end_date, 1)) as month_end_date,
        cast(0 as decimal(24, 10))                            as mrr_eur
    from paid_months as current_month
    left anti join paid_months as next_month
        on current_month.customer_id = next_month.customer_id
       and current_month.product_id = next_month.product_id
       and next_month.month_end_date = last_day(add_months(current_month.month_end_date, 1))

),

all_months as (

    select * from paid_months
    union all
    select * from churn_months

),

with_opening as (

    select
        all_months.*,
        coalesce(previous_month.mrr_eur, 0) as opening_mrr_eur,
        -- The earliest row is always a paid month, because churn rows only follow a paid month.
        min(all_months.month_end_date) over (
            partition by all_months.customer_id, all_months.product_id
        ) as first_paid_month
    from all_months
    left join paid_months as previous_month
        on all_months.customer_id = previous_month.customer_id
       and all_months.product_id = previous_month.product_id
       and previous_month.month_end_date = last_day(add_months(all_months.month_end_date, -1))

),

classified as (

    select
        *,
        case
            when opening_mrr_eur = 0 and month_end_date = first_paid_month then 'new'
            when opening_mrr_eur = 0                                         then 'reactivation'
            when mrr_eur = 0                                                 then 'churn'
            when mrr_eur > opening_mrr_eur                                   then 'expansion'
            when mrr_eur < opening_mrr_eur                                   then 'contraction'
            else 'unchanged'
        end as movement_type
    from with_opening

)

select
    customer_id,
    product_id,
    month_end_date,
    mrr_eur,
    opening_mrr_eur,
    movement_type,
    -- Movement amounts are positive; bridge: opening + new + expansion + reactivation - contraction - churn = closing.
    case when movement_type = 'new'          then mrr_eur - opening_mrr_eur else 0 end as new_mrr_eur,
    case when movement_type = 'expansion'    then mrr_eur - opening_mrr_eur else 0 end as expansion_mrr_eur,
    case when movement_type = 'reactivation' then mrr_eur - opening_mrr_eur else 0 end as reactivation_mrr_eur,
    case when movement_type = 'contraction'  then opening_mrr_eur - mrr_eur else 0 end as contraction_mrr_eur,
    case when movement_type = 'churn'        then opening_mrr_eur - mrr_eur else 0 end as churn_mrr_eur
from classified
