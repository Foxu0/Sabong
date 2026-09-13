import asyncio
import json
import websockets
import subprocess
import time
import sys
import os
import urllib.request

PORT = 10007

async def test_tournament_relay():
    print("--- [TEST] Starting Multi-Client Tournament Relay Test ---")
    # 1. Host creates tournament room
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/new/host") as host_ws:
        await host_ws.send(json.dumps({
            "host_name": "MasterHost",
            "local_ip": "127.0.0.1",
            "port": 7777,
            "mode": "tournament",
            "max_players": 5 # 1 Host + 4 Clients
        }))
        created_msg = json.loads(await host_ws.recv())
        room_code = created_msg["code"]
        assert created_msg.get("mode") == "tournament", "Room mode must be tournament"
        assert created_msg.get("max_players") == 5, "Max players must be 5"
        print(f"[HOST] Created tournament room: {room_code} (max: 5)")

        # 2. Check HTTP /rooms endpoint
        req = urllib.request.urlopen(f"http://127.0.0.1:{PORT}/rooms")
        room_list = json.loads(req.read().decode())
        found = [r for r in room_list if r["code"] == room_code]
        assert len(found) == 1, "Tournament room should appear in /rooms"
        assert found[0]["mode"] == "tournament"
        assert found[0]["current_players"] == 1
        print("[REST API] /rooms listing verified:", found[0])

        # 3. Connect 4 clients
        clients = []
        for i in range(1, 5):
            c_ws = await websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{room_code}/join")
            c_ready = json.loads(await c_ws.recv())
            host_notif = json.loads(await host_ws.recv())
            assert c_ready.get("type") == "host_ready"
            assert c_ready.get("mode") == "tournament"
            assert host_notif.get("type") == "client_joined"
            assert host_notif.get("total_clients") == i
            clients.append(c_ws)
            print(f"[CLIENT {i}] Joined room {room_code}, total clients on host: {host_notif.get('total_clients')}")

        # 4. Attempt 5th client (should be rejected since max 5 players = 1 host + 4 clients)
        print("[CLIENT 5] Attempting to join full tournament room...")
        try:
            async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{room_code}/join") as c5_ws:
                msg = json.loads(await c5_ws.recv())
                assert msg.get("type") == "error"
                print(f"[CLIENT 5] Correctly rejected with error: {msg.get('msg')}")
        except websockets.exceptions.ConnectionClosed:
            print("[CLIENT 5] Connection closed as expected.")

        # 5. Broadcast message from Host to all 4 clients
        broadcast_payload = json.dumps({"type": "bracket_sync", "data": "dummy_bracket"})
        await host_ws.send(broadcast_payload)
        for idx, c_ws in enumerate(clients, 1):
            received = await asyncio.wait_for(c_ws.recv(), timeout=1.0)
            assert received == broadcast_payload
            print(f"[CLIENT {idx}] Successfully received host broadcast message!")

        # Clean up clients
        for c in clients:
            await c.close()

    print(">>> TOURNAMENT RELAY TEST PASSED 100%! <<<\n")

if __name__ == "__main__":
    env = os.environ.copy()
    env["PORT"] = str(PORT)
    proc = subprocess.Popen([sys.executable, "server.py"], env=env)
    time.sleep(1)
    try:
        asyncio.run(test_tournament_relay())
    finally:
        proc.terminate()
        proc.wait()
