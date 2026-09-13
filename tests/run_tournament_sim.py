import subprocess
import time
import os
import sys

GODOT_BIN = r"D:\Downloads\Godot_v4.7.1-stable_win64_console.exe"
PROJECT_DIR = r"D:\Games\sabong_roosters - Copy"

def run_tournament_sim():
    print("=== STARTING MULTI-PLAYER TOURNAMENT HEADLESS SIMULATION ===")
    print("Participants: Host (Goku) + Alice (Vegeta) + Bob (Cocktaro)")
    print("Expected: 3 Players -> 4-Slot Bracket with 1 Bye in SF1, SF2 active duel, GF Finals.")

    host_log = open("tests/tourney_host.log", "w", encoding="utf-8")
    c1_log = open("tests/tourney_c1.log", "w", encoding="utf-8")
    c2_log = open("tests/tourney_c2.log", "w", encoding="utf-8")

    # 1. Start Host
    print("\n[LAUNCH] Starting Tournament Host...", flush=True)
    host_proc = subprocess.Popen(
        [GODOT_BIN, "--headless", "tests/sim_tourney_host.tscn"],
        cwd=PROJECT_DIR,
        stdout=host_log,
        stderr=subprocess.STDOUT,
        text=True
    )

    time.sleep(2.0)

    # 2. Start Client 1 (Alice)
    print("[LAUNCH] Starting Client 1 (Alice)...", flush=True)
    env_alice = os.environ.copy()
    env_alice["CLIENT_NAME"] = "Alice"
    env_alice["CLIENT_ROOSTER"] = "decluck"
    env_alice["CLIENT_CARD"] = "decluck_all_for_one_punch"
    client1_proc = subprocess.Popen(
        [GODOT_BIN, "--headless", "tests/sim_tourney_client.tscn"],
        cwd=PROJECT_DIR,
        stdout=c1_log,
        stderr=subprocess.STDOUT,
        env=env_alice,
        text=True
    )

    time.sleep(1.0)

    # 3. Start Client 2 (Bob)
    print("[LAUNCH] Starting Client 2 (Bob)...", flush=True)
    env_bob = os.environ.copy()
    env_bob["CLIENT_NAME"] = "Bob"
    env_bob["CLIENT_ROOSTER"] = "cocktaro"
    env_bob["CLIENT_CARD"] = "cocktaro_stand_barrage"
    client2_proc = subprocess.Popen(
        [GODOT_BIN, "--headless", "tests/sim_tourney_client.tscn"],
        cwd=PROJECT_DIR,
        stdout=c2_log,
        stderr=subprocess.STDOUT,
        env=env_bob,
        text=True
    )

    # Wait for completion (max 20 seconds)
    print("\n[SIMULATION] Waiting for tournament flow to resolve...", flush=True)
    start_time = time.time()
    while time.time() - start_time < 25:
        if host_proc.poll() is not None:
            break
        time.sleep(0.5)

    host_proc.poll()
    client1_proc.poll()
    client2_proc.poll()

    if host_proc.returncode is None:
        host_proc.kill()
    if client1_proc.returncode is None:
        client1_proc.kill()
    if client2_proc.returncode is None:
        client2_proc.kill()

    host_log.close()
    c1_log.close()
    c2_log.close()

    with open("tests/tourney_host.log", "r", encoding="utf-8") as f:
        host_out = f.read()
    with open("tests/tourney_c1.log", "r", encoding="utf-8") as f:
        client1_out = f.read()
    with open("tests/tourney_c2.log", "r", encoding="utf-8") as f:
        client2_out = f.read()

    print("\n=================== HOST LOG ===================")
    print(host_out)
    print("\n================= ALICE (C1) LOG =================")
    print(client1_out)
    print("\n================== BOB (C2) LOG ==================")
    print(client2_out)

    print("Host exit code:", host_proc.returncode)
    print("Alice exit code:", client1_proc.returncode)
    print("Bob exit code:", client2_proc.returncode)

    assert host_proc.returncode == 0, "Host failed!"
    assert "[HOST_SUCCESS]" in host_out, "Host did not report success!"
    print("\n>>> ALL MULTI-PLAYER TOURNAMENT TESTS PASSED WITH 100% SUCCESS! <<<")

if __name__ == "__main__":
    run_tournament_sim()
