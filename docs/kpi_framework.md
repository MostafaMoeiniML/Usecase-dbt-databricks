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
| 6 | Customer churn rate % | Customers paying at the previous month-end who pay nothing at this one | `churned customers / opening customers` → `customer_churn_rate_pct` | Most direct signal of customer health | Low and falling |
| 7 | Active customers | Active customer: in a given month, the customer has at least one paid recurring order running at month end. Free bundled items (0.01 €) don't count. | `COUNT(is_active)` → `active_customers` | Reach of the customer base | Rising |
| 8 | New logos | Customers in their first paid month who joined within 12 months of it | `COUNT(is_new_logo)` → `new_logos` | True acquisition, not returning customers with missing history | Stable or rising |
| 9 | ARPU | Average MRR per paying customer | `MRR / active customers` → `arpu_eur` | Pricing power and product mix | Rising together with active customers |
| 10 | Cross-sell rate % | Paying customers with paid MRR in more than one product category | `COUNT(is_cross_sold) / active customers` → `cross_sell_rate_pct` | Multi-category customers pay more and stay longer | Rising |

The MRR bridge columns (`opening_mrr_eur`, `new_mrr_eur`, `expansion_mrr_eur`, `reactivation_mrr_eur`,
`contraction_mrr_eur`, `churn_mrr_eur`) satisfy opening + new + expansion + reactivation − contraction − churn
= MRR in every month. Category MRR, active customers and revenue churn rate (same formula, computed per customer × category) are in
`gold.rpt_category_monthly`.

## Reading the churn rate

A customer churns in the month their paid MRR drops to zero: paid at the previous month-end, not at this one.
This is the same rule as churn in the MRR bridge, so the number of churned customers always equals the number of
churn movements. A customer who renews late and is back at the next month-end counts as churn followed by a
reactivation; this applies to 935 of the 47,991 churn events in the window (1.9%).

**Missing renewals affect the whole window, not only late 2022.** The order extract does not hold every billing
period. Of new customers on 12-month products who started between mid-2019 and mid-2021, only about 11% have an
order around their renewal date, while the subscriptions file shows about 78% of those subscriptions were extended
by at least a year. When a renewal order is missing, the customer appears to stop paying and is counted as churned.

As a result, in every month of the window:
- customer churn and revenue churn are strongly **overstated**;
- GRR and NRR are strongly **understated**;
- cohort retention from month 12 onwards is strongly **understated**.

Use these KPIs to compare periods, cohorts and categories, not as absolute levels.

| Average monthly churn | 2019 | 2020 | 2021 | 2022 (Jan–Nov) |
|---|---|---|---|---|
| `customer_churn_rate_pct` | 6.43% | 6.30% | 6.53% | 6.96% |

## Supporting measures

| Measure | Formula (`rpt_kpi_monthly` column) | Why it matters |
|---|---|---|
| Revenue churn rate % | `(churn MRR + contraction MRR) / opening MRR` → `revenue_churn_rate_pct` | Share of last month's MRR lost to customers leaving or paying less |
| Average categories per customer | Average paid categories per active customer → `avg_categories_per_customer` | Depth of cross-sell, next to the cross-sell rate (KPI 10) |

## Cohort retention

`gold.rpt_cohort_retention` follows each monthly cohort of new logos (KPI 8) from their first paid month,
2019-02 to 2022-11. Customers paying in 2019-01 may have started earlier, so they form no cohort. For each
cohort it shows, at 0, 1, 3, 6, 12 and 24 months after the start:

- **Customer retention %** = cohort customers still paying / cohort customers.
- **MRR retention %** = MRR of the cohort at the checkpoint / MRR in its first month. Expansion counts, and
  customers who stopped paying count as 0, as in NRR.

Checkpoints after 2022-11 are empty, not 0: they cannot be observed yet.

**Cohort retention from month 12 onwards is strongly understated, in every cohort.** 93% of new logos start on
a 12-month product, so month 12 is their first renewal. Only about 11% of these customers have a renewal order
in the extract, while about 78% of their subscriptions were in fact extended (see "Reading the churn rate").
This, not customer behaviour, is why retention drops from about 95% at month 6 to about 12% at month 12.
Checkpoints in late 2022 are pulled down further by the run-off of renewals that fall after the extract.
Use the curves to compare cohorts and track changes over time, not as absolute retention levels.
