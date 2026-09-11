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

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("sabong-relay")

# Config
PORT = int(os.environ.get("PORT", 10000))
ROOM_CODE_LENGTH = 4
ROOM_TIMEOUT_SECS = 300

# Room Registry
class Room:
    def __init__(self, code: str, host_name: str):
        self.code = code
        self.host_name = host_name
        self.created_at = time.time()
        self.host_ws: Optional[WebSocketServerProtocol] = None
        self.client_ws: Optional[WebSocketServerProtocol] = None
        self.started = False
        self.closed = False

    def is_open(self) -> bool:
        return self.host_ws is not None and not self.started and not self.closed

    def to_dict(self) -> dict:
        return {"code": self.code, "host_name": self.host_name, "created_at": int(self.created_at)}

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
    return None

async def ws_handler(websocket: WebSocketServerProtocol, path: str) -> None:
    parts = path.strip("/").split("/")
    if len(parts) < 3 or parts[0] != "ws":
        await websocket.close(1008, "Invalid path")
        return
    code_or_new = parts[1].upper()
    role = parts[2].lower()

    if code_or_new == "NEW" and role == "host":
        try:
            raw = await asyncio.wait_for(websocket.recv(), timeout=10)
            data = json.loads(raw)
            host_name = str(data.get("host_name", "Anonymous"))[:32]
        except Exception:
            host_name = "Anonymous"
        code = _generate_code()
        room = Room(code, host_name)
        room.host_ws = websocket
        rooms[code] = room
        log.info("Room %s created by '%s'", code, host_name)
        await websocket.send(json.dumps({"type": "room_created", "code": code}))
        await _host_loop(room, websocket)
        return

    if role == "join":
        code = code_or_new
        if code not in rooms:
            await websocket.send(json.dumps({"type": "error", "msg": "Room not found"}))
            await websocket.close(1008, "Room not found")
            return
        room = rooms[code]
        if room.started or room.closed:
            await websocket.send(json.dumps({"type": "error", "msg": "Room already full or closed"}))
            await websocket.close(1008, "Room full")
            return
        if room.host_ws is None:
            await websocket.send(json.dumps({"type": "error", "msg": "Host not connected"}))
            await websocket.close(1008, "No host")
            return
        room.client_ws = websocket
        room.started = True
        log.info("Room %s: client joined, starting relay", code)
        await room.host_ws.send(json.dumps({"type": "client_joined"}))
        await room.client_ws.send(json.dumps({"type": "host_ready"}))
        await _relay_loop(room)
        return

    await websocket.close(1008, "Unknown role")

async def _host_loop(room: Room, host_ws: WebSocketServerProtocol) -> None:
    try:
        async for message in host_ws:
            if room.started and room.client_ws and not room.client_ws.closed:
                await room.client_ws.send(message)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        log.info("Room %s: host disconnected", room.code)
        room.closed = True
        if room.client_ws and not room.client_ws.closed:
            await room.client_ws.send(json.dumps({"type": "host_left"}))
            await room.client_ws.close()

async def _relay_loop(room: Room) -> None:
    host_ws = room.host_ws
    client_ws = room.client_ws

    async def forward(src, dst, label: str):
        try:
            async for message in src:
                if not dst.closed:
                    await dst.send(message)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            log.info("Room %s: %s disconnected", room.code, label)
            room.closed = True
            if not dst.closed:
                await dst.send(json.dumps({"type": f"{label}_left"}))
                await dst.close()

    await asyncio.gather(forward(host_ws, client_ws, "host"), forward(client_ws, host_ws, "client"))

async def main():
    log.info("Sabong Roosters Relay starting on port %d", PORT)
    async with websockets.serve(ws_handler, "0.0.0.0", PORT, process_request=http_handler, ping_interval=20, ping_timeout=60, max_size=10*1024*1024):
        log.info("Server ready.")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
