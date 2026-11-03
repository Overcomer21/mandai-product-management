# Mandai Merchandise — Functional Specification

**Project:** Full-Stack Product Management Demo  
**Assessment:** Mandai Wildlife Group — Coding Assessment, Question 5

## 1. Overview

Mandai Merchandise is a full-stack application featuring a customer storefront, an administrator inventory dashboard, a FastAPI backend, and a Microsoft SQL Server database. Flutter provides a shared codebase for responsive web, mobile, and desktop interfaces.

## 2. Technology Stack

- **Frontend:** Flutter / Dart (Web, Windows, Android, iOS, macOS, and Linux support; individual platform validation may be required)
- **Backend:** Python / FastAPI REST API
- **Database:** Microsoft SQL Server RDBMS (`MandaiDB`)
- **Payment integration:** Stripe Checkout in Test Mode (sandbox)

## 3. Functional Requirements

### Customer Module

- View product catalog, details, images, and an interactive product viewer where available.
- Search products, filter by category or stock availability, and sort by price or name.
- Sign in, add products to a shopping cart, and initiate purchases.
- View order information and proceed through a Stripe test checkout flow.
- Block purchases of out-of-stock products and prevent purchases exceeding available inventory.
- Use a responsive layout with incremental product loading where implemented.

### Administrator Module

- Access administrator functions according to role-based permissions.
- Create, search, view, edit, and deactivate product records.
- Manage product inventory and stock information.
- Preserve historical sales references; products referenced by sales transactions must not be deleted in a way that compromises transaction integrity.

## 4. API and Transaction Requirements

- Provide authenticated REST endpoints for catalog, administration, and purchasing.
- Enforce authorization on the server using JWT-based authentication and Role-Based Access Control (RBAC).
- Validate product prices and stock on the server rather than trusting client-supplied values.
- Process purchases atomically with commit/rollback behavior, concurrency-safe stock updates, and idempotency safeguards to avoid duplicate orders and overselling.
- Maintain relational data integrity using appropriate SQL Server constraints and controlled deletion policies.

## 5. Stripe Payment Gateway — Sandbox

The application integrates with Stripe's actual payment platform using **Stripe Test Mode**, including test API credentials and hosted Stripe Checkout. It demonstrates payment-session creation, test card transactions, and payment-result handling **without real charges or fund transfers**. Sandbox functionality does not imply production payment certification or live payment readiness.

## 5.1. Inventory and Payment Scope Assumptions

- **In scope:** Deduct inventory atomically for purchases and prevent overselling, including concurrent requests, through database-level concurrency controls and transactional safeguards.
- **Assessment assumption:** Payment is treated as successful, and no payment cancellation occurs in the evaluated scenario. This assumption limits the assessment scenario; it does not describe how all real-world payments behave.
- **Outside this assessment scope:** End-to-end handling of payment failure, cancellation, refund, and associated inventory compensation/restoration. Stripe Test Mode demonstration does not establish complete coverage of these scenarios.
- **Potential future enhancement:** Use Apache Kafka with an event-driven payment and inventory workflow to process cancellation/failure events and trigger safe stock release or restoration, with idempotent consumers, retries, reconciliation, and concurrency testing. This is a proposed enhancement, **not a completed capability**.

## 6. Acceptance Criteria — Mandai Q5

1. Full-stack product management solution with a backend API.
2. Administrator dashboard for inventory management.
3. Customer-facing storefront.
4. Role-protected administrator CRUD operations.
5. Secure, authenticated customer buy endpoint.
6. Database-level race-condition and overselling prevention for concurrent purchases.
7. Public GitHub repository containing project source and a root-level `SPEC.md` or `ARCHITECTURE.md` explaining database design, concurrency strategy, and technical trade-offs.

## 7. Testing and Scope

Validation includes unit and widget tests, backend and API tests, SQL Server integration tests, concurrency checks, and read-only API stress testing. Automated testing across every supported target device is not claimed. Stripe payments use sandbox transactions only.

For component design, transaction details, security configuration, and technical trade-offs, see [`ARCHITECTURE.md`](ARCHITECTURE.md).
