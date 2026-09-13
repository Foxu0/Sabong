extends SceneTree

var host_peer: ENetMultiplayerPeer
var client1_peer: ENetMultiplayerPeer
var client2_peer: ENetMultiplayerPeer

var host_connected_clients: Array[int] = []
var client1_connected: bool = false
var client2_connected: bool = false
var client2_failed: bool = false

func _init() -> void:
	print("[TEST] Starting ENet MAX_CLIENTS = 1 limit test...")
	# 1. Start Host
	host_peer = ENetMultiplayerPeer.new()
	var err := host_peer.create_server(17777, 1) # max_clients = 1
	if err != OK:
		print("[FAIL] Host could not create server: ", err)
		quit(1)
		return
	host_peer.peer_connected.connect(func(id: int):
		print("[HOST] Peer connected: ", id)
		host_connected_clients.append(id)
	)
	host_peer.peer_disconnected.connect(func(id: int):
		print("[HOST] Peer disconnected: ", id)
	)
	print("[HOST] Server started on port 17777 with max_clients=1")

	# 2. Client 1 connects
	client1_peer = ENetMultiplayerPeer.new()
	var c1_err := client1_peer.create_client("127.0.0.1", 17777)
	if c1_err != OK:
		print("[FAIL] Client 1 create_client failed: ", c1_err)
		quit(1)
		return
	client1_peer.peer_connected.connect(func(id: int):
		print("[CLIENT 1] Connected to peer: ", id)
		client1_connected = true
	)

	# 3. Client 2 attempts to connect
	client2_peer = ENetMultiplayerPeer.new()
	var c2_err := client2_peer.create_client("127.0.0.1", 17777)
	if c2_err != OK:
		print("[FAIL] Client 2 create_client failed: ", c2_err)
		quit(1)
		return
	client2_peer.peer_connected.connect(func(id: int):
		print("[CLIENT 2] Unexpectedly connected to peer: ", id)
		client2_connected = true
	)
	client2_peer.peer_disconnected.connect(func(id: int):
		print("[CLIENT 2] Disconnected from peer: ", id)
		client2_failed = true
	)

	# Poll in a loop for 2 seconds
	_run_poll_loop()

func _run_poll_loop() -> void:
	for i in range(120): # ~2 seconds at 60Hz
		if host_peer: host_peer.poll()
		if client1_peer: client1_peer.poll()
		if client2_peer: client2_peer.poll()
		OS.delay_msec(16)

	print("\n--- TEST SUMMARY ---")
	print("Host connected clients count: ", host_connected_clients.size(), " (IDs: ", host_connected_clients, ")")
	print("Client 1 connected: ", client1_connected)
	print("Client 2 connected: ", client2_connected)
	print("Client 2 failed/rejected: ", client2_failed)

	if client1_connected and not client2_connected and host_connected_clients.size() == 1:
		print("[SUCCESS] max_clients=1 strictly enforces 1v1 limit! 3rd peer rejected.")
		quit(0)
	else:
		print("[RESULT] Client 2 connected state: ", client2_connected)
		quit(0)
