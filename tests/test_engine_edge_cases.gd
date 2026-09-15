extends Node

func _ready() -> void:
	print("=========================================================")
	print("TESTING GODOT COMBAT ENGINE & TOURNAMENT EDGE CASES")
	print("=========================================================\n")

	GameManager._load_all_roosters()

	# -----------------------------------------------------------------------
	# Test 1: Simultaneous Double-KO (Mutual Draw) in CombatEngine
	# -----------------------------------------------------------------------
	print("--- TEST 1: Simultaneous Double-KO in CombatEngine ---")
	var r1: RoosterData = GameManager.get_rooster_by_id("hen_goku")
	var r2: RoosterData = GameManager.get_rooster_by_id("decluck")
	assert(r1 != null and r2 != null, "Roosters must be loaded")

	var p1 := Duelist.new(1, "Player 1", r1)
	var p2 := Duelist.new(2, "Player 2", r2)

	# Set both to 4 HP
	p1.hp = 4
	p2.hp = 4

	# Give both high-damage attack cards
	var strike_card := CardData.new()
	strike_card.card_id = "test_strike"
	strike_card.display_name = "Heavy Strike"
	strike_card.card_type = CardData.CardType.ATTACK
	strike_card.base_value = 15
	strike_card.taya_cost = 2

	p1.queued_cards = [strike_card]
	p2.queued_cards = [strike_card]

	# Resolve simultaneous clash (is_clash = true)
	var events: Array[Dictionary] = CombatEngine.resolve_turn(p1, p2, 1, 1, true)
	print("  [CLASH] CombatEngine resolved turn with %d events." % events.size())

	# Verify both dropped to <= 0 HP
	assert(p1.hp <= 0, "P1 should be at 0 HP")
	assert(p2.hp <= 0, "P2 should be at 0 HP")

	# Find MATCH_END event
	var match_end_ev: Dictionary = {}
	for ev in events:
		if ev.get("type") == CombatEngine.EventType.MATCH_END:
			match_end_ev = ev
			break

	assert(not match_end_ev.is_empty(), "MATCH_END event must be generated")
	assert(match_end_ev.get("winner_id") == -1, "winner_id must be -1 for DRAW")
	print("  [PASS] Mutual Double-KO successfully resulted in DRAW (winner_id = -1)")

	# -----------------------------------------------------------------------
	# Test 2: Tournament Draw Tiebreaker Resolution in TournamentManager
	# -----------------------------------------------------------------------
	print("\n--- TEST 2: Tournament Draw Tiebreaker Resolution ---")
	var tm = get_node_or_null("/root/TournamentManager")
	if not tm:
		var tm_script = load("res://scripts/TournamentManager.gd")
		tm = tm_script.new()
		add_child(tm)

	var p3: Array[Dictionary] = [
		{"peer_id": 1, "name": "Goku", "rooster": r1},
		{"peer_id": 2, "name": "Decluck", "rooster": r2}
	]
	tm.build_dynamic_online_tournament(p3)

	# SF2 is the active duel between P1 and P2
	var sf2 = tm.get_match("SF2")
	assert(sf2 != null, "SF2 must exist")

	# Simulate mutual draw by passing winner = null to record_match_result
	print("  [DRAW TRIGGER] Recording match result with winner = null (Double KO)...")
	tm.record_match_result(null, "SF2")

	assert(sf2["is_completed"] == true, "SF2 must be marked as completed after tiebreaker")
	assert(sf2["winner"] != null, "SF2 must have a valid winner selected via tiebreaker")
	print("  [PASS] Tiebreaker arbiter successfully determined winner: %s" % sf2["winner"].display_name)

	# -----------------------------------------------------------------------
	# Test 3: Rogue / Fabricated Card ID Rejection in NetworkManager
	# -----------------------------------------------------------------------
	print("\n--- TEST 3: Rogue / Invalid Card ID Filtering ---")
	var nm = get_node_or_null("/root/NetworkManager")
	assert(nm != null, "NetworkManager must exist")

	var test_duelist := Duelist.new(1, "TestDuelist", r1)
	# Attempt to submit valid card and a rogue injected card
	var card_submissions: Array[String] = [
		"hen_goku_kamecock",          # Valid card in rooster deck
		"rogue_injected_cheat_card",   # Fake fabricated card
		"sql_injection_drop_tables"    # Malicious string
	]

	nm._apply_card_ids_to_duelist(test_duelist, card_submissions)

	print("  [FILTER] Total cards queued in duelist: %d" % test_duelist.queued_cards.size())
	assert(test_duelist.queued_cards.size() == 1, "Only the 1 legitimate card should be queued!")
	assert(test_duelist.queued_cards[0].card_id == "hen_goku_kamecock", "Legitimate card must match")
	print("  [PASS] Rogue and fabricated card IDs safely filtered and rejected by authoritative host!")

	print("\n>>> ALL GODOT COMBAT ENGINE & TOURNAMENT EDGE CASES PASSED 100%! <<<")
	get_tree().quit(0)
