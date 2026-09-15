"""
Sabong Roosters - Online Relay & Matchmaking Server
====================================================
Provides:
  REST API (HTTP on PORT and API_PORT):
    POST /auth/google     -> 1-click Google Account Sign-In / Registration
    POST /auth/login      -> Classic Username/Password Authentication
    POST /auth/register   -> New Player Account Registration
    GET  /leaderboard     -> Live Competitive Standings (Master, Grandmaster, etc.)
    GET  /rooms           -> Open and Active Match Lobbies (with Spectator flags)
    POST /bet/place       -> Wager Taya coins on Meron vs Wala
    GET  /health          -> Server & TiDB Cloud Health Check

  WebSockets (on PORT):
    WS   /ws/new/host     -> Host a new battle room (1v1 or Tournament)
    WS   /ws/{code}/join  -> Join as a contender/duelist
    WS   /ws/{code}/spectate -> Join as a live spectator with betting stream

Run locally:
    pip install websockets pymysql
    python server.py
"""

import asyncio
import json
import logging
import os
import random
import string
import time
import threading
import socket
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

# Leaderboard in-memory cache to prevent database hammering
_lb_cache = None
_lb_cache_time = 0.0
_lb_lock = threading.Lock()

def _get_cached_leaderboard():
    global _lb_cache, _lb_cache_time
    now = time.time()
    with _lb_lock:
        if _lb_cache is None or (now - _lb_cache_time > 5.0):
            if db:
                _lb_cache = db.get_leaderboard(20)
                _lb_cache_time = now
            else:
                _lb_cache = []
        return _lb_cache
from typing import Optional, List, Dict, Any, Tuple

# OTP Store for Email Verification & Password Resets
# email -> {"code": "123456", "expires_at": float, "purpose": "register"|"forgot_password", "last_sent": float}
_otp_store: Dict[str, Dict[str, Any]] = {}
_otp_lock = threading.Lock()

import websockets
from websockets.server import WebSocketServerProtocol



try:
    from db_manager import db, compute_rank_tier
except ImportError:
    try:
        from scripts.db_manager import db, compute_rank_tier
    except ImportError:
        db = None
        def compute_rank_tier(taya): return "BRONZE"

try:
    from security import security_manager
except ImportError:
    try:
        from scripts.security import security_manager
    except ImportError:
        security_manager = None

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("sabong-relay")

# Config
PORT = int(os.environ.get("PORT", 10005))
API_PORT = int(os.environ.get("API_PORT", PORT + 1))
INTERNAL_WS_PORT = int(os.environ.get("INTERNAL_WS_PORT", PORT + 10))
ROOM_CODE_LENGTH = 4
ROOM_TIMEOUT_SECS = 300

# WebSocket concurrency tracker per IP
_active_ws_per_ip: Dict[str, int] = {}
_ws_ip_lock = threading.Lock()

def _increment_ws_ip(ip: str) -> int:
    with _ws_ip_lock:
        cnt = _active_ws_per_ip.get(ip, 0) + 1
        _active_ws_per_ip[ip] = cnt
        return cnt

def _decrement_ws_ip(ip: str) -> None:
    with _ws_ip_lock:
        if ip in _active_ws_per_ip:
            _active_ws_per_ip[ip] = max(0, _active_ws_per_ip[ip] - 1)
            if _active_ws_per_ip[ip] == 0:
                del _active_ws_per_ip[ip]

def _extract_client_ip(ws: WebSocketServerProtocol) -> str:
    fallback = str(ws.remote_address[0]) if ws.remote_address else "127.0.0.1"
    if security_manager and hasattr(ws, "request_headers") and ws.request_headers:
        return security_manager.extract_ip_from_headers(ws.request_headers, fallback)
    return fallback

# In-memory Leaderboard Cache (5-second TTL to shield DB from hammering/DDoS)
_cached_leaderboard: List[Dict[str, Any]] = []
_last_leaderboard_fetch: float = 0.0
_leaderboard_cache_lock = threading.Lock()

def _get_cached_leaderboard(limit: int = 20) -> List[Dict[str, Any]]:
    global _cached_leaderboard, _last_leaderboard_fetch
    if not db:
        return []
    now = time.time()
    with _leaderboard_cache_lock:
        if now - _last_leaderboard_fetch >= 5.0 or not _cached_leaderboard:
            try:
                _cached_leaderboard = db.get_leaderboard(limit)
                _last_leaderboard_fetch = now
            except Exception as e:
                log.error("Failed to refresh leaderboard cache: %s", e)
        return _cached_leaderboard

# Room Registry
class Room:
    def __init__(self, code: str, host_name: str, host_public_ip: str = "", host_local_ip: str = "", host_port: int = 7777, mode: str = "duel", max_players: int = 2):
        self.code = code
        self.host_name = host_name
        self.host_public_ip = host_public_ip
        self.host_local_ip = host_local_ip
        self.host_port = host_port
        self.mode = mode  # "duel" or "tournament"
        self.max_players = max_players
        self.created_at = time.time()
        self.host_ws: Optional[WebSocketServerProtocol] = None
        self.clients: List[WebSocketServerProtocol] = []
        self.spectators: List[WebSocketServerProtocol] = []
        self.bets: List[Dict[str, Any]] = []
        self.started = False
        self.closed = False
        self.meron_rooster = ""
        self.wala_rooster = ""
        self.winner = None

    def is_open(self) -> bool:
        if self.host_ws is None or self.started or self.closed:
            return False
        max_clients = 1 if self.mode == "duel" else max(1, self.max_players - 1)
        return len(self.clients) < max_clients

    def can_spectate(self) -> bool:
        return not self.closed and self.host_ws is not None

    def get_meron_pool(self) -> int:
        return sum(b.get("amount", 0) for b in self.bets if b.get("side", "").upper() == "MERON")

    def get_wala_pool(self) -> int:
        return sum(b.get("amount", 0) for b in self.bets if b.get("side", "").upper() == "WALA")

    def get_odds(self) -> Tuple[float, float]:
        m = self.get_meron_pool()
        w = self.get_wala_pool()
        total = m + w
        if total == 0:
            return (1.95, 1.95)
        if m == 0:
            return (1.95, 1.05)
        if w == 0:
            return (1.05, 1.95)
        m_odds = round(max(1.05, total / m), 2)
        w_odds = round(max(1.05, total / w), 2)
        return (m_odds, w_odds)

    def to_dict(self) -> dict:
        status_str = "IN_PROGRESS" if self.started else ("WAITING" if self.is_open() else "FULL")
        m_odds, w_odds = self.get_odds()
        return {
            "code": self.code,
            "host": self.host_name,
            "mode": self.mode,
            "current_players": len(self.clients) + (1 if self.host_ws else 0),
            "max_players": self.max_players,
            "spectators_count": len(self.spectators),
            "can_spectate": self.can_spectate(),
            "status": status_str,
            "meron_rooster": self.meron_rooster,
            "wala_rooster": self.wala_rooster,
            "meron_pool": self.get_meron_pool(),
            "wala_pool": self.get_wala_pool(),
            "meron_odds": m_odds,
            "wala_odds": w_odds,
            "created_at": int(self.created_at)
        }

rooms: dict = {}

def _generate_code() -> str:
    chars = string.ascii_uppercase + string.digits
    while True:
        code = "".join(random.choices(chars, k=ROOM_CODE_LENGTH))
        if code not in rooms:
            return code

def _cleanup_old_rooms() -> None:
    now = time.time()
    stale = [code for code, room in rooms.items() if room.closed or (not room.started and now - room.created_at > ROOM_TIMEOUT_SECS)]
    for code in stale:
        rooms.pop(code, None)
        log.info("Cleaned up room %s", code)

# ---------------------------------------------------------------------------
# HTTP REST API SERVER (Running on API_PORT with full CORS support)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# HTTP REST API LOGIC & STATIC FILE DISPATCHER
# ---------------------------------------------------------------------------

WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exports", "web")

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".ico": "image/x-icon",
    ".css": "text/css; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
}

def _read_file_sync(file_path: str) -> bytes:
    with open(file_path, "rb") as f:
        return f.read()

def handle_api_post(parsed_path: str, payload: Dict[str, Any], client_ip: str) -> Tuple[int, Dict[str, Any], int]:
    """Centralized REST POST handler for both API_PORT and PORT"""
    if parsed_path == "/auth/google":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        google_id = payload.get("google_id") or payload.get("sub") or payload.get("id") or ""
        email = payload.get("email") or ""
        name = payload.get("name") or payload.get("username") or "Challenger"
        avatar_url = payload.get("avatar_url") or payload.get("picture") or ""
        res = db.authenticate_or_register_google(google_id, email, name, avatar_url)
        return (200 if res.get("success") else 400, res, 0)

    if parsed_path == "/auth/login":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        if security_manager:
            allowed, retry_after = security_manager.check_login_allowed(client_ip)
            if not allowed:
                return (429, {
                    "success": False,
                    "error": f"Too many failed login attempts. Account temporarily locked for {retry_after}s."
                }, retry_after)
        user = payload.get("username", "")
        pw = payload.get("password", "")
        res = db.authenticate_player(user, pw)
        if res.get("success"):
            if security_manager:
                security_manager.reset_login_failures(client_ip)
            return (200, res, 0)
        else:
            if security_manager:
                security_manager.record_login_failure(client_ip)
            return (401, res, 0)

    if parsed_path == "/auth/send-otp":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        email = str(payload.get("email", "")).strip().lower()
        purpose = str(payload.get("purpose", "register")).strip().lower()
        if not email or "@" not in email or "." not in email:
            return (400, {"success": False, "error": "Please enter a valid email address."}, 0)
        if purpose not in ("register", "forgot_password"):
            return (400, {"success": False, "error": "Invalid verification purpose."}, 0)
        now = time.time()
        with _otp_lock:
            rec = _otp_store.get(email)
            if rec and now - rec.get("last_sent", 0) < 30.0:
                wait_s = int(30.0 - (now - rec.get("last_sent", 0)))
                return (429, {
                    "success": False,
                    "error": f"Please wait {wait_s}s before requesting another verification code."
                }, 0)
        if purpose == "register":
            if db.check_email_exists(email):
                return (400, {
                    "success": False,
                    "error": "This email is already registered. Please sign in or reset your password."
                }, 0)
        elif purpose == "forgot_password":
            if not db.check_email_exists(email):
                return (404, {
                    "success": False,
                    "error": "No account associated with this email address was found."
                }, 0)
        otp_code = f"{random.randint(100000, 999999)}"
        with _otp_lock:
            _otp_store[email] = {
                "code": otp_code,
                "expires_at": now + 600.0,
                "purpose": purpose,
                "last_sent": now,
                "verified": False
            }
        log.info("[AUTH OTP] Generated %s OTP for %s: %s (expires in 10m)", purpose.upper(), email, otp_code)
        smtp_host = os.environ.get("SMTP_HOST")
        if smtp_host:
            try:
                import smtplib
                from email.mime.text import MIMEText
                smtp_port = int(os.environ.get("SMTP_PORT", 587))
                smtp_user = os.environ.get("SMTP_USER", "")
                smtp_pass = os.environ.get("SMTP_PASS", "")
                from_email = os.environ.get("SMTP_FROM", smtp_user or "noreply@sabongroosters.com")
                subject = "Sabong Roosters - Email Verification Code" if purpose == "register" else "Sabong Roosters - Password Reset Code"
                body_text = f"Your Sabong Roosters verification code is: {otp_code}\n\nThis code will expire in 10 minutes. If you did not request this code, please disregard this email."
                msg = MIMEText(body_text)
                msg["Subject"] = subject
                msg["From"] = from_email
                msg["To"] = email
                with smtplib.SMTP(smtp_host, smtp_port, timeout=5) as s:
                    s.starttls()
                    if smtp_user and smtp_pass:
                        s.login(smtp_user, smtp_pass)
                    s.send_message(msg)
                log.info("[AUTH OTP] Successfully dispatched email via SMTP to %s", email)
            except Exception as ex:
                log.warning("[AUTH OTP] SMTP dispatch failed (dev fallback active): %s", ex)
        return (200, {
            "success": True,
            "message": f"Verification code sent to {email}.",
            "dev_otp": otp_code
        }, 0)

    if parsed_path == "/auth/verify-otp":
        email = str(payload.get("email", "")).strip().lower()
        code = str(payload.get("otp") or payload.get("code", "")).strip()
        purpose = str(payload.get("purpose", "")).strip().lower()
        now = time.time()
        with _otp_lock:
            rec = _otp_store.get(email)
            if not rec or now > rec.get("expires_at", 0):
                return (400, {"success": False, "error": "Verification code has expired. Please request a new code."}, 0)
            if purpose and rec.get("purpose") != purpose:
                return (400, {"success": False, "error": "Invalid verification purpose."}, 0)
            if rec.get("code") != code:
                return (400, {"success": False, "error": "Incorrect verification code. Please check and try again."}, 0)
            rec["verified"] = True
        return (200, {"success": True, "message": "Email verified successfully."}, 0)

    if parsed_path == "/auth/register":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        if security_manager:
            allowed, retry_after = security_manager.check_registration(client_ip)
            if not allowed:
                return (429, {
                    "success": False,
                    "error": f"Registration rate limit reached. Please wait {retry_after}s before creating another account."
                }, retry_after)
        user = str(payload.get("username", "")).strip()
        email = str(payload.get("email", "")).strip().lower()
        pw = str(payload.get("password", ""))
        otp_code = str(payload.get("otp", "")).strip()
        if not email or "@" not in email or "." not in email:
            return (400, {"success": False, "error": "A valid email address is required to register."}, 0)
        if not otp_code:
            return (400, {"success": False, "error": "Email verification code (OTP) is required."}, 0)
        now = time.time()
        with _otp_lock:
            rec = _otp_store.get(email)
            if not rec or now > rec.get("expires_at", 0):
                return (400, {"success": False, "error": "Verification code has expired. Please request a new code."}, 0)
            if rec.get("purpose") != "register":
                return (400, {"success": False, "error": "Invalid verification code for registration."}, 0)
            if rec.get("code") != otp_code:
                return (400, {"success": False, "error": "Incorrect verification code. Please re-enter."}, 0)
            _otp_store.pop(email, None)
        res = db.register_player(user, email, pw)
        if res.get("success"):
            if security_manager:
                security_manager.record_registration(client_ip)
            return (200, res, 0)
        else:
            return (400, res, 0)

    if parsed_path == "/auth/reset-password":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        email = str(payload.get("email", "")).strip().lower()
        otp_code = str(payload.get("otp", "")).strip()
        new_password = str(payload.get("new_password", ""))
        if not email or not otp_code or not new_password:
            return (400, {"success": False, "error": "Email, verification code, and new password are required."}, 0)
        if len(new_password) < 6:
            return (400, {"success": False, "error": "New password must be at least 6 characters long."}, 0)
        now = time.time()
        with _otp_lock:
            rec = _otp_store.get(email)
            if not rec or now > rec.get("expires_at", 0):
                return (400, {"success": False, "error": "Verification code has expired. Please request a new code."}, 0)
            if rec.get("purpose") != "forgot_password":
                return (400, {"success": False, "error": "Invalid verification code for password reset."}, 0)
            if rec.get("code") != otp_code:
                return (400, {"success": False, "error": "Incorrect verification code. Please re-enter."}, 0)
            _otp_store.pop(email, None)
        res = db.reset_password(email, new_password)
        if res.get("success"):
            return (200, res, 0)
        else:
            return (400, res, 0)

    if parsed_path == "/bet/place":
        if not db:
            return (500, {"success": False, "error": "Database not configured"}, 0)
        pid = int(payload.get("player_id", 0))
        side = str(payload.get("side", "")).strip().upper()
        amount = int(payload.get("amount", 0))
        room_code = str(payload.get("room_code", "")).upper()
        if amount <= 0:
            return (400, {"success": False, "error": "Bet amount must be greater than 0"}, 0)
        if side not in ["MERON", "WALA"]:
            return (400, {"success": False, "error": "Side must be MERON or WALA"}, 0)
        res = db.place_bet(pid, side, amount)
        if res.get("success") and room_code in rooms:
            r = rooms[room_code]
            r.bets.append({
                "player_id": pid,
                "username": payload.get("username", "Spectator"),
                "side": side.upper(),
                "amount": amount
            })
            if async_loop and not async_loop.is_closed():
                asyncio.run_coroutine_threadsafe(
                    _broadcast_room(r, json.dumps({
                        "type": "bet_pool_updated",
                        "meron_pool": r.get_meron_pool(),
                        "wala_pool": r.get_wala_pool(),
                        "new_bet": {"side": side.upper(), "amount": amount, "user": payload.get("username", "Spectator")}
                    })),
                    async_loop
                )
        return (200 if res.get("success") else 400, res, 0)

    return (404, {"error": "Not found"}, 0)

class UnifiedServerHandler(BaseHTTPRequestHandler):
    """
    Unified HTTP Server Handler:
      1. Serves pre-compressed Godot 4 Web client assets (.pck.gz, .wasm.gz, .js.gz)
         via standard OS sockets in chunked streams without the 10s timeout truncation.
      2. Handles all REST API routes (/health, /rooms, /leaderboard, /auth/*, /bet/*).
      3. Seamlessly bridges WebSocket upgrade requests (ws://) to the internal WebSocket relay.
    """
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")

    def _send_coop_coep_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")

    def address_string(self) -> str:
        return str(self.client_address[0]) if self.client_address else "127.0.0.1"

    def _get_client_ip(self) -> str:
        fallback = self.client_address[0] if self.client_address else "127.0.0.1"
        if security_manager:
            return security_manager.extract_ip_from_headers(self.headers, fallback)
        return fallback

    def _send_json(self, status: int, data: Any, retry_after: int = 0):
        body = json.dumps(data, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        if retry_after > 0:
            self.send_header("Retry-After", str(retry_after))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _handle_websocket_proxy(self):
        client_ip = self._get_client_ip()
        try:
            ws_backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            ws_backend.connect(("127.0.0.1", INTERNAL_WS_PORT))
        except Exception as e:
            log.error("Failed to connect to internal WebSocket relay on port %d: %s", INTERNAL_WS_PORT, e)
            self.send_error(502, "Bad Gateway: WebSocket server unavailable")
            return

        # Forward handshake request line and headers, ensuring client IP is preserved
        req_lines = [f"{self.command} {self.path} {self.request_version}\r\n"]
        has_xff = False
        for k, v in self.headers.items():
            if k.lower() == "x-forwarded-for":
                req_lines.append(f"{k}: {v}, {client_ip}\r\n")
                has_xff = True
            else:
                req_lines.append(f"{k}: {v}\r\n")
        if not has_xff:
            req_lines.append(f"X-Forwarded-For: {client_ip}\r\n")
        req_lines.append("\r\n")

        try:
            ws_backend.sendall("".join(req_lines).encode("latin-1"))
        except Exception as e:
            log.error("Failed sending handshake to internal backend: %s", e)
            try:
                ws_backend.close()
            except Exception:
                pass
            return

        client_sock = self.connection

        def pipe(src, dst):
            try:
                while True:
                    buf = src.recv(65536)
                    if not buf:
                        break
                    dst.sendall(buf)
            except Exception:
                pass
            finally:
                try:
                    dst.shutdown(socket.SHUT_WR)
                except Exception:
                    pass

        t1 = threading.Thread(target=pipe, args=(client_sock, ws_backend), daemon=True)
        t2 = threading.Thread(target=pipe, args=(ws_backend, client_sock), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
        try:
            ws_backend.close()
        except Exception:
            pass
        self.close_connection = True

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        is_ws = (
            self.headers.get("Upgrade", "").lower() == "websocket"
            or "upgrade" in self.headers.get("Connection", "").lower()
        )
        if is_ws:
            self._handle_websocket_proxy()
            return

        _cleanup_old_rooms()
        parsed_path = self.path.split("?")[0]
        client_ip = self._get_client_ip()

        # 1. Health check
        if parsed_path == "/health":
            db_ok = db.test_connection() if db else False
            self._send_json(200, {
                "status": "ok",
                "database": "connected" if db_ok else "disconnected",
                "rooms": len(rooms)
            })
            return

        # 2. Rate limiting on API routes
        is_api = (
            parsed_path in ["/rooms", "/leaderboard", "/bet/place"]
            or parsed_path.startswith("/auth/")
            or parsed_path.startswith("/admin/")
        )
        if is_api and security_manager:
            allowed, retry_after = security_manager.check_general_api(client_ip)
            if not allowed:
                self._send_json(429, {"success": False, "error": f"API rate limit reached. Please wait {retry_after}s."}, retry_after=retry_after)
                return

        if parsed_path == "/rooms":
            room_list = [r.to_dict() for r in rooms.values() if not r.closed]
            self._send_json(200, room_list)
            return

        if parsed_path == "/leaderboard":
            lb = _get_cached_leaderboard(20)
            self._send_json(200, lb)
            return

        # 3. Static Web Client Asset Serving from exports/web/
        clean_path = parsed_path.lstrip("/")
        if not clean_path:
            clean_path = "index.html"

        target_file = os.path.abspath(os.path.join(WEB_DIR, clean_path))
        if target_file.startswith(os.path.abspath(WEB_DIR)):
            accept_enc = self.headers.get("Accept-Encoding", "").lower()
            use_gzip = "gzip" in accept_enc and os.path.isfile(target_file + ".gz")
            file_to_serve = (target_file + ".gz") if use_gzip else target_file

            if os.path.isfile(file_to_serve):
                ext = os.path.splitext(clean_path)[1].lower()
                mime = MIME_TYPES.get(ext, "application/octet-stream")
                file_size = os.path.getsize(file_to_serve)

                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(file_size))
                self._send_cors_headers()
                self._send_coop_coep_headers()
                if use_gzip:
                    self.send_header("Content-Encoding", "gzip")
                if clean_path == "index.html":
                    self.send_header("Cache-Control", "no-cache")
                else:
                    self.send_header("Cache-Control", "public, max-age=86400")
                self.end_headers()

                # Chunked streaming via OS socket to guarantee 100% download without timeout
                with open(file_to_serve, "rb") as f:
                    while chunk := f.read(512 * 1024):
                        self.wfile.write(chunk)
                return

        self._send_json(404, {"error": "Not found"})

    def do_HEAD(self):
        parsed_path = self.path.split("?")[0]
        clean_path = parsed_path.lstrip("/")
        if not clean_path:
            clean_path = "index.html"

        target_file = os.path.abspath(os.path.join(WEB_DIR, clean_path))
        if target_file.startswith(os.path.abspath(WEB_DIR)):
            accept_enc = self.headers.get("Accept-Encoding", "").lower()
            use_gzip = "gzip" in accept_enc and os.path.isfile(target_file + ".gz")
            file_to_serve = (target_file + ".gz") if use_gzip else target_file

            if os.path.isfile(file_to_serve):
                ext = os.path.splitext(clean_path)[1].lower()
                mime = MIME_TYPES.get(ext, "application/octet-stream")
                file_size = os.path.getsize(file_to_serve)

                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(file_size))
                self._send_cors_headers()
                self._send_coop_coep_headers()
                if use_gzip:
                    self.send_header("Content-Encoding", "gzip")
                self.end_headers()
                return

        self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        client_ip = self._get_client_ip()

        if security_manager and content_length > security_manager.MAX_PAYLOAD_BYTES:
            log.warning("Rejected oversized payload (%d bytes) from IP %s", content_length, client_ip)
            self._send_json(413, {"success": False, "error": f"Payload too large (max {security_manager.MAX_PAYLOAD_BYTES // 1024} KB)"})
            return

        body = self.rfile.read(content_length).decode("utf-8") if content_length > 0 else "{}"
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}

        parsed_path = self.path.split("?")[0]
        status, resp_data, retry_after = handle_api_post(parsed_path, payload, client_ip)
        self._send_json(status, resp_data, retry_after=retry_after)

    def log_message(self, format, *args):
        pass

def start_http_server():
    server_address = ("0.0.0.0", API_PORT)
    httpd = ThreadingHTTPServer(server_address, UnifiedServerHandler)
    log.info("Dedicated REST API Server running on port %d", API_PORT)
    httpd.serve_forever()

async def ws_handler(websocket: WebSocketServerProtocol, path: str) -> None:
    client_ip = _extract_client_ip(websocket)
    cur_conns = _increment_ws_ip(client_ip)
    try:
        if security_manager and not security_manager.can_open_ws_connection(client_ip, cur_conns):
            log.warning("Rejecting WebSocket from IP %s (Too many connections: %d)", client_ip, cur_conns)
            try:
                await websocket.send(json.dumps({"type": "error", "msg": "Too many concurrent connections from your IP"}))
                await websocket.close(1008, "Too many connections")
            except Exception:
                pass
            return

        parts = path.strip("/").split("/")
        if len(parts) < 3 or parts[0] != "ws":
            await websocket.close(1008, "Invalid path")
            return
        code_or_new = parts[1].upper()
        role = parts[2].lower()

        if code_or_new == "NEW" and role == "host":
            host_public_ip = _extract_client_ip(websocket)
            try:
                raw = await asyncio.wait_for(websocket.recv(), timeout=10)
                data = json.loads(raw)
                host_name = str(data.get("host_name", "Anonymous"))[:32]
                host_local_ip = str(data.get("local_ip", ""))
                host_port = int(data.get("port", 7777))
                mode = str(data.get("mode", "duel")).lower()
                if mode not in ["duel", "tournament"]:
                    mode = "duel"
                max_players = int(data.get("max_players", 2 if mode == "duel" else 8))
                max_players = max(2, min(16, max_players))
            except Exception:
                host_name = "Anonymous"
                host_local_ip = ""
                host_port = 7777
                mode = "duel"
                max_players = 2

            code = _generate_code()
            room = Room(code, host_name, host_public_ip, host_local_ip, host_port, mode, max_players)
            room.host_ws = websocket
            rooms[code] = room
            log.info("Room %s (%s, max %d) created by '%s'", code, mode, max_players, host_name)
            await websocket.send(json.dumps({"type": "room_created", "code": code, "mode": mode, "max_players": max_players}))
            await _host_loop(room, websocket)
            return

        if role == "join":
            code = code_or_new
            if code not in rooms:
                await websocket.send(json.dumps({"type": "error", "msg": "Room not found"}))
                await websocket.close(1008, "Room not found")
                return
            room = rooms[code]
            if not room.is_open():
                await websocket.send(json.dumps({"type": "error", "msg": "Room already full or in match"}))
                await websocket.close(1008, "Room full")
                return
            if room.host_ws is None:
                await websocket.send(json.dumps({"type": "error", "msg": "Host not connected"}))
                await websocket.close(1008, "No host")
                return
            
            client_public_ip = _extract_client_ip(websocket)
            chosen_ip = room.host_local_ip if (client_public_ip and client_public_ip == room.host_public_ip and room.host_local_ip) else (room.host_public_ip or room.host_local_ip)

            room.clients.append(websocket)
            if room.mode == "duel":
                room.started = True

            log.info("Room %s (%s): contender joined. Total contenders: %d", code, room.mode, len(room.clients))
            await room.host_ws.send(json.dumps({
                "type": "client_joined",
                "client_ip": client_public_ip,
                "client_index": len(room.clients),
                "total_clients": len(room.clients)
            }))
            await websocket.send(json.dumps({
                "type": "host_ready",
                "host_ip": chosen_ip,
                "host_public_ip": room.host_public_ip,
                "host_local_ip": room.host_local_ip,
                "host_port": room.host_port,
                "mode": room.mode,
                "player_number": len(room.clients) + 1
            }))
            await _client_loop(room, websocket)
            return

        if role == "spectate":
            code = code_or_new
            if code not in rooms:
                await websocket.send(json.dumps({"type": "error", "msg": "Room not found"}))
                await websocket.close(1008, "Room not found")
                return
            room = rooms[code]
            if not room.can_spectate():
                await websocket.send(json.dumps({"type": "error", "msg": "Match has ended or closed"}))
                await websocket.close(1008, "Match ended")
                return

            room.spectators.append(websocket)
            log.info("Room %s: new spectator connected. Total spectators: %d", code, len(room.spectators))
            
            # Send initial spectate status with dynamic odds
            m_odds, w_odds = room.get_odds()
            await websocket.send(json.dumps({
                "type": "spectate_joined",
                "code": room.code,
                "host": room.host_name,
                "mode": room.mode,
                "status": "IN_PROGRESS" if room.started else "WAITING",
                "meron_rooster": room.meron_rooster,
                "wala_rooster": room.wala_rooster,
                "meron_pool": room.get_meron_pool(),
                "wala_pool": room.get_wala_pool(),
                "meron_odds": m_odds,
                "wala_odds": w_odds,
                "spectators_count": len(room.spectators)
            }))

            # Broadcast updated spectator count to ALL connected (host, clients, spectators)
            await _broadcast_room(room, json.dumps({
                "type": "spectator_count",
                "count": len(room.spectators)
            }), include_clients=True, include_spectators=True, include_host=True)

            await _spectator_loop(room, websocket)
            return

        await websocket.close(1008, "Unknown role")
    finally:
        _decrement_ws_ip(client_ip)

async def _broadcast_room(room: Room, message_str: str, include_clients: bool = True, include_spectators: bool = True, include_host: bool = False):
    targets = []
    if include_host and room.host_ws:
        targets.append(room.host_ws)
    if include_clients:
        targets.extend(room.clients)
    if include_spectators:
        targets.extend(room.spectators)

    for ws in list(targets):
        if not ws.closed:
            try:
                await ws.send(message_str)
            except Exception:
                pass

async def _host_loop(room: Room, host_ws: WebSocketServerProtocol) -> None:
    try:
        async for message in host_ws:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "start_tournament":
                    room.started = True
                    log.info("Room %s: tournament started by host", room.code)

                elif msg_type == "match_ready":
                    room.started = True
                    room.meron_rooster = data.get("p1_rooster_id", "")
                    room.wala_rooster = data.get("p2_rooster_id", "")
                    log.info("Room %s match started: %s (Meron) vs %s (Wala)", room.code, room.meron_rooster, room.wala_rooster)

                elif msg_type == "duel_finished":
                    winner_side = data.get("winner", "MERON").upper()
                    room.winner = winner_side
                    log.info("Room %s: match finished! Winner: %s", room.code, winner_side)
                    
                    m_odds, w_odds = room.get_odds()
                    winning_odds = m_odds if winner_side == "MERON" else w_odds

                    # Settle all bets with dynamic odds
                    payouts = db.resolve_bets(winner_side, room.bets, winning_odds) if db else []
                    
                    # Broadcast victory & bet payouts to everyone (including host)
                    finish_payload = json.dumps({
                        "type": "match_finished",
                        "winner": winner_side,
                        "payouts": payouts,
                        "winning_odds": winning_odds,
                        "meron_pool": room.get_meron_pool(),
                        "wala_pool": room.get_wala_pool()
                    })
                    await _broadcast_room(room, finish_payload, include_clients=True, include_spectators=True, include_host=True)

            except Exception as e:
                log.error("Error processing host message: %s", e)

            # Broadcast host game events to clients and spectators
            await _broadcast_room(room, message, include_clients=True, include_spectators=True)

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        log.info("Room %s: host disconnected", room.code)
        room.closed = True

        # Escrow protection: If host disconnects mid-match before winner declared, refund all bets
        if room.bets and room.winner is None:
            log.info("Room %s: Host disconnected mid-match. Automatically refunding %d bets in escrow...", room.code, len(room.bets))
            refund_payouts = db.resolve_bets("REFUND", room.bets, 1.0) if db else []
            refund_msg = json.dumps({
                "type": "match_finished",
                "winner": "REFUND",
                "payouts": refund_payouts,
                "winning_odds": 1.0,
                "reason": "Host disconnected mid-match"
            })
            await _broadcast_room(room, refund_msg, include_clients=True, include_spectators=True)

        close_msg = json.dumps({"type": "host_left"})
        await _broadcast_room(room, close_msg, include_clients=True, include_spectators=True)
        for ws in list(room.clients) + list(room.spectators):
            try:
                await ws.close()
            except Exception:
                pass

async def _client_loop(room: Room, client_ws: WebSocketServerProtocol) -> None:
    try:
        async for message in client_ws:
            if room.host_ws and not room.host_ws.closed:
                await room.host_ws.send(message)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        log.info("Room %s: a contender disconnected", room.code)
        if client_ws in room.clients:
            room.clients.remove(client_ws)
        if room.host_ws and not room.host_ws.closed:
            try:
                await room.host_ws.send(json.dumps({"type": "client_left", "total_clients": len(room.clients)}))
            except Exception:
                pass
        if room.mode == "duel":
            room.closed = True

async def _spectator_loop(room: Room, spec_ws: WebSocketServerProtocol) -> None:
    try:
        async for message in spec_ws:
            try:
                data = json.loads(message)
                if data.get("type") == "place_bet":
                    pid = int(data.get("player_id", 0))
                    side = str(data.get("side", "")).strip().upper()
                    amt = int(data.get("amount", 0))
                    user = str(data.get("username", "Spectator"))

                    if amt <= 0:
                        await spec_ws.send(json.dumps({"type": "bet_rejected", "error": "Bet amount must be greater than 0"}))
                        continue
                    if side not in ["MERON", "WALA"]:
                        await spec_ws.send(json.dumps({"type": "bet_rejected", "error": "Invalid side (must be MERON or WALA)"}))
                        continue

                    bet_ok = False
                    new_bal = 1000 - amt
                    if db and pid > 0:
                        res = db.place_bet(pid, side, amt)
                        if res.get("success"):
                            bet_ok = True
                            new_bal = res.get("new_balance", 0)
                        elif "Player not found" in res.get("error", ""):
                            # Allow guest / simulation players in-memory escrow
                            bet_ok = True
                        else:
                            await spec_ws.send(json.dumps({"type": "bet_rejected", "error": res.get("error")}))
                            continue
                    else:
                        bet_ok = True

                    if bet_ok:
                        room.bets.append({
                            "player_id": pid,
                            "username": user,
                            "side": side,
                            "amount": amt
                        })
                        await spec_ws.send(json.dumps({"type": "bet_confirmed", "side": side, "amount": amt, "new_balance": new_bal}))
                        m_odds, w_odds = room.get_odds()
                        await _broadcast_room(room, json.dumps({
                            "type": "bet_pool_updated",
                            "meron_pool": room.get_meron_pool(),
                            "wala_pool": room.get_wala_pool(),
                            "meron_odds": m_odds,
                            "wala_odds": w_odds
                        }), include_clients=True, include_spectators=True, include_host=True)
            except Exception as e:
                log.error("Spectator message error: %s", e)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        if spec_ws in room.spectators:
            room.spectators.remove(spec_ws)
        log.info("Room %s: spectator disconnected, remaining: %d", room.code, len(room.spectators))
        await _broadcast_room(room, json.dumps({
            "type": "spectator_count",
            "count": len(room.spectators)
        }), include_clients=True, include_spectators=True, include_host=True)

async_loop = None

async def main():
    global async_loop
    async_loop = asyncio.get_running_loop()

    # Start dedicated REST API server if API_PORT differs from PORT (e.g. local desktop dev)
    if API_PORT != PORT:
        http_thread = threading.Thread(target=start_http_server, daemon=True)
        http_thread.start()

    # Start Unified HTTP Server on the public PORT (Handles Web Client, REST API, & WS Proxy)
    unified_server = ThreadingHTTPServer(("0.0.0.0", PORT), UnifiedServerHandler)
    unified_thread = threading.Thread(target=unified_server.serve_forever, daemon=True)
    unified_thread.start()
    log.info("Sabong Roosters Unified Web, REST & Relay Server running on port %d", PORT)

    # Launch internal WebSocket relay on loopback INTERNAL_WS_PORT
    log.info("Sabong Roosters Internal WebSocket Relay running on 127.0.0.1:%d", INTERNAL_WS_PORT)
    async with websockets.serve(ws_handler, "127.0.0.1", INTERNAL_WS_PORT, ping_interval=20, ping_timeout=60, max_size=10*1024*1024):
        log.info("Relay & Matchmaking ready.")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
