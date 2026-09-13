extends Resource
class_name CardData

## CardData — pure data definition for all Sabong cards (.tres).

enum CardType { ATTACK, GUARD, HEAL, DOT, SPECIAL, ROLL_MANIPULATION }
enum UsageGate { ALWAYS, STATE_LOCKED, ONCE_PER_MATCH, REACTIVE }

@export var card_id: String = ""              # unique key, e.g. "kame_cock"
@export var display_name: String = ""         # what shows on the card, e.g. "Kame-cock"
@export var card_type: CardType = CardType.ATTACK
@export var is_universal: bool = false        # true for the shared universal cards
@export var character_id: String = ""         # rooster_id if signature card, e.g. "hen_goku"

@export var taya_cost: int = 1                # base Taya cost (1-3)
@export var is_variable_cost: bool = false    # true for Decluck variable taya scaling
@export var dice_requirement: int = 1         # minimum rolled dice face needed (1-6)

@export var base_value: int = 0               # damage / shield / heal / dot amount
@export var value_per_taya: int = 0           # bonus value per extra taya committed
@export var self_damage: int = 0              # HP cost to play (Titan Stomp, Ryuk's Watch)

# Roll Manipulation (self-only)
@export var is_dice_reroll: bool = false      # true if rerolls own die
@export var roll_delta: int = 0               # +/- delta applied to own die

@export var usage_gate: UsageGate = UsageGate.ALWAYS
@export var required_state: String = ""       # e.g. "titan_mode_active", "tension_ge_5"
@export var locks_out_card_type: int = -1      # -1 = no lock, otherwise CardType enum value (e.g. 1 for GUARD)

@export var is_passive_trigger: bool = false   # true for passive triggers that never appear in active hand
@export var trigger_condition: String = ""     # e.g. "shield_absorbed_hit"

@export var buff_stat: String = ""             # e.g. "heal"
@export var buff_amount: int = 0               # e.g. 2
@export var buff_duration: int = 0             # in turns (e.g. 3)

@export_multiline var effect_text: String = ""
@export var art_path: String = ""             # e.g. "res://resources/cards/2.png"
@export var vfx_type: String = ""             # visual effect key e.g. "slash", "beam", "stomp", "shield"

