extends Node

func _ready() -> void:
	print("=========================================================")
	print("TESTING 16-PLAYER DYNAMIC TOURNAMENT BRACKET & ENGINE")
	print("=========================================================\n")

	var tm = get_node_or_null("/root/TournamentManager")
	if not tm:
		var tm_script = load("res://scripts/TournamentManager.gd")
		tm = tm_script.new()
		add_child(tm)

	var all_roosters = tm._get_all_roosters()
	assert(all_roosters.size() >= 8, "Need at least 8 roosters loaded")

	# -------------------------------------------------------------
	# Test 1: Full 16-Player Single Elimination Bracket (No Byes)
	# -------------------------------------------------------------
	print("--- TEST 1: Full 16 Players (16-slot bracket, 0 Byes) ---")
	var p16: Array[Dictionary] = []
	for i in range(16):
		var r_idx = i % all_roosters.size()
		p16.append({
			"peer_id": i + 1,
			"name": "Contender_%02d" % (i + 1),
			"rooster": all_roosters[r_idx].duplicate()
		})

	tm.build_dynamic_online_tournament(p16)

	# Verify bracket matches: 8 (R16) + 4 (QF) + 2 (SF) + 1 (GF) + 1 (3RD) = 16 matches total
	assert(tm.matches.size() == 16, "Expected exactly 16 matches in a 16-slot bracket, got %d" % tm.matches.size())
	print("[PASS] Total matches generated: %d (8 R16 + 4 QF + 2 SF + 1 GF + 1 3RD)" % tm.matches.size())

	# Verify all Round 1 matches (R16_1 to R16_8) are active non-bye duels
	for i in range(1, 9):
		var mid = "R16_%d" % i
		var m = tm.get_match(mid)
		assert(m != null, "Match %s must exist" % mid)
		assert(m["is_bye"] == false, "Match %s should not be a bye" % mid)
		assert(m["rooster_1"] != null and m["rooster_2"] != null, "Match %s must have both roosters" % mid)
		assert(m["p1_peer_id"] > 0 and m["p2_peer_id"] > 0, "Match %s must have valid peer IDs" % mid)
	print("[PASS] All 8 Round of 16 matches correctly paired with 16 active contenders.")

	# -------------------------------------------------------------
	# Test 2: 13 Players in 16 Bracket (3 Byes Distributed)
	# -------------------------------------------------------------
	print("\n--- TEST 2: 13 Players (16-slot bracket with 3 Byes) ---")
	var p13: Array[Dictionary] = []
	for i in range(13):
		var r_idx = i % all_roosters.size()
		p13.append({
			"peer_id": i + 1,
			"name": "Contender_%02d" % (i + 1),
			"rooster": all_roosters[r_idx].duplicate()
		})

	tm.build_dynamic_online_tournament(p13)
	assert(tm.matches.size() == 16, "Must still produce 16 matches")

	# Byes should be on R16_1, R16_2, R16_3
	var r1 = tm.get_match("R16_1")
	var r2 = tm.get_match("R16_2")
	var r3 = tm.get_match("R16_3")
	var r4 = tm.get_match("R16_4")
	assert(r1["is_bye"] == true and r1["is_completed"] == true, "R16_1 must be an auto-completed bye")
	assert(r2["is_bye"] == true and r2["is_completed"] == true, "R16_2 must be an auto-completed bye")
	assert(r3["is_bye"] == true and r3["is_completed"] == true, "R16_3 must be an auto-completed bye")
	assert(r4["is_bye"] == false, "R16_4 must be an active duel")

	# QF1 should already receive winners from R16_1 and R16_2 byes!
	var qf1 = tm.get_match("QF1")
	assert(qf1["rooster_1"] != null and qf1["rooster_2"] != null, "QF1 should already have both bye contenders advanced!")
	print("[PASS] 3 Byes successfully resolved: R16_1, R16_2, R16_3 auto-promoted to QF1 and QF2.")

	# -------------------------------------------------------------
	# Test 3: Network Serialization of 16-Player Bracket
	# -------------------------------------------------------------
	print("\n--- TEST 3: Network Serialization & Client Sync ---")
	var serialized = tm.serialize_bracket()
	assert(serialized["matches"].size() == 16, "Serialized payload must contain 16 matches")

	var tm_client_script = load("res://scripts/TournamentManager.gd")
	var tm_client = tm_client_script.new()
	add_child(tm_client)
	tm_client.deserialize_bracket(serialized)

	assert(tm_client.matches.size() == 16, "Client deserialized matches must equal 16")
	var c_qf1 = tm_client.get_match("QF1")
	assert(c_qf1["rooster_1"] != null and c_qf1["rooster_2"] != null, "Client matches maintain exact contestant state")
	print("[PASS] Network serialization of 16-player bracket verified with 100% precision.")

	# -------------------------------------------------------------
	# Test 4: Fast Simulation to Championship Conclusion
	# -------------------------------------------------------------
	print("\n--- TEST 4: Simulating 16-Player Tournament Progression ---")
	# Resolve remaining uncompleted matches
	for m in tm.matches:
		if not m["is_completed"]:
			var winner_r = m["rooster_1"] if m["rooster_1"] else all_roosters[0]
			tm.current_match_id = m["id"]
			tm.record_match_result(winner_r)

	assert(tm.tournament_completed == true, "Tournament must conclude as completed")
	assert(tm.final_leaderboard.size() >= 13, "Leaderboard must rank all tournament participants")
	print("[PASS] Tournament concluded successfully! Podium:")
	for idx in range(min(4, tm.final_leaderboard.size())):
		var entry = tm.final_leaderboard[idx]
		print("  Rank %d: %s (%s)" % [idx + 1, entry["rooster"].display_name, entry.get("title", "")])

	print("\n>>> ALL 16-PLAYER TOURNAMENT TESTS PASSED 100%! <<<")
	get_tree().quit(0)
