import subprocess
import time

GODOT_BIN = r"D:\Downloads\Godot_v4.7.1-stable_win64_console.exe"

with open("tests/host.log", "w") as hf, open("tests/client1.log", "w") as c1f, open("tests/client3.log", "w") as c3f:
    p_host = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_host.tscn"], stdout=hf, stderr=subprocess.STDOUT)
    time.sleep(1.0)
    p_c1 = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_client.tscn"], stdout=c1f, stderr=subprocess.STDOUT)
    time.sleep(0.5)
    p_c3 = subprocess.Popen([GODOT_BIN, "--headless", "res://tests/sim_client3.tscn"], stdout=c3f, stderr=subprocess.STDOUT)

    time.sleep(5.0)

    p_c3.terminate()
    p_c1.terminate()
    p_host.terminate()

print("Debug run completed.")
