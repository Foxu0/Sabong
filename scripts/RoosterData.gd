extends Resource
class_name RoosterData

## RoosterData — pure data definition for all 8 Rooster champions (.tres).

@export var rooster_id: String = ""           # e.g. "hen_goku"
@export var display_name: String = ""         # e.g. "Hen-Goku"
@export var anime_reference: String = ""      # e.g. "Dragon Ball (Goku)"
@export var base_hp: int = 20
@export var portrait_path: String = ""        # e.g. "res://resources/cards/1.png"
@export_multiline var passive_description: String = ""

# 3D Visual Mesh and Prop Asset Paths
@export var model_path: String = ""           # e.g. "res://resources/models/hen_goku/Cluck Kakarot.vox"
@export var alt_model_path: String = ""       # e.g. "res://resources/models/hen_goku/Golden Cluck Kakarot.vox"
@export var dice_model_path: String = ""      # e.g. "res://resources/models/hen_goku/kakarotdice.vox"
@export var stand_model_path: String = ""     # e.g. "res://resources/models/cocktaro/kotarostand.vox"

# The rooster's 3 signature cards
@export var moveset: Array[CardData] = []

# Color theme for UI accents
@export var theme_color: Color = Color(1.0, 0.3, 0.3)
