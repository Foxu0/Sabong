extends RefCounted
class_name AIController

## AIController — Smart decision maker for CPU rooster opponents in Sabong Roosters.

static func make_ai_turn(ai_duelist: Duelist, opponent: Duelist) -> void:
	if ai_duelist.hand.is_empty():
		return

	# Sort playable cards by situational priority
	var playable: Array[CardData] = []
	for card in ai_duelist.hand:
		if ai_duelist.can_play_card(card):
			playable.append(card)

	# Shuffle to keep some organic unpredictability
	playable.shuffle()

	# Priority 1: Check high-impact character transformations
	for card in playable:
		if card.card_type == CardData.CardType.SPECIAL and ai_duelist.can_play_card(card):
			# If Cluckey has 5 tension -> play 5th gear
			if card.card_id == "cluckey_5th_gear" and ai_duelist.tension_stacks >= 5:
				ai_duelist.queue_card(card)
				break
			# If Eren -> play Pecker Titan
			elif card.card_id == "eren_pecker_titan" and not ai_duelist.titan_form_active and ai_duelist.hp > 8:
				ai_duelist.queue_card(card)
				break
			# If Yagami and opponent has >= 3 DoT stacks -> Chixecution
			elif card.card_id == "yagami_chixecution" and opponent.dot_stacks >= 3:
				ai_duelist.queue_card(card)
				break
			# If Decluck -> All For One Cock
			elif card.card_id == "decluck_all_for_one_cock" and not ai_duelist.all_for_one_active:
				ai_duelist.queue_card(card)
				break
			# If Nechicko -> Demon Form
			elif card.card_id == "nechicko_demon_form" and not ai_duelist.demon_form_active:
				ai_duelist.queue_card(card)
				break

	# Priority 2: Low HP Defense / Healing
	var is_low_hp: bool = (ai_duelist.hp <= 8)
	if is_low_hp:
		for card in playable:
			if card.card_type == CardData.CardType.GUARD or card.card_type == CardData.CardType.HEAL:
				if ai_duelist.can_play_card(card):
					var extra: int = 0
					if card.is_variable_cost:
						extra = min(2, ai_duelist.taya_remaining - card.taya_cost)
					ai_duelist.queue_card(card, extra)
					if ai_duelist.taya_remaining <= 0:
						return

	# Priority 3: Attack / DoT Spends
	for card in playable:
		if not ai_duelist.hand.has(card):
			continue
		if ai_duelist.can_play_card(card):
			var extra_taya: int = 0
			if card.is_variable_cost:
				extra_taya = min(2, ai_duelist.taya_remaining - card.taya_cost)
			ai_duelist.queue_card(card, extra_taya)
			if ai_duelist.taya_remaining <= 0:
				break

	# If Chick Yagami used Ryuk's Watch -> guess opponent's most likely move
	if ai_duelist.rooster_data and ai_duelist.rooster_data.rooster_id == "chick_yagami":
		var choices: Array[String] = ["ATTACK", "DEFEND", "SPECIAL"]
		ai_duelist.secret_prediction = choices[randi() % choices.size()]
