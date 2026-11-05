# Node.js SQL Concurrency and Overselling — Execution Evidence

**Result: PASS**  
**Scope:** AC07 / AC08, Node.js API backed by SQL Server MandaiDB.  
**Source of truth:** [Machine-generated JSON evidence](nodejs-overselling-evidence.json).  
**Runner:** [Reproducible Python runner](scripts/verify_nodejs_overselling.py).

| Metric | Verified result |
|---|---:|
| Concurrent purchase attempts completed | 1,000 |
| Configured request workers | 60 |
| Test product ID | 2127 |
| Product active at start | Yes |
| Initial stock | 29 |
| Accepted orders / HTTP 201 | 29 |
| Stock rejections / HTTP 409 | 971 |
| Rejection reason | Insufficient stock |
| Unique orders | 29 |
| Unexpected responses | 0 |
| Ending stock | 0 |
| Elapsed test execution | 4.127 seconds |

**Assertions:** Attempts completed = accepted + rejected; 29 accepted orders and 29 unique IDs; no unexpected results; stock never became negative and ended at zero; the number of accepted orders did not exceed initial stock. These observed assertions support **no overselling** in this test execution.

The test created an active disposable `Tests` product and 29 orders in MandaiDB. No Stripe payment, cancellation, inventory restoration, or mutation of an existing master product was part of this execution. The product has order references and should not be deleted; maintain transaction history.

**Evidence provenance:** Captured from the user's actual local Node.js test run. This report summarizes the attached JSON; it is not a separately run test.
