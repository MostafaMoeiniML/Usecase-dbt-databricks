# Validation Report – Revenue & Product Performance Model

This report validates the pipeline end to end, from the Bronze extract to the Gold star schema
(`workspace.gold`). All figures were produced from the current build.

**Result: the model reconciles completely.** Every order row is accounted for at each layer, revenue is
neither created nor lost between layers, the Gold models agree with each other, and three customers traced
by hand behave as the business rules intend.

---

## 1. Full build

`dbt build` (all models and tests):

| Models | Tests | Pass | Warn | Error |
|---|---|---|---|---|
| 11 (4 views, 7 tables) | 136 | 146 | 1 | 0 |

The pass count covers both the model builds and the tests. The single warning is expected:
4 orders reference a `subscription_id` that does not exist in the subscriptions table. They are kept and
flagged (`has_unknown_subscription`).

---

## 2. Reconciliation from Bronze to Gold

### 2.1 Rows

Exclusions are applied in the order shown, so each row is counted once. Numbers in brackets refer to the
data quality items in the project documentation.

| Step | Rows | Change | Reason |
|---|---|---|---|
| Bronze orders | 210,000 | | Raw extract |
| After dedupe (`stg_orders`) | 199,989 | −10,011 removed | Exact duplicate rows [1]. The only rows removed in the pipeline. |
| Enriched (`int_orders_enriched`) | 199,989 | 0 | One row per order line, cross-table flags added |
| − not recurring | | −2,299 excluded | MRR counts recurring revenue only |
| − credits | | −1,611 excluded | Negative prices [4] (1,661 in total; 50 are also non-recurring) |
| − invalid dates | | −54 excluded | expire_date before order_date [6] (129 in total) |
| − invalid duration | | 0 | Duration 0 and not derivable [7] (78 in total, all already excluded above) |
| − internal clients | | −22,169 excluded | Registry / EUROMNT accounts [9, 13] (22,182 in total) |
| **MRR-eligible lines** | **173,856** | | |
| − placeholder prices | | −65,742 at 0 MRR | Price 0.01, free bundled products [5]. Kept as eligible with 0 MRR. |
| **Paid lines** | **108,114** | | Drive MRR and active status |
| Order-line-months (`int_mrr_order_months`) | 2,077,661 | | Eligible lines × month-ends active (1,340,158 paid) |
| Paid client × product × month-ends | 1,213,973 | −126,185 combined | Several lines of the same product in one month are summed |
| **`fct_mrr_monthly`** | **1,305,536** | +91,563 churn rows | Churn row (MRR 0) in the first month without paid MRR |
| Paid client × month-ends | 961,564 | | |
| **`fct_customer_monthly`** | **1,026,018** | +64,454 churn rows | Churn row at customer level |

**Flagged, not removed** (orders are the source of truth):

| Flag | Lines | Reason |
|---|---|---|
| No subscription (`has_subscription_id = false`) | 24,428 | Text `'NULL'` in subscription_id [2] |
| Orders on repaired product 164202 | 23 | Misaligned product row repaired in staging [3] (24 before dedupe) |
| Duration derived from dates | 21 | Delivered duration 0, derived with CEIL [7] |
| `has_unknown_subscription` | 4 | Subscription missing from the subscriptions table [8] |
| `has_product_mismatch` | 16,000 | Order product differs from the subscription's product [8] |
| `has_subscription_conflict` | 1,586 | Subscription linked to more than one client or product [8] |

### 2.2 Revenue

| Measure | EUR |
|---|---|
| Total price of paid eligible lines (`int_orders_enriched`) | 3,615,275.33 |
| Total `mrr_eur` over all month-ends (`int_mrr_order_months`) | 3,615,275.33 |
| Total `mrr_eur` over all month-ends (`fct_mrr_monthly`) | 3,615,275.33 |
| Total `mrr_eur` over all month-ends (`fct_customer_monthly`) | 3,615,275.33 |
| Of which in the reporting window (2019-01 to 2022-11) | 2,813,077.65 |

The four totals are identical to the cent: spreading each order over its month-ends and aggregating to
the Gold grains neither creates nor loses revenue.

---

## 3. Cross-checks between the Gold models

| Check | Scope | Result |
|---|---|---|
| MRR by product category (`fct_mrr_monthly` + `dim_product`) = customer MRR (`fct_customer_monthly`) | 47 reporting months | 0 months differ (max difference €0.00) |
| Active customers in `fct_customer_monthly` = distinct clients with paid MRR in `fct_mrr_monthly` | 47 reporting months | 0 months differ (733,689 active customer-months) |
| Every client in both facts exists in `dim_customer` | all rows | 0 missing |
| Every product in `fct_mrr_monthly` exists in `dim_product` | all rows | 0 missing |
| Every month in both facts exists in `dim_date` | all rows | 0 missing |
| MRR bridge (opening + new + expansion + reactivation − contraction − churn = closing; opening = previous closing) | every month, both grains | Passes (singular test `assert_mrr_bridge_reconciles`) |

MRR by category at selected month-ends (EUR):

| Month-end | Domains | Hosting | Applications | Other | Total by category | Total customer grain |
|---|---|---|---|---|---|---|
| 2019-01 | 27,825.32 | 10,273.87 | 12,737.40 | 879.15 | 51,715.75 | 51,715.75 |
| 2020-12 | 31,105.19 | 11,725.64 | 16,795.24 | 792.72 | 60,418.79 | 60,418.79 |
| 2021-12 | 32,236.13 | 13,600.84 | 18,015.07 | 1,848.77 | 65,700.81 | 65,700.81 |
| 2022-11 | 32,794.22 | 13,060.16 | 17,669.85 | 1,735.42 | 65,259.65 | 65,259.65 |

---

## 4. Spot checks

Three real customers traced from Bronze orders to Gold, month by month. MRR is an end-of-month snapshot:
an order line counts at month-end M when `order_date <= M < order_date + duration_months`.

### 4.1 Simple single-product customer – `DP17973-EURO`

Italy, segment Ret-E, joined 2017-03-03. One Applications product (1588).

**Bronze orders**

| orderdate | expiredate | product | price | duration | recurring | quantity |
|---|---|---|---|---|---|---|
| 2019-08-14 | 2020-09-03 | 1588 | 25.00 | 12 | 1 | 0 |
| 2019-08-14 | 2020-09-03 | 1588 | 25.00 | 12 | 1 | 0 |
| 2020-08-15 | 2021-09-03 | 1588 | 33.90 | 12 | 1 | 0 |

**Silver**: the first two rows are exact duplicates; one is removed [1]. Two paid lines remain:
€25.00 / 12 = €2.0833 per month (period 2019-08-14 → 2020-08-14) and €33.90 / 12 = €2.8250
(period 2020-08-15 → 2021-08-15). Quantity 0 is ignored for MRR [10].

**Gold**

| Month-end | Opening | Closing | Movement |
|---|---|---|---|
| 2019-08 | 0.00 | 2.08 | new |
| 2019-09 … 2020-07 | 2.08 | 2.08 | unchanged (11 months) |
| 2020-08 | 2.08 | 2.83 | expansion |
| 2020-09 … 2021-07 | 2.83 | 2.83 | unchanged (11 months) |
| 2021-08 | 2.83 | 0.00 | churn |

**Why this is correct**

- **2019-08 new**: the first line starts on 2019-08-14, so it is active on 2019-08-31. This is the
  customer's first paid month, so it is the cohort month. It is not a new logo: the customer joined 29
  months earlier.
- **2020-08 expansion**: the first period ends on 2020-08-14, before the August month-end, and the renewal
  starts on 2020-08-15. At 2020-08-31 only the renewal is active, at a higher price (€33.90 instead of
  €25.00), so MRR rises from €2.08 to €2.83. The renewal is contiguous, with no gap and no double count.
- **2021-08 churn**: the renewal ends on 2021-08-15 and there is no further order, so there is no paid MRR
  at 2021-08-31. This is churn under both definitions (`is_churned_after_grace = true`).
- In total the customer has 24 paid month-ends, 12 per 12-month line, and the MRR sums to €25.00 + €33.90
  = €58.90.

### 4.2 Late renewal: churn then reactivation – `AC26555-EURO`

Italy, segment Ret-E, joined 2008-09-30. One Domains product (359), subscription 2414432.

**Bronze orders**

| orderdate | expiredate | product | price | duration | recurring |
|---|---|---|---|---|---|
| 2019-09-23 | 2020-10-23 | 359 | 38.50 | 12 | 1 |
| 2020-10-03 | 2021-10-23 | 359 | 40.50 | 12 | 1 |

**Silver**: two paid lines, €38.50 / 12 = €3.2083 (period 2019-09-23 → 2020-09-23) and
€40.50 / 12 = €3.3750 (period 2020-10-03 → 2021-10-03).

**Gold**

| Month-end | Opening | Closing | Movement | Inactive months | After-grace flag |
|---|---|---|---|---|---|
| 2019-09 | 0.00 | 3.21 | new | | |
| 2019-10 … 2020-08 | 3.21 | 3.21 | unchanged | | |
| 2020-09 | 3.21 | 0.00 | churn | 1 | `is_churned_after_grace = false` |
| 2020-10 | 0.00 | 3.38 | reactivation | 1 | `is_reactivated_after_grace = false` |
| 2020-11 … 2021-09 | 3.38 | 3.38 | unchanged | | |
| 2021-10 | 3.38 | 0.00 | churn | | `is_churned_after_grace = true` |

**Why this is correct**

- **2020-09 churn**: the first period ends on 2020-09-23, and the renewal was only ordered on 2020-10-03,
  ten days late. At 2020-09-30 nothing is active, so the MRR bridge shows the €3.21 leaving as churn.
- **2020-10 reactivation**: the renewal is active on 2020-10-31. The customer had paid MRR before, so this
  is a reactivation, not a new customer.
- **Grace period**: the customer was inactive for only one month-end. The Bronze `expiredate` of the first
  order (2020-10-23) shows that the domain had not actually lapsed when it was renewed. The grace-period
  KPI therefore does not count this as churn (`is_churned_after_grace = false`, and the return is not a
  reactivation after grace). The bridge still shows churn followed by reactivation, so it reconciles every
  month.
- **2021-10 churn**: the second period ends on 2021-10-03 with no further order, so this is churn under
  both definitions.

### 4.3 Cross-sold customer – `AA9874-EURO`

Italy, segment Ret-E, joined 2009-02-04. Three paid products in two categories.

**Bronze orders**

| orderdate | expiredate | product | category | price | duration | recurring |
|---|---|---|---|---|---|---|
| 2020-05-28 | 2021-06-17 | 84301 | Applications | 35.00 | 12 | 1 |
| 2021-01-20 | 2022-02-09 | 771 | Domains | 40.50 | 12 | 1 |
| 2021-06-12 | 2023-02-09 | 1647 | Applications | 6.50 | 12 | 1 |

**Silver**: three paid lines, at €2.9167 (84301, 2020-05-28 → 2021-05-28), €3.3750
(771, 2021-01-20 → 2022-01-20) and €0.5417 (1647, 2021-06-12 → 2022-06-12) per month. The third line's
Bronze `expiredate` lies 20 months after its order date. The MRR period follows the documented rule,
order_date + duration_months, so it is not affected.

**Gold** (customer grain, with the product-grain movements behind it)

| Month-end | Opening | Closing | Customer movement | Paid categories | Cross-sold | Product movements |
|---|---|---|---|---|---|---|
| 2020-05 | 0.00 | 2.92 | new | 1 | no | Applications 84301 new |
| 2020-06 … 2020-12 | 2.92 | 2.92 | unchanged | 1 | no | |
| 2021-01 | 2.92 | 6.29 | expansion | 2 | **yes** | Domains 771 new |
| 2021-02 … 2021-04 | 6.29 | 6.29 | unchanged | 2 | **yes** | |
| 2021-05 | 6.29 | 3.38 | contraction | 1 | no | Applications 84301 churn |
| 2021-06 | 3.38 | 3.92 | expansion | 2 | **yes** | Applications 1647 new |
| 2021-07 … 2021-12 | 3.92 | 3.92 | unchanged | 2 | **yes** | |
| 2022-01 | 3.92 | 0.54 | contraction | 1 | no | Domains 771 churn |
| 2022-02 … 2022-05 | 0.54 | 0.54 | unchanged | 1 | no | |
| 2022-06 | 0.54 | 0.00 | churn | 0 | no | Applications 1647 churn |

**Why this is correct**

- **2021-01 expansion and cross-sell**: the customer adds a paid Domains product while the Applications
  product is still active. At product grain this is a new product. At customer grain the total MRR rises,
  so it is an expansion. With paid MRR in two categories, `is_cross_sold` becomes true.
- **2021-05 contraction**: the first Applications product ends on 2021-05-28, before the May month-end,
  and the replacement only starts on 2021-06-12. At product grain the old product churns. At customer
  grain the customer is still active through the Domains product, so this is a contraction, not churn.
  Cross-sell drops to false for that month, because only one paid category is left.
- **2021-06 expansion**: a different Applications product (1647) starts, so cross-sell is true again.
- **2022-01 contraction and 2022-06 churn**: the Domains product ends on 2022-01-20, and the last product
  ends on 2022-06-12 with no further orders. Only then does the customer churn.
- The example shows why both grains are needed. Product swaps appear as churn plus new at product grain
  (category performance) but as net movements at customer grain (customer retention). Both bridges
  reconcile to the same closing MRR.

---

## 5. Configuration change

The reporting window is now configured once, in `dbt_project.yml`:

```yaml
vars:
  reporting_start_month: '2019-01-31'
  reporting_end_month: '2022-11-30'
```

`dim_date.is_reporting_month` reads these variables. After the rebuild, all `dim_date` tests pass,
including `assert_reporting_window_47_months` (47 month-ends, 2019-01 to 2022-11). The test keeps its own
fixed expectation, so an accidental change to the variables is caught.

---

## 6. Known limitations (unchanged by this validation)

- **Reporting window**: months before 2019 and from 2022-12 onwards are incomplete because of how the
  extract was filtered. Lines longer than 12 months (about 10% of MRR) are still understated in 2021–2022,
  by up to about 5% of total MRR.
- **Missing renewal periods**: some renewal periods are missing from the extract. This inflates churn and
  reactivation. `is_probable_data_gap` flags 2,026 churn events in the window (an upper bound).
- **New customers**: `new` means the first paid month in the extract. Only 10,270 of the 40,099 new
  customers in the window are new logos (joined within 12 months).
