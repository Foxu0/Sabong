import subprocess
import time
import re
import sys
import os

GODOT_BIN = r"D:\Downloads\Godot_v4.7.1-stable_win64_console.exe"

def run_simulation():
    print("=========================================================")
    print("SABONG ROOSTERS: 1 HOST + MULTIPLE PLAYERS FULL SIMULATION")
    print("=========================================================\n")

    host_log_path = "tests/sim_host.log"
    c1_log_path = "tests/sim_c1.log"
    c3_log_path = "tests/sim_c3.log"

    for p in [host_log_path, c1_log_path, c3_log_path]:
        if os.path.exists(p):
            os.remove(p)

    with open(host_log_path, "w", encoding="utf-8") as hf, \
         open(c1_log_path, "w", encoding="utf-8") as c1f, \
         open(c3_log_path, "w", encoding="utf-8") as c3f:

        print("[STEP 1] Starting Host scene (res://tests/sim_host.tscn)...")
        p_host = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_host.tscn"], stdout=hf, stderr=subprocess.STDOUT)
        time.sleep(1.2) # Allow host to bind port 17782

        print("[STEP 2] Starting Client 1 scene (res://tests/sim_client.tscn)...")
        p_c1 = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_client.tscn"], stdout=c1f, stderr=subprocess.STDOUT)
        time.sleep(0.5)

        print("[STEP 3] Starting Client 3 scene (res://tests/sim_client3.tscn)...")
        p_c3 = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_client3.tscn"], stdout=c3f, stderr=subprocess.STDOUT)

        # Wait for all processes to finish (max 6 seconds)
        start_t = time.time()
        while time.time() - start_t < 7.0:
            if p_host.poll() is not None and p_c1.poll() is not None and p_c3.poll() is not None:
                break
            time.sleep(0.2)

        p_c3.terminate()
        p_c1.terminate()
        p_host.terminate()

    with open(host_log_path, "r", encoding="utf-8") as hf:
        host_out = hf.read()
    with open(c1_log_path, "r", encoding="utf-8") as c1f:
        c1_out = c1f.read()
    with open(c3_log_path, "r", encoding="utf-8") as c3f:
        c3_out = c3f.read()

    print("\n------------------ HOST OUTPUT ------------------")
    print(host_out.strip())

    print("\n----------------- CLIENT 1 OUTPUT ---------------")
    print(c1_out.strip())

    print("\n----------------- CLIENT 3 OUTPUT ---------------")
    print(c3_out.strip())

    print("\n================ VERIFICATION CHECKS ================")

    # 1. Check 3rd player rejection
    assert "[CLIENT3_BLOCKED]" in c3_out or "Rejecting extra peer" in host_out, "Client 3 must be rejected!"
    print(" Check 1: 3rd player was successfully blocked/rejected from 1v1 match.")

    # 2. Check Match Ready on both Host and Client 1
    assert "MATCH READY" in host_out, "Host should reach MATCH READY"
    assert "MATCH READY" in c1_out, "Client 1 should reach MATCH READY"
    print(" Check 2: Rooster selection synchronized between Host & Client 1.")

    # 3. Check Dice Rolls
    assert "Broadcasting dice rolls" in host_out, "Host should roll and broadcast dice"
    assert "Received dice rolls from host" in c1_out, "Client 1 should receive dice rolls"
    print(" Check 3: Dice rolls authoritatively broadcasted and received.")

    # 4. Check Authoritative Combat Resolution
    assert "[HOST_TURN_RESOLVED]" in host_out, "Host must resolve turn via CombatEngine"
    assert "[CLIENT_TURN_RESOLVED]" in c1_out, "Client 1 must receive resolved combat events"
    print(" Check 4: Host authoritatively executed CombatEngine turn.")

    # 5. Check Health Synchronization
    host_hp_match = re.search(r"P1_HP:\s*(\d+)\s*\|\s*P2_HP:\s*(\d+)", host_out)
    client_hp_match = re.search(r"P1_HP:\s*(\d+)\s*\|\s*P2_HP:\s*(\d+)", c1_out)

    assert host_hp_match, f"Host HP output not found in:\n{host_out}"
    assert client_hp_match, f"Client HP output not found in:\n{c1_out}"

    host_p1, host_p2 = host_hp_match.group(1), host_hp_match.group(2)
    client_p1, client_p2 = client_hp_match.group(1), client_hp_match.group(2)

    print(f" Check 5: HP State -> Host:[P1={host_p1}, P2={host_p2}] vs Client:[P1={client_p1}, P2={client_p2}]")
    assert host_p1 == client_p1 and host_p2 == client_p2, f"HP desync! Host: {host_p1}/{host_p2}, Client: {client_p1}/{client_p2}"
    print(" Check 6: Exact HP and combat state match between Host and Client (Zero desync!).")

    print("\n>>> ALL TESTS PASSED: 1 Host + Multiple Players verified thoroughly! <<<")

if __name__ == "__main__":
    run_simulation()
