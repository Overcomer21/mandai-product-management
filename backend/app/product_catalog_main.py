"""Independent read-only catalog ASGI entrypoint.

Run from backend/: python -m uvicorn app.product_catalog_main:app --port 8100
No existing files, database schema, or transaction code need to change.
"""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute
from .api.routes.catalog import router_segment_2

app = FastAPI(title="Mandai Product Catalog Read API", version="1.0.0")

# Reuse the exact existing FastAPI route objects: preserves validation,
# response models, query parameters, and SQLAlchemy read implementations.
READ_PATHS = frozenset({
    "/api/products",
    "/api/products/count",
    "/api/products/categories",
    "/api/products/{product_id}",
})
selected = [r for r in router_segment_2.routes if isinstance(r, APIRoute)
            and r.path in READ_PATHS and r.methods == {"GET"}]
if len(selected) != len(READ_PATHS) or {r.path for r in selected} != READ_PATHS:
    raise RuntimeError("Catalog read route contract changed; refusing to start")
for route in selected:
    app.router.routes.append(route)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080").split(","),
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["Authorization", "Content-Type"],
)

# Optional Redis response cache. Existing catalog routes and SQL queries are untouched.
from .catalog_redis_cache import CatalogRedisCacheMiddleware
app.add_middleware(CatalogRedisCacheMiddleware)
