"""
security.py - Application-Level DDoS, Rate Limiting & Anti-Abuse Engine
======================================================================
Provides thread-safe in-memory sliding-window rate limiting, IP tracking,
brute-force login defense, payload size capping, and WebSocket connection throttling.
"""

import time
import threading
import logging
from typing import Dict, List, Tuple

log = logging.getLogger("sabong-security")

class SlidingWindowRateLimiter:
    """
    Thread-safe in-memory rate limiter using sliding timestamp windows.
    Zero external dependencies (no Redis required for single-node / local dev).
    """

    def __init__(self):
        self._lock = threading.Lock()
        
        # IP -> list of timestamps
        self._registrations: Dict[str, List[float]] = {}
        self._login_failures: Dict[str, List[float]] = {}
        self._general_api: Dict[str, List[float]] = {}
        
        # IP -> temporary ban expiry timestamp
        self._quarantined_ips: Dict[str, float] = {}

        # Configuration Thresholds
        self.REGISTER_LIMIT = 3          # Max 3 accounts
        self.REGISTER_WINDOW = 600       # per 10 minutes (600s)

        self.LOGIN_FAIL_LIMIT = 5        # Max 5 failed attempts
        self.LOGIN_FAIL_WINDOW = 300     # per 5 minutes (300s)

        self.GENERAL_API_LIMIT = 60      # Max 60 requests
        self.GENERAL_API_WINDOW = 60     # per 1 minute (60s)

        self.MAX_WS_PER_IP = 4           # Max 4 concurrent sockets per IP
        self.MAX_PAYLOAD_BYTES = 64 * 1024  # 64 KB max body size
        self.QUARANTINE_DURATION = 900   # 15 minutes ban for persistent offenders
        self._last_purge = time.time()

    def _clean_window(self, timestamps: List[float], window_secs: float, now: float) -> List[float]:
        """Removes timestamps outside the current sliding window."""
        cutoff = now - window_secs
        return [t for t in timestamps if t > cutoff]

    def purge_stale_entries(self) -> None:
        """Purges expired IPs and timestamps from memory to maintain near-zero RAM footprint."""
        now = time.time()
        for ip in list(self._registrations.keys()):
            h = self._clean_window(self._registrations[ip], self.REGISTER_WINDOW, now)
            if h:
                self._registrations[ip] = h
            else:
                del self._registrations[ip]

        for ip in list(self._login_failures.keys()):
            h = self._clean_window(self._login_failures[ip], self.LOGIN_FAIL_WINDOW, now)
            if h:
                self._login_failures[ip] = h
            else:
                del self._login_failures[ip]

        for ip in list(self._general_api.keys()):
            h = self._clean_window(self._general_api[ip], self.GENERAL_API_WINDOW, now)
            if h:
                self._general_api[ip] = h
            else:
                del self._general_api[ip]

        for ip, expiry in list(self._quarantined_ips.items()):
            if now >= expiry:
                del self._quarantined_ips[ip]

        self._last_purge = now

    def _maybe_purge(self, now: float) -> None:
        """Executes purge at most once every 5 minutes."""
        if now - self._last_purge > 300.0:
            self.purge_stale_entries()

    def _is_quarantined(self, ip: str, now: float) -> Tuple[bool, int]:
        """Checks if an IP is in temporary quarantine."""
        expiry = self._quarantined_ips.get(ip, 0.0)
        if now < expiry:
            return True, int(expiry - now)
        elif ip in self._quarantined_ips:
            del self._quarantined_ips[ip]
        return False, 0

    def check_registration(self, ip: str) -> Tuple[bool, int]:
        """
        Validates if an IP can create a new account.
        Returns (allowed: bool, retry_after_seconds: int).
        """
        now = time.time()
        with self._lock:
            self._maybe_purge(now)
            # Check quarantine
            quarantined, remaining = self._is_quarantined(ip, now)
            if quarantined:
                return False, remaining

            history = self._clean_window(self._registrations.get(ip, []), self.REGISTER_WINDOW, now)
            self._registrations[ip] = history

            if len(history) >= self.REGISTER_LIMIT:
                oldest = history[0]
                retry_after = max(1, int(oldest + self.REGISTER_WINDOW - now))
                log.warning("Registration rate limit exceeded for IP %s (Retry after %ds)", ip, retry_after)
                return False, retry_after

            return True, 0

    def record_registration(self, ip: str) -> None:
        """Records a successful account creation from an IP."""
        now = time.time()
        with self._lock:
            history = self._registrations.get(ip, [])
            history.append(now)
            self._registrations[ip] = history
            log.info("Recorded registration for IP %s (%d/%d in window)", ip, len(history), self.REGISTER_LIMIT)

    def check_login_allowed(self, ip: str) -> Tuple[bool, int]:
        """
        Validates if an IP is allowed to attempt a login (anti-brute-force).
        Returns (allowed: bool, retry_after_seconds: int).
        """
        now = time.time()
        with self._lock:
            self._maybe_purge(now)
            quarantined, remaining = self._is_quarantined(ip, now)
            if quarantined:
                return False, remaining

            history = self._clean_window(self._login_failures.get(ip, []), self.LOGIN_FAIL_WINDOW, now)
            self._login_failures[ip] = history

            if len(history) >= self.LOGIN_FAIL_LIMIT:
                oldest = history[0]
                retry_after = max(1, int(oldest + self.LOGIN_FAIL_WINDOW - now))
                log.warning("Login brute-force lockout triggered for IP %s (Retry after %ds)", ip, retry_after)
                return False, retry_after

            return True, 0

    def record_login_failure(self, ip: str) -> None:
        """Records a failed password attempt."""
        now = time.time()
        with self._lock:
            history = self._login_failures.get(ip, [])
            history.append(now)
            self._login_failures[ip] = history
            log.warning("Failed login attempt from IP %s (%d/%d allowed)", ip, len(history), self.LOGIN_FAIL_LIMIT)

            # Auto-quarantine if persistent abuse
            if len(history) >= self.LOGIN_FAIL_LIMIT * 2:
                self._quarantined_ips[ip] = now + self.QUARANTINE_DURATION
                log.error("IP %s quarantined for %ds due to excessive brute-force attempts", ip, self.QUARANTINE_DURATION)

    def reset_login_failures(self, ip: str) -> None:
        """Clears failed login attempts after a successful login."""
        with self._lock:
            self._login_failures.pop(ip, None)

    def check_general_api(self, ip: str) -> Tuple[bool, int]:
        """
        Throttles general REST endpoints (/rooms, /leaderboard).
        Returns (allowed: bool, retry_after_seconds: int).
        """
        now = time.time()
        with self._lock:
            self._maybe_purge(now)
            quarantined, remaining = self._is_quarantined(ip, now)
            if quarantined:
                return False, remaining

            history = self._clean_window(self._general_api.get(ip, []), self.GENERAL_API_WINDOW, now)
            history.append(now)
            self._general_api[ip] = history

            if len(history) > self.GENERAL_API_LIMIT:
                retry_after = max(1, int(history[0] + self.GENERAL_API_WINDOW - now))
                return False, retry_after

            return True, 0

    def can_open_ws_connection(self, ip: str, current_active_count: int) -> bool:
        """Checks if an IP has reached the concurrent WebSocket limit."""
        limit = 32 if ip in ["127.0.0.1", "localhost", "::1"] else self.MAX_WS_PER_IP
        if current_active_count >= limit:
            log.warning("WebSocket connection cap (%d) reached for IP %s", limit, ip)
            return False
        return True

    @staticmethod
    def extract_ip_from_headers(headers, fallback_ip: str = "127.0.0.1") -> str:
        """
        Resolves the true client IP, prioritizing reverse proxy and Cloudflare headers:
        1. CF-Connecting-IP (Cloudflare Edge)
        2. X-Forwarded-For (Nginx, Render, AWS ALB)
        3. Raw socket address
        """
        if hasattr(headers, "get"):
            cf_ip = headers.get("CF-Connecting-IP") or headers.get("cf-connecting-ip")
            if cf_ip:
                return cf_ip.strip()

            xff = headers.get("X-Forwarded-For") or headers.get("x-forwarded-for")
            if xff:
                return xff.split(",")[0].strip()

        return fallback_ip or "127.0.0.1"


# Global singleton instance
security_manager = SlidingWindowRateLimiter()
