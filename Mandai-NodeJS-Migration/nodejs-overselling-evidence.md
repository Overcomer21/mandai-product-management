# Mandai Node.js — Overselling Concurrency Retest Evidence

**Result:** PASS
**Acceptance:** AC07 / AC08
**Target:** Running Node.js gateway and SQL Server MandaiDB
**Raw results:** [nodejs-overselling-evidence.json](nodejs-overselling-evidence.json)

| Metric | Observed |
|---|---:|
| Product ID (new disposable Tests product) | 2127 |
| Active product verified | True |
| Initial stock | 29 |
| Submitted attempts | 1000 / 1000 |
| HTTP 201 (orders created) | 29 |
| HTTP 409 (rejected) | 971 |
| Unexpected responses / transport errors | 0 |
| Distinct successful order IDs | 29 |
| Ending stock | 0 |
| Elapsed seconds | 4.127 |

**Assertion:** PASS requires exactly one accepted unit per available item, the remaining attempts rejected, all order IDs unique, zero unexpected responses, ending inventory zero, and the test product still active.

**Scope:** No Stripe API, no cancellation, no stock restoration and no DELETE. Previously executed cancellation/restoration tests are separate historical evidence.
**Data preservation:** This test creates one active Tests-category product and purchase/order records. Those records remain in MandaiDB for audit. Products referenced by orders must not be deleted.
