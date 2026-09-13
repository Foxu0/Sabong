extends RefCounted
class_name Duelist

## Duelist — Runtime state for one combatant in a Sabong match.

var duelist_id: int = 0                  # 1 for P1 (Meron), 2 for P2 (Wala)
var display_name: String = "Rooster"
var rooster_data: RoosterData

# Health & Defense
var max_hp: int = 20
var hp: int = 20
var shield: int = 0
var dot_stacks: int = 0                  # capped at 5 stacks, ticks 1 dmg/stack/turn

# Energy / Bet Currency & Dice Roll
var taya_remaining: int = 3
const MAX_TAYA: int = 3
var current_dice_roll: int = 1           # 1-6 rolled at start of round

# Deck & Hand state (Random Draw mechanic)
const MAX_HAND_SIZE: int = 6
var deck: Array[CardData] = []
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var queued_cards: Array[CardData] = []
var card_committed_taya: Dictionary = {} # card_id -> int (for variable taya cards)
var passive_cards: Array[CardData] = []      # Passive trigger cards (e.g. Platinum Chick)
var active_buffs: Array[Dictionary] = []     # Active turn buffs: [{ "stat": "heal", "amount": 2, "turns_left": 3 }]

# Character-Specific Combat Mechanics & Forms
var tension_stacks: int = 0              # Cluckey D Puffy (Gear 5 requirement)
var demonic_aura_stacks: int = 0          # Nechicko
var titan_form_active: bool = false       # Eren Pecker
var titan_turns_left: int = 0
var titan_just_activated: bool = false
var golden_form_active: bool = false      # Hen-Goku
var all_for_one_active: bool = false      # Decluck
var all_for_one_turns_left: int = 0
var gear_5_active: bool = false           # Cluckey D Puffy
var demon_form_active: bool = false       # Nechicko
var demon_form_turns_left: int = 0
var return_by_death_used: bool = false    # Daniel
var stand_counter_active: bool = false    # Cocktaro
var secret_prediction: String = ""       # Chick Yagami: "ATTACK", "GUARD", "SPECIAL"
var bonus_flat_attack: int = 0

func _init(p_id: int = 1, p_name: String = "Rooster", p_rooster: RoosterData = null) -> void:
	duelist_id = p_id
	display_name = p_name
	rooster_data = p_rooster
	if rooster_data:
		max_hp = rooster_data.base_hp
		hp = rooster_data.base_hp
	else:
		max_hp = 20
		hp = 20

const PASSIVE_CARD_IDS: Array[String] = [
	"hen_goku_golden_form",
	"cocktaro_platinum_chick",
	"daniel_chick_to_zero"
]

## Helper to identify special transformation / ultimate cards that must be unique (1-per-deck / consumed first)
func is_special_transformation_card(card: CardData) -> bool:
	if not card:
		return false
	if card.card_id == "eren_titan_stomp":
		return false
	if card.card_type == CardData.CardType.SPECIAL:
		return true
	if card.usage_gate == CardData.UsageGate.ONCE_PER_MATCH:
		return true
	var id_lower: String = card.card_id.to_lower()
	if "5th_gear" in id_lower or "pecker_titan" in id_lower or "demon_form" in id_lower or "all_for_one_cock" in id_lower or "golden_form" in id_lower or "chick_to_zero" in id_lower:
		return true
	if card.usage_gate == CardData.UsageGate.STATE_LOCKED:
		return true
	return false

## Builds the initial deck (universal + signature moves, strictly excluding passive triggers) and shuffles.
func setup_deck(universal_cards: Array[CardData]) -> void:
	deck.clear()
	hand.clear()
	discard_pile.clear()
	queued_cards.clear()
	card_committed_taya.clear()
	passive_cards.clear()
	active_buffs.clear()

	# Add 8 universal cards to deck (duplicated as distinct instances)
	for card in universal_cards:
		if card:
			deck.append(card.duplicate())

	# Add signature moves: passives go to passive_cards list only.
	# Special / Transformation cards get EXACTLY 1 unique copy in the entire deck.
	# Standard signature combat cards get 2 copies for consistency.
	if rooster_data and rooster_data.moveset.size() > 0:
		for card in rooster_data.moveset:
			if card:
				if PASSIVE_CARD_IDS.has(card.card_id) or card.is_passive_trigger:
					passive_cards.append(card.duplicate())
				elif card.card_id == "eren_titan_stomp":
					# In human form, Eren starts with NO Titan Stomps in deck.
					# They all start as Claw Stomps, and only awaken into Titan Stomps when Eren activates Pecker Titan!
					var claw_res: CardData = null
					if ResourceLoader.exists("res://resources/cards/eren_claw_stomp.tres"):
						claw_res = load("res://resources/cards/eren_claw_stomp.tres")
					var c_to_add: CardData = claw_res.duplicate() if claw_res else card.duplicate()
					deck.append(c_to_add.duplicate())
					deck.append(c_to_add.duplicate())
				elif is_special_transformation_card(card):
					# Strictly 1 unique copy of special/transformation cards in deck
					deck.append(card.duplicate())
				else:
					# 2 distinct unique copies of standard signature cards
					var c_to_add: CardData = card.duplicate()
					deck.append(c_to_add.duplicate())
					deck.append(c_to_add.duplicate())

	deck.shuffle()

## Transforms Eren's cards between Human (Claw Stomp) and Titan (Titan Stomp) forms
func transform_eren_cards(to_titan: bool) -> void:
	var target_res_path: String = "res://resources/cards/eren_titan_stomp.tres" if to_titan else "res://resources/cards/eren_claw_stomp.tres"
	var source_id: String = "eren_claw_stomp" if to_titan else "eren_titan_stomp"
	if not ResourceLoader.exists(target_res_path):
		return
	var template: CardData = load(target_res_path)
	if not template:
		return

	for card_list in [hand, deck, discard_pile, queued_cards]:
		for i in range(card_list.size()):
			if card_list[i] and card_list[i].card_id == source_id:
				card_list[i] = template.duplicate()

## Helper to find an active passive trigger card on this duelist
func get_passive_trigger(condition: String) -> CardData:
	for p in passive_cards:
		if p.trigger_condition == condition:
			return p
	return null

## Helper to get total active buff value for a stat (e.g. "heal")
func get_stat_buff(stat_name: String) -> int:
	var total: int = 0
	for b in active_buffs:
		if b.get("stat", "") == stat_name and int(b.get("turns_left", 0)) > 0:
			total += int(b.get("amount", 0))
	return total

## Rolls the rooster's 3D dice for the current round
func roll_dice() -> int:
	current_dice_roll = randi_range(1, 6)
	return current_dice_roll

## Draws a single card from deck, reshuffling discard pile if deck is empty before drawing.
## Strictly prevents drawing duplicate special/transformation cards if one is already unconsumed in hand.
func draw_card() -> CardData:
	if deck.is_empty():
		if discard_pile.is_empty():
			return null # Nothing left anywhere — hand stays short
		deck = discard_pile.duplicate()
		discard_pile.clear()
		deck.shuffle()
	
	if not deck.is_empty():
		for i in range(deck.size()):
			var candidate: CardData = deck[i]
			if is_special_transformation_card(candidate):
				var already_has: bool = false
				for h in hand:
					if h.card_id == candidate.card_id:
						already_has = true
						break
				if already_has:
					continue
				else:
					deck.remove_at(i)
					return candidate
			else:
				deck.remove_at(i)
				return candidate
		
		# If only duplicate specials remain in deck, return the first card
		return deck.pop_front()
	return null

## Draws cards from deck until hand reaches max_size (default MAX_HAND_SIZE = 6)
func draw_cards_up_to_max(max_size: int = MAX_HAND_SIZE) -> int:
	var drawn_count: int = 0
	while hand.size() < max_size:
		var card: CardData = draw_card()
		if not card:
			break
		hand.append(card)
		drawn_count += 1
	return drawn_count

## Legacy helper (draws a specific count up to MAX_HAND_SIZE)
func draw_cards(count: int = 4) -> void:
	for _i in range(count):
		if hand.size() >= MAX_HAND_SIZE:
			break
		var card: CardData = draw_card()
		if not card:
			break
		hand.append(card)

## Discards a single card from hand into discard pile
func discard_card(card: CardData) -> bool:
	if hand.has(card):
		hand.erase(card)
		discard_pile.append(card)
		return true
	return false


## Checks if the player can afford and play a specific card
func can_play_card(card: CardData, extra_taya: int = 0) -> bool:
	var total_cost: int = card.taya_cost + extra_taya
	if total_cost > taya_remaining:
		return false

	# Passive trigger cards are not actively playable
	if card.is_passive_trigger:
		return false

	# Dice Requirement check (Rolled dice face must meet card requirement)
	if current_dice_roll < card.dice_requirement:
		return false
	
	# Check usage gates & required states
	if card.usage_gate == CardData.UsageGate.STATE_LOCKED:
		if (card.required_state == "titan_mode_active" or card.required_state == "titan_form_active") and not titan_form_active:
			return false
		if card.required_state == "tension_ge_5" and tension_stacks < 5:
			return false
	
	# Generic Category Lockout check (e.g. Titan Stomp locks out GUARD)
	if card.locks_out_card_type != -1:
		for q in queued_cards:
			if q.card_type == card.locks_out_card_type:
				return false

	for q in queued_cards:
		if q.locks_out_card_type != -1 and card.card_type == q.locks_out_card_type:
			return false

	return true

## Queues a card from hand to play this turn
func queue_card(card: CardData, committed_taya: int = 0) -> bool:
	var cost: int = card.taya_cost if not card.is_variable_cost else (card.taya_cost + committed_taya)
	if cost > taya_remaining:
		return false
	
	if not hand.has(card):
		return false

	hand.erase(card)
	queued_cards.append(card)
	card_committed_taya[card] = cost
	card_committed_taya[card.card_id] = cost
	taya_remaining -= cost
	return true

## Removes a card from queue back into hand
func unqueue_card(card: CardData) -> void:
	if queued_cards.has(card):
		queued_cards.erase(card)
		var cost: int = card_committed_taya.get(card, card_committed_taya.get(card.card_id, card.taya_cost))
		taya_remaining += cost
		card_committed_taya.erase(card)
		var other_has_id: bool = false
		for q in queued_cards:
			if q.card_id == card.card_id:
				other_has_id = true
				break
		if not other_has_id:
			card_committed_taya.erase(card.card_id)
		hand.append(card)

## Resets turn energy, updates buff durations, and discards played cards
func reset_turn_for_new_round() -> void:
	for c in queued_cards:
		discard_pile.append(c)
	queued_cards.clear()
	card_committed_taya.clear()
	taya_remaining = MAX_TAYA
	shield = 0

	# Decrement active buffs
	var remaining_buffs: Array[Dictionary] = []
	for b in active_buffs:
		b["turns_left"] = int(b.get("turns_left", 0)) - 1
		if int(b.get("turns_left", 0)) > 0:
			remaining_buffs.append(b)
		else:
			if str(b.get("stat", "")) == "heal":
				demon_form_active = false
	active_buffs = remaining_buffs

## Calculates missing HP percentage (0.0 to 1.0) for low-HP scaling cards
func get_missing_hp_ratio() -> float:
	if max_hp <= 0:
		return 0.0
	return max(0.0, float(max_hp - hp) / float(max_hp))

## Helper: sum base values of queued cards of a type
func sum_by_type(type: CardData.CardType) -> int:
	var total: int = 0
	for c in queued_cards:
		if c.card_type == type:
			total += c.base_value
	return total

