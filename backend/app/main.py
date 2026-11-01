"""Composition root: existing API configuration and paths are preserved."""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .media_static import mount_product_media
from .stripe_test_router import router as stripe_test_router
from .stripe_checkout_router import router as stripe_checkout_router
from .stripe_payment_reconciliation import router as stripe_reconciliation_router
from .stripe_payment_return import router as stripe_payment_return_router
from .q5_test_launcher import router as q5_test_launcher_router
from .api.routes import health as health_module
from .api.routes import identity as identity_module
from .api.routes import catalog as catalog_module
from .api.routes import orders as orders_module
from .api.routes import report as report_module

app = FastAPI(title='Mandai Merchandise Assessment API', version='1.0.0')
app.include_router(stripe_test_router)
app.include_router(stripe_checkout_router)
app.include_router(stripe_reconciliation_router)
app.include_router(stripe_payment_return_router)
app.include_router(q5_test_launcher_router)
mount_product_media(app)
app.add_middleware(CORSMiddleware, allow_origins=os.getenv('CORS_ORIGINS','http://localhost:3000,http://localhost:8080').split(','), allow_credentials=False, allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type','Idempotency-Key'])

# Preserve the route-registration sequence of the original main.py.
app.include_router(health_module.router_segment_0)
app.include_router(identity_module.router_segment_1)
app.include_router(catalog_module.router_segment_2)
app.include_router(orders_module.router_segment_3)
app.include_router(report_module.router_segment_4)
