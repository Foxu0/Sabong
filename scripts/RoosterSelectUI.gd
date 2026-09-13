extends Control
class_name RoosterSelectUI

## RoosterSelectUI — Character selection screen showcasing all 8 Parody Roosters.

signal battle_started(p1_rooster: RoosterData, p2_rooster: RoosterData, vs_ai: bool)

const ROOSTER_PATHS: Array[String] = [
	"res://resources/roosters/hen_goku.tres",
	"res://resources/roosters/decluck.tres",
	"res://resources/roosters/eren_pecker.tres",
	"res://resources/roosters/cluckey_d_puffy.tres",
	"res://resources/roosters/chick_yagami.tres",
	"res://resources/roosters/cocktaro.tres",
	"res://resources/roosters/nechicko.tres",
	"res://resources/roosters/daniel.tres"
]

var roosters: Array[RoosterData] = []
var p1_selected: RoosterData
var p2_selected: RoosterData
var vs_ai_mode: bool = true
var buttons: Array[Button] = []

var name_label: Label
var anime_label: Label
var hp_label: Label
var desc_label: Label
var moves_label: Label

func _ready() -> void:
	for path in ROOSTER_PATHS:
		if ResourceLoader.exists(path):
			var r: RoosterData = load(path)
			roosters.append(r)

	if roosters.size() > 0:
		p1_selected = roosters[0]
		p2_selected = roosters[randi() % roosters.size()]

	_build_ui()
	_update_character_details(p1_selected)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.09, 0.96)
	add_child(bg)

	var title: Label = Label.new()
	title.text = "CHOOSE YOUR ROOSTER CHAMPION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(1280, 48)
	UIFontStyle.style_title(title, 24)
	title.add_theme_color_override("font_color", Color.GOLD)
	add_child(title)

	# Character Grid (Left side)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(50, 85)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	add_child(grid)

	buttons.clear()
	for r in roosters:
		var card_btn: Button = Button.new()
		card_btn.custom_minimum_size = Vector2(145, 215)
		card_btn.text = ""
		if r.portrait_path != "" and ResourceLoader.exists(r.portrait_path):
			card_btn.icon = load(r.portrait_path)
			card_btn.expand_icon = true
			card_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		card_btn.pressed.connect(_on_rooster_card_clicked.bind(r))
		grid.add_child(card_btn)
		buttons.append(card_btn)

	# Info Details Panel (Right side)
	var info_panel: PanelContainer = PanelContainer.new()
	info_panel.position = Vector2(710, 85)
	info_panel.custom_minimum_size = Vector2(520, 520)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	p_style.border_color = Color.GOLD
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(10)
	p_style.content_margin_left = 20
	p_style.content_margin_right = 20
	p_style.content_margin_top = 18
	p_style.content_margin_bottom = 18
	info_panel.add_theme_stylebox_override("panel", p_style)
	add_child(info_panel)

	var info_vbox: VBoxContainer = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 12)
	info_panel.add_child(info_vbox)

	name_label = Label.new()
	UIFontStyle.style_title(name_label, 20)
	name_label.add_theme_color_override("font_color", Color.GOLD)
	info_vbox.add_child(name_label)

	anime_label = Label.new()
	UIFontStyle.style_body(anime_label, 14, true)
	anime_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	info_vbox.add_child(anime_label)

	hp_label = Label.new()
	UIFontStyle.style_subheading(hp_label, 18)
	hp_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	info_vbox.add_child(hp_label)

	desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIFontStyle.style_body(desc_label, 13)
	info_vbox.add_child(desc_label)

	moves_label = Label.new()
	moves_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIFontStyle.style_body(moves_label, 13, true)
	moves_label.add_theme_color_override("font_color", Color.CYAN)
	info_vbox.add_child(moves_label)

	# Start Battle Button
	var start_btn: Button = Button.new()
	start_btn.text = "ENTER SABONG ARENA"
	start_btn.custom_minimum_size = Vector2(280, 56)
	start_btn.position = Vector2(830, 625)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.85, 0.2, 0.2, 1.0)
	btn_style.set_corner_radius_all(8)
	start_btn.add_theme_stylebox_override("normal", btn_style)
	UIFontStyle.style_button(start_btn, 18)
	start_btn.pressed.connect(_on_start_battle_pressed)
	add_child(start_btn)

	# Back Button
	var back_btn: Button = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(120, 42)
	back_btn.position = Vector2(50, 635)
	UIFontStyle.style_button(back_btn, 16)
	back_btn.pressed.connect(func():
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.has_method("change_scene"):
			gm.change_scene("res://scenes/main_menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	add_child(back_btn)

func _on_rooster_card_clicked(r: RoosterData) -> void:
	p1_selected = r
	_update_character_details(r)

func _update_character_details(r: RoosterData) -> void:
	if not r: return
	name_label.text = r.display_name
	anime_label.text = "Parody: %s" % r.anime_reference
	hp_label.text = "Base HP: %d" % r.base_hp
	desc_label.text = "Passive: %s" % r.passive_description
	var moves_text: String = "Signature Moves:\n"
	for m in r.moveset:
		if m:
			moves_text += "• %s (%d Taya | Dice: %d+): %s\n" % [m.display_name, m.taya_cost, m.dice_requirement, m.effect_text]
	moves_label.text = moves_text

func _on_start_battle_pressed() -> void:
	# Random CPU opponent if not P2 selected
	if not p2_selected or p2_selected == p1_selected:
		var opponents: Array[RoosterData] = []
		for x in roosters:
			if x != p1_selected:
				opponents.append(x)
		if opponents.size() > 0:
			p2_selected = opponents[randi() % opponents.size()]
		else:
			p2_selected = p1_selected
	
	battle_started.emit(p1_selected, p2_selected, vs_ai_mode)
	hide()
