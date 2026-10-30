# Code Review — 27 October 2026

## Actual changes in this review
- Avoid stale product prices: acquire the product write lock by conditional stock UPDATE before retrieving the price used for Order/OrderItem.
- Flutter asynchronous state updates now check mounted; dispose persistent controllers.
- Fix duplicate purchase success notifications and generate cryptographically random idempotency keys.
- Use Unicode mappings for SQL Server product descriptions/names and email.
- Fix malformed PowerShell paths in README.
- Add backend regression tests for invalid tokens, quantity validation, and server-owned product pricing.

## Verified here
- `python -m pytest -q`: 5 passed (SQLite isolated integration tests).
- `python -m compileall`: passed.

## Not verified here
- `flutter analyze`, `flutter test`, Flutter UI build: SDK not installed here.
- SQL Server scripts/integration and concurrent requests: SQL Server instance not available here.
- End-to-end Flutter -> FastAPI -> SQL Server: requires local environment.

## Remaining risks / follow-up checks
- Client timeout after an unknown purchase result must reuse the SAME idempotency key; the sample frontend creates one per user confirmation but does not implement automatic retry.
- SQLite concurrency passing does not demonstrate SQL Server concurrency passing.
- Test SQL Server locking behavior, updates competing with purchases, and SQL Server driver errors using `sqlserver_concurrency_check.py`.
- Do not deploy the demo security/token lifecycle or seed credentials as a production service.
- No payment processing is implemented; orders are simulated.
