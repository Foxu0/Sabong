"""
security.py - Application-Level DDoS, Rate Limiting & Anti-Abuse Engine
======================================================================
Provides thread-safe in-memory sliding-window rate limiting, IP tracking,
brute-force login defense, payload size capping, and WebSocket connection throttling.
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
import threading
import logging
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

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


# ---------------------------------------------------------------------------
# Server-Issued Session Tokens
# ---------------------------------------------------------------------------
# Format: base64url(json claims) + "." + base64url(HMAC-SHA256(claims_b64, SESSION_SECRET))
# The secret must be set in production; otherwise tokens stop working on every restart.

SESSION_TTL_SECS = int(os.environ.get("SESSION_TTL_SECS", 7 * 24 * 3600))
_SESSION_SECRET = os.environ.get("SESSION_SECRET", "").encode("utf-8")
if not _SESSION_SECRET:
    _SESSION_SECRET = secrets.token_bytes(32)
    log.warning("SESSION_SECRET is not set. Using a random per-process secret; sessions will reset on restart.")

def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")

def _b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))

def issue_session_token(player_id: int, username: str) -> str:
    claims = {"pid": int(player_id), "usr": str(username), "exp": int(time.time()) + SESSION_TTL_SECS}
    body = _b64url(json.dumps(claims, separators=(",", ":")).encode("utf-8"))
    sig = _b64url(hmac.new(_SESSION_SECRET, body.encode("ascii"), hashlib.sha256).digest())
    return f"{body}.{sig}"

def verify_session_token(token: str) -> Optional[Dict[str, Any]]:
    """Returns {"player_id", "username"} for a valid, unexpired token, else None."""
    try:
        body, sig = str(token).strip().split(".")
        expected = _b64url(hmac.new(_SESSION_SECRET, body.encode("ascii"), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, expected):
            return None
        claims = json.loads(_b64url_decode(body))
        if int(claims.get("exp", 0)) < time.time() or int(claims.get("pid", 0)) <= 0:
            return None
        return {"player_id": int(claims["pid"]), "username": str(claims.get("usr", ""))}
    except Exception:
        return None

def token_from_auth_header(auth_header: str) -> str:
    if auth_header and auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()
    return ""


# ---------------------------------------------------------------------------
# Google ID Token Verification
# ---------------------------------------------------------------------------
# GOOGLE_CLIENT_IDS: comma-separated OAuth client IDs whose tokens are accepted.

GOOGLE_CLIENT_IDS = [c.strip() for c in os.environ.get("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]
_GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
_GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"

def verify_google_id_token(id_token: str) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Verifies a Google ID token with Google's tokeninfo endpoint (signature, expiry)
    and checks audience, issuer and verified email locally.
    Returns (claims, "") on success or (None, error_message).
    """
    if not GOOGLE_CLIENT_IDS:
        return None, "Google Sign-In is not configured on this server."
    if not id_token:
        return None, "Missing Google ID token."
    try:
        url = _GOOGLE_TOKENINFO_URL + "?" + urllib.parse.urlencode({"id_token": id_token})
        with urllib.request.urlopen(url, timeout=8) as res:
            claims = json.loads(res.read().decode("utf-8"))
    except Exception as e:
        log.warning("Google ID token rejected by tokeninfo: %s", e)
        return None, "Invalid Google credential."

    if claims.get("aud") not in GOOGLE_CLIENT_IDS:
        return None, "Google credential was issued for a different application."
    if claims.get("iss") not in _GOOGLE_ISSUERS:
        return None, "Invalid Google credential issuer."
    try:
        if int(claims.get("exp", 0)) < time.time():
            return None, "Google credential has expired."
    except (TypeError, ValueError):
        return None, "Invalid Google credential."
    if str(claims.get("email_verified", "")).lower() != "true" or not claims.get("email") or not claims.get("sub"):
        return None, "Google account email is not verified."
    return claims, ""
