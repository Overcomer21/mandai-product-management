# Mandai E-Merchandise - Lazy Loading Performance Test Results

Assessment: Mandai Wildlife Group, Question 5
Database: SQL Server (MandaiDB)
Catalog: 2,022 product items

## 1. Technical Approach

The FastAPI catalog endpoint uses server-side filtering, sorting, and pagination. The Flutter catalog retrieves data incrementally and displays products as users navigate or scroll. The SQL query applies the selected filters and ordering before offset/limit pagination.

Supported catalog options:

- Category: All (without a category restriction) or a specific category such as Apparel.
- Sorting: Default, Name, Price low, Price high.
- Additional filtering: search text and in-stock status.
- Pagination: limit and offset parameters.

These operations allow the application to work with the 2,022-item catalog without retrieving the complete catalog in one API response.

## 2. SQL Server Indexes

The following indexes were verified on dbo.Products:

- PK_Products: clustered primary key on Id.
- IX_Products_Name_Id: nonclustered index on Name, Id.
- IX_Products_Price_Id: nonclustered index on Price, Id.
- IX_Products_IsActive_Category: nonclustered index on IsActive, Category.

The active-category index supports filtering by active status and category. Improved category-filter responsiveness was observed after it was added. This observation was qualitative; a before-and-after UI latency measurement was not recorded.

## 3. Combined SQL Performance Test

Method: Eight category/sort scenarios, five runs each, totaling 40 read-only SQL executions. Tests used the active-product condition, category filtering, sorting, and offset/limit pagination against the 2,022-item catalog.

Results (milliseconds):

- All / Default: min 3 ms, average 6.60 ms, max 18 ms.
- All / Name: min 2 ms, average 2.40 ms, max 3 ms.
- All / Price low: min 2 ms, average 3.60 ms, max 5 ms.
- All / Price high: min 2 ms, average 3.00 ms, max 4 ms.
- Apparel / Default: min 1 ms, average 1.20 ms, max 2 ms.
- Apparel / Name: min 1 ms, average 2.20 ms, max 3 ms.
- Apparel / Price low: min 1 ms, average 1.80 ms, max 3 ms.
- Apparel / Price high: min 1 ms, average 1.80 ms, max 2 ms.

Summary:

- Completed executions: 40 of 40.
- Minimum measured execution time: 1 ms.
- Maximum measured execution time: 18 ms.
- Overall average from the eight scenario averages: 2.83 ms (rounded).

## 4. Measurement Scope

The combined benchmark used a SQL query with conditional CASE ordering and counted rows from a paginated subquery. It is a SQL-level comparison rather than an exact replay of the SQLAlchemy-generated API query.

The recorded milliseconds represent local SQL benchmark elapsed time. FastAPI response latency, network transfer, product-image loading, and Flutter rendering require separate end-to-end measurements.

## 5. Outcome

The combined SQL benchmark completed all 40 executions with observed times between 1 and 18 ms. The implemented catalog design combines server-side filtering, sorting, and pagination with incremental Flutter loading. Category-filter responsiveness improved following the active-category index addition.

Production readiness requires further testing using actual production data volumes, workload, hardware, network, SQL Server configuration, and deployment settings. API and Flutter performance should be measured under the intended Docker, Nginx, and FastAPI worker/instance configuration.

Architecture reference: ARCHITECTURE.md
