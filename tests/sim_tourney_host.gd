extends Node

var nm: Node = null
var alice_peer: int = -1
var bob_peer: int = -1
var active_p1_duelist: Duelist = null
var active_p2_duelist: Duelist = null
var _tournament_started: bool = false

func _ready() -> void:
	print("[HOST] Starting Tournament Host Simulation (3 Players, 1 Bye)...")
	GameManager._load_all_roosters()

	nm = get_node_or_null("/root/NetworkManager")
	if not nm:
		push_error("NetworkManager not found!")
		get_tree().quit(1)
		return

	nm.player_connected.connect(_on_player_connected)
	nm.player_disconnected.connect(_on_player_disconnected)
	nm.tournament_roster_updated.connect(_on_roster_updated)
	nm.turn_received_from_host.connect(_on_turn_received_from_host)

	var err: int = nm.host_match(17790, nm.MatchMode.TOURNAMENT, 4)
	if err != OK:
		print("[HOST_ERROR] Failed to start tournament host on port 17790: ", err)
		get_tree().quit(1)
		return

	# Host registers itself
	nm.register_local_tournament_player("Host", "hen_goku")
	print("[HOST] Server listening on port 17790 for tournament (Max 4 players). Host registered.")

func _on_player_connected(id: int) -> void:
	print("[HOST] Peer connected: %d" % id)

func _on_player_disconnected(id: int) -> void:
	print("[HOST] Peer disconnected: %d" % id)

func _on_roster_updated(roster: Dictionary) -> void:
	print("[HOST] Tournament Roster updated. Total players: %d" % roster.size())
	for pid in roster:
		var p = roster[pid]
		print("  - Peer %d: %s (%s)" % [pid, p.get("name"), p.get("rooster_id")])
		if p.get("name") == "Alice":
			alice_peer = pid
		elif p.get("name") == "Bob":
			bob_peer = pid

	if roster.size() == 3 and alice_peer != -1 and bob_peer != -1 and not _tournament_started:
		_tournament_started = true
		call_deferred("_start_tournament_flow")

func _start_tournament_flow() -> void:
	print("\n[HOST] --- GENERATING 3-PLAYER TOURNAMENT BRACKET ---")
	var participants: Array[Dictionary] = [
		{ "peer_id": 1, "name": "Host", "rooster_id": "hen_goku" },
		{ "peer_id": alice_peer, "name": "Alice", "rooster_id": "decluck" },
		{ "peer_id": bob_peer, "name": "Bob", "rooster_id": "cocktaro" }
	]

	TournamentManager.build_dynamic_online_tournament(participants, TournamentManager.Format.SINGLE_ELIMINATION)
	
	# Verify bracket properties
	assert(TournamentManager.matches.size() == 4, "Expected 4 matches in 4-bracket (SF1, SF2, GF, 3RD)!")
	var sf1 = TournamentManager.get_match("SF1")
	var sf2 = TournamentManager.get_match("SF2")
	var gf = TournamentManager.get_match("GF")

	print("[HOST] SF1 (Match 1): %s vs %s | is_bye=%s, is_completed=%s" % [
		sf1.get("p1_name", ""), sf1.get("p2_name", ""), sf1.get("is_bye", false), sf1.get("is_completed", false)
	])
	assert(sf1.get("is_bye", false) == true, "SF1 must be a Bye!")
	assert(sf1.get("is_completed", false) == true, "SF1 must be auto-completed!")
	assert(gf.get("p1_name", "") == "Host", "Host should already be promoted to GF!")

	print("[HOST] SF2 (Match 2): %s (peer %d) vs %s (peer %d)" % [
		sf2.get("p1_name", ""), sf2.get("p1_peer_id", 0), sf2.get("p2_name", ""), sf2.get("p2_peer_id", 0)
	])
	assert(sf2.get("p1_peer_id", 0) == alice_peer, "SF2 P1 must be Alice!")
	assert(sf2.get("p2_peer_id", 0) == bob_peer, "SF2 P2 must be Bob!")

	# Broadcast bracket to all peers
	var bracket_data := TournamentManager.serialize_bracket()
	nm.broadcast_start_tournament(bracket_data)
	print("[HOST] Broadcasted tournament bracket to all peers.")

	# Wait a short moment then start SF2 (Alice vs Bob)
	await get_tree().create_timer(0.5).timeout
	_start_sf2_duel()

func _start_sf2_duel() -> void:
	print("\n[HOST] --- STARTING SF2 DUEL: ALICE VS BOB ---")
	var r1 = GameManager.get_rooster_by_id("decluck")
	var r2 = GameManager.get_rooster_by_id("cocktaro")
	active_p1_duelist = Duelist.new(alice_peer, "Alice", r1)
	active_p2_duelist = Duelist.new(bob_peer, "Bob", r2)
	nm.register_duelists(active_p1_duelist, active_p2_duelist)

	nm.broadcast_start_tournament_match("SF2", alice_peer, bob_peer, "decluck", "cocktaro")
	# Host broadcasts dice rolls
	nm.broadcast_dice_rolls(5, 4)

func _on_turn_received_from_host(events: Array) -> void:
	if events.is_empty():
		# Empty signal indicates both contenders submitted cards to host
		print("[HOST] Both contenders submitted turn cards! Authoritatively resolving combat...")
		var resolved: Array[Dictionary] = CombatEngine.resolve_turn(
			active_p1_duelist,
			active_p2_duelist,
			1,
			1,
			false
		)
		print("[HOST] CombatEngine resolved %d events. Broadcasting turn resolution..." % resolved.size())
		nm.broadcast_turn_events(resolved)

		# Check SF2 completion
		var current_match = TournamentManager.get_current_match()
		if current_match.get("id") == "SF2":
			call_deferred("_conclude_sf2_match")
		elif current_match.get("id") == "GF":
			call_deferred("_conclude_gf_match")

func _conclude_sf2_match() -> void:
	print("\n[HOST] --- CONCLUDING SF2: DECLARING ALICE WINNER ---")
	var win_rooster = GameManager.get_rooster_by_id("decluck")
	TournamentManager.record_match_result(win_rooster, "SF2")
	
	var gf = TournamentManager.get_match("GF")
	print("[HOST] GF Finalists: %s (peer %d) vs %s (peer %d)" % [
		gf.get("p1_name", ""), gf.get("p1_peer_id", 0),
		gf.get("p2_name", ""), gf.get("p2_peer_id", 0)
	])
	assert(gf.get("p2_peer_id", 0) == alice_peer, "Alice must be promoted to GF as P2!")

	# Broadcast match result and updated bracket
	nm.broadcast_tournament_match_result(win_rooster.rooster_id, TournamentManager.serialize_bracket())

	# Start Grand Finals: Host vs Alice
	await get_tree().create_timer(0.5).timeout
	_start_gf_duel()

func _start_gf_duel() -> void:
	print("\n[HOST] --- STARTING GRAND FINALS: HOST VS ALICE ---")
	var r1 = GameManager.get_rooster_by_id("hen_goku")
	var r2 = GameManager.get_rooster_by_id("decluck")
	active_p1_duelist = Duelist.new(1, "Host", r1)
	active_p2_duelist = Duelist.new(alice_peer, "Alice", r2)
	nm.register_duelists(active_p1_duelist, active_p2_duelist)

	nm.broadcast_start_tournament_match("GF", 1, alice_peer, "hen_goku", "decluck")
	nm.broadcast_dice_rolls(6, 2)

	# Host submits its card
	nm.submit_turn(["hen_goku_kamecock"])

func _conclude_gf_match() -> void:
	print("\n[HOST] --- CONCLUDING GRAND FINALS: DECLARING HOST CHAMPION ---")
	var win_rooster = GameManager.get_rooster_by_id("hen_goku")
	TournamentManager.record_match_result(win_rooster, "GF")
	nm.broadcast_tournament_match_result(win_rooster.rooster_id, TournamentManager.serialize_bracket())

	assert(TournamentManager.tournament_completed == true, "Tournament must be completed!")
	var leaderboard = TournamentManager.final_leaderboard
	print("[HOST] Tournament concluded! Final Leaderboard size: %d" % leaderboard.size())
	for item in leaderboard:
		var r: RoosterData = item.get("rooster")
		var r_name: String = r.display_name if r else "Unknown"
		print("  Rank %d: %s - %s (%s)" % [item.get("rank"), r_name, item.get("title", ""), item.get("badge", "")])

	assert(leaderboard.size() >= 3, "Leaderboard must contain all 3 participants!")
	assert(leaderboard[0].get("rank") == 1, "Rank 1 must be champion!")
	print("\n[HOST_SUCCESS] ONLINE TOURNAMENT WITH BYES SIMULATION COMPLETED 100% OK!\n")
	get_tree().quit(0)
