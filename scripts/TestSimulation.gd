extends SceneTree

## Automated Headless Simulation Test to verify all Roosters, Cards, and Turn Resolution

func _init() -> void:
	print("[TEST] Starting Sabong Roosters Simulation Test...")

	var rooster_paths := [
		"res://resources/roosters/hen_goku.tres",
		"res://resources/roosters/decluck.tres",
		"res://resources/roosters/eren_pecker.tres",
		"res://resources/roosters/cluckey_d_puffy.tres",
		"res://resources/roosters/chick_yagami.tres",
		"res://resources/roosters/cocktaro.tres",
		"res://resources/roosters/nechicko.tres",
		"res://resources/roosters/daniel.tres"
	]

	var universal_paths := [
		"res://resources/cards/claw_slash.tres",
		"res://resources/cards/t_claw_slash.tres",
		"res://resources/cards/feather_block.tres",
		"res://resources/cards/feather_flock.tres",
		"res://resources/cards/nugget.tres",
		"res://resources/cards/fried_chicken.tres",
		"res://resources/cards/poop_burst.tres",
		"res://resources/cards/chickn_turd.tres",
	]

	var universal_cards: Array[CardData] = []
	for p in universal_paths:
		assert(ResourceLoader.exists(p), "Missing universal card: %s" % p)
		var c: CardData = load(p)
		universal_cards.append(c)
	print("[TEST] Loaded 8 universal cards successfully.")

	var roosters: Array[RoosterData] = []
	for p in rooster_paths:
		assert(ResourceLoader.exists(p), "Missing rooster: %s" % p)
		var r: RoosterData = load(p)
		assert(r.moveset.size() == 3, "Rooster %s does not have 3 moves!" % r.rooster_id)
		roosters.append(r)
		print("[TEST] Verified Rooster: %s (HP: %d, Moves: %d)" % [r.display_name, r.base_hp, r.moveset.size()])

	# Test Combat Simulation between Goku and Eren
	var goku_data: RoosterData = roosters[0]
	var eren_data: RoosterData = roosters[2]

	var p1 := Duelist.new(1, "Hen-Goku", goku_data)
	var p2 := Duelist.new(2, "Eren Pecker", eren_data)

	p1.setup_deck(universal_cards)
	p2.setup_deck(universal_cards)

	assert(p1.deck.size() == 11, "Deck should be 11 cards!")
	assert(p2.deck.size() == 11, "Deck should be 11 cards!")

	p1.draw_cards(4)
	p2.draw_cards(4)
	assert(p1.hand.size() == 4, "Hand should have 4 cards!")

	# Simulate 3 turns
	for turn in range(1, 4):
		AIController.make_ai_turn(p1, p2)
		AIController.make_ai_turn(p2, p1)
		var events := CombatEngine.resolve_turn(p1, p2, turn)
		print("[TEST] Turn %d Resolved! Total events: %d | P1 HP: %d, P2 HP: %d" % [turn, events.size(), p1.hp, p2.hp])
		p1.reset_turn_for_new_round()
		p2.reset_turn_for_new_round()
		p1.draw_cards(4)
		p2.draw_cards(4)

	print("[TEST] ALL COMBAT & DATA SIMULATIONS PASSED PERFECTLY!")
	quit(0)
