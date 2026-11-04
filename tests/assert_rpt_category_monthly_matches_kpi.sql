-- Category MRR (opening and closing) summed over all categories must equal total MRR in rpt_kpi_monthly.
with by_category as (

    select
        month_end_date,
        sum(mrr_eur)         as mrr_eur,
        sum(opening_mrr_eur) as opening_mrr_eur,
        sum(share_of_mrr_pct) as share_of_mrr_pct
    from {{ ref('rpt_category_monthly') }}
    group by month_end_date

)

select
    coalesce(by_category.month_end_date, kpi.month_end_date) as month_end_date,
    by_category.mrr_eur as category_mrr_eur,
    kpi.mrr_eur         as kpi_mrr_eur
from by_category
full outer join {{ ref('rpt_kpi_monthly') }} as kpi
    on by_category.month_end_date = kpi.month_end_date
where by_category.month_end_date is null
   or kpi.month_end_date is null
   or abs(by_category.mrr_eur - kpi.mrr_eur) > 0.01
   or abs(by_category.opening_mrr_eur - kpi.opening_mrr_eur) > 0.01
   or abs(by_category.share_of_mrr_pct - 100) > 0.01
