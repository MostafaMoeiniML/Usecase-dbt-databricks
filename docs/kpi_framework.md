# KPI Framework – Revenue & Product Performance

This framework defines the 10 KPIs used to assess the health of team.blue's subscription business, covering
acquisition, retention, monetisation, growth and cross-sell. Each KPI is computed from the Gold star schema
(`workspace.gold`) and published month by month in `rpt_kpi_monthly`. Category performance is published in
`rpt_category_monthly`. Both tables are reference points to check Power BI figures against.

**Reporting window:** month-ends 2019-01 to 2022-11 (47 months). Months outside the window are incomplete
because of how the extract was filtered.

---

## 1. How to read these KPIs

The extract supports two kinds of conclusions with very different reliability.

| Reliable | Lower or upper bounds only |
|---|---|
| Trends over time (direction and pace of MRR, ARPU, churn, new logos) | Absolute customer churn rate (an **upper bound**) |
| Relative comparisons: category vs category, first-year vs tenured customers, cross-sold vs single-category | Absolute NRR and GRR levels (**lower bounds**) |
| MRR, ARPU and the MRR bridge (they reconcile to the cent with the source) | |

### Why absolute retention levels are not reliable

The order extract does not contain every billing period of every customer. When a renewal is missing, the
model sees the customer stop paying, which records a churn even though the customer may still be a client.
The evidence:

1. **Subscriptions outlive their orders.** For each customer churn event in the window, we checked whether
   the customer still holds a paid subscription whose own `expire_date` (from the subscriptions table) lies
   after the churn month.
   - Example: subscription 9013343 has a single order line covering 2018-06 to 2019-06, but the subscription
     itself expires on 2021-06-26.

   | Churn events in the window (immediate churn) | 47,991 |
   |---|---|
   | Customer still has a subscription expiring after the churn month | 40,565 (84.5%) |
   | … counting only subscriptions on paid lines | **39,929 (83.2%)** |
   | … whose subscription runs at least 2 more months | 36,337 (75.7%) |
   | … excluding subscriptions with status Cancelled, Suspended, To delete, Lost or Unpaid | 34,213 (71.3%) |
   | Churn events after the 1-month grace period (KPI 6) contradicted this way | 82.9% |

   The share is stable by year: 81.8% in 2019, 82.6% in 2020, 82.6% in 2021 and 84.5% in 2022. The median
   subscription still has 4 to 6 years to run at the moment the model records the churn.
2. **"New" customers are often not new.** 70% of customers whose first paid month falls in the window joined
   more than 13 months earlier.
3. **Renewal years are missing.** Of 4,491 consecutive order-line pairs within a subscription, 2,655 (59%)
   have a gap of about one year.
4. **Most subscriptions appear only once.** 163,019 of 167,975 subscriptions with eligible orders have a
   single order line.

**What this means.** Each contradicted churn event is flagged in `fct_customer_monthly` as
`is_contradicted_by_subscription`. The flag uses the conservative 71.3% definition, with Cancelled,
Suspended, To delete, Lost and Unpaid subscriptions not counted as running. The churn logic and movement
types are unchanged: they correctly reflect the order data supplied. `rpt_kpi_monthly` reports both views:

| Average monthly customer churn | 2019 | 2020 | 2021 | 2022 (Jan–Nov) |
|---|---|---|---|---|
| Measured (KPI 6, upper bound) | 6.30% | 6.16% | 6.40% | 6.85% |
| Excluding contradicted events (lower-bound estimate) | 1.97% | 1.83% | 1.84% | 1.80% |

The true churn rate lies between the two lines, and is most likely close to the lower one. It is a rate in
line with a domain and hosting business. For the same reason, NRR (about 40%) and GRR (about 28%) are lower
bounds. A complete order history, or using `stg_subscriptions.expire_date` as a second source of truth for
active status, would close the gap.

---

## 2. The 10 KPIs

Unless stated otherwise, KPIs use `fct_customer_monthly`. "Opening customers" are customers with paid MRR
at the previous month-end (`previous_mrr_eur > 0`). Only paid lines count: placeholder-price products (0.01)
add no MRR and do not make a customer active.

### Growth

**1. MRR (closing, end of month)**
- *Formula:* `SUM(mrr_eur)` at the month-end. An order line counts at month-end M when
  `order_date <= M < order_date + duration_months`.
- *Why it matters:* the size of the recurring revenue base and the anchor for all other KPIs.
- *Healthy:* rising steadily. *Unhealthy:* flat or falling.
- *Caveat:* lines longer than 12 months (about 10% of MRR) are understated in 2021–2022, because their
  renewals run past 2023 and fall outside the extract.

**2. MRR growth % (year-over-year headline, month-over-month supporting)**
- *Formula:* YoY = `MRR_M / MRR_M−12 − 1`; MoM = `MRR_M / MRR_M−1 − 1`.
- *Why it matters:* YoY removes renewal seasonality; MoM gives early signals but is noisy.
- *Healthy:* stable or accelerating YoY. *Unhealthy:* slowing YoY.
- *Caveat:* YoY is NULL until 2019-11, because the 2018 base is incomplete. The 2022 figure is depressed by
  the multi-year run-off (see the insights).

**3. Net new MRR**
- *Formula:* `SUM(new_mrr_eur + expansion_mrr_eur + reactivation_mrr_eur − contraction_mrr_eur − churn_mrr_eur)`.
  Opening MRR + net new MRR = closing MRR in every month.
- *Why it matters:* explains *why* MRR moved, and whether growth comes from new sales, upsell or win-back.
- *Healthy:* consistently positive, with gains well above losses (quick ratio clearly above 1).
- *Caveat:* because history starts in 2018, part of what should be reactivation is recorded as new.

### Retention

**4. Net Revenue Retention (NRR, trailing 12 months)**
- *Formula:* current MRR of the customers who paid 12 months ago ÷ their MRR 12 months ago.
- *Why it matters:* shows whether the existing base grows on its own, including upsell and win-back.
- *Healthy:* 100% or more. *Unhealthy:* falling.
- *Caveat:* a **lower bound**, because of the missing order lines (section 1). NULL until 2019-11.

**5. Gross Revenue Retention (GRR, trailing 12 months)**
- *Formula:* as NRR, but each customer is capped at their MRR 12 months ago, so expansion cannot hide churn.
  GRR ≤ NRR.
- *Why it matters:* the purest measure of revenue kept.
- *Healthy:* stable or rising. *Unhealthy:* a widening gap to NRR, or a downward trend.
- *Caveat:* a **lower bound**, as for NRR. NULL until 2019-11.

**6. Customer churn rate (monthly)**
- *Formula:* `COUNT(is_churned_after_grace) / opening customers`. A customer who is back at the next
  month-end, such as a late renewal, is not counted (1-month grace period). A supplementary version
  excludes churn events flagged `is_probable_data_gap`.
- *Why it matters:* the most direct signal of customer health in a subscription business.
- *Healthy:* low and falling. *Unhealthy:* rising.
- *Caveat:* an **upper bound**. Most measured churn events are contradicted by subscriptions that are still
  running (section 1). Always read it next to `churn_rate_excl_contradicted_pct`, the lower-bound estimate.

### Customers and acquisition

**7. Active paying customers**
- *Formula:* `COUNT(is_active)`, meaning customers with paid MRR at the month-end.
- *Why it matters:* the reach of the customer base. Healthy MRR growth should not come at its expense.
- *Healthy:* rising. *Unhealthy:* falling while MRR still grows.
- *Caveat:* missing order lines also understate this count, roughly consistently over time.

**8. New logos**
- *Formula:* `COUNT(is_new_logo)`, meaning first paid month AND joined within 12 months of it.
- *Why it matters:* true acquisition. The simpler "first paid month" count is 3–4× higher because of missing
  history.
- *Healthy:* stable or rising. *Unhealthy:* declining.
- *Caveat:* customers who join late in 2022 and start with a multi-year product fall outside the extract.

### Monetisation

**9. ARPU (average revenue per user)**
- *Formula:* `MRR / active paying customers`.
- *Why it matters:* reflects pricing power and product mix.
- *Healthy:* rising together with the customer count. *Unhealthy:* rising only because the customer base
  shrinks to its most valuable part.
- *Caveat:* a blend across categories. Read it together with `rpt_category_monthly`.

### Cross-sell

**10. Cross-sell rate**
- *Formula:* `COUNT(is_cross_sold) / COUNT(is_active)`, meaning active customers with paid MRR in more than
  one product category. Free bundled products are excluded; they are tracked separately as
  `has_free_bundled_product`.
- *Why it matters:* multi-category customers are far more valuable and far more loyal (see the insights).
- *Healthy:* rising. *Unhealthy:* flat or falling.
- *Caveat:* a cross-sold customer only counts as churned when all their products are missing at the same
  month-end. Losing one category counts as contraction, not churn. Their lower churn rate is therefore
  partly an artefact of the definition (see insight 4).

### Supplementary diagnostics (in `rpt_kpi_monthly`)

- **Quick ratio** = (new + expansion + reactivation) / (contraction + churn). Above 1 means MRR grows.
- **Customer churn rate excluding probable data gaps**, meaning returns after about 12 or 24 inactive months.
- **Customer churn rate excluding contradicted events** (`churn_rate_excl_contradicted_pct`). Churn events
  where a paid subscription is still running are left out: a lower-bound estimate of the true churn rate.
- **MRR from lines longer than 12 months**, which shows the multi-year run-off in 2021–2022.

---

## 3. KPI values

| KPI | 2019-12 | 2020-12 | 2021-12 | 2022-11 | Trend |
|---|---|---|---|---|---|
| 1. MRR | €54,908 | €60,419 | €65,701 | €65,260 | Steady growth to the end of 2021, then flat |
| 2. MRR growth YoY (MoM) | +8.5% (−0.1%) | +10.0% (+0.5%) | +8.7% (+1.0%) | +0.4% (+0.3%) | 9–10% a year, then a sharp slowdown in 2022 |
| 3. Net new MRR (month) | −€50 | +€298 | +€677 | +€218 | Per year: +€4.3k, +€5.5k, +€5.3k, then −€0.4k (2022, Jan–Nov) |
| 4. NRR (lower bound) | 43.9% | 43.7% | 41.1% | 39.0% | Slowly declining |
| 5. GRR (lower bound) | 30.2% | 30.2% | 28.0% | 26.4% | Slowly declining |
| 6. Customer churn, measured (upper bound) | 5.50% | 5.36% | 5.81% | 7.28% | Yearly averages 6.30%, 6.16%, 6.40%, 6.85%: rises in 2022 |
| 6b. Churn excluding contradicted events (lower-bound estimate) | 1.59% | 1.44% | 1.62% | 1.86% | Yearly averages 1.97%, 1.83%, 1.84%, 1.80%: stable |
| 7. Active paying customers | 15,217 | 16,259 | 16,041 | 15,109 | Peaked in 2020–2021, down 6% in 2022 |
| 8. New logos (month) | 198 | 214 | 168 | 175 | Per year: 2,859, 2,910, 2,509, then 1,992 (Jan–Nov 2022) |
| 9. ARPU | €3.61 | €3.72 | €4.10 | €4.32 | +20% in three years |
| 10. Cross-sell rate | 7.9% | 7.1% | 7.6% | 7.2% | Flat at 7–8% |
| Quick ratio (month) | 0.99 | 1.07 | 1.16 | 1.04 | Per year: 1.09, 1.10, 1.09, 0.99 |

**Category view** (`rpt_category_monthly`):

| Category | MRR 2022-11 | Share of MRR | MRR growth since 2019-01 | YoY at 2022-11 | ARPU 2022-11 | Average monthly gross MRR churn |
|---|---|---|---|---|---|---|
| Domains | €32,794 | 50.3% | +17.9% | +2.3% | €3.76 | 6.59% |
| Applications | €17,670 | 27.1% | +38.7% | −2.0% | €3.47 | 7.41% |
| Hosting | €13,060 | 20.0% | +27.1% | −0.5% | €6.17 | 11.50% |
| Other | €1,735 | 2.7% | +97.4% | −4.6% | €3.72 | 13.31% |

---

## 4. Key business insights

These insights rest on trends and relative comparisons, which the extract supports reliably.

1. **Growth has been driven by price and mix, not by more customers.** From 2019-12 to 2022-11, MRR grew
   19% (€54.9k to €65.3k), while active paying customers were flat (15,217 to 15,109). ARPU rose 20%, from
   €3.61 to €4.32. Hosting ARPU alone rose 31% (€4.70 to €6.17). This model has a ceiling unless acquisition
   or retention improves.

2. **Momentum slowed in 2022, even after correcting for the data.** Headline YoY growth fell to 0.4%, but
   part of this is the multi-year run-off: MRR from lines longer than 12 months fell from €5.6k to €2.9k.
   Excluding those lines, YoY growth was +9.6% (2020), +10.2% (2021) and **+4.9% (2022)**. That is a real
   halving of momentum. The quick ratio (0.99 for the year) and new logos (about 13% lower on an
   annualised basis) point the same way. The slowdown is an acquisition problem, not a churn problem.
   Measured churn rises 0.45 points in 2022, but churn excluding contradicted events is flat at about 1.8%.
   The 2022 rise comes from renewals missing from the extract, not from more customers leaving.

3. **The first year is where revenue leaks.** Customers in their first 12 months churn far more than
   customers past their first year, on either basis:

   | Monthly churn | First 12 months | After 12 months | Ratio |
   |---|---|---|---|
   | Measured | 7.14% | 4.91% | 1.5× |
   | Excluding contradicted events | 2.36% | 0.82% | 2.9× |

   Once missing renewals are removed, the gap is even larger. Onboarding and the first renewal are the main
   retention lever.

4. **Cross-sold customers are far more valuable, and probably more loyal, but rare.**
   - They pay 2.7× more: ARPU €9.21 against €3.39. This is the solid part of the finding.
   - Measured churn is 0.7% a month against 6.9% for single-category customers (0.07% against 2.01%
     excluding contradicted events). **That gap is partly an artefact.** A cross-sold customer only counts
     as churned when all their products are missing at the same month-end; losing one category is recorded
     as contraction. Each month, 9.9% of cross-sold customers lose at least one paid category while staying
     active. Counting a lost category as churn, they would show 10.6% against 6.9%. Missing order lines
     affect each product separately, so the true advantage cannot be measured from this extract. The
     direction is plausible, but the size of the gap should not be quoted.
   - Only 7–8% of active customers are cross-sold, and the rate has not moved since 2019.
   - Another 11.5% of active customers already hold a free bundled product. They are the most natural
     candidates for a paid second category.

5. **Each category plays a distinct role.**
   - **Domains** is the stable base: half of MRR with the lowest churn, and still growing in 2022 (+2.3% YoY).
   - **Applications** grew fastest over the window (+38.7%) but stalled in 2022 (−2.0% YoY).
   - **Hosting** earns the highest ARPU (€6.17) but loses 11.5% of its MRR a month, offset by 10.7% new MRR.
     It is valuable but leaky, and the clearest target for retention work.

---

## 5. Where the numbers live

| Need | Source |
|---|---|
| Monthly KPIs, bridge and diagnostics | `gold.rpt_kpi_monthly` (47 rows) |
| Category performance | `gold.rpt_category_monthly` (4 categories × 47 months) |
| Drill-down by customer and month | `gold.fct_customer_monthly` + `dim_customer` + `dim_date` |
| Drill-down by product and category | `gold.fct_mrr_monthly` + `dim_product` + `dim_date` |

Tests guarantee the following:
- The report tables match the facts.
- The MRR bridge reconciles every month at both grains.
- GRR never exceeds NRR.
- All rates are within 0–100%.
