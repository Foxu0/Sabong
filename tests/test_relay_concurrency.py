import asyncio
import json
import websockets
import subprocess
import time
import sys

PORT = 10006

async def test_relay():
    print("--- [TEST 1] Testing 3rd Player Rejection on Full Room ---")
    # 1. Host creates room
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/new/host") as host_ws:
        await host_ws.send(json.dumps({"host_name": "HostPlayer", "local_ip": "127.0.0.1", "port": 7777}))
        host_msg = json.loads(await host_ws.recv())
        room_code = host_msg["code"]
        print(f"[HOST] Room created with code: {room_code}")

        # 2. Client 1 joins room
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{room_code}/join") as c1_ws:
            c1_ready = json.loads(await c1_ws.recv())
            host_notif = json.loads(await host_ws.recv())
            print(f"[CLIENT 1] Successfully paired with host (type: {c1_ready.get('type')})")
            print(f"[HOST] Received notification of client joining (type: {host_notif.get('type')})")

            # 3. Client 2 attempts to join the SAME room
            print("[CLIENT 2] Attempting to join full room...")
            try:
                async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{room_code}/join") as c2_ws:
                    c2_msg = json.loads(await c2_ws.recv())
                    print(f"[CLIENT 2] Received message: {c2_msg}")
                    assert c2_msg.get("type") == "error", f"Expected error, got {c2_msg}"
                    assert "full or closed" in c2_msg.get("msg", ""), f"Unexpected error message: {c2_msg}"
            except websockets.exceptions.ConnectionClosed as e:
                print(f"[CLIENT 2] Correctly rejected and closed with code {e.rcvd.code}: {e.rcvd.reason}")

    print(">>> TEST 1 PASSED: 3rd player was rejected by relay server!\n")

    print("--- [TEST 2] Testing Concurrent Multiple Rooms (Isolation) ---")
    # Host A creates Room A
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/new/host") as host_a:
        await host_a.send(json.dumps({"host_name": "Host_A", "local_ip": "127.0.0.1", "port": 7777}))
        code_a = json.loads(await host_a.recv())["code"]

        # Host B creates Room B
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/new/host") as host_b:
            await host_b.send(json.dumps({"host_name": "Host_B", "local_ip": "127.0.0.1", "port": 7778}))
            code_b = json.loads(await host_b.recv())["code"]

            print(f"Room A code: {code_a} | Room B code: {code_b}")
            assert code_a != code_b, "Room codes must be unique"

            # Client A joins Room A
            async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{code_a}/join") as client_a:
                # Client B joins Room B
                async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/{code_b}/join") as client_b:
                    ca_ready = json.loads(await client_a.recv())
                    cb_ready = json.loads(await client_b.recv())
                    print(f"Client A paired with Room A ({ca_ready.get('type')})")
                    print(f"Client B paired with Room B ({cb_ready.get('type')})")

                    # Cross-talk test: Send message in Room A, verify Room B does NOT get it
                    test_payload = json.dumps({"test": "hello_room_a"})
                    await host_a.send(test_payload)
                    recvd = await client_a.recv()
                    assert recvd == test_payload, "Client A should receive Room A message"
                    print("Client A received message from Host A.")

                    # Ensure client B has NOT received anything
                    try:
                        await asyncio.wait_for(client_b.recv(), timeout=0.3)
                        assert False, "Client B received cross-talk message!"
                    except asyncio.TimeoutError:
                        print("Client B received nothing (zero cross-talk confirmed).")

    print(">>> TEST 2 PASSED: Multiple concurrent rooms operate in complete isolation!\n")

if __name__ == "__main__":
    # Start temporary relay server on PORT
    import os
    env = os.environ.copy()
    env["PORT"] = str(PORT)
    proc = subprocess.Popen([sys.executable, "server.py"], env=env)
    time.sleep(1)
    try:
        asyncio.run(test_relay())
    finally:
        proc.terminate()
        proc.wait()
