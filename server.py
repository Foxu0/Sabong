"""
Sabong Roosters - Online Relay & Matchmaking Server
====================================================
Provides:
  GET  /rooms          ? JSON list of open (waiting) rooms
  POST /rooms          ? Create a new room; returns { room_code, ws_url }
  WS   /ws/new/host    ? Create room, become host; server sends back room code
  WS   /ws/{code}/join ? Join room as client and pair with host

Run locally:
    pip install websockets
    python server.py

Deploy on Render.com:
    Start command: python server.py
    Runtime: Python 3.11
    Port set via PORT env var (default 10000)
"""

import asyncio
import json
import logging
import os
import random
import string
import time
from typing import Optional

import websockets
from websockets.server import WebSocketServerProtocol

try:
    from db_manager import db
except ImportError:
    try:
        from scripts.db_manager import db
    except ImportError:
        db = None

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("sabong-relay")

# Config
PORT = int(os.environ.get("PORT", 10005))
ROOM_CODE_LENGTH = 4
ROOM_TIMEOUT_SECS = 300

def _extract_client_ip(ws: WebSocketServerProtocol) -> str:
    if hasattr(ws, "request_headers") and ws.request_headers:
        forwarded = ws.request_headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
        cf = ws.request_headers.get("cf-connecting-ip")
        if cf:
            return cf.strip()
    if ws.remote_address:
        return str(ws.remote_address[0])
    return ""

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
        self.clients: list[WebSocketServerProtocol] = []
        self.started = False
        self.closed = False

    def is_open(self) -> bool:
        if self.host_ws is None or self.started or self.closed:
            return False
        max_clients = 1 if self.mode == "duel" else max(1, self.max_players - 1)
        return len(self.clients) < max_clients

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "host": self.host_name,
            "mode": self.mode,
            "current_players": len(self.clients) + (1 if self.host_ws else 0),
            "max_players": self.max_players,
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

async def http_handler(path: str, request_headers) -> Optional[tuple]:
    _cleanup_old_rooms()
    if path == "/rooms" and request_headers.get("upgrade", "").lower() != "websocket":
        open_rooms = [r.to_dict() for r in rooms.values() if r.is_open()]
        body = json.dumps(open_rooms).encode()
        headers = [("Content-Type", "application/json"), ("Content-Length", str(len(body))), ("Access-Control-Allow-Origin", "*")]
        return (200, headers, body)
    if path == "/leaderboard" and request_headers.get("upgrade", "").lower() != "websocket":
        lb = db.get_leaderboard(20) if db else []
        body = json.dumps(lb, default=str).encode()
        headers = [("Content-Type", "application/json"), ("Content-Length", str(len(body))), ("Access-Control-Allow-Origin", "*")]
        return (200, headers, body)
    if path == "/health" and request_headers.get("upgrade", "").lower() != "websocket":
        db_ok = db.test_connection() if db else False
        body = json.dumps({"status": "ok", "database": "connected" if db_ok else "disconnected"}).encode()
        headers = [("Content-Type", "application/json"), ("Content-Length", str(len(body))), ("Access-Control-Allow-Origin", "*")]
        return (200, headers, body)
    return None

async def ws_handler(websocket: WebSocketServerProtocol, path: str) -> None:
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
        log.info("Room %s (%s, max %d) created by '%s' (pub=%s, local=%s:%d)", code, mode, max_players, host_name, host_public_ip, host_local_ip, host_port)
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
            await websocket.send(json.dumps({"type": "error", "msg": "Room already full or closed"}))
            await websocket.close(1008, "Room full")
            return
        if room.host_ws is None:
            await websocket.send(json.dumps({"type": "error", "msg": "Host not connected"}))
            await websocket.close(1008, "No host")
            return
        
        client_public_ip = _extract_client_ip(websocket)
        # If client and host share the same public IP (e.g. same home network/Wi-Fi),
        # use the host's LAN local IP to bypass router NAT loopback blocks.
        if client_public_ip and client_public_ip == room.host_public_ip and room.host_local_ip:
            chosen_ip = room.host_local_ip
            log.info("Room %s: client is on same LAN as host (%s), using local IP %s", code, client_public_ip, chosen_ip)
        else:
            chosen_ip = room.host_public_ip or room.host_local_ip
            log.info("Room %s: client joining from %s -> host at %s", code, client_public_ip, chosen_ip)

        room.clients.append(websocket)
        if room.mode == "duel":
            room.started = True

        log.info("Room %s (%s): client %d joined, total clients: %d", code, room.mode, len(room.clients), len(room.clients))
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

    await websocket.close(1008, "Unknown role")

async def _host_loop(room: Room, host_ws: WebSocketServerProtocol) -> None:
    try:
        async for message in host_ws:
            try:
                data = json.loads(message)
                if data.get("type") == "start_tournament":
                    room.started = True
                    log.info("Room %s: tournament started by host, room locked", room.code)
            except Exception:
                pass

            for client_ws in list(room.clients):
                if not client_ws.closed:
                    try:
                        await client_ws.send(message)
                    except Exception:
                        pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        log.info("Room %s: host disconnected", room.code)
        room.closed = True
        for client_ws in list(room.clients):
            if not client_ws.closed:
                try:
                    await client_ws.send(json.dumps({"type": "host_left"}))
                    await client_ws.close()
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
        log.info("Room %s: a client disconnected", room.code)
        if client_ws in room.clients:
            room.clients.remove(client_ws)
        if room.host_ws and not room.host_ws.closed:
            await room.host_ws.send(json.dumps({"type": "client_left", "total_clients": len(room.clients)}))
        if room.mode == "duel":
            room.closed = True

async def main():
    log.info("Sabong Roosters Relay starting on port %d", PORT)
    async with websockets.serve(ws_handler, "0.0.0.0", PORT, process_request=http_handler, ping_interval=20, ping_timeout=60, max_size=10*1024*1024):
        log.info("Server ready.")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
