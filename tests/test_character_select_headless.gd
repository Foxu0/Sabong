extends Node

func _ready() -> void:
	print("=========================================================")
	print("[TEST] RUNNING CHARACTER SELECT REDESIGN VALIDATION TEST")
	print("=========================================================")
	
	var scene_res = load("res://scenes/character_select.tscn")
	assert(scene_res != null, "Failed to load character_select.tscn")
	
	var node = scene_res.instantiate()
	add_child(node)
	
	print("[TEST] CharacterSelect instantiated successfully!")
	print("[TEST] Selected Player Rooster: ", GameManager.selected_player_rooster.display_name if GameManager.selected_player_rooster else "None")
	
	# Verify navigation buttons exist
	assert(node.btn_nav_prev != null, "btn_nav_prev must exist")
	assert(node.btn_nav_next != null, "btn_nav_next must exist")
	assert(node.cards_layer != null, "cards_layer must exist")
	
	print("[TEST] Navigation buttons & cards layer verified.")
	print("[TEST] Active moveset cards count: ", node.moveset_card_buttons.size())
	assert(node.moveset_card_buttons.size() == 3, "Expected 3 moveset cards for selected rooster")
	
	# Test Next Rooster (>)
	print("\n[TEST] Testing Next Rooster (>) navigation...")
	var old_idx = node.current_index
	node.is_transitioning = false
	node._select_next_rooster()
	assert(node.current_index == (old_idx + 1) % node.roosters.size(), "Index should have advanced!")
	print("[TEST] New Rooster: ", node.roosters[node.current_index].display_name)
	print("[TEST] Active moveset cards count: ", node.moveset_card_buttons.size())
	assert(node.moveset_card_buttons.size() == 3, "Expected 3 moveset cards after navigation")
	
	# Test Previous Rooster (<)
	print("\n[TEST] Testing Prev Rooster (<) navigation...")
	node.is_transitioning = false
	node._select_previous_rooster()
	assert(node.current_index == old_idx, "Index should return to original!")
	print("[TEST] Returned to: ", node.roosters[node.current_index].display_name)
	print("[TEST] Active moveset cards count: ", node.moveset_card_buttons.size())
	assert(node.moveset_card_buttons.size() == 3, "Expected 3 moveset cards after returning")
	
	# Cycle through ALL 8 roosters to ensure each one loads their 3 moveset cards smoothly without any errors!
	print("\n[TEST] Cycling through all 8 roosters to verify moveset cards...")
	for i in range(node.roosters.size()):
		node.is_transitioning = false
		node._select_rooster(i)
		var r = node.roosters[i]
		print("  - Rooster %d: %s (HP: %d) -> %d moveset cards" % [i + 1, r.display_name, r.base_hp, node.moveset_card_buttons.size()])
		assert(node.moveset_card_buttons.size() == 3, "Each rooster must have exactly 3 moveset cards!")
	
	print("\n*** ALL 8 ROOSTERS AND THEIR CARDS VERIFIED 100% SUCCESSFULLY! ***")
	get_tree().quit(0)
