extends Node

var nm: Node = null
var client_name: String = "Alice"
var rooster_id: String = "decluck"
var card_id: String = "decluck_all_for_one_punch"
var my_peer_id: int = -1

func _ready() -> void:
	if OS.has_environment("CLIENT_NAME"):
		client_name = OS.get_environment("CLIENT_NAME")
	if OS.has_environment("CLIENT_ROOSTER"):
		rooster_id = OS.get_environment("CLIENT_ROOSTER")
	if OS.has_environment("CLIENT_CARD"):
		card_id = OS.get_environment("CLIENT_CARD")

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			client_name = arg.replace("--name=", "")
		elif arg.begins_with("--rooster="):
			rooster_id = arg.replace("--rooster=", "")
		elif arg.begins_with("--card="):
			card_id = arg.replace("--card=", "")

	print("[%s] Client starting. Rooster: %s" % [client_name, rooster_id])
	GameManager._load_all_roosters()

	nm = get_node_or_null("/root/NetworkManager")
	if not nm:
		push_error("NetworkManager not found!")
		get_tree().quit(1)
		return

	nm.player_connected.connect(_on_player_connected)
	nm.tournament_roster_updated.connect(_on_roster_updated)
	nm.tournament_bracket_received.connect(_on_bracket_received)
	nm.tournament_match_started.connect(_on_match_started)
	nm.turn_received_from_host.connect(_on_turn_resolution)
	TournamentManager.tournament_state_changed.connect(_on_tournament_state_changed)

	var err: int = nm.join_match("127.0.0.1", 17790)
	if err != OK:
		print("[%s_ERROR] Failed to connect to host on 17790: %d" % [client_name, err])
		get_tree().quit(1)
		return

func _on_player_connected(id: int) -> void:
	if id == 1:
		my_peer_id = nm.local_peer_id
		print("[%s] Connected to host! Local Peer ID: %d. Registering tournament contender..." % [client_name, my_peer_id])
		nm.register_local_tournament_player(client_name, rooster_id)

func _on_roster_updated(roster: Dictionary) -> void:
	print("[%s] Tournament roster update: %d players currently registered." % [client_name, roster.size()])

func _on_bracket_received(bracket_data: Dictionary) -> void:
	print("[%s] Received tournament bracket sync (%d nodes)!" % [client_name, bracket_data.get("nodes", []).size()])
	var sf1 = TournamentManager.get_match("SF1")
	assert(sf1.get("is_bye", false) == true, "SF1 must be Bye!")
	print("[%s] Confirmed SF1 is Bye match. Ready for tournament combat." % client_name)

func _on_match_started(match_id: String, p1_peer: int, p2_peer: int) -> void:
	print("[%s] Match %s started! Contenders: P1=%d vs P2=%d. (My ID=%d)" % [
		client_name, match_id, p1_peer, p2_peer, my_peer_id
	])

	if my_peer_id == p1_peer or my_peer_id == p2_peer:
		print("[%s] I am a contender in %s! Submitting turn card: %s" % [client_name, match_id, card_id])
		# Brief delay to simulate player action
		await get_tree().create_timer(0.2).timeout
		var cards_to_send: Array[String] = [card_id]
		nm.submit_turn(cards_to_send)
	else:
		print("[%s] I am spectating match %s." % [client_name, match_id])

func _on_turn_resolution(events: Array) -> void:
	if not events.is_empty():
		print("[%s] Received %d combat resolution events from host!" % [client_name, events.size()])

func _on_tournament_state_changed() -> void:
	print("[%s] Tournament bracket updated." % client_name)
	if TournamentManager.tournament_completed:
		print("[%s_SUCCESS] Tournament concluded successfully!" % client_name)
		get_tree().quit(0)
