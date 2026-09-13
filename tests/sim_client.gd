extends SceneTree

var nm: Node = null
var p1_duelist: Duelist = null
var p2_duelist: Duelist = null

func _init() -> void:
	print("[CLIENT] Initializing client simulation...")
	var nm_script = load("res://scripts/NetworkManager.gd")
	nm = nm_script.new()
	root.add_child(nm)

	nm.player_connected.connect(_on_player_connected)
	nm.match_ready.connect(_on_match_ready)
	nm.dice_rolls_received.connect(_on_dice_rolls_received)
	nm.turn_received_from_host.connect(_on_turn_received_from_host)

	var err: int = nm.join_match("127.0.0.1", 17780)
	if err != OK:
		print("[CLIENT_ERROR] Failed to join host: ", err)
		quit(1)
		return
	print("[CLIENT] Connecting to host at 127.0.0.1:17780...")

func _on_player_connected(peer_id: int) -> void:
	print("[CLIENT] Connected to host! (local peer id: %d)" % nm.local_peer_id)
	# Client chooses Eren Pecker
	nm.submit_rooster_choice("eren_pecker")
	print("[CLIENT] Submitted rooster choice: eren_pecker")

func _on_match_ready(p1_id: String, p2_id: String) -> void:
	print("[CLIENT] MATCH READY: P1 = %s, P2 = %s" % [p1_id, p2_id])
	var r1: RoosterData = load("res://resources/roosters/%s.tres" % p1_id)
	var r2: RoosterData = load("res://resources/roosters/%s.tres" % p2_id)
	p1_duelist = Duelist.new(1, r1.display_name, r1)
	p2_duelist = Duelist.new(2, r2.display_name, r2)
	print("[CLIENT] Duelists initialized locally (P1 HP: %d, P2 HP: %d)" % [p1_duelist.hp, p2_duelist.hp])

func _on_dice_rolls_received(meron_roll: int, wala_roll: int) -> void:
	print("[CLIENT] Received dice rolls from host: Meron=%d, Wala=%d" % [meron_roll, wala_roll])
	# Client submits turn cards
	print("[CLIENT] Submitting client turn cards: ['eren_claw_stomp']")
	nm.submit_turn(["eren_claw_stomp"])

func _on_turn_received_from_host(events: Array) -> void:
	if events.is_empty():
		return # Empty signal is host-internal
	print("[CLIENT] Received %d combat events from authoritative host!" % events.size())
	for ev in events:
		if ev.has("p1_final_hp"):
			p1_duelist.hp = ev["p1_final_hp"]
		if ev.has("p2_final_hp"):
			p2_duelist.hp = ev["p2_final_hp"]

	print("[CLIENT_TURN_RESOLVED] Events: %d | P1_HP: %d | P2_HP: %d" % [events.size(), p1_duelist.hp, p2_duelist.hp])
	print("[CLIENT_SIM_COMPLETE] Client combat state synchronized with host.")

	var timer := create_timer(0.5)
	timer.timeout.connect(func():
		nm.disconnect_from_match()
		quit(0)
	)

func _process(_delta: float) -> bool:
	return false
