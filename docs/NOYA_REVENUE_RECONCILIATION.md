# Historical revenue reconciliation

Adam has stated about £60k of revenue over roughly 18 months to October 2026. That figure is the reconciliation
target, not a revenue record: it lives in `system_config.historical_revenue` (status `TO_BE_RECONCILED`) and is never
counted. HQ counts only revenue rows that carry evidence. The composition of the £60k is never estimated.

## What Adam provides

Drop files in the private Google Drive folder **NOYA Revenue Evidence (private)** (owned by noya@, not shared), or
attach them in chat:

- invoices (PDF or exported list)
- Stripe exports (payments or payouts CSV)
- bank statements (CSV or PDF) for the same period
- supplier invoices, only where gross profit should be shown

## What Claude does (no action needed from Adam until step 5)

1. **Read** every file in the folder. One candidate row per client invoice: client, date, project, service, gross,
   currency, invoice reference, file name.
2. **Match payments.** Each Stripe charge or bank credit is matched to an invoice by amount, currency, date window and
   client name or reference. Result per invoice: `PAID`, `PART_PAID` (with `amount_paid`) or `PENDING`.
3. **Supplier cost** only from a supplier invoice or a payment out that clearly belongs to the job. Otherwise blank,
   and gross profit stays unknown.
4. **Dry run.** Rows go through `hq_revenue_import(rows, false)`: it validates every field, rejects rows without
   evidence, and flags duplicates already recorded. Nothing is written.
5. **Adam reviews one table**: matched invoices, unmatched payments, unpaid invoices, and the total against the stated
   £60k (reconciled, remaining, and anything above it). Adam answers "approve" or corrects rows.
6. **Import** with `hq_revenue_import(rows, true)` (or Admin › Revenue & finance › Import, which runs the same check).
   Rows are marked `historical`, linked to the company where the name matches, with the evidence reference.

## Rules

- No row without evidence (invoice number, Stripe charge id, bank reference, contract or email).
- Amounts and dates come from the documents only. A payment without an invoice is listed as unmatched, not invented
  into an invoice. An invoice without a payment stays `PENDING`.
- Currencies are kept as invoiced (GBP, USD, EUR, EGP). Totals are shown per currency; no conversion is applied
  unless Adam supplies the rate actually received (bank credit).
- The gap between the stated £60k and the reconciled total stays visible as HISTORICAL REVENUE — TO BE RECONCILED
  until it is closed by evidence or Adam revises the stated figure.
- Client files are never committed to the repository.

Import columns (`docs/templates/revenue_import_template.csv`): client, date (YYYY-MM-DD), project, service, gross,
currency, payment_status (PAID, PART_PAID, PENDING), amount_paid (PART_PAID only), supplier_cost, invoice_reference,
evidence, director (optional Director key), notes.
