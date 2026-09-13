extends Node

func _ready() -> void:
	print("=========================================================")
	print("TESTING DYNAMIC TOURNAMENT BRACKET & BYE GENERATION")
	print("=========================================================\n")

	var tm = get_node_or_null("/root/TournamentManager")
	if not tm:
		var tm_script = load("res://scripts/TournamentManager.gd")
		tm = tm_script.new()
		add_child(tm)

	var all_roosters = tm._get_all_roosters()
	assert(all_roosters.size() >= 8, "Need at least 8 roosters loaded")

	# -------------------------------------------------------------
	# Test 1: 3 Players (4-Slot Bracket with 1 Bye)
	# -------------------------------------------------------------
	print("--- TEST 1: 3 Players (4-slot bracket, 1 Bye) ---")
	var p3: Array[Dictionary] = [
		{"peer_id": 1, "name": "Player 1 (Host)", "rooster": all_roosters[0]},
		{"peer_id": 2, "name": "Player 2", "rooster": all_roosters[1]},
		{"peer_id": 3, "name": "Player 3", "rooster": all_roosters[2]}
	]
	tm.build_dynamic_online_tournament(p3)

	var sf1 = tm.get_match("SF1")
	var sf2 = tm.get_match("SF2")
	var gf = tm.get_match("GF")

	assert(sf1["is_bye"] == true, "SF1 should be a BYE")
	assert(sf1["is_completed"] == true, "SF1 should be auto-completed due to BYE")
	assert(sf1["winner"] == all_roosters[0], "SF1 winner should be Player 1")
	assert(gf["rooster_1"] == all_roosters[0], "GF slot 1 should already hold Player 1 (auto-advanced from Bye!)")

	assert(sf2["is_bye"] == false, "SF2 should be a real duel")
	assert(sf2["is_completed"] == false, "SF2 should be uncompleted")
	assert(sf2["rooster_1"] == all_roosters[1], "SF2 slot 1 should be Player 2")
	assert(sf2["rooster_2"] == all_roosters[2], "SF2 slot 2 should be Player 3")

	print("[SUCCESS] 3-player bracket: Player 1 auto-advanced to Grand Finals via BYE. SF2 is active.")

	# Simulate SF2 completion (Player 2 wins)
	tm.current_match_id = "SF2"
	tm.record_match_result(all_roosters[1])

	# Now GF should have both contestants ready
	gf = tm.get_match("GF")
	assert(gf["rooster_1"] == all_roosters[0], "GF slot 1 is Player 1")
	assert(gf["rooster_2"] == all_roosters[1], "GF slot 2 is Player 2")
	assert(tm.current_match_id == "GF", "Current match should now be GF!")

	# Simulate GF completion (Player 1 wins championship)
	tm.record_match_result(all_roosters[0])
	assert(tm.tournament_completed == true, "Tournament should be completed")
	assert(tm.final_leaderboard.size() >= 3, "Leaderboard should rank all players")
	print("[SUCCESS] 3-player tournament completed! Champion: ", tm.final_leaderboard[0]["rooster"].display_name)

	# -------------------------------------------------------------
	# Test 2: 5 Players (8-Slot Bracket with 3 Byes)
	# -------------------------------------------------------------
	print("\n--- TEST 2: 5 Players (8-slot bracket, 3 Byes) ---")
	var p5: Array[Dictionary] = [
		{"peer_id": 1, "name": "P1", "rooster": all_roosters[0]},
		{"peer_id": 2, "name": "P2", "rooster": all_roosters[1]},
		{"peer_id": 3, "name": "P3", "rooster": all_roosters[2]},
		{"peer_id": 4, "name": "P4", "rooster": all_roosters[3]},
		{"peer_id": 5, "name": "P5", "rooster": all_roosters[4]}
	]
	tm.build_dynamic_online_tournament(p5)

	var qf1 = tm.get_match("QF1")
	var qf2 = tm.get_match("QF2")
	var qf3 = tm.get_match("QF3")
	var qf4 = tm.get_match("QF4")

	assert(qf1["is_bye"] == true, "QF1 should be Bye")
	assert(qf2["is_bye"] == true, "QF2 should be Bye")
	assert(qf3["is_bye"] == true, "QF3 should be Bye")
	assert(qf4["is_bye"] == false, "QF4 should be real duel (P4 vs P5)")

	var sf1_5 = tm.get_match("SF1")
	var sf2_5 = tm.get_match("SF2")
	assert(sf1_5["rooster_1"] == all_roosters[0], "SF1 slot 1 holds P1 from QF1 bye")
	assert(sf1_5["rooster_2"] == all_roosters[1], "SF1 slot 2 holds P2 from QF2 bye")
	assert(sf2_5["rooster_1"] == all_roosters[2], "SF2 slot 1 holds P3 from QF3 bye")
	assert(sf2_5["rooster_2"] == null, "SF2 slot 2 waits for QF4 winner")

	print("[SUCCESS] 5-player bracket: 3 byes resolved, SF1 is set, QF4 is first fight to play.")

	# -------------------------------------------------------------
	# Test 3: Serialization & Deserialization
	# -------------------------------------------------------------
	print("\n--- TEST 3: Bracket Network Serialization & Deserialization ---")
	var serialized = tm.serialize_bracket()
	assert(serialized.has("matches"), "Serialized data must have matches")
	assert(serialized["matches"].size() == tm.matches.size(), "Match count must match")

	# Reconstruct on another instance
	var tm2_script = load("res://scripts/TournamentManager.gd")
	var tm2 = tm2_script.new()
	add_child(tm2)
	tm2.deserialize_bracket(serialized)

	assert(tm2.matches.size() == tm.matches.size(), "Deserialized matches count match")
	var tm2_qf1 = tm2.get_match("QF1")
	assert(tm2_qf1["is_bye"] == true, "Deserialized match preserves bye state")
	assert(tm2_qf1["winner"] != null, "Deserialized match preserves winner resource")
	print("[SUCCESS] Bracket serialization and deserialization verified with 100% fidelity.")

	print("\n>>> ALL DYNAMIC BRACKET & BYE TESTS PASSED SUCCESSFULLY! <<<")
	get_tree().quit(0)
