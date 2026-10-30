# Mandai Merchandise — Architecture

**Assessment:** Mandai Wildlife Group — Coding Assessment, Question 5

## 1. Architecture Overview

```text
Flutter / Dart UI (Storefront and Admin Dashboard)
                     |
                     | REST / JSON
                     v
             Python FastAPI
     Authentication | Products | Purchases
                     |
                     v
          SQL Server (MandaiDB)
                     |
             Orders / Inventory

        Stripe Test Mode (optional checkout flow)
```

The project uses a shared Flutter frontend, FastAPI backend, and SQL Server as the authoritative transaction and inventory database. Frontend code adopts modular/repository and BLoC patterns in selected areas; this does not imply every screen uses strict Clean Architecture layering.

## 2. Clean Architecture Principles and VGV Engineering Practices

The application follows **Clean Architecture principles** by promoting separation of concerns and organizing selected features around presentation, state management, and data access. This is a pragmatic, modular approach rather than a claim of complete strict layering across every screen.

Selected **Very Good Ventures (VGV) engineering practices** include:

- **BLoC-based state management:** Separates application state and business workflows from UI components in applicable features.
- **Repository pattern:** Organizes access to backend APIs and data behind reusable repositories.
- **Modular, maintainable code:** Encourages reusable components and clearer feature boundaries.
- **Automated testing and static analysis:** Helps validate behavior and improve code reliability.

## 3. Main Components

- **Presentation:** Customer catalog, shopping cart, and administrator dashboard.
- **API:** Authentication, product catalog, administrator CRUD, purchase, checkout, and order routes.
- **Authorization:** Authenticated endpoints and role checks for administrator-only functions.
- **Persistence:** SQL Server transactions for stock updates and order recording.
- **Payments:** Stripe Test Mode integration for demonstrating card-payment workflows.

## 4. Database Design and Referential Integrity

| Entity | Purpose |
| --- | --- |
| Users | Accounts and role assignments |
| Products | Catalog details, available stock, active status |
| Orders / Purchases | Purchase transactions, ownership and status |
| Order Items | Products, quantities and recorded prices associated with an order |
| Payment Records | Payment/check-out status where applicable |

This is a logical summary, not an exhaustive physical table/column listing. `MandaiDB` remains the source of truth for actual schema names and constraints.

### Relational Data Integrity

Microsoft SQL Server is used as the relational database management system (RDBMS). Foreign key constraints, where defined in the physical `MandaiDB` schema, enforce referential integrity between related records (for example, orders, order items, and products). They help prevent orphaned records and reject deletes or updates that would violate those relationships.

Foreign key constraints work alongside transactional commits/rollbacks and controlled deletion policies, including soft deactivation of products referenced by previous sales, to preserve relational consistency and transaction history.

## 5. API Security: JWT, RBAC and CORS

- **JWT authentication:** After successful login, the API issues an access token. Protected endpoints validate the token before granting access.
- **Role-Based Access Control (RBAC):** Backend authorization checks restrict administrative operations to administrators and purchases to authorized customers.
- **CORS:** Cross-Origin Resource Sharing controls which web origins browsers may use to access the FastAPI API. Deployment should explicitly configure trusted frontend origins.
- **Secure operations:** The backend validates requests, prices, and stock; HTTPS is required for secure deployed communication.

CORS is a browser access policy, not a replacement for JWT authentication or server-side authorization.

## 6. Transaction Management and Concurrency Control

1. Authenticate the customer and validate the purchase request.
2. Require an idempotency key to protect against duplicate retries.
3. Open a database transaction through the SQLAlchemy session (conceptually `BEGIN TRANSACTION`).
4. Perform an **atomic conditional stock update**, only when sufficient stock exists.
5. Verify affected rows, record the order, and `COMMIT` together as one atomic unit.
6. Reject insufficient-stock requests and `ROLLBACK` failed transactions, leaving inventory and order data consistent.

Database constraints and transaction boundaries prevent two concurrent requests from consuming the same inventory. Prices and stock availability are validated server-side rather than trusted from the client.

## 7. Frontend Architecture: Responsive UI and Lazy Loading

- **Cross-platform:** Flutter and Dart share frontend code for Web, Windows, Android, iOS, Linux, and macOS. Platform-specific setup and testing remain necessary.
- **Responsive UI:** Layouts adapt to available screen space, including desktop side panels and mobile-friendly navigation.
- **Catalog loading:** Incremental/lazy rendering and scrolling reduce the amount of UI work at once. This does not imply backend pagination unless the API explicitly implements it.
- **Code organization:** Selected modules use feature-oriented structure, repositories, and BLoC for state management; the entire UI is not claimed to follow strict Clean Architecture.

## 8. Stripe Payment Gateway (Sandbox)

Stripe Test Mode integrates with Stripe's real payment APIs to demonstrate checkout, payment status handling, and test-card transactions without charging real funds. Production operation requires live credentials, secure webhook validation, and additional deployment checks.

## 9. Testing and Limitations

Backend unit/API tests, SQL Server integration tests, concurrent purchase tests, Flutter tests, and read-only API stress testing have been performed. The dedicated concurrency test verified that 20 requests against stock of 10 resulted in 10 successful purchases and 10 rejected requests, without overselling.

Full multi-device UI validation and production payment certification are outside the demonstrated test evidence. Protect environment secrets; use HTTPS and verified payment webhooks in production deployments.

## 10. Technical Decisions and Trade-offs

- **Flutter:** Reuses UI code across platforms, while native features and device layouts may need platform-specific work.
- **FastAPI:** Simple typed REST endpoints and straightforward API testing.
- **SQL Server:** Strong transactional integrity for purchase and stock consistency; correct indexing and connection-pool configuration matter under load.
- **Modular application:** Simpler for a focused assessment than deploying microservices prematurely.
- **Soft deactivation:** Keeps products referenced by previous transactions available for historical integrity.
