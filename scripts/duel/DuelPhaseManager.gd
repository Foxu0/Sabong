class_name DuelPhaseManager
extends Node

## DuelPhaseManager — Central state machine orchestrating the round-based phase loop:
## DICE_ROLL -> DISCARD (skipped R1) -> DRAW -> REROLL -> FIGHTING -> ROUND_END

signal phase_changed(new_phase: DuelPhase.Phase)
signal round_started(round_number: int)
signal round_ended(round_number: int)
signal dice_rolled(meron_result: int, wala_result: int, is_clash: bool)
signal priority_determined(priority_player_id: String)
signal discard_required(player_id: String, count: int)
signal duel_finished(winner_id: String)
signal player_ready_updated(player_id: String, is_ready: bool)
signal card_rerolled(player_id: String, card: CardData, remaining_rerolls: int, slot_index: int)
signal cards_drawn(player_id: String, count: int)
signal roll_manipulated(player_id: String, new_roll: int)
signal combat_resolved(events: Array[Dictionary])
signal auto_discarded(player_id: String, discarded_cards: Array)

const CARD_LIMIT: int = 6
const FREE_REROLLS_PER_ROUND: int = 3
const MAX_CARD_ROLL_MANIPULATIONS_PER_ROUND: int = 1
const HUMAN_TIMEOUT_SECONDS: float = 60.0

var current_round: int = 1
var current_phase: DuelPhase.Phase = DuelPhase.Phase.DICE_ROLL
var meron_state: PlayerRoundState = null
var wala_state: PlayerRoundState = null
var is_clash_round: bool = false

# Online multiplayer flags (Blueprint §11: server-authoritative architecture)
var is_online_match: bool = false
var is_host_peer: bool = false  ## True only on the authoritative host peer

# Table / 3D Scene references
var arena_root: Node = null
var meron_dice_model_path: String = ""
var wala_dice_model_path: String = ""

# Input readiness tracking
var _ready_map: Dictionary = { "MERON": false, "WALA": false }
var _pending_discards: Dictionary = { "MERON": [], "WALA": [] }
var _human_timers: Dictionary = {}
var _timer_generation_token: int = 0
var _phase_waiting: bool = false
signal _ready_state_changed()

func _ready() -> void:
	pass

## ---------------------------------------------------------------------------
## Public Initialization
## ---------------------------------------------------------------------------

func start_duel(p1_duelist: Duelist, p2_duelist: Duelist, p2_is_ai: bool = true, root_node: Node = null) -> void:
	current_round = 1
	arena_root = root_node if root_node else get_parent()

	meron_state = PlayerRoundState.new()
	meron_state.player_id = "MERON"
	meron_state.is_ai = false
	meron_state.bind_duelist(p1_duelist)

	wala_state = PlayerRoundState.new()
	wala_state.player_id = "WALA"
	wala_state.is_ai = p2_is_ai
	wala_state.bind_duelist(p2_duelist)

	if p1_duelist and p1_duelist.rooster_data:
		meron_dice_model_path = p1_duelist.rooster_data.dice_model_path
	if p2_duelist and p2_duelist.rooster_data:
		wala_dice_model_path = p2_duelist.rooster_data.dice_model_path

	# Configure online flags from GameManager
	is_online_match = GameManager.is_online_match
	if is_online_match:
		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			is_host_peer = nm.is_host
			# Register duelists so host can apply submitted card IDs
			nm.register_duelists(p1_duelist, p2_duelist)
			# Wire forfeit handler
			if not nm.opponent_disconnected_forfeit.is_connected(_on_online_forfeit):
				nm.opponent_disconnected_forfeit.connect(_on_online_forfeit)
		# In online mode, WALA is not local AI
		wala_state.is_ai = false

	_enter_phase(DuelPhase.Phase.DICE_ROLL)

## Handles opponent forfeit mid-duel (Blueprint §12 Risk handler)
func _on_online_forfeit() -> void:
	DuelLogger.info("DuelPhaseManager", "Opponent forfeited due to disconnect. Declaring winner.")
	# Award win to MERON (local player = host or client who remained)
	duel_finished.emit("MERON")

func get_state(player_id: String) -> PlayerRoundState:
	if player_id == "MERON" or player_id == "1":
		return meron_state
	return wala_state

func get_opponent_state(player_id: String) -> PlayerRoundState:
	if player_id == "MERON" or player_id == "1":
		return wala_state
	return meron_state

## ---------------------------------------------------------------------------
## State Machine Funnel
## ---------------------------------------------------------------------------

func _enter_phase(phase: DuelPhase.Phase) -> void:
	current_phase = phase
	_clear_human_timers()
	_ready_map["MERON"] = false
	_ready_map["WALA"] = false
	DuelLogger.phase(DuelPhase.Phase.keys()[phase], current_round)
	phase_changed.emit(phase)

	match phase:
		DuelPhase.Phase.DICE_ROLL:
			round_started.emit(current_round)
			if meron_state: meron_state.reset_for_new_round()
			if wala_state: wala_state.reset_for_new_round()
			_run_dice_roll_phase()
		DuelPhase.Phase.DISCARD:
			_run_discard_phase()
		DuelPhase.Phase.DRAW:
			_run_draw_phase()
		DuelPhase.Phase.REROLL:
			_run_reroll_phase()
		DuelPhase.Phase.FIGHTING:
			_run_fighting_phase()
		DuelPhase.Phase.ROUND_END:
			_run_round_end()

func _advance_phase() -> void:
	match current_phase:
		DuelPhase.Phase.DICE_ROLL:
			# Round 1 skips Discard entirely — go straight to Draw.
			if current_round == 1:
				_enter_phase(DuelPhase.Phase.DRAW)
			else:
				_enter_phase(DuelPhase.Phase.DISCARD)
		DuelPhase.Phase.DISCARD:
			_enter_phase(DuelPhase.Phase.DRAW)
		DuelPhase.Phase.DRAW:
			_enter_phase(DuelPhase.Phase.REROLL)
		DuelPhase.Phase.REROLL:
			_enter_phase(DuelPhase.Phase.FIGHTING)
		DuelPhase.Phase.FIGHTING:
			_enter_phase(DuelPhase.Phase.ROUND_END)
		DuelPhase.Phase.ROUND_END:
			current_round += 1
			_enter_phase(DuelPhase.Phase.DICE_ROLL)

## ---------------------------------------------------------------------------
## Phase 1: Dice Roll Phase (Simultaneous Reveal & Turn Priority Determination)
## Blueprint §9: "Roll round dice & replenish energy" — host generates, broadcasts to client
## ---------------------------------------------------------------------------

func _run_dice_roll_phase() -> void:
	if is_online_match and not is_host_peer:
		# CLIENT: Wait for host to broadcast the authoritative dice rolls
		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			var rolls = await nm.dice_rolls_received
			var host_roll: int = rolls[0]
			var client_roll: int = rolls[1]
			# On client: MERON is local (Client), WALA is opponent (Host)
			meron_state.dice_result = client_roll
			wala_state.dice_result = host_roll
			if meron_state.duelist: meron_state.duelist.current_dice_roll = client_roll
			if wala_state.duelist: wala_state.duelist.current_dice_roll = host_roll
			# Trigger 3D dice animation with the received values
			if arena_root and arena_root.has_method("transition_camera_view"):
				arena_root.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.25)
			if is_inside_tree():
				await get_tree().create_timer(0.12).timeout
			if arena_root:
				DiceRoller3D.roll_duel_dice(arena_root, meron_dice_model_path, wala_dice_model_path, client_roll, host_roll, false)
			await _wait_for_dice_settle()
			dice_rolled.emit(client_roll, host_roll, client_roll == host_roll)
			if is_inside_tree(): await get_tree().create_timer(0.20).timeout
			_resolve_dice_outcome()
		return

	# HOST (or offline): Generate authoritative dice rolls
	var meron_roll: int = randi_range(1, 6)
	var wala_roll: int = randi_range(1, 6)

	meron_state.dice_result = meron_roll
	wala_state.dice_result = wala_roll
	if meron_state.duelist:
		meron_state.duelist.current_dice_roll = meron_roll
	if wala_state.duelist:
		wala_state.duelist.current_dice_roll = wala_roll

	# Broadcast rolls to client (online) before starting dice animation
	if is_online_match and is_host_peer:
		var nm = get_node_or_null("/root/NetworkManager")
		if nm: nm.broadcast_dice_rolls(meron_roll, wala_roll)

	# Transition camera down to Table View so player watches both dice tumble, bounce, and settle on the table!
	if arena_root and arena_root.has_method("transition_camera_view"):
		arena_root.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.25)

	# Quick pause (~0.12s) for camera to begin table view, THEN roll dice onto the table!
	if is_inside_tree():
		await get_tree().create_timer(0.12).timeout

	# Roll 3D physics dice on the table (in_arena = false)
	if arena_root:
		DiceRoller3D.roll_duel_dice(
			arena_root,
			meron_dice_model_path,
			wala_dice_model_path,
			meron_roll,
			wala_roll,
			false # in_arena = false (on the table!)
		)

	# Wait for both dice to settle
	await _wait_for_dice_settle()

	dice_rolled.emit(meron_state.dice_result, wala_state.dice_result, meron_state.dice_result == wala_state.dice_result)

	# Give players a brief moment to see the dice at rest
	if is_inside_tree():
		await get_tree().create_timer(0.20).timeout

	_resolve_dice_outcome()

func _wait_for_dice_settle() -> void:
	if not is_inside_tree():
		return
	var dice: Array = DiceRoller3D.active_dice.duplicate()
	if dice.size() >= 2:
		var settled_count: int = 0
		var max_wait := 0.95
		var timer := get_tree().create_timer(max_wait)
		for die in dice:
			if die is DiceRigidBody3D:
				die.settled.connect(func(_val): settled_count += 1)
		while settled_count < dice.size() and timer.time_left > 0.0 and is_inside_tree():
			await get_tree().process_frame
	else:
		await get_tree().create_timer(0.75).timeout

func _resolve_dice_outcome() -> void:
	meron_state.discard_count = meron_state.dice_result
	wala_state.discard_count = wala_state.dice_result

	if meron_state.dice_result == wala_state.dice_result:
		is_clash_round = true
		meron_state.has_priority = false
		wala_state.has_priority = false
		priority_determined.emit("CLASH")
	else:
		is_clash_round = false
		var meron_wins_priority: bool = meron_state.dice_result > wala_state.dice_result
		meron_state.has_priority = meron_wins_priority
		wala_state.has_priority = not meron_wins_priority
		var winner_id: String = "MERON" if meron_wins_priority else "WALA"
		priority_determined.emit(winner_id)

	# Wait for the punchy YOU FIRST / YOU LAST screen pop announcement to display
	if is_inside_tree():
		await get_tree().create_timer(0.70).timeout
	_advance_phase()

## ---------------------------------------------------------------------------
## Roll Manipulation API (Self-Only, max 1 per player per round)
## ---------------------------------------------------------------------------

func request_reroll(player_id: String) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or state.card_rerolls_used >= MAX_CARD_ROLL_MANIPULATIONS_PER_ROUND:
		return false
	state.card_rerolls_used += 1
	state.dice_result = randi_range(1, 6)
	if state.duelist:
		state.duelist.current_dice_roll = state.dice_result
	roll_manipulated.emit(player_id, state.dice_result)
	return true

func request_modify_roll(player_id: String, delta: int) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or state.card_rerolls_used >= MAX_CARD_ROLL_MANIPULATIONS_PER_ROUND:
		return false
	state.card_rerolls_used += 1
	state.dice_result = clampi(state.dice_result + delta, 1, 6)
	if state.duelist:
		state.duelist.current_dice_roll = state.dice_result
	roll_manipulated.emit(player_id, state.dice_result)
	return true

func can_manipulate_roll(player_id: String) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.DICE_ROLL:
		return false
	return state.card_rerolls_used < MAX_CARD_ROLL_MANIPULATIONS_PER_ROUND

func pass_roll_manipulation(player_id: String) -> void:
	if current_phase == DuelPhase.Phase.DICE_ROLL:
		mark_player_ready(player_id)

func apply_roll_manipulation(player_id: String, card: CardData) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.DICE_ROLL:
		return false
	if state.card_rerolls_used >= MAX_CARD_ROLL_MANIPULATIONS_PER_ROUND:
		return false
	if not state.hand.has(card):
		return false

	var success: bool = false
	if card.is_dice_reroll:
		success = request_reroll(player_id)
	elif card.roll_delta != 0:
		success = request_modify_roll(player_id, card.roll_delta)

	if success:
		state.hand.erase(card)
		state.discard_pile.append(card)
		return true
	return false

## ---------------------------------------------------------------------------
## Phase 2: Discard Phase (Dice-Driven Count, Skipped Round 1)
## ---------------------------------------------------------------------------

func _run_discard_phase() -> void:
	_pending_discards["MERON"].clear()
	_pending_discards["WALA"].clear()

	var meron_auto_discarded: bool = false

	for state in [meron_state, wala_state]:
		var actual_discard: int = mini(state.discard_count, state.hand.size())
		discard_required.emit(state.player_id, actual_discard)
		DuelLogger.info("DuelPhaseManager", "Discard required for %s: %d cards (Dice result: %d, Hand: %d)" % [state.player_id, actual_discard, state.dice_result, state.hand.size()])

		# Auto-discard if required discard exceeds or equals total hand size
		if state.discard_count >= state.hand.size() and state.hand.size() > 0:
			var cards_to_discard: Array = state.hand.duplicate()
			_pending_discards[state.player_id] = cards_to_discard
			for card in cards_to_discard:
				if state.hand.has(card):
					state.hand.erase(card)
					state.discard_pile.append(card)
			mark_player_ready(state.player_id)
			DuelLogger.action(state.player_id, "AUTO_DISCARD_ALL", "Discard count (%d) >= Hand size (%d). All %d cards auto-discarded & bell rung." % [state.discard_count, cards_to_discard.size(), cards_to_discard.size()])
			auto_discarded.emit(state.player_id, cards_to_discard)
			if state.player_id == "MERON":
				meron_auto_discarded = true
		elif state.hand.is_empty():
			mark_player_ready(state.player_id)

	var hold_timer: SceneTreeTimer = null
	if meron_auto_discarded and is_inside_tree():
		# Brief hold so player can read the auto-discard notice before dealing fresh hand
		hold_timer = get_tree().create_timer(0.45)

	await _wait_for_both_sides_ready()

	if hold_timer and hold_timer.time_left > 0.0:
		await hold_timer.timeout
	elif is_inside_tree():
		# Brief pacing delay to allow card discard animations to finish cleanly
		await get_tree().create_timer(0.18).timeout

	# Process confirmed discards immediately
	for player_id in ["MERON", "WALA"]:
		var state: PlayerRoundState = get_state(player_id)
		var chosen: Array = _pending_discards.get(player_id, [])
		for card in chosen:
			if state.hand.has(card):
				state.hand.erase(card)
				state.discard_pile.append(card)
		_pending_discards[player_id].clear()

	_advance_phase()

func select_discard_card(player_id: String, card: CardData) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.DISCARD:
		DuelLogger.warn("DuelPhaseManager", "select_discard_card called outside DISCARD phase (current: %s) by %s" % [DuelPhase.Phase.keys()[current_phase], player_id])
		return false
	var actual_needed: int = mini(state.discard_count, state.hand.size())
	var current_list: Array = _pending_discards[player_id]

	# Handle duplicate card instances in hand safely
	var copies_in_hand: int = 0
	for c in state.hand:
		if c == card:
			copies_in_hand += 1
	var copies_selected: int = 0
	for c in current_list:
		if c == card:
			copies_selected += 1

	if copies_selected > 0 and copies_selected >= copies_in_hand:
		current_list.erase(card)
		DuelLogger.action(player_id, "UNSELECT_DISCARD", "Card: %s (Selected: %d/%d)" % [card.display_name, current_list.size(), actual_needed])
		return true
	elif current_list.size() < actual_needed:
		current_list.append(card)
		DuelLogger.action(player_id, "SELECT_DISCARD", "Card: %s (Selected: %d/%d)" % [card.display_name, current_list.size(), actual_needed])
		return true
	elif current_list.has(card):
		current_list.erase(card)
		DuelLogger.action(player_id, "UNSELECT_DISCARD", "Card: %s (Selected: %d/%d)" % [card.display_name, current_list.size(), actual_needed])
		return true
	return false

func get_selected_discards(player_id: String) -> Array:
	return _pending_discards.get(player_id, [])

func confirm_discard(player_id: String) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.DISCARD:
		DuelLogger.warn("DuelPhaseManager", "confirm_discard called outside DISCARD phase (current: %s) by %s" % [DuelPhase.Phase.keys()[current_phase], player_id])
		return false
	if is_player_ready(player_id):
		DuelLogger.warn("DuelPhaseManager", "confirm_discard ignored: %s is already ready" % player_id)
		return false
	var actual_needed: int = mini(state.discard_count, state.hand.size())
	var chosen: Array = _pending_discards.get(player_id, [])
	if chosen.size() < actual_needed:
		DuelLogger.warn("DuelPhaseManager", "%s tried to confirm discard with only %d/%d cards selected" % [player_id, chosen.size(), actual_needed])
		return false
	DuelLogger.action(player_id, "CONFIRM_DISCARD", "Confirmed %d discards" % chosen.size())
	for card in chosen:
		if state.hand.has(card):
			state.hand.erase(card)
			state.discard_pile.append(card)
	_pending_discards[player_id].clear()
	mark_player_ready(player_id)
	return true

## ---------------------------------------------------------------------------
## Phase 3: Draw Phase (Finite Deck with Discard Reshuffle, R1 = 3, R2+ = 6)
## ---------------------------------------------------------------------------

func _draw_single_card(state: PlayerRoundState) -> CardData:
	if state.duelist:
		return state.duelist.draw_card()
	if state.draw_pile.is_empty():
		if state.discard_pile.is_empty():
			return null
		state.draw_pile = state.discard_pile.duplicate()
		state.discard_pile.clear()
		state.draw_pile.shuffle()
	var card = state.draw_pile.pop_back()
	return card as CardData

func _draw_cards_for_player(state: PlayerRoundState, count: int) -> void:
	for _i in range(count):
		var card: CardData = _draw_single_card(state)
		if card:
			state.hand.append(card)
		else:
			break

func _run_draw_phase() -> void:
	var target_count: int = CARD_LIMIT # Draw up to 6 cards on start of round and all rounds
	for state in [meron_state, wala_state]:
		var needed: int = target_count - state.hand.size()
		if needed > 0:
			_draw_cards_for_player(state, needed)
			cards_drawn.emit(state.player_id, needed)

	if is_inside_tree():
		await get_tree().create_timer(0.45).timeout
	_advance_phase()

## ---------------------------------------------------------------------------
## Phase 4: Reroll Phase (3 Free Card Mulligans per Round)
## ---------------------------------------------------------------------------

func _run_reroll_phase() -> void:
	for state in [meron_state, wala_state]:
		state.free_rerolls_used = 0

	await _wait_for_both_sides_ready()
	_advance_phase()

func request_card_reroll(player_id: String, card: CardData, target_index: int = -1) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.REROLL:
		return false
	if state.free_rerolls_used >= FREE_REROLLS_PER_ROUND:
		return false

	# Identify the exact slot index of the card being rerolled
	var idx: int = target_index
	if idx < 0 or idx >= state.hand.size() or (state.hand[idx] != card and state.hand[idx].card_id != card.card_id):
		idx = state.hand.find(card)
	if idx == -1:
		return false

	state.free_rerolls_used += 1
	var old_card: CardData = state.hand[idx]
	state.discard_pile.append(old_card)

	# Draw replacement and substitute IN-PLACE at index `idx` so no other cards shift slots!
	var new_card: CardData = _draw_single_card(state)
	if new_card:
		state.hand[idx] = new_card
	else:
		state.hand.remove_at(idx)

	var remaining: int = FREE_REROLLS_PER_ROUND - state.free_rerolls_used
	card_rerolled.emit(player_id, old_card, remaining, idx)
	return true

func can_reroll(player_id: String) -> bool:
	var state: PlayerRoundState = get_state(player_id)
	if not state or current_phase != DuelPhase.Phase.REROLL:
		return false
	return state.free_rerolls_used < FREE_REROLLS_PER_ROUND

func finish_reroll(player_id: String) -> void:
	if current_phase == DuelPhase.Phase.REROLL:
		mark_player_ready(player_id)

## ---------------------------------------------------------------------------
## Phase 5: Fighting Phase (Priority Order vs Simultaneous Clash)
## ---------------------------------------------------------------------------

func _run_fighting_phase() -> void:
	# Sanity check: ensure no stale queued cards linger from earlier rounds
	var p1: Duelist = meron_state.duelist if meron_state else null
	var p2: Duelist = wala_state.duelist if wala_state else null
	if p1 and p1.queued_cards.size() > 0:
		DuelLogger.error("DuelPhaseManager", "Stale queued_cards detected on MERON entering Fighting phase (%d cards)! Auto-clearing." % p1.queued_cards.size())
		p1.reset_turn_for_new_round()
	if p2 and p2.queued_cards.size() > 0:
		DuelLogger.error("DuelPhaseManager", "Stale queued_cards detected on WALA entering Fighting phase (%d cards)! Auto-clearing." % p2.queued_cards.size())
		p2.reset_turn_for_new_round()

	# ------- ONLINE: CLIENT path -------
	# Blueprint §11: client submits card IDs to host, then waits for resolved events
	if is_online_match and not is_host_peer:
		# Wait for local player to select cards and ring the bell
		_phase_waiting = true
		if not is_player_ready("MERON"):
			_start_human_input_timeout(meron_state, HUMAN_TIMEOUT_SECONDS)
		while not is_player_ready("MERON"):
			await _ready_state_changed
		_phase_waiting = false
		_clear_human_timers()

		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			# Collect local player's (MERON=client's local) queued card IDs
			var card_ids: Array[String] = []
			if p1:
				for c in p1.queued_cards:
					card_ids.append(c.card_id if c else "")
			nm.submit_turn(card_ids)
			DuelLogger.info("DuelPhaseManager", "[CLIENT] Submitted %d card IDs to host. Waiting for resolution…" % card_ids.size())
			# Wait for host to broadcast resolved events
			var raw_events: Array = await nm.turn_received_from_host
			var events: Array[Dictionary] = _remap_events_for_client(raw_events)
			DuelLogger.info("DuelPhaseManager", "[CLIENT] Received %d combat events from host." % events.size())

			# Sync duelists' HP from server authoritative events
			for ev in events:
				if ev.has("p1_final_hp") and p1: p1.hp = ev["p1_final_hp"]
				if ev.has("p2_final_hp") and p2: p2.hp = ev["p2_final_hp"]

			combat_resolved.emit(events)
			# Play the 3D combat sequence
			var arena: ArenaController = arena_root as ArenaController
			if not arena and arena_root:
				arena = arena_root.get_node_or_null("ArenaController") as ArenaController
			if arena and arena.has_method("play_combat_sequence"):
				await arena.play_combat_sequence(events)
			else:
				await get_tree().create_timer(1.2).timeout
		if p1: p1.reset_turn_for_new_round()
		if p2: p2.reset_turn_for_new_round()
		_advance_phase()
		return

	# ------- ONLINE: HOST path (authoritative) -------
	# Blueprint §9: "Execute authoritative combat resolution"
	if is_online_match and is_host_peer:
		# Wait for host's local player to select cards and ring the bell
		_phase_waiting = true
		if not is_player_ready("MERON"):
			_start_human_input_timeout(meron_state, HUMAN_TIMEOUT_SECONDS)
		while not is_player_ready("MERON"):
			await _ready_state_changed
		_phase_waiting = false
		_clear_human_timers()

		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			# Submit host's own cards (MERON = host)
			var host_card_ids: Array[String] = []
			if p1:
				for c in p1.queued_cards:
					host_card_ids.append(c.card_id if c else "")
			nm.submit_turn(host_card_ids)
			DuelLogger.info("DuelPhaseManager", "[HOST] Submitted %d card IDs. Waiting for client…" % host_card_ids.size())
			# Wait for NetworkManager to signal that both sides have submitted
			await nm.turn_received_from_host
			DuelLogger.info("DuelPhaseManager", "[HOST] Both turns received. Running CombatEngine…")
		var priority_id: int = 1 if meron_state.has_priority else 2
		var events: Array[Dictionary] = CombatEngine.resolve_turn(p1, p2, current_round, priority_id, is_clash_round)
		DuelLogger.info("DuelPhaseManager", "[HOST] CombatEngine resolved %d events. Broadcasting…" % events.size())
		# Broadcast resolved events to client
		if nm: nm.broadcast_turn_events(events)
		combat_resolved.emit(events)
		# Play 3D combat sequence on host
		var arena: ArenaController = arena_root as ArenaController
		if not arena and arena_root:
			arena = arena_root.get_node_or_null("ArenaController") as ArenaController
		if arena and arena.has_method("play_combat_sequence"):
			await arena.play_combat_sequence(events)
		else:
			await get_tree().create_timer(1.2).timeout
		if p1: p1.reset_turn_for_new_round()
		if p2: p2.reset_turn_for_new_round()
		DuelLogger.info("DuelPhaseManager", "[HOST] Combat sequence complete. Turn buffers reset.")
		_advance_phase()
		return

	# ------- OFFLINE path (unchanged) -------
	await _wait_for_both_sides_ready()

	# Both players have locked in their cards; resolve via CombatEngine
	var priority_id: int = 1 if meron_state.has_priority else 2

	var p1_card_ids: Array = []
	if p1:
		for c in p1.queued_cards:
			p1_card_ids.append(c.card_id if c else "")
	var p2_card_ids: Array = []
	if p2:
		for c in p2.queued_cards:
			p2_card_ids.append(c.card_id if c else "")
	DuelLogger.info("DuelPhaseManager", "Combat Resolving: P1 cards=%s | P2 cards=%s | Priority=%d | Clash=%s" % [str(p1_card_ids), str(p2_card_ids), priority_id, str(is_clash_round)])

	var events: Array[Dictionary] = CombatEngine.resolve_turn(
		p1,
		p2,
		current_round,
		priority_id,
		is_clash_round
	)
	combat_resolved.emit(events)

	# Run 3D sequence through ArenaController if present
	var arena: ArenaController = arena_root as ArenaController
	if not arena and arena_root:
		arena = arena_root.get_node_or_null("ArenaController") as ArenaController

	if arena and arena.has_method("play_combat_sequence"):
		await arena.play_combat_sequence(events)
	else:
		await get_tree().create_timer(1.2).timeout

	# Immediately move all played queued cards to discard pile and reset buffers!
	if p1:
		p1.reset_turn_for_new_round()
	if p2:
		p2.reset_turn_for_new_round()
	DuelLogger.info("DuelPhaseManager", "Combat sequence complete. Turn buffers reset and played cards moved to discard pile.")

	_advance_phase()

## ---------------------------------------------------------------------------
## Phase 6: Round End Phase
## ---------------------------------------------------------------------------

func _run_round_end() -> void:
	round_ended.emit(current_round)

	var p1: Duelist = meron_state.duelist
	var p2: Duelist = wala_state.duelist
	var duel_over: bool = false
	var winner_id: String = ""

	if p1 and p2:
		if p1.hp <= 0 and p2.hp <= 0:
			duel_over = true
			winner_id = "DRAW"
		elif p1.hp <= 0:
			duel_over = true
			winner_id = "WALA"
		elif p2.hp <= 0:
			duel_over = true
			winner_id = "MERON"

	if duel_over:
		DuelLogger.info("DuelPhaseManager", "Duel concluded! Winner: %s" % winner_id)
		duel_finished.emit(winner_id)
		return # Do not advance — duel concluded!

	# Ensure turn buffers are reset for the new round
	if p1:
		p1.reset_turn_for_new_round()
	if p2:
		p2.reset_turn_for_new_round()

	# Hold in ARENA_VIEW briefly so players can view the Round End arena phase notification
	if is_inside_tree():
		await get_tree().create_timer(0.60).timeout
	else:
		await get_tree().create_timer(0.05).timeout
	_advance_phase()

## ---------------------------------------------------------------------------
## Unified Ready & Input Waiting Pattern (Section 9)
## ---------------------------------------------------------------------------

func mark_player_ready(player_id: String) -> void:
	_ready_map[player_id] = true
	player_ready_updated.emit(player_id, true)
	_ready_state_changed.emit()

func is_player_ready(player_id: String) -> bool:
	return _ready_map.get(player_id, false)

func _wait_for_both_sides_ready() -> void:
	_phase_waiting = true

	if is_online_match:
		if not is_player_ready("MERON"):
			_start_human_input_timeout(meron_state, HUMAN_TIMEOUT_SECONDS)
		while not is_player_ready("MERON"):
			await _ready_state_changed
		_phase_waiting = false
		_clear_human_timers()
		return

	for state in [meron_state, wala_state]:
		if is_player_ready(state.player_id):
			continue
		if state.is_ai:
			_run_ai_decision_for_current_phase(state)
		else:
			_start_human_input_timeout(state, HUMAN_TIMEOUT_SECONDS)

	while not (_ready_map.get("MERON", false) and _ready_map.get("WALA", false)):
		await _ready_state_changed

	_phase_waiting = false
	_clear_human_timers()

func _start_human_input_timeout(state: PlayerRoundState, seconds: float) -> void:
	if not is_inside_tree():
		return
	_timer_generation_token += 1
	var token: int = _timer_generation_token
	var phase_when_started: DuelPhase.Phase = current_phase
	var timer := get_tree().create_timer(seconds)
	_human_timers[state.player_id] = timer
	timer.timeout.connect(func():
		if _timer_generation_token != token:
			return # Stale timer from previous phase/round
		if current_phase != phase_when_started:
			return # Phase already changed
		if _phase_waiting and not is_player_ready(state.player_id):
			DuelLogger.info("DuelPhaseManager", "Human input timeout reached for %s in %s" % [state.player_id, DuelPhase.Phase.keys()[current_phase]])
			_auto_resolve_current_phase_for(state)
			mark_player_ready(state.player_id)
	)

func _clear_human_timers() -> void:
	_timer_generation_token += 1
	_human_timers.clear()

func get_time_remaining(player_id: String = "MERON") -> float:
	if _human_timers.has(player_id):
		var t = _human_timers[player_id]
		if t is SceneTreeTimer:
			return t.time_left
	return 0.0

func _auto_resolve_current_phase_for(state: PlayerRoundState) -> void:
	match current_phase:
		DuelPhase.Phase.DICE_ROLL:
			# Pass on roll manipulation
			pass
		DuelPhase.Phase.DISCARD:
			# Auto-select first N cards if player hasn't picked enough
			var actual_needed: int = mini(state.discard_count, state.hand.size())
			var current_list: Array = _pending_discards[state.player_id]
			while current_list.size() < actual_needed:
				for card in state.hand:
					if not current_list.has(card):
						current_list.append(card)
						break
			if state.player_id == "MERON" and current_list.size() > 0:
				auto_discarded.emit("MERON", current_list.duplicate())
		DuelPhase.Phase.REROLL:
			# Done rerolling
			pass
		DuelPhase.Phase.FIGHTING:
			# Pass / lock whatever cards are currently queued
			pass

func _run_ai_decision_for_current_phase(state: PlayerRoundState) -> void:
	if not is_inside_tree():
		mark_player_ready(state.player_id)
		return
	# Natural snappy pacing delay (~0.10 - 0.22s) so AI feels responsive without stall
	var delay: float = randf_range(0.10, 0.22)
	await get_tree().create_timer(delay).timeout
	if not _phase_waiting:
		return

	match current_phase:
		DuelPhase.Phase.DICE_ROLL:
			# AI roll manipulation: if roll <= 3 and has roll manipulation card, use it
			if state.dice_result <= 3 and state.card_rerolls_used == 0:
				for card in state.hand:
					if card.card_type == CardData.CardType.ROLL_MANIPULATION or card.is_dice_reroll or card.roll_delta != 0:
						if apply_roll_manipulation(state.player_id, card):
							break
			mark_player_ready(state.player_id)

		DuelPhase.Phase.DISCARD:
			var actual_needed: int = mini(state.discard_count, state.hand.size())
			var discards: Array = []
			# Discard lowest utility cards first
			for card in state.hand:
				if discards.size() >= actual_needed:
					break
				discards.append(card)
			_pending_discards[state.player_id] = discards
			mark_player_ready(state.player_id)

		DuelPhase.Phase.REROLL:
			# AI reroll: up to 2 cards if hand has unplayable or duplicate cards
			if state.hand.size() > 2 and state.free_rerolls_used < 2:
				var candidate = state.hand[0]
				request_card_reroll(state.player_id, candidate)
			mark_player_ready(state.player_id)

		DuelPhase.Phase.FIGHTING:
			if state.duelist and meron_state.duelist:
				AIController.make_ai_turn(state.duelist, meron_state.duelist)
			mark_player_ready(state.player_id)

		_:
			mark_player_ready(state.player_id)

## Remaps combat events received from host to client local perspective (swaps duelist 1 <-> 2)
func _remap_events_for_client(raw_events: Array) -> Array[Dictionary]:
	var remapped: Array[Dictionary] = []
	for raw in raw_events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw.duplicate(true)

		# Swap duelist ID (1 <-> 2)
		if ev.has("duelist"):
			var d = ev["duelist"]
			if d == 1: ev["duelist"] = 2
			elif d == 2: ev["duelist"] = 1
			elif str(d) == "1": ev["duelist"] = 2
			elif str(d) == "2": ev["duelist"] = 1

		# Swap attacker (1 <-> 2)
		if ev.has("attacker"):
			var a = ev["attacker"]
			if a == 1: ev["attacker"] = 2
			elif a == 2: ev["attacker"] = 1
			elif str(a) == "1": ev["attacker"] = 2
			elif str(a) == "2": ev["attacker"] = 1

		# Swap target / defender (1 <-> 2)
		if ev.has("target"):
			var t = ev["target"]
			if t == 1: ev["target"] = 2
			elif t == 2: ev["target"] = 1
			elif str(t) == "1": ev["target"] = 2
			elif str(t) == "2": ev["target"] = 1

		if ev.has("defender"):
			var def_id = ev["defender"]
			if def_id == 1: ev["defender"] = 2
			elif def_id == 2: ev["defender"] = 1
			elif str(def_id) == "1": ev["defender"] = 2
			elif str(def_id) == "2": ev["defender"] = 1

		if ev.has("predictor"):
			var pred_id = ev["predictor"]
			if pred_id == 1: ev["predictor"] = 2
			elif pred_id == 2: ev["predictor"] = 1
			elif str(pred_id) == "1": ev["predictor"] = 2
			elif str(pred_id) == "2": ev["predictor"] = 1

		# Swap source_player_id
		if ev.has("source_player_id"):
			var sp = ev["source_player_id"]
			if sp == 1: ev["source_player_id"] = 2
			elif sp == 2: ev["source_player_id"] = 1

		# Swap HP fields
		if ev.has("p1_hp") and ev.has("p2_hp"):
			var temp = ev["p1_hp"]
			ev["p1_hp"] = ev["p2_hp"]
			ev["p2_hp"] = temp

		if ev.has("p1_final_hp") and ev.has("p2_final_hp"):
			var temp = ev["p1_final_hp"]
			ev["p1_final_hp"] = ev["p2_final_hp"]
			ev["p2_final_hp"] = temp

		# Swap winner / winner_id
		if ev.has("winner"):
			var w = ev["winner"]
			if w == 1: ev["winner"] = 2
			elif w == 2: ev["winner"] = 1
			elif str(w) == "MERON": ev["winner"] = "WALA"
			elif str(w) == "WALA": ev["winner"] = "MERON"

		if ev.has("winner_id"):
			var wi = ev["winner_id"]
			if wi == 1: ev["winner_id"] = 2
			elif wi == 2: ev["winner_id"] = 1
			elif str(wi) == "MERON": ev["winner_id"] = "WALA"
			elif str(wi) == "WALA": ev["winner_id"] = "MERON"

		remapped.append(ev)
	return remapped
