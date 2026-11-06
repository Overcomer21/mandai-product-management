# Mandai E-Merchandise — Functional Specification (Question 5)

**Assessment:** Full-stack Product Management Application — Question 5
**Scope:** Business and functional requirements for the Node.js candidate
**Status:** Local assessment demonstration; not a production specification

## 1. Objective

Provide a full-stack product-management application with a backend API, an administrator inventory dashboard, and a customer-facing storefront. Enforce role-based administrative CRUD and secure customer purchases, while preventing race conditions and inventory overselling.

This document specifies **what the application must do**, not how the technology is implemented. Database schema, concurrency strategy, component design, performance engineering, and technical trade-offs are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## 2. Business roles and journeys

### Guest
- Browse the public product catalogue, view product details, and search, filter, and sort products.
- View available products without signing in.
- Cannot perform authenticated purchase operations or administrator actions.

### Customer
- Sign in and access the storefront.
- Browse products, add items to a shopping cart, and adjust quantities.
- Submit an authorized purchase using server-validated product prices, quantities, and stock availability.
- View their own purchases and order history.

### Administrator
- Sign in to an authorized administrator dashboard.
- View the product catalogue and inventory, including products not shown in the public storefront.
- **Create, Read, Update, and Delete (CRUD)** product records through protected operations.
- Update product details, prices, and stock quantities.
- Receive an appropriate response if deletion is prohibited because an item is referenced by existing transactions.

## 3. Functional requirements

| ID | Business requirement | Expected behavior |
|---|---|---|
| FR01 | Public product catalogue | Guests and customers can view and browse eligible merchandise. |
| FR02 | Product discovery | Search, category filtering, sorting, product details, and pagination return consistent results. |
| FR03 | Administrator inventory CRUD | Authorized administrators can create, read, update, and delete product records, subject to business and data-integrity rules. |
| FR04 | Role-based access | Guests and customers cannot perform administrator CRUD. Only authenticated customers can submit customer purchases. |
| FR05 | Shopping cart | Customers can add products, change quantities, and review purchases before submission. |
| FR06 | Secure purchase | The system validates quantity, availability, price, and the authenticated customer's permission on the server. |
| FR07 | Transaction consistency | A failed or duplicate purchase must not cause unintended duplicate orders or stock reductions. |
| FR08 | Overselling prevention | Concurrent purchase requests must not sell more units than available in stock; unavailable stock must be rejected. |
| FR09 | Inventory visibility | Product details, prices, and stock changes remain consistent across Admin, Customer, and Guest views as applicable. |
| FR10 | Purchase history | Authenticated customers can view their own purchases and order statuses within the demonstrated scope. |

## 4. Acceptance criteria (AC01–AC08)

The AC01–AC08 descriptions below follow the recorded local Node.js acceptance matrix. They are verification categories for the Question 5 business requirements, not additional technology mandates from the original assessment prompt.

| AC | Acceptance criterion | Acceptance expectation |
|---|---|---|
| **AC01** | Full-stack functionality | Customer and administrator interfaces interact correctly with the backend, with functional UI flows. |
| **AC02** | Product API and catalogue | Product listing, details, search, category filters, sorting, pagination, and invalid-input handling behave correctly. |
| **AC03** | Administrator CRUD | Authenticated administrators can create, read, update, and delete eligible test products; inventory changes are reflected correctly. |
| **AC04** | Customer storefront and checkout demonstration | Product browsing, shopping cart, quantity changes, and demonstrated purchase flows operate as expected. |
| **AC05** | Authentication and authorization | Administrator operations are denied to guests and customers; customer purchase operations are limited to eligible authenticated users. |
| **AC06** | Secure purchase | Product availability, quantity, and authoritative server-side pricing are enforced; successful demonstration purchases are recorded and visible in order history. |
| **AC07** | Transaction consistency and concurrency | Identical purchase retries do not duplicate orders or stock reductions; conflicting repeated requests are rejected; failed operations preserve inventory integrity. |
| **AC08** | Overselling prevention | Under simultaneous purchase attempts, accepted purchases never exceed available stock, rejected purchases do not reduce stock, and the final stock remains valid. |

## 5. Scope of Stripe payment simulation

**Stripe payment is used in Test Mode as a simulation, with payment assumed successful for the demonstrated flow. The complete Stripe payment end-to-end lifecycle remains out of scope and requires further testing and, if necessary, targeted modifications.**

**Payment cancellation and order cancellation are outside the current acceptance scope.** These exclusions do not change the requirements for secure purchases, inventory consistency, idempotency, and overselling prevention in AC01–AC08. Any cancellation-related functionality already present or tested separately is not claimed as a completed acceptance deliverable here.

## 6. Acceptance evidence and limitations

The recorded Node.js local verification includes:

- **44 PASS / 0 FAIL** among checks executed in the expanded API acceptance run.
- **11 passing Flutter unit/widget tests** in the recorded run.
- **1,000 concurrent purchase attempts** against stock of 29 units: **29 accepted**, **971 rejected** for insufficient stock, **zero unexpected outcomes**, and final stock **0**.
- Tester-confirmed administrator CRUD and catalogue consistency across administrator, customer, and guest flows.

These are results from the documented local tests and manual confirmations, not a claim that all tests were rerun for this specification revision. The complete Stripe payment lifecycle and production readiness are **not** covered by the acceptance claim.

For exact test evidence, distinctions between automated and manual verification, and qualifications, see [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md).

## 7. Deliverables and documentation

Question 5 requests a public GitHub repository and root-level `SPEC.md` or `ARCHITECTURE.md` documenting the database schema, concurrency strategy, and technical trade-offs. The repository and this functional specification cover the application requirements; technical design details are deliberately located in [ARCHITECTURE.md](ARCHITECTURE.md).

**Related documents:** [README.md](README.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md)
