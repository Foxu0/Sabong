class_name PlayerRoundState
extends RefCounted

## PlayerRoundState — Runtime state tracking for one player across duel phases.

var player_id: String = ""              # "MERON" / "WALA"
var is_ai: bool = false                 # true if this side is AI-controlled

var dice_result: int = 0:               # 1-6, this round's roll (post-manipulation, final value)
	set(val):
		dice_result = val
		if duelist and val > 0:
			duelist.current_dice_roll = val
var discard_count: int = 0              # always equal to dice_result — no separate derivation
var has_priority: bool = false          # true if this player acts first in Fighting Phase (unused during a Clash)
var card_rerolls_used: int = 0          # dice-manipulation card charges used this round (max 1)
var free_rerolls_used: int = 0          # Reroll Phase mulligans used this round (max 3)

var hand: Array = []                    # cards currently in hand (max CARD_LIMIT)
var draw_pile: Array = []               # this player's remaining deck
var discard_pile: Array = []            # cards discarded or played — reshuffled into draw_pile when dry

var duelist: Duelist = null             # Underlying Duelist reference for HP, shields, buffs, rooster_data

## Resets round-specific variables at the start of a new round
func reset_for_new_round() -> void:
	dice_result = 0
	discard_count = 0
	has_priority = false
	card_rerolls_used = 0
	free_rerolls_used = 0

## Synchronizes references with underlying Duelist
func bind_duelist(d: Duelist) -> void:
	duelist = d
	if duelist:
		hand = duelist.hand
		draw_pile = duelist.deck
		discard_pile = duelist.discard_pile
		if dice_result > 0:
			duelist.current_dice_roll = dice_result
