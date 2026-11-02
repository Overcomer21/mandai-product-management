"""Optional Redis cache for public, read-only catalog responses.

In-process single-flight limits concurrent cache misses per key. For multiple
Uvicorn processes/replicas, use a distributed coordination strategy as well.
"""
import asyncio
import hashlib
import logging
import os

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

logger = logging.getLogger(__name__)


class CatalogRedisCacheMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.url = os.getenv('CATALOG_REDIS_URL', '').strip()
        try:
            ttl = int(os.getenv('CATALOG_CACHE_TTL_SECONDS', '60'))
        except ValueError:
            logger.warning('Invalid CATALOG_CACHE_TTL_SECONDS; using 60 seconds')
            ttl = 60
        self.ttl = max(1, min(ttl, 3600))
        # Fixed-size lock stripes avoid unbounded lock creation for arbitrary URLs.
        # Different keys sharing a stripe may briefly serialize on cache misses.
        self._miss_locks = [asyncio.Lock() for _ in range(256)]
        self.client = None
        if self.url:
            try:
                from redis.asyncio import Redis
                self.client = Redis.from_url(
                    self.url, socket_connect_timeout=0.2,
                    socket_timeout=0.2, decode_responses=False,
                )
            except (ImportError, ValueError) as exc:
                logger.warning('Redis catalog cache disabled: %s', exc)

    async def _cache_get(self, key):
        try:
            return await self.client.get(key), True
        except Exception as exc:
            logger.warning('Redis cache read failed; using SQL: %s', exc)
            return None, False

    async def _fetch_and_cache(self, request, call_next, key):
        response = await call_next(request)
        if response.status_code != 200 or 'application/json' not in response.headers.get('content-type', ''):
            return response
        try:
            chunks = [chunk async for chunk in response.body_iterator]
            body = b''.join(chunks)
            if len(body) <= 1024 * 1024:
                try:
                    await self.client.set(key, body, ex=self.ttl)
                except Exception as exc:
                    logger.warning('Redis cache write failed: %s', exc)
            headers = dict(response.headers)
            headers.pop('content-length', None)
            headers['X-Catalog-Cache'] = 'MISS'
            return Response(
                body, status_code=200, headers=headers,
                media_type='application/json', background=response.background,
            )
        except Exception:
            logger.exception('Catalog cache response handling failed')
            raise

    async def dispatch(self, request: Request, call_next):
        if request.method != 'GET' or self.client is None or 'authorization' in request.headers:
            return await call_next(request)
        path = request.url.path
        if path not in ('/api/products', '/api/products/count', '/api/products/categories'):
            if not (path.startswith('/api/products/') and path[len('/api/products/'):].isdigit()):
                return await call_next(request)

        identity = path.encode() + b'?' + request.scope.get('query_string', b'')
        digest = hashlib.sha256(identity).hexdigest()
        key = 'mandai:catalog:v1:' + digest
        payload, available = await self._cache_get(key)
        if payload is not None:
            return Response(payload, media_type='application/json', headers={'X-Catalog-Cache': 'HIT'})
        if not available:
            # Redis failure must not prevent catalog reads or serialize SQL fallback.
            return await call_next(request)

        lock = self._miss_locks[int(digest[:8], 16) % len(self._miss_locks)]
        async with lock:
            # Recheck after acquiring lock: a preceding request may have filled cache.
            payload, available = await self._cache_get(key)
            if payload is not None:
                return Response(payload, media_type='application/json', headers={'X-Catalog-Cache': 'HIT'})
            if not available:
                return await call_next(request)
            return await self._fetch_and_cache(request, call_next, key)
