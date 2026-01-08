"""
HTTP client with throttling, retries, caching, and optional Playwright hook.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import requests
from requests import Response


DEFAULT_CACHE_DIR = Path(".cache/http")


@dataclass
class RequestConfig:
    url: str
    method: str = "GET"
    data: Optional[Any] = None
    json_body: Optional[Dict[str, Any]] = None
    params: Optional[Dict[str, Any]] = None
    headers: Optional[Dict[str, str]] = None
    cache_key: Optional[str] = None
    return_response: bool = False


class HttpClient:
    def __init__(
        self,
        cache_enabled: bool = True,
        cache_dir: Path = DEFAULT_CACHE_DIR,
        throttle_seconds: float = 1.0,
        max_retries: int = 5,
        timeout: float = 20.0,
    ) -> None:
        self.session = requests.Session()
        self.cache_enabled = cache_enabled
        self.cache_dir = cache_dir
        self.throttle_seconds = throttle_seconds
        self.max_retries = max_retries
        self.timeout = timeout
        self._last_request_time: float = 0.0
        if self.cache_enabled:
            self.cache_dir.mkdir(parents=True, exist_ok=True)

    def fetch(self, config: RequestConfig) -> Any:
        cache_path = self._cache_path(config) if self.cache_enabled else None
        if cache_path and cache_path.exists():
            with cache_path.open("rb") as fh:
                cached = fh.read()
            content = self._decode_cached(cached)
            if config.return_response:
                return (200, content, None)  # no request body when cached
            return content

        self._throttle()
        resp = self._request_with_retry(config)
        content = resp.content
        if cache_path:
            with cache_path.open("wb") as fh:
                fh.write(content)
        decoded = self._decode_response(resp)
        if config.return_response:
            return (resp.status_code, decoded, resp.request.body)
        return decoded

    def _decode_cached(self, data: bytes) -> Any:
        try:
            return json.loads(data.decode("utf-8"))
        except Exception:
            return data.decode("utf-8", errors="ignore")

    def _decode_response(self, resp: Response) -> Any:
        ctype = resp.headers.get("Content-Type", "")
        if "application/json" in ctype:
            return resp.json()
        return resp.text

    def _request_with_retry(self, config: RequestConfig) -> Response:
        attempt = 0
        backoff = 1.0
        while True:
            attempt += 1
            try:
                resp = self.session.request(
                    config.method,
                    config.url,
                    params=config.params,
                    data=config.data,
                    json=config.json_body,
                    headers=config.headers,
                    timeout=self.timeout,
                )
                if resp.status_code in (429,) or 500 <= resp.status_code < 600:
                    raise TemporaryError(f"HTTP {resp.status_code}")
                resp.raise_for_status()
                return resp
            except (requests.Timeout, requests.ConnectionError, TemporaryError) as exc:
                if attempt >= self.max_retries:
                    raise
                time.sleep(backoff)
                backoff *= 2

    def _cache_path(self, config: RequestConfig) -> Path:
        key = config.cache_key or self._hash_key(config)
        return self.cache_dir / f"{key}.cache"

    def _hash_key(self, config: RequestConfig) -> str:
        h = hashlib.sha256()
        h.update(config.url.encode("utf-8"))
        if config.params:
          h.update(json.dumps(config.params, sort_keys=True).encode("utf-8"))
        if config.json_body:
          h.update(json.dumps(config.json_body, sort_keys=True).encode("utf-8"))
        return h.hexdigest()

    def _throttle(self) -> None:
        elapsed = time.monotonic() - self._last_request_time
        sleep_for = self.throttle_seconds - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)
        self._last_request_time = time.monotonic()


class TemporaryError(Exception):
    """Raised for retry-able HTTP errors."""
