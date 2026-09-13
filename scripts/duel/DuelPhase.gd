class_name DuelPhase
extends RefCounted

## DuelPhase — Authoritative Phase enumeration for Sabong Roosters round loop.
enum Phase {
	DICE_ROLL,
	DISCARD,      # skipped entirely on Round 1
	DRAW,
	REROLL,
	FIGHTING,
	ROUND_END,
}
