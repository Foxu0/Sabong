extends Node

@onready var nm = get_node("/root/NetworkManager")
var p1_duelist: Duelist = null
var p2_duelist: Duelist = null
var match_started: bool = false

func _ready() -> void:
	print("[HOST] Initializing Sabong Roosters authoritative host simulation...")
	nm.player_connected.connect(_on_player_connected)
	nm.match_ready.connect(_on_match_ready)
	nm.turn_received_from_host.connect(_on_turn_received_from_host)

	var err: int = nm.host_match(17782)
	if err != OK:
		print("[HOST_ERROR] Failed to start host server on port 17782: ", err)
		get_tree().quit(1)
		return
	print("[HOST] Server listening on port 17782 with MAX_CLIENTS=1")

func _on_player_connected(peer_id: int) -> void:
	print("[HOST] Opponent connected with peer ID: ", peer_id)
	nm.submit_rooster_choice("hen_goku")
	print("[HOST] Submitted rooster choice: hen_goku")

func _on_match_ready(p1_id: String, p2_id: String) -> void:
	if match_started:
		return
	match_started = true
	print("[HOST] MATCH READY: P1 = %s, P2 = %s" % [p1_id, p2_id])
	var r1: RoosterData = load("res://resources/roosters/%s.tres" % p1_id)
	var r2: RoosterData = load("res://resources/roosters/%s.tres" % p2_id)
	p1_duelist = Duelist.new(1, r1.display_name, r1)
	p2_duelist = Duelist.new(2, r2.display_name, r2)
	nm.register_duelists(p1_duelist, p2_duelist)

	# Broadcast dice roll: Meron 6, Wala 3 (P1 has priority)
	print("[HOST] Broadcasting dice rolls: Meron=6, Wala=3")
	nm.broadcast_dice_rolls(6, 3)

	# Host locks turn cards
	var host_cards: Array[String] = ["hen_goku_kamecock"]
	print("[HOST] Submitting host turn cards: ", host_cards)
	nm.submit_turn(host_cards)

func _on_turn_received_from_host(events: Array) -> void:
	# Empty array emitted by NetworkManager when both turns are locked
	if events.is_empty():
		print("[HOST] Both players submitted cards! Authoritatively resolving combat via CombatEngine...")
		var resolved_events: Array[Dictionary] = CombatEngine.resolve_turn(
			p1_duelist,
			p2_duelist,
			1, # round 1
			1, # P1 priority
			false # not clash
		)
		print("[HOST] CombatEngine produced %d events. Broadcasting to client..." % resolved_events.size())
		nm.broadcast_turn_events(resolved_events)

		var final_p1_hp: int = p1_duelist.hp
		var final_p2_hp: int = p2_duelist.hp
		print("[HOST_TURN_RESOLVED] Events: %d | P1_HP: %d | P2_HP: %d" % [resolved_events.size(), final_p1_hp, final_p2_hp])

		# Wait 1.5s for client to receive and verify, then quit cleanly
		var timer := get_tree().create_timer(1.5)
		timer.timeout.connect(func():
			print("[HOST_SIM_COMPLETE] All game phases simulated successfully.")
			nm.disconnect_from_match()
			get_tree().quit(0)
		)
