"""Development-only, single-process login attempt limiter.

Five invalid attempts per (normalised email, TCP peer IP) in a rolling 15-minute
window lead to HTTP 429 on subsequent requests until the window expires.
Not suitable for multi-worker/multi-instance production deployments: use a
shared atomic Redis-backed limiter or gateway in production.
"""
from collections import deque
from threading import Lock
from time import monotonic
from fastapi import HTTPException

class LoginAttemptGuard:
    def __init__(self, max_failures=5, window_seconds=900):
        self.max_failures = max_failures
        self.window_seconds = window_seconds
        self._failures = {}
        self._lock = Lock()

    def _key(self, email, ip):
        return (email.strip().lower(), ip)

    def _prune(self, key, now):
        entries = self._failures.get(key)
        if entries is None:
            return 0
        while entries and now - entries[0] >= self.window_seconds:
            entries.popleft()
        if not entries:
            self._failures.pop(key, None)
            return 0
        return len(entries)

    def check(self, email, ip):
        key = self._key(email, ip)
        with self._lock:
            count = self._prune(key, monotonic())
        if count >= self.max_failures:
            raise HTTPException(429, 'Too many login attempts. Try again later.',
                                headers={'Retry-After': str(self.window_seconds)})

    def failure(self, email, ip):
        key = self._key(email, ip)
        with self._lock:
            now = monotonic()
            self._prune(key, now)
            self._failures.setdefault(key, deque()).append(now)

    def success(self, email, ip):
        with self._lock:
            self._failures.pop(self._key(email, ip), None)

login_guard = LoginAttemptGuard()
