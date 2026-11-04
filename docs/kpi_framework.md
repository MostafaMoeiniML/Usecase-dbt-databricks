# KPI Framework – Revenue & Product Performance

Ten KPIs to track the health of team.blue's subscription business. All ten are published month by month in
`gold.rpt_kpi_monthly`. The reporting window covers month-ends 2019-01 to 2022-11 (47 months). MRR is an
end-of-month snapshot: an order line counts at month-end M when `order_date <= M < order_date + duration_months`,
with MRR = price / duration in months. Only paid lines count; placeholder-price products (0.01) add no MRR.

"Opening customers" are customers paying at the previous month-end. Retention KPIs compare each month with
12 months earlier, so they start in 2019-12.

| # | KPI | Definition | Formula (`rpt_kpi_monthly` column) | Why it matters | Healthy trend |
|---|---|---|---|---|---|
| 1 | MRR | Recurring revenue at the month-end | `SUM(mrr_eur)` → `mrr_eur` | Size of the recurring revenue base | Rising steadily |
| 2 | MRR growth YoY % | MRR against the same month a year earlier | `MRR(M) / MRR(M−12) − 1` → `mrr_growth_yoy_pct` | Growth pace without renewal seasonality | Stable or accelerating |
| 3 | Net new MRR | Net change in MRR during the month | `new + expansion + reactivation − contraction − churn` → `net_new_mrr_eur` | Explains why MRR moved: sales, upsell, win-back or losses | Consistently positive |
| 4 | Net revenue retention % | What customers paying 12 months ago pay today, against what they paid then | `current MRR of that base / their MRR 12 months ago` → `net_revenue_retention_pct` | Whether the existing base grows on its own | 100% or more |
| 5 | Gross revenue retention % | As NRR, with each customer capped at their MRR 12 months ago | `SUM(MIN(current, old)) / SUM(old)` → `gross_revenue_retention_pct` | Revenue kept, without upsell hiding losses | Stable or rising; close to NRR |
| 6 | Customer churn rate % | Customers who stopped paying and are not back at the next month-end (1-month grace) | `churned customers / opening customers` → `customer_churn_rate_pct` | Most direct signal of customer health | Low and falling |
| 7 | Active customers | Customers with paid MRR at the month-end | `COUNT(is_active)` → `active_customers` | Reach of the customer base | Rising |
| 8 | New logos | Customers in their first paid month who joined within 12 months of it | `COUNT(is_new_logo)` → `new_logos` | True acquisition, not returning customers with missing history | Stable or rising |
| 9 | ARPU | Average MRR per paying customer | `MRR / active customers` → `arpu_eur` | Pricing power and product mix | Rising together with active customers |
| 10 | Cross-sell rate % | Paying customers with paid MRR in more than one product category | `COUNT(is_cross_sold) / active customers` → `cross_sell_rate_pct` | Multi-category customers pay more and stay longer | Rising |

The MRR bridge columns (`opening_mrr_eur`, `new_mrr_eur`, `expansion_mrr_eur`, `reactivation_mrr_eur`,
`contraction_mrr_eur`, `churn_mrr_eur`) satisfy opening + new + expansion + reactivation − contraction − churn
= MRR in every month. Category MRR, active customers and gross MRR churn rate are in `gold.rpt_category_monthly`.

## Adjusted churn rate

The order extract does not hold every billing period of every customer. When a renewal is missing, the model
sees the customer stop paying and records a churn. For 71% of churn events, the customer still holds a paid
subscription (status not Cancelled, Suspended, To delete, Lost or Unpaid) that started on or before and expires
after the churn month. These events are flagged `is_churn_contradicted_by_subscription` in `fct_customer_monthly`.

`adjusted_churn_rate_pct` is KPI 6 without the contradicted events. Measured churn is an upper bound and adjusted
churn a lower-bound estimate; the true rate lies between them, most likely close to the adjusted rate. For the
same reason, NRR and GRR are lower bounds. Trends and comparisons remain reliable.

| Average monthly churn | 2019 | 2020 | 2021 | 2022 (Jan–Nov) |
|---|---|---|---|---|
| Measured (`customer_churn_rate_pct`) | 6.30% | 6.16% | 6.40% | 6.85% |
| Adjusted (`adjusted_churn_rate_pct`) | 1.97% | 1.83% | 1.84% | 1.80% |

Measured churn rises in 2022 while adjusted churn stays flat: the increase comes from renewals missing from the
extract, not from more customers leaving.
