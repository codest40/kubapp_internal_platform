from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from sre.metrics_service import request_latency_seconds
import time

class PrometheusMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)
        duration = time.time() - start

        endpoint = request.url.path
        request_latency_seconds.labels(endpoint=endpoint).observe(duration)
        return response

