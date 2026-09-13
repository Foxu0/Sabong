extends RefCounted
class_name CombatEngine

## CombatEngine — Authoritative simultaneous turn resolution arbiter for Sabong Roosters.

# Combat Event constants for animation & UI sequencing
enum EventType {
	TURN_START,
	SELF_DAMAGE,
	TRANSFORM,
	PREDICTION_RESULT,
	SHIELD_GAIN,
	ATTACK_HIT,
	COUNTER_HIT,
	HEAL,
	DOT_APPLY,
	DOT_TICK,
	REVIVE,
	TURN_DECAY,
	MATCH_END
}

## Resolves a single turn simultaneously between Player 1 (Meron) and Player 2 (Wala).
## Returns a detailed array of event dictionaries for UI and 3D visual execution.
static func resolve_turn(p1: Duelist, p2: Duelist, turn_number: int, priority_player_id: int = 1, is_clash: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not p1 or not p2:
		return events

	events.append({
		"type": EventType.TURN_START,
		"turn": turn_number,
		"p1_hp": p1.hp,
		"p2_hp": p2.hp
	})

	# -----------------------------------------------------------------------
	# 0. Self-Damage & Activation HP Costs
	# -----------------------------------------------------------------------
	_process_self_costs(p1, events)
	_process_self_costs(p2, events)

	# -----------------------------------------------------------------------
	# 1. Phase 1: Transformations & Stances
	# -----------------------------------------------------------------------
	_process_transformations(p1, events)
	_process_transformations(p2, events)

	# -----------------------------------------------------------------------
	# 2. Phase 2: Predictions & Traps (Chick Yagami)
	# -----------------------------------------------------------------------
	_process_predictions(p1, p2, events)
	_process_predictions(p2, p1, events)

	# -----------------------------------------------------------------------
	# 3. Phase 3: Defensive Buffs & Shielding
	# -----------------------------------------------------------------------
	_process_shields(p1, turn_number, events)
	_process_shields(p2, turn_number, events)

	# -----------------------------------------------------------------------
	# 4. Phase 4: Attacks & Mitigations (Priority vs Simultaneous Clash)
	# -----------------------------------------------------------------------
	var p1_absorbed_damage: int = 0
	var p2_absorbed_damage: int = 0
	var p1_took_hit: bool = false
	var p2_took_hit: bool = false

	var p1_atk_result: Dictionary = _calculate_attack(p1, p2, turn_number)
	var p2_atk_result: Dictionary = _calculate_attack(p2, p1, turn_number)

	if is_clash:
		# Simultaneous Clash: both attacks resolve at once
		var r1: Dictionary = _apply_attack_list(p1, p2, p1_atk_result, events)
		var r2: Dictionary = _apply_attack_list(p2, p1, p2_atk_result, events)
		p2_absorbed_damage = r1.get("absorbed", 0)
		p2_took_hit = r1.get("took_hit", false)
		p1_absorbed_damage = r2.get("absorbed", 0)
		p1_took_hit = r2.get("took_hit", false)
	else:
		# Sequential Priority: Winner strikes first; defender strikes if still alive
		if priority_player_id == 1:
			var r1: Dictionary = _apply_attack_list(p1, p2, p1_atk_result, events)
			p2_absorbed_damage = r1.get("absorbed", 0)
			p2_took_hit = r1.get("took_hit", false)
			if p2.hp > 0:
				var r2: Dictionary = _apply_attack_list(p2, p1, p2_atk_result, events)
				p1_absorbed_damage = r2.get("absorbed", 0)
				p1_took_hit = r2.get("took_hit", false)
		else:
			var r2: Dictionary = _apply_attack_list(p2, p1, p2_atk_result, events)
			p1_absorbed_damage = r2.get("absorbed", 0)
			p1_took_hit = r2.get("took_hit", false)
			if p1.hp > 0:
				var r1: Dictionary = _apply_attack_list(p1, p2, p1_atk_result, events)
				p2_absorbed_damage = r1.get("absorbed", 0)
				p2_took_hit = r1.get("took_hit", false)

	# -----------------------------------------------------------------------
	# 5. Phase 5: Reactive Counters (Cocktaro Stand Counter)
	# -----------------------------------------------------------------------
	_process_counters(p1, p2, p1_absorbed_damage, p1_took_hit, events)
	_process_counters(p2, p1, p2_absorbed_damage, p2_took_hit, events)

	# -----------------------------------------------------------------------
	# 6. Phase 6: Healing & Aura Buffs
	# -----------------------------------------------------------------------
	_process_healing(p1, turn_number, events)
	_process_healing(p2, turn_number, events)

	# -----------------------------------------------------------------------
	# 7. Phase 7: DoT Applications & Ticks
	# -----------------------------------------------------------------------
	_process_dots(p1, p2, events)
	_process_dots(p2, p1, events)

	# DoT Ticks (each stack deals 1 damage, bypasses shield)
	_tick_dot(p1, events)
	_check_hp_passives(p1, events)
	_tick_dot(p2, events)
	_check_hp_passives(p2, events)

	# -----------------------------------------------------------------------
	# 8. Phase 8: Turn Decay & Transformation Upkeep
	# -----------------------------------------------------------------------
	_process_turn_decay(p1, events)
	_process_turn_decay(p2, events)

	# -----------------------------------------------------------------------
	# 9. Phase 9: Death & Revival Check (Daniel Return by Death & KO)
	# -----------------------------------------------------------------------
	_check_revival(p1, events)
	_check_revival(p2, events)

	# Check final win condition for this turn
	var winner_id: int = 0
	if p1.hp <= 0 and p2.hp <= 0:
		winner_id = -1 # Draw
	elif p1.hp <= 0:
		winner_id = p2.duelist_id
	elif p2.hp <= 0:
		winner_id = p1.duelist_id

	events.append({
		"type": EventType.MATCH_END if (p1.hp <= 0 or p2.hp <= 0) else EventType.TURN_START,
		"winner": winner_id,
		"winner_id": winner_id,
		"p1_final_hp": p1.hp,
		"p2_final_hp": p2.hp
	})

	return events

# ---------------------------------------------------------------------------
# Private Helper Methods for Turn Phases
# ---------------------------------------------------------------------------

static func _check_hp_passives(duelist: Duelist, events: Array[Dictionary]) -> void:
	if duelist.hp <= 0 or duelist.max_hp <= 0:
		return
	
	# Hen-Goku Auto trigger for Golden Form (triggers immediately when HP <= 50%)
	var has_golden_passive: bool = (duelist.get_passive_trigger("hp_le_50") != null) or (duelist.get_passive_trigger("hp_le_25") != null) or (duelist.rooster_data and duelist.rooster_data.rooster_id == "hen_goku")
	if has_golden_passive and (float(duelist.hp) / float(duelist.max_hp) <= 0.50) and not duelist.golden_form_active:
		duelist.golden_form_active = true
		duelist.bonus_flat_attack += 3
		events.append({
			"type": EventType.TRANSFORM,
			"duelist": duelist.duelist_id,
			"form": "golden_form",
			"model_path": duelist.rooster_data.alt_model_path if duelist.rooster_data else "",
			"text": "Golden Hen-Goku Awakened! (+3 Flat ATK)"
		})

static func _process_self_costs(duelist: Duelist, events: Array[Dictionary]) -> void:
	for card in duelist.queued_cards:
		if card.self_damage > 0:
			duelist.hp = max(1, duelist.hp - card.self_damage)
			events.append({
				"type": EventType.SELF_DAMAGE,
				"duelist": duelist.duelist_id,
				"card_id": card.card_id,
				"amount": card.self_damage,
				"remaining_hp": duelist.hp
			})
			_check_hp_passives(duelist, events)

static func _process_transformations(duelist: Duelist, events: Array[Dictionary]) -> void:
	_check_hp_passives(duelist, events)
	# Hen-Goku Auto trigger for Golden Form (Passive Slot: triggers when HP <= 25%)
	var has_golden_passive: bool = (duelist.get_passive_trigger("hp_le_25") != null) or (duelist.rooster_data and duelist.rooster_data.rooster_id == "hen_goku")
	if has_golden_passive and (duelist.get_missing_hp_ratio() >= 0.75) and not duelist.golden_form_active:
		duelist.golden_form_active = true
		duelist.bonus_flat_attack += 3
		events.append({
			"type": EventType.TRANSFORM,
			"duelist": duelist.duelist_id,
			"form": "golden_form",
			"model_path": duelist.rooster_data.alt_model_path if duelist.rooster_data else "",
			"text": "Golden Hen-Goku Awakened! (+3 Flat ATK)"
		})


	# Decluck All for One Cock
	for card in duelist.queued_cards:
		if card.card_id == "decluck_all_for_one_cock":
			duelist.all_for_one_active = true
			duelist.all_for_one_turns_left = 3
			events.append({
				"type": EventType.TRANSFORM,
				"duelist": duelist.duelist_id,
				"form": "all_for_one",
				"model_path": duelist.rooster_data.alt_model_path,
				"text": "All For One Cock Activated! (2x Taya Power for 3 turns)"
			})

	# Eren Pecker Titan
	for card in duelist.queued_cards:
		if card.card_id == "eren_pecker_titan":
			duelist.titan_form_active = true
			duelist.titan_turns_left = 3
			duelist.titan_just_activated = true
			duelist.dot_stacks = 0 # Clears DoT!
			if duelist.has_method("transform_eren_cards"):
				duelist.transform_eren_cards(true)
			events.append({
				"type": EventType.TRANSFORM,
				"duelist": duelist.duelist_id,
				"form": "titan_form",
				"model_path": duelist.rooster_data.alt_model_path,
				"text": "Eren transformed into Pecker Titan! (+1/+2/+4 ATK, +2 HP/turn, Clears DoT)"
			})

	# Cluckey 5th Gear
	for card in duelist.queued_cards:
		if card.card_id == "cluckey_5th_gear" and duelist.tension_stacks >= 5:
			duelist.gear_5_active = true
			events.append({
				"type": EventType.TRANSFORM,
				"duelist": duelist.duelist_id,
				"form": "gear_5",
				"model_path": duelist.rooster_data.alt_model_path,
				"text": "5th Gear Activated! (Rubber Drums Awakening)"
			})

	# Nechicko Demon Form
	for card in duelist.queued_cards:
		if card.card_id == "nechicko_demon_form":
			duelist.demon_form_active = true
			duelist.demon_form_turns_left = 3
			duelist.demonic_aura_stacks = 0 # Consumes aura on activation
			if card.buff_stat != "" and card.buff_amount > 0:
				duelist.active_buffs.append({
					"stat": card.buff_stat,
					"amount": card.buff_amount,
					"turns_left": card.buff_duration if card.buff_duration > 0 else 3
				})
			events.append({
				"type": EventType.TRANSFORM,
				"duelist": duelist.duelist_id,
				"form": "demon_form",
				"model_path": duelist.rooster_data.alt_model_path,
				"text": "Nechicko Demon Form! (+2 Heal power for 3 turns)"
			})

static func _process_predictions(predictor: Duelist, target: Duelist, events: Array[Dictionary]) -> void:
	if predictor.secret_prediction != "":
		var pred: String = predictor.secret_prediction.to_upper()
		var success: bool = false
		var matched_card_name: String = ""

		for c in target.queued_cards:
			match pred:
				"ATTACK":
					# Attack category includes direct Attacks & Poop DoT
					if c.card_type == CardData.CardType.ATTACK or c.card_type == CardData.CardType.DOT:
						success = true
						matched_card_name = c.display_name
						break
				"DEFEND", "GUARD":
					# Defend category includes Shields (Guard) & Heals
					if c.card_type == CardData.CardType.GUARD or c.card_type == CardData.CardType.HEAL:
						success = true
						matched_card_name = c.display_name
						break
				"SPECIAL":
					# Special category includes Specials & Roll Manipulations / Buffs
					if c.card_type == CardData.CardType.SPECIAL or c.card_type == CardData.CardType.ROLL_MANIPULATION:
						success = true
						matched_card_name = c.display_name
						break
				_:
					var tname: String = CardData.CardType.keys()[c.card_type]
					if pred == tname:
						success = true
						matched_card_name = c.display_name
						break

		if success:
			target.dot_stacks = min(5, target.dot_stacks + 2)
			events.append({
				"type": EventType.PREDICTION_RESULT,
				"predictor": predictor.duelist_id,
				"target": target.duelist_id,
				"success": true,
				"prediction": pred,
				"text": "Ryuk's Watch predicted %s correctly! (Opponent played %s) -> Opponent gains +2 Poop DoT stacks." % [pred, matched_card_name]
			})
		else:
			events.append({
				"type": EventType.PREDICTION_RESULT,
				"predictor": predictor.duelist_id,
				"target": target.duelist_id,
				"success": false,
				"prediction": pred,
				"text": "Ryuk's Watch predicted %s, but opponent did not play a matching card." % pred
			})
		predictor.secret_prediction = ""

static func _process_shields(duelist: Duelist, _turn: int, events: Array[Dictionary]) -> void:
	var total_shield: int = 0
	duelist.stand_counter_active = false

	for card in duelist.queued_cards:
		if card.card_type == CardData.CardType.GUARD:
			var s: int = card.base_value
			# Hen-Goku Barrier scaling with missing HP
			if card.card_id == "hen_goku_kikiriki_barrier":
				var bonus: int = int(duelist.get_missing_hp_ratio() / 0.25)
				s += bonus
			# Decluck Heart scaling with extra taya: +2 Shield per extra Taya (+4 in AFO)
			elif card.card_id == "decluck_all_for_one_heart":
				var spent: int = duelist.card_committed_taya.get(card.card_id, 1)
				var per_taya: int = 4 if duelist.all_for_one_active else 2
				s = 1 + (spent - 1) * per_taya
			# Cluckey Gum Barrier gives +2 Tension (or 6 Shield in 5th Gear)
			elif card.card_id == "cluckey_gum_barrier":
				if not duelist.gear_5_active:
					duelist.tension_stacks += 2
				else:
					s += 4 # 5th Gear enhances Gum Barrier (+4 Shield -> 6 Shield Total)
			
			total_shield += s
		elif card.card_id == "cocktaro_platinum_chick":
			duelist.stand_counter_active = true

	if total_shield > 0:
		duelist.shield += total_shield
		var spent_val: int = 1
		for c in duelist.queued_cards:
			if c.card_id == "decluck_all_for_one_heart":
				spent_val = duelist.card_committed_taya.get(c.card_id, 1)
				break
		events.append({
			"type": EventType.SHIELD_GAIN,
			"duelist": duelist.duelist_id,
			"amount": total_shield,
			"spent_taya": spent_val,
			"total_shield": duelist.shield
		})

static func _calculate_attack(attacker: Duelist, _defender: Duelist, turn_number: int) -> Dictionary:
	var attacks: Array[Dictionary] = []

	# Escalating titan attack bonus (+1 on Turn 1, +2 on Turn 2, +4 on Turn 3)
	var titan_bonus: int = 0
	if attacker.titan_form_active:
		match attacker.titan_turns_left:
			3: titan_bonus = 1
			2: titan_bonus = 2
			1: titan_bonus = 4
			_: titan_bonus = 4

	for card in attacker.queued_cards:
		if card.card_type == CardData.CardType.ATTACK:
			if card.card_id == "yagami_chixecution":
				continue # Detonates DoT stacks in _process_dots Phase 7
			var atk_dmg: int = card.base_value + attacker.bonus_flat_attack + titan_bonus
			var shield_pierce: float = 0.0
			var spent_taya: int = 1

			# Hen-Goku Kamecock
			if card.card_id == "hen_goku_kamecock":
				var missing_bonus: int = int(attacker.get_missing_hp_ratio() / 0.25)
				atk_dmg += missing_bonus
			# Decluck Punch: +2 ATK per extra Taya (+4 in AFO)
			elif card.card_id == "decluck_all_for_one_punch":
				spent_taya = attacker.card_committed_taya.get(card.card_id, 1)
				var per_taya: int = 4 if attacker.all_for_one_active else 2
				atk_dmg = 1 + (spent_taya - 1) * per_taya + attacker.bonus_flat_attack + titan_bonus
			# Cluckey Gum Slash
			elif card.card_id == "cluckey_gum_slash":
				shield_pierce = 0.5
				if attacker.gear_5_active:
					atk_dmg += 5 # 5th Gear enhances Gum Slash (+5 ATK -> 7 DMG Total, 50% Shield Pierce)
			# Cocktaro Ora Ora
			elif card.card_id == "cocktaro_ora_ora":
				if attacker.shield > 0:
					atk_dmg += 2 # +2 ATK if shield active
			# Nechicko Peck Breaker
			elif card.card_id == "nechicko_peck_breaker":
				atk_dmg = max(1, attacker.demonic_aura_stacks)
				attacker.demonic_aura_stacks = 0
			# Daniel Unseen Claw
			elif card.card_id == "daniel_unseen_claw":
				atk_dmg = 2 + (turn_number - 1)

			attacks.append({
				"card_id": card.card_id,
				"damage": atk_dmg,
				"shield_pierce": shield_pierce,
				"spent_taya": spent_taya,
				"vfx": card.vfx_type
			})

	return { "attacks": attacks }

static func _apply_attack_list(attacker: Duelist, defender: Duelist, atk_result: Dictionary, events: Array[Dictionary]) -> Dictionary:
	var absorbed_damage: int = 0
	var took_hit: bool = false
	var attacks: Array = atk_result.get("attacks", [])
	for atk in attacks:
		var target_shield: int = defender.shield
		var shield_pierce_factor: float = float(atk.get("shield_pierce", 0.0))
		var effective_shield: int = int(float(target_shield) * (1.0 - shield_pierce_factor))
		var raw_atk_dmg: int = int(atk.get("damage", 0))
		var mitigated: int = min(effective_shield, raw_atk_dmg)
		var unblocked_dmg: int = max(0, raw_atk_dmg - mitigated)

		defender.shield = max(0, defender.shield - mitigated)
		defender.hp = max(0, defender.hp - unblocked_dmg)
		absorbed_damage += mitigated
		if raw_atk_dmg > 0:
			took_hit = true

		events.append({
			"type": EventType.ATTACK_HIT,
			"attacker": attacker.duelist_id,
			"defender": defender.duelist_id,
			"card_id": str(atk.get("card_id", "")),
			"raw_damage": raw_atk_dmg,
			"mitigated": mitigated,
			"actual_hp_damage": unblocked_dmg,
			"defender_remaining_hp": defender.hp,
			"defender_remaining_shield": defender.shield,
			"spent_taya": int(atk.get("spent_taya", 1)),
			"vfx": str(atk.get("vfx", "slash"))
		})

		if defender.hp <= 0:
			_check_revival(defender, events)
		else:
			_check_hp_passives(defender, events)

		if str(atk.get("card_id", "")) == "cluckey_gum_slash" and not attacker.gear_5_active:
			attacker.tension_stacks += 2

	return { "absorbed": absorbed_damage, "took_hit": took_hit }

static func _process_counters(duelist: Duelist, opponent: Duelist, absorbed: int, took_hit: bool, events: Array[Dictionary]) -> void:
	var passive: CardData = duelist.get_passive_trigger("shield_absorbed_hit")
	if (duelist.stand_counter_active or passive != null) and absorbed > 0 and took_hit:
		var counter_dmg: int = passive.base_value if passive != null else 2
		opponent.hp = max(0, opponent.hp - counter_dmg)
		events.append({
			"type": EventType.COUNTER_HIT,
			"attacker": duelist.duelist_id,
			"defender": opponent.duelist_id,
			"damage": counter_dmg,
			"defender_remaining_hp": opponent.hp,
			"vfx": "standcounter",
			"text": "Platinum Chick Counter-Strike! Deals %d follow-up damage." % counter_dmg
		})

static func _process_healing(duelist: Duelist, turn_number: int, events: Array[Dictionary]) -> void:
	var total_heal: int = 0
	var demon_boost: int = duelist.get_stat_buff("heal")
	if demon_boost == 0 and duelist.demon_form_active:
		demon_boost = 2

	for card in duelist.queued_cards:
		if card.card_type == CardData.CardType.HEAL:
			var h: int = card.base_value + demon_boost
			if card.card_id == "nechicko_ketchup_aura":
				h = max(1, duelist.demonic_aura_stacks) + demon_boost
				duelist.demonic_aura_stacks = 0
			elif card.card_id == "daniel_chickens_heart":
				h = max(1, 10 - (turn_number - 1)) + demon_boost

			total_heal += h
			# Nechicko gains demonic aura stack per heal action
			if duelist.rooster_data and duelist.rooster_data.rooster_id == "nechicko":
				duelist.demonic_aura_stacks += 1

	if total_heal > 0:
		duelist.hp = min(duelist.max_hp, duelist.hp + total_heal)
		events.append({
			"type": EventType.HEAL,
			"duelist": duelist.duelist_id,
			"amount": total_heal,
			"new_hp": duelist.hp
		})


static func _process_dots(attacker: Duelist, defender: Duelist, events: Array[Dictionary]) -> void:
	var applied_dots: int = 0
	for card in attacker.queued_cards:
		if card.card_type == CardData.CardType.DOT:
			applied_dots += card.base_value
		elif card.card_id == "yagami_chixecution":
			var detonate_dmg: int = defender.dot_stacks * 2
			defender.hp = max(0, defender.hp - detonate_dmg)
			defender.dot_stacks = 0
			events.append({
				"type": EventType.ATTACK_HIT,
				"attacker": attacker.duelist_id,
				"defender": defender.duelist_id,
				"card_id": "yagami_chixecution",
				"raw_damage": detonate_dmg,
				"mitigated": 0,
				"actual_hp_damage": detonate_dmg,
				"defender_remaining_hp": defender.hp,
				"defender_remaining_shield": defender.shield,
				"vfx": "chixecution",
				"text": "Chixecution Detonated all DoT stacks for %d direct damage!" % detonate_dmg
			})

	if applied_dots > 0:
		defender.dot_stacks = min(5, defender.dot_stacks + applied_dots)
		events.append({
			"type": EventType.DOT_APPLY,
			"attacker": attacker.duelist_id,
			"defender": defender.duelist_id,
			"added_stacks": applied_dots,
			"total_stacks": defender.dot_stacks
		})

static func _tick_dot(duelist: Duelist, events: Array[Dictionary]) -> void:
	if duelist.dot_stacks > 0:
		var dmg: int = duelist.dot_stacks
		duelist.hp = max(0, duelist.hp - dmg)
		duelist.dot_stacks = max(0, duelist.dot_stacks - 1)
		events.append({
			"type": EventType.DOT_TICK,
			"duelist": duelist.duelist_id,
			"damage": dmg,
			"remaining_hp": duelist.hp,
			"stacks": duelist.dot_stacks
		})

static func _process_turn_decay(duelist: Duelist, events: Array[Dictionary]) -> void:
	# Titan Stance regeneration (+2 HP per turn)
	if duelist.titan_form_active:
		if duelist.titan_just_activated:
			duelist.titan_just_activated = false
		else:
			var heal_amount: int = 2
			duelist.hp = min(duelist.max_hp, duelist.hp + heal_amount)
			duelist.titan_turns_left -= 1
			var titan_expired: bool = (duelist.titan_turns_left <= 0)
			if titan_expired:
				duelist.titan_form_active = false
				if duelist.has_method("transform_eren_cards"):
					duelist.transform_eren_cards(false)
			events.append({
				"type": EventType.TURN_DECAY,
				"duelist": duelist.duelist_id,
				"form": "titan_ended" if titan_expired else "",
				"text": "Pecker Titan ended" if titan_expired else "Pecker Titan regeneration (+2 HP, %d turns left)" % duelist.titan_turns_left
			})

	# Cluckey Gear 5 tension upkeep (Preset A: -1 Tension per turn -> lasts 5 rounds)
	if duelist.gear_5_active:
		duelist.tension_stacks = max(0, duelist.tension_stacks - 1)
		if duelist.tension_stacks <= 0:
			duelist.gear_5_active = false
			events.append({
				"type": EventType.TURN_DECAY,
				"duelist": duelist.duelist_id,
				"form": "gear_5_ended",
				"text": "5th Gear ended (Tension exhausted)"
			})

	# Decluck All for one decay
	if duelist.all_for_one_active:
		duelist.all_for_one_turns_left -= 1
		if duelist.all_for_one_turns_left <= 0:
			duelist.all_for_one_active = false
			events.append({
				"type": EventType.TURN_DECAY,
				"duelist": duelist.duelist_id,
				"form": "all_for_one_ended",
				"text": "One For All Full Cowling expired"
			})

	# Demon form decay
	if duelist.demon_form_active:
		duelist.demon_form_turns_left -= 1
		if duelist.demon_form_turns_left <= 0:
			duelist.demon_form_active = false
			events.append({
				"type": EventType.TURN_DECAY,
				"duelist": duelist.duelist_id,
				"form": "demon_form_ended",
				"text": "Demon Form expired"
			})

static func _check_revival(duelist: Duelist, events: Array[Dictionary]) -> void:
	var has_death_save: bool = (duelist.get_passive_trigger("on_fatal_damage") != null) or (duelist.rooster_data and duelist.rooster_data.rooster_id == "daniel")
	if duelist.hp <= 0 and has_death_save and not duelist.return_by_death_used:
		duelist.return_by_death_used = true
		duelist.hp = duelist.max_hp
		events.append({
			"type": EventType.REVIVE,
			"duelist": duelist.duelist_id,
			"new_hp": duelist.hp,
			"text": "Chick to Zero Triggered! Daniel revived by Return by Death!"
		})
