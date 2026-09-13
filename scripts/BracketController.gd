extends Node3D
class_name BracketController

## BracketController — 3D Bird's-Eye Tournament Visualizer.
## Scaled-up arenas, roosters, and lines with configurable bot deployment (3, 7, 15 bots).
## Summons mini arenas and 3D roosters on each matchup box, renders connecting lines,
## replaces defeated roosters with fried chicken, and presents the final leaderboard.

@onready var camera: Camera3D = $Camera3D

var arena_packed: PackedScene = preload("res://resources/world/arena.vox")
var fried_chicken_packed: PackedScene = preload("res://resources/world/friedchicken(dead).vox")

# Nodes container
var bracket_root: Node3D = null
var lines_root: Node3D = null
var podium_root: Node3D = null

# UI Canvas
var ui_layer: CanvasLayer = null
var title_label: Label = null
var match_info_label: Label = null
var match_rooster_label: Label = null
var btn_start_match: Button = null
var btn_format_toggle: Button = null
var btn_bot_prev: Button = null
var btn_bot_next: Button = null
var bot_count_label: Label = null
var btn_main_menu: Button = null
var leaderboard_panel: Control = null

# Spotlight for active match
var active_spotlight: SpotLight3D = null

const BOT_TIERS: Array[int] = [3, 7, 15]

func _ready() -> void:
	_setup_3d_containers()
	_ensure_tournament_initialized()
	_build_ui()
	_render_bracket()

	TournamentManager.tournament_state_changed.connect(_on_tournament_state_changed)
	TournamentManager.tournament_finished.connect(_on_tournament_finished)

	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		if not nm.tournament_match_started.is_connected(_on_network_tournament_match_started):
			nm.tournament_match_started.connect(_on_network_tournament_match_started)
		if not nm.tournament_bracket_received.is_connected(_on_network_bracket_received):
			nm.tournament_bracket_received.connect(_on_network_bracket_received)

	if TournamentManager.tournament_completed:
		_show_leaderboard_presentation(TournamentManager.final_leaderboard)

func _setup_3d_containers() -> void:
	bracket_root = Node3D.new()
	bracket_root.name = "BracketNodes"
	add_child(bracket_root)

	lines_root = Node3D.new()
	lines_root.name = "ConnectingLines"
	add_child(lines_root)

	podium_root = Node3D.new()
	podium_root.name = "PodiumRoot"
	add_child(podium_root)

	active_spotlight = SpotLight3D.new()
	active_spotlight.name = "ActiveMatchSpotlight"
	active_spotlight.light_color = Color(1.0, 0.92, 0.6)
	active_spotlight.light_energy = 5.5
	active_spotlight.spot_range = 35.0
	active_spotlight.spot_angle = 28.0
	active_spotlight.position = Vector3(0, 18, 0)
	active_spotlight.rotation_degrees = Vector3(-90, 0, 0)
	add_child(active_spotlight)

func _ensure_tournament_initialized() -> void:
	if TournamentManager.is_online_tournament:
		return
	if not TournamentManager.is_tournament_active:
		var p: RoosterData = GameManager.selected_player_rooster
		if not p:
			if GameManager.all_roosters.is_empty():
				GameManager._load_all_roosters()
			p = GameManager.all_roosters[0] if not GameManager.all_roosters.is_empty() else null
		TournamentManager.start_new_tournament(p, TournamentManager.Format.SINGLE_ELIMINATION, 7)

## ---------------------------------------------------------------------------
## 3D Bracket Rendering (Scaled Up & Cliff-Clear)
## ---------------------------------------------------------------------------

func _render_bracket() -> void:
	_clear_bracket_visuals()

	# Dynamically adjust camera height to frame chosen tournament size
	if camera:
		if TournamentManager.current_bot_count <= 3:
			camera.position.y = 16.5
		elif TournamentManager.current_bot_count <= 7:
			camera.position.y = 19.5
		else:
			camera.position.y = 25.0

	var matches: Array[Dictionary] = TournamentManager.matches
	var active_match: Dictionary = TournamentManager.get_current_match()

	# Position active spotlight over the player's upcoming matchup
	if not active_match.is_empty():
		var target_pos: Vector3 = active_match.get("pos", Vector3.ZERO)
		active_spotlight.position = Vector3(target_pos.x, camera.position.y - 1.5, target_pos.z)
		active_spotlight.visible = true
	else:
		active_spotlight.visible = false

	# 1. Spawn matchup boxes (Bigger Mini Arena + Roosters / Fried Chicken)
	for m in matches:
		_spawn_matchup_box(m, m == active_match)

	# 2. Draw 3D connecting lines between rounds
	_draw_all_connecting_lines()

	_update_hud()

func _clear_bracket_visuals() -> void:
	for c in bracket_root.get_children():
		c.queue_free()
	for c in lines_root.get_children():
		c.queue_free()

func _spawn_matchup_box(m: Dictionary, is_active: bool) -> void:
	var box_node := Node3D.new()
	box_node.name = "Box_" + m["id"]
	box_node.position = m["pos"]
	bracket_root.add_child(box_node)

	# Scaled Up Arena Model: ~1.8x to 2.2x larger than before
	var arena_scale: float = 0.44
	var is_gf: bool = (m["id"] == "GF")
	
	if TournamentManager.current_bot_count <= 3:
		arena_scale = 0.65 if is_gf else 0.52
	elif TournamentManager.current_bot_count <= 7:
		arena_scale = 0.54 if is_gf else 0.44
	else:
		arena_scale = 0.42 if is_gf else 0.32

	if arena_packed:
		var arena_inst: Node3D = arena_packed.instantiate()
		arena_inst.scale = Vector3(arena_scale, arena_scale, arena_scale)
		arena_inst.position = Vector3(0, 0.05, 0)
		box_node.add_child(arena_inst)

	# Active match golden aura ring
	if is_active:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var ring_radius: float = arena_scale * 4.8
		torus.inner_radius = ring_radius
		torus.outer_radius = ring_radius + 0.35
		ring.mesh = torus
		var r_mat := StandardMaterial3D.new()
		r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
		ring.material_override = r_mat
		ring.position = Vector3(0, 0.12, 0)
		box_node.add_child(ring)

		var pulse_tw := ring.create_tween().set_loops()
		pulse_tw.tween_property(ring, "scale", Vector3(1.10, 1.0, 1.10), 0.75).set_trans(Tween.TRANS_SINE)
		pulse_tw.tween_property(ring, "scale", Vector3(0.95, 1.0, 0.95), 0.75).set_trans(Tween.TRANS_SINE)

	# Model scaling factors
	var rooster_scale: float = 1.05 if TournamentManager.current_bot_count <= 7 else 0.75
	var rooster_offset_x: float = arena_scale * 2.3

	# 1. Left Contestant (Rooster 1)
	var r1: RoosterData = m.get("rooster_1", null)
	var r1_node := Node3D.new()
	r1_node.position = Vector3(-rooster_offset_x, 0.25, 0.0)
	r1_node.rotation_degrees = Vector3(0, 90, 0)
	box_node.add_child(r1_node)

	if r1:
		var is_r1_loser: bool = m["is_completed"] and m["loser"] == r1
		if is_r1_loser:
			_spawn_fried_chicken_model(r1_node, rooster_scale * 1.15)
		else:
			_spawn_rooster_model(r1_node, r1, m["is_completed"] and m["winner"] == r1, rooster_scale)

	var is_bye: bool = m.get("is_bye", false)

	# 2. Right Contestant (Rooster 2 or BYE badge)
	var r2: RoosterData = m.get("rooster_2", null)
	var r2_node := Node3D.new()
	r2_node.position = Vector3(rooster_offset_x, 0.25, 0.0)
	r2_node.rotation_degrees = Vector3(0, -90, 0)
	box_node.add_child(r2_node)

	if is_bye:
		var bye_lbl := Label3D.new()
		bye_lbl.text = "[ BYE ]"
		var f_title = UIFontStyle.get_title_font()
		if f_title: bye_lbl.font = f_title
		bye_lbl.font_size = 42
		bye_lbl.outline_size = 10
		bye_lbl.outline_modulate = Color(0.1, 0.08, 0.02)
		bye_lbl.modulate = Color.GOLD
		bye_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bye_lbl.position = Vector3(0, 0.4, 0)
		r2_node.add_child(bye_lbl)
	elif r2:
		var is_r2_loser: bool = m["is_completed"] and m["loser"] == r2
		if is_r2_loser:
			_spawn_fried_chicken_model(r2_node, rooster_scale * 1.15)
		else:
			_spawn_rooster_model(r2_node, r2, m["is_completed"] and m["winner"] == r2, rooster_scale)

	# 3. Top-Down Separated 3D Labels (Offset on Z-axis so they NEVER overlap!)
	var z_offset_title: float = -arena_scale * 3.4
	var z_offset_names: float = arena_scale * 3.4

	# Match Title (Above the Arena on screen: -Z)
	var b_title := Label3D.new()
	b_title.text = m["name"]
	var f_title = UIFontStyle.get_title_font()
	if f_title:
		b_title.font = f_title
	b_title.font_size = 36
	b_title.outline_size = 8
	b_title.outline_modulate = Color.BLACK
	b_title.modulate = Color.GOLD if is_active else (Color(0.88, 0.92, 1.0) if not m["is_completed"] else Color(0.6, 0.65, 0.75))
	b_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b_title.position = Vector3(0, 0.40, z_offset_title)
	box_node.add_child(b_title)

	# Duelist Names (Below the Arena on screen: +Z)
	var r1_name: String = r1.display_name.to_upper() if r1 else "TBD"
	var r2_name: String = r2.display_name.to_upper() if r2 else "TBD"
	var b_names := Label3D.new()
	if is_bye:
		b_names.text = "%s   (BYE ADVANCE)" % r1_name
	else:
		b_names.text = "%s   VS   %s" % [r1_name, r2_name]
	var f_btn = UIFontStyle.get_button_font()
	if f_btn:
		b_names.font = f_btn
	b_names.font_size = 28
	b_names.outline_size = 7
	b_names.outline_modulate = Color.BLACK
	b_names.modulate = Color.WHITE
	b_names.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b_names.position = Vector3(0, 0.40, z_offset_names)
	box_node.add_child(b_names)

	if m["is_completed"] and m["winner"]:
		var b_win := Label3D.new()
		if is_bye:
			b_win.text = "PROMOTED TO ROUND 2"
		else:
			b_win.text = "WINNER: %s" % m["winner"].display_name.to_upper()
		if f_btn:
			b_win.font = f_btn
		b_win.font_size = 26
		b_win.outline_size = 7
		b_win.outline_modulate = Color.BLACK
		b_win.modulate = Color.GREEN_YELLOW
		b_win.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b_win.position = Vector3(0, 0.40, z_offset_names + 0.65)
		box_node.add_child(b_win)

func _spawn_rooster_model(parent: Node3D, r: RoosterData, is_winner: bool, model_scale: float) -> void:
	if not r or r.model_path == "":
		return
	if ResourceLoader.exists(r.model_path):
		var p_scene = load(r.model_path)
		if p_scene is PackedScene:
			var inst: Node3D = p_scene.instantiate()
			inst.scale = Vector3(model_scale, model_scale, model_scale)
			parent.add_child(inst)

			if is_winner:
				inst.position.y += 0.15
				var tw := inst.create_tween().set_loops()
				tw.tween_property(inst, "position:y", inst.position.y + 0.20, 0.5).set_trans(Tween.TRANS_SINE)
				tw.tween_property(inst, "position:y", inst.position.y, 0.5).set_trans(Tween.TRANS_SINE)

func _spawn_fried_chicken_model(parent: Node3D, chicken_scale: float) -> void:
	if fried_chicken_packed:
		var inst: Node3D = fried_chicken_packed.instantiate()
		inst.scale = Vector3(chicken_scale, chicken_scale, chicken_scale)
		inst.position = Vector3(0, 0.08, 0)
		parent.add_child(inst)

## ---------------------------------------------------------------------------
## Thicker Glowing 3D Bracket Connecting Lines
## ---------------------------------------------------------------------------

func _draw_all_connecting_lines() -> void:
	var matches: Array[Dictionary] = TournamentManager.matches

	for m in matches:
		var target_id: String = m.get("target_match_id", "")
		if target_id != "":
			var target_m: Dictionary = TournamentManager.get_match(target_id)
			if not target_m.is_empty():
				_draw_bracket_connector(m, target_m)

func _draw_bracket_connector(source_m: Dictionary, target_m: Dictionary) -> void:
	var p1: Vector3 = source_m["pos"] + Vector3(0, 0.06, 0)
	var p2: Vector3 = target_m["pos"] + Vector3(0, 0.06, 0)

	var line_color: Color = Color(0.40, 0.50, 0.65, 0.70) # Silver steel
	if source_m["is_completed"]:
		if source_m["winner"] != null and (target_m["rooster_1"] == source_m["winner"] or target_m["rooster_2"] == source_m["winner"]):
			line_color = Color(1.0, 0.85, 0.25, 0.98) # Glowing Gold winning path
		else:
			line_color = Color(0.22, 0.24, 0.30, 0.50) # Dimmed

	var mid_x: float = (p1.x + p2.x) * 0.5
	var corner1 := Vector3(mid_x, p1.y, p1.z)
	var corner2 := Vector3(mid_x, p1.y, p2.z)

	# Thicker lines: 0.16 thickness
	_create_line_segment(p1, corner1, line_color, 0.16)
	_create_line_segment(corner1, corner2, line_color, 0.16)
	_create_line_segment(corner2, p2, line_color, 0.16)

func _create_line_segment(start_pt: Vector3, end_pt: Vector3, color: Color, thickness: float = 0.16) -> void:
	var dist: float = start_pt.distance_to(end_pt)
	if dist < 0.02:
		return

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, 0.04, dist)
	mi.mesh = box

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat

	mi.position = (start_pt + end_pt) * 0.5
	mi.look_at_from_position(mi.position, end_pt, Vector3.UP)
	lines_root.add_child(mi)

## ---------------------------------------------------------------------------
## UI Layer & HUD with Bot Count Stepper
## ---------------------------------------------------------------------------

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# --- Top Header Bar ---
	var top_bar := PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 24
	top_bar.offset_top = 16
	top_bar.offset_right = -24
	top_bar.offset_bottom = 82
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.05, 0.07, 0.12, 0.94)
	t_style.border_color = Color(0.24, 0.32, 0.46, 0.70)
	t_style.set_border_width_all(1)
	t_style.set_corner_radius_all(10)
	t_style.content_margin_left = 18
	t_style.content_margin_right = 18
	top_bar.add_theme_stylebox_override("panel", t_style)
	ui_layer.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 18)
	top_bar.add_child(top_hbox)

	# Back button
	var btn_back := Button.new()
	btn_back.text = "BACK TO MENU"
	btn_back.icon = UIIcons.get_icon("arrow_left", 16)
	btn_back.custom_minimum_size = Vector2(160, 42)
	UIFontStyle.style_button(btn_back, 15)
	var b_back_style := StyleBoxFlat.new()
	b_back_style.bg_color = Color(0.09, 0.12, 0.18, 0.90)
	b_back_style.border_color = Color(0.28, 0.36, 0.50, 0.75)
	b_back_style.set_border_width_all(1)
	b_back_style.set_corner_radius_all(6)
	b_back_style.content_margin_left = 12
	b_back_style.content_margin_right = 12
	btn_back.add_theme_stylebox_override("normal", b_back_style)
	btn_back.pressed.connect(func():
		TournamentManager.is_tournament_active = false
		GameManager.change_scene("res://scenes/main_menu.tscn")
	)
	top_hbox.add_child(btn_back)

	# Title & Tournament Stage Pill
	var title_vbox := VBoxContainer.new()
	title_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_vbox.add_theme_constant_override("separation", 2)
	top_hbox.add_child(title_vbox)

	title_label = Label.new()
	title_label.text = "SABONG CHAMPIONSHIP BRACKET"
	UIFontStyle.style_title(title_label, 26)
	title_label.add_theme_color_override("font_color", Color.GOLD)
	title_vbox.add_child(title_label)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "3D BIRD'S-EYE ARENA • SINGLE & DOUBLE ELIMINATION"
	UIFontStyle.style_body(subtitle_lbl, 12, true)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90, 0.85))
	title_vbox.add_child(subtitle_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	# Format Toggle Button
	btn_format_toggle = Button.new()
	btn_format_toggle.text = "FORMAT: SINGLE ELIMINATION"
	btn_format_toggle.icon = UIIcons.get_icon("trophy", 16)
	btn_format_toggle.custom_minimum_size = Vector2(250, 42)
	UIFontStyle.style_button(btn_format_toggle, 14)
	var fmt_sb := StyleBoxFlat.new()
	fmt_sb.bg_color = Color(0.10, 0.13, 0.20, 0.90)
	fmt_sb.border_color = Color(0.35, 0.45, 0.65, 0.75)
	fmt_sb.set_border_width_all(1)
	fmt_sb.set_corner_radius_all(6)
	fmt_sb.content_margin_left = 12
	fmt_sb.content_margin_right = 12
	btn_format_toggle.add_theme_stylebox_override("normal", fmt_sb)
	btn_format_toggle.pressed.connect(_on_toggle_format_pressed)
	top_hbox.add_child(btn_format_toggle)

	# Bot / Duelist Stepper
	var bot_box := PanelContainer.new()
	var bb_sb := StyleBoxFlat.new()
	bb_sb.bg_color = Color(0.08, 0.10, 0.16, 0.90)
	bb_sb.border_color = Color(0.25, 0.35, 0.50, 0.70)
	bb_sb.set_border_width_all(1)
	bb_sb.set_corner_radius_all(6)
	bb_sb.content_margin_left = 8
	bb_sb.content_margin_right = 8
	bb_sb.content_margin_top = 3
	bb_sb.content_margin_bottom = 3
	bot_box.add_theme_stylebox_override("panel", bb_sb)
	top_hbox.add_child(bot_box)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 8)
	bot_box.add_child(bot_hbox)

	var users_icon := UIIcons.create_icon_rect("users", 18, Color(0.75, 0.85, 1.0))
	bot_hbox.add_child(users_icon)

	btn_bot_prev = Button.new()
	btn_bot_prev.text = "<"
	btn_bot_prev.custom_minimum_size = Vector2(32, 34)
	UIFontStyle.style_button(btn_bot_prev, 16)
	btn_bot_prev.pressed.connect(_on_bot_count_prev)
	bot_hbox.add_child(btn_bot_prev)

	bot_count_label = Label.new()
	bot_count_label.text = "7 BOTS (8 DUELISTS)"
	bot_count_label.custom_minimum_size = Vector2(190, 0)
	bot_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(bot_count_label, 14, true)
	bot_count_label.add_theme_color_override("font_color", Color.GOLD)
	bot_hbox.add_child(bot_count_label)

	btn_bot_next = Button.new()
	btn_bot_next.text = ">"
	btn_bot_next.custom_minimum_size = Vector2(32, 34)
	UIFontStyle.style_button(btn_bot_next, 16)
	btn_bot_next.pressed.connect(_on_bot_count_next)
	bot_hbox.add_child(btn_bot_next)

	# --- Bottom Action Card (Esports Matchup Broadcast Deck) ---
	var bot_card := PanelContainer.new()
	bot_card.anchor_left = 0.5
	bot_card.anchor_right = 0.5
	bot_card.anchor_top = 1.0
	bot_card.anchor_bottom = 1.0
	bot_card.offset_left = -460
	bot_card.offset_top = -152
	bot_card.offset_right = 460
	bot_card.offset_bottom = -20
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.06, 0.08, 0.13, 0.96)
	b_style.border_color = Color.GOLD
	b_style.set_border_width_all(2)
	b_style.set_corner_radius_all(12)
	b_style.shadow_color = Color(0, 0, 0, 0.6)
	b_style.shadow_size = 16
	b_style.content_margin_left = 28
	b_style.content_margin_right = 28
	b_style.content_margin_top = 12
	b_style.content_margin_bottom = 12
	bot_card.add_theme_stylebox_override("panel", b_style)
	ui_layer.add_child(bot_card)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.add_theme_constant_override("separation", 6)
	bot_card.add_child(bot_vbox)

	# Top match round info
	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 10)
	bot_vbox.add_child(info_row)

	var swords_tag_icon := UIIcons.create_icon_rect("swords", 16, Color.GOLD)
	info_row.add_child(swords_tag_icon)

	match_info_label = Label.new()
	match_info_label.text = "UPCOMING MATCH"
	UIFontStyle.style_subheading(match_info_label, 16)
	match_info_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	info_row.add_child(match_info_label)

	# Matchup Duelists Display
	match_rooster_label = Label.new()
	match_rooster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_rooster_label.text = "HEN-GOKU VS COCKTARO"
	UIFontStyle.style_title(match_rooster_label, 26)
	match_rooster_label.add_theme_color_override("font_color", Color.GOLD)
	bot_vbox.add_child(match_rooster_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_vbox.add_child(btn_row)

	btn_start_match = Button.new()
	btn_start_match.custom_minimum_size = Vector2(300, 46)
	btn_start_match.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sm_style := StyleBoxFlat.new()
	sm_style.bg_color = Color(0.28, 0.22, 0.08, 0.96)
	sm_style.border_color = Color.GOLD
	sm_style.set_border_width_all(2)
	sm_style.set_corner_radius_all(8)
	sm_style.content_margin_left = 16
	sm_style.content_margin_right = 16
	sm_style.content_margin_top = 6
	sm_style.content_margin_bottom = 6
	btn_start_match.add_theme_stylebox_override("normal", sm_style)
	var sm_hover := sm_style.duplicate() as StyleBoxFlat
	sm_hover.bg_color = Color(0.40, 0.32, 0.12, 0.98)
	btn_start_match.add_theme_stylebox_override("hover", sm_hover)
	UIIcons.setup_centered_button(
		btn_start_match,
		"ENTER ARENA (START MATCH)",
		"swords",
		20,
		17,
		Color.GOLD,
		Color.WHITE,
		10
	)
	btn_start_match.pressed.connect(_on_start_match_pressed)
	btn_row.add_child(btn_start_match)

	btn_main_menu = Button.new()
	btn_main_menu.custom_minimum_size = Vector2(160, 46)
	btn_main_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var mm_sb := StyleBoxFlat.new()
	mm_sb.bg_color = Color(0.10, 0.12, 0.18, 0.90)
	mm_sb.border_color = Color(0.30, 0.38, 0.52, 0.70)
	mm_sb.set_border_width_all(1)
	mm_sb.set_corner_radius_all(8)
	mm_sb.content_margin_left = 14
	mm_sb.content_margin_right = 14
	mm_sb.content_margin_top = 6
	mm_sb.content_margin_bottom = 6
	btn_main_menu.add_theme_stylebox_override("normal", mm_sb)
	var mm_hover := mm_sb.duplicate() as StyleBoxFlat
	mm_hover.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	btn_main_menu.add_theme_stylebox_override("hover", mm_hover)
	UIIcons.setup_centered_button(
		btn_main_menu,
		"MAIN MENU",
		"arrow_left",
		16,
		16,
		Color(0.80, 0.85, 0.95),
		Color(1.0, 0.85, 0.2),
		10
	)
	btn_main_menu.pressed.connect(func():
		TournamentManager.is_tournament_active = false
		GameManager.change_scene("res://scenes/main_menu.tscn")
	)
	btn_row.add_child(btn_main_menu)

func _update_hud() -> void:
	var is_online: bool = TournamentManager.is_online_tournament
	if is_online:
		btn_format_toggle.visible = false
		if bot_count_label and bot_count_label.get_parent():
			bot_count_label.get_parent().visible = false
		title_label.text = "ONLINE SABONG CHAMPIONSHIP"
	else:
		var fmt_str: String = "SINGLE ELIMINATION" if TournamentManager.current_format == TournamentManager.Format.SINGLE_ELIMINATION else "DOUBLE ELIMINATION"
		btn_format_toggle.text = "FORMAT: %s" % fmt_str
		bot_count_label.text = "%d BOTS (%d DUELISTS)" % [TournamentManager.current_bot_count, TournamentManager.current_bot_count + 1]

	var any_completed: bool = false
	for m in TournamentManager.matches:
		if m["is_completed"]:
			any_completed = true
			break
	btn_format_toggle.disabled = any_completed
	btn_bot_prev.disabled = any_completed
	btn_bot_next.disabled = any_completed

	var active_match: Dictionary = TournamentManager.get_current_match()
	if active_match.is_empty():
		match_info_label.text = "TOURNAMENT CONCLUDED"
		match_rooster_label.text = "ALL MATCHES COMPLETE"
		UIIcons.update_centered_button(btn_start_match, "VIEW LEADERBOARD", "trophy", 20)
		btn_start_match.disabled = false
	else:
		match_info_label.text = active_match["name"]
		var r1_name: String = active_match["rooster_1"].display_name.to_upper() if active_match["rooster_1"] else "TBD"
		var r2_name: String = active_match["rooster_2"].display_name.to_upper() if active_match["rooster_2"] else "TBD"
		match_rooster_label.text = "%s   VS   %s" % [r1_name, r2_name]

		if is_online:
			var nm = get_node_or_null("/root/NetworkManager")
			var my_peer_id: int = nm.local_peer_id if nm else 1
			var is_host: bool = nm.is_host if nm else false
			var p1_peer: int = active_match.get("p1_peer_id", 0)
			var p2_peer: int = active_match.get("p2_peer_id", 0)

			if my_peer_id == p1_peer or my_peer_id == p2_peer:
				UIIcons.update_centered_button(btn_start_match, "ENTER ARENA (FIGHT!)", "swords", 20)
			else:
				UIIcons.update_centered_button(btn_start_match, "ENTER ARENA (SPECTATE)", "eye", 20)

			if is_host:
				btn_start_match.disabled = (active_match["rooster_1"] == null or active_match["rooster_2"] == null)
			else:
				btn_start_match.disabled = true
		else:
			UIIcons.update_centered_button(btn_start_match, "ENTER ARENA (START MATCH)", "swords", 20)
			btn_start_match.disabled = (active_match["rooster_1"] == null or active_match["rooster_2"] == null)

func _on_bot_count_prev() -> void:
	var cur_idx: int = BOT_TIERS.find(TournamentManager.current_bot_count)
	if cur_idx > 0:
		var new_count: int = BOT_TIERS[cur_idx - 1]
		TournamentManager.start_new_tournament(TournamentManager.player_rooster, TournamentManager.current_format, new_count)

func _on_bot_count_next() -> void:
	var cur_idx: int = BOT_TIERS.find(TournamentManager.current_bot_count)
	if cur_idx >= 0 and cur_idx < BOT_TIERS.size() - 1:
		var new_count: int = BOT_TIERS[cur_idx + 1]
		TournamentManager.start_new_tournament(TournamentManager.player_rooster, TournamentManager.current_format, new_count)

func _on_toggle_format_pressed() -> void:
	var any_completed: bool = false
	for m in TournamentManager.matches:
		if m["is_completed"]:
			any_completed = true
			break
	if any_completed:
		return

	var new_fmt = TournamentManager.Format.DOUBLE_ELIMINATION if TournamentManager.current_format == TournamentManager.Format.SINGLE_ELIMINATION else TournamentManager.Format.SINGLE_ELIMINATION
	TournamentManager.start_new_tournament(TournamentManager.player_rooster, new_fmt, TournamentManager.current_bot_count)

func _on_start_match_pressed() -> void:
	if TournamentManager.tournament_completed:
		_show_leaderboard_presentation(TournamentManager.final_leaderboard)
		return

	var active_match: Dictionary = TournamentManager.get_current_match()
	if active_match.is_empty():
		return

	var r1: RoosterData = active_match["rooster_1"]
	var r2: RoosterData = active_match["rooster_2"]
	if not r1 or not r2:
		return

	if TournamentManager.is_online_tournament:
		var nm = get_node_or_null("/root/NetworkManager")
		if nm and nm.is_host:
			nm.broadcast_start_tournament_match(
				active_match["id"],
				active_match.get("p1_peer_id", 1),
				active_match.get("p2_peer_id", 0),
				r1.rooster_id,
				r2.rooster_id
			)
		return

	if r1 == TournamentManager.player_rooster:
		GameManager.selected_player_rooster = r1
		GameManager.selected_opponent_rooster = r2
	elif r2 == TournamentManager.player_rooster:
		GameManager.selected_player_rooster = r2
		GameManager.selected_opponent_rooster = r1
	else:
		GameManager.selected_player_rooster = r1
		GameManager.selected_opponent_rooster = r2

	_flash_to_arena()

func _on_network_tournament_match_started(_match_id: String, p1_peer: int, p2_peer: int) -> void:
	var active_match: Dictionary = TournamentManager.get_current_match()
	if active_match.is_empty():
		return
	var r1: RoosterData = active_match["rooster_1"]
	var r2: RoosterData = active_match["rooster_2"]
	var nm = get_node_or_null("/root/NetworkManager")
	var my_peer_id: int = nm.local_peer_id if nm else 1

	if my_peer_id == p1_peer:
		GameManager.selected_player_rooster = r1
		GameManager.selected_opponent_rooster = r2
	elif my_peer_id == p2_peer:
		GameManager.selected_player_rooster = r2
		GameManager.selected_opponent_rooster = r1
	else:
		# Spectator in tournament
		GameManager.selected_player_rooster = r1
		GameManager.selected_opponent_rooster = r2

	_flash_to_arena()

func _on_network_bracket_received(_data: Dictionary) -> void:
	_render_bracket()

func _flash_to_arena() -> void:
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.95, 0.8)
	flash.modulate.a = 0.0
	ui_layer.add_child(flash)

	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		GameManager.change_scene("res://scenes/arena.tscn")
	)

func _on_tournament_state_changed() -> void:
	_render_bracket()

func _on_tournament_finished(leaderboard: Array[Dictionary]) -> void:
	_show_leaderboard_presentation(leaderboard)

## ---------------------------------------------------------------------------
## Final Leaderboard Presentation (3D Podiums & High-Contrast Overlay)
## ---------------------------------------------------------------------------

func _show_leaderboard_presentation(leaderboard: Array[Dictionary]) -> void:
	if leaderboard.is_empty():
		return

	_build_3d_podiums(leaderboard)

	if leaderboard_panel != null and is_instance_valid(leaderboard_panel):
		leaderboard_panel.queue_free()

	leaderboard_panel = Control.new()
	leaderboard_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(leaderboard_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.08, 0.85)
	leaderboard_panel.add_child(bg)

	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(920, 680)
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	dialog.position = Vector2(
		(vp_size.x - 920) * 0.5,
		(vp_size.y - 680) * 0.5
	)
	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	d_style.border_color = Color.GOLD
	d_style.set_border_width_all(2)
	d_style.set_corner_radius_all(14)
	d_style.shadow_color = Color(0, 0, 0, 0.8)
	d_style.shadow_size = 28
	d_style.content_margin_left = 36
	d_style.content_margin_right = 36
	d_style.content_margin_top = 28
	d_style.content_margin_bottom = 28
	dialog.add_theme_stylebox_override("panel", d_style)
	leaderboard_panel.add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	dialog.add_child(vbox)

	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(title_hbox)

	var trophy_icon := UIIcons.create_icon_rect("trophy", 36, Color.GOLD)
	title_hbox.add_child(trophy_icon)

	var title := Label.new()
	title.text = "TOURNAMENT CHAMPIONSHIP STANDINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(title, 34)
	title.add_theme_color_override("font_color", Color.GOLD)
	title_hbox.add_child(title)

	var sub := Label.new()
	sub.text = "Official Cockpit Circuit Final Standings & Tournament Podiums"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(sub, 16)
	sub.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 0.85))
	vbox.add_child(sub)

	# Column Headers
	var col_header := HBoxContainer.new()
	col_header.add_theme_constant_override("separation", 16)
	vbox.add_child(col_header)

	var ch_rank := Label.new()
	ch_rank.text = "RANK"
	ch_rank.custom_minimum_size = Vector2(80, 0)
	UIFontStyle.style_subheading(ch_rank, 13)
	ch_rank.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
	col_header.add_child(ch_rank)

	var ch_title := Label.new()
	ch_title.text = "TIER"
	ch_title.custom_minimum_size = Vector2(150, 0)
	UIFontStyle.style_subheading(ch_title, 13)
	ch_title.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
	col_header.add_child(ch_title)

	var ch_name := Label.new()
	ch_name.text = "DUELIST"
	ch_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_subheading(ch_name, 13)
	ch_name.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
	col_header.add_child(ch_name)

	var ch_badge := Label.new()
	ch_badge.text = "STATUS / DIVISION"
	UIFontStyle.style_subheading(ch_badge, 13)
	ch_badge.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
	col_header.add_child(ch_badge)

	# Divider line
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.20, 0.28, 0.40, 0.60)
	vbox.add_child(div)

	# Scrollable or VBox for rank rows
	var rank_scroll := ScrollContainer.new()
	rank_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rank_scroll.custom_minimum_size = Vector2(0, 320)
	vbox.add_child(rank_scroll)

	var rank_box := VBoxContainer.new()
	rank_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_box.add_theme_constant_override("separation", 8)
	rank_scroll.add_child(rank_box)

	for item in leaderboard:
		var rank_num: int = int(item.get("rank", 1))
		var is_player: bool = (item.get("rooster", null) == TournamentManager.player_rooster)
		var row_panel := PanelContainer.new()
		var rp_sb := StyleBoxFlat.new()
		rp_sb.set_corner_radius_all(6)
		rp_sb.content_margin_left = 12
		rp_sb.content_margin_right = 12
		rp_sb.content_margin_top = 8
		rp_sb.content_margin_bottom = 8

		if is_player:
			rp_sb.bg_color = Color(0.24, 0.18, 0.06, 0.85)
			rp_sb.border_color = Color.GOLD
			rp_sb.set_border_width_all(1)
		else:
			rp_sb.bg_color = Color(0.08, 0.10, 0.16, 0.60)
			rp_sb.border_color = Color(0.18, 0.24, 0.35, 0.40)
			rp_sb.set_border_width_all(1)
		row_panel.add_theme_stylebox_override("panel", rp_sb)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row_panel.add_child(row)

		# Rank icon + number
		var r_icon_name := "circle"
		var r_color: Color = item.get("color", Color.WHITE)
		if rank_num == 1:
			r_icon_name = "trophy"
			r_color = Color.GOLD
		elif rank_num == 2:
			r_icon_name = "shield"
			r_color = Color(0.85, 0.88, 0.95)
		elif rank_num == 3:
			r_icon_name = "shield"
			r_color = Color(0.85, 0.55, 0.25)

		var r_icon := UIIcons.create_icon_rect(r_icon_name, 18, r_color)
		row.add_child(r_icon)

		var r_num := Label.new()
		r_num.text = "#%d" % rank_num
		r_num.custom_minimum_size = Vector2(46, 0)
		UIFontStyle.style_subheading(r_num, 20)
		r_num.add_theme_color_override("font_color", r_color)
		row.add_child(r_num)

		var title_r := Label.new()
		title_r.text = item.get("title", "")
		title_r.custom_minimum_size = Vector2(140, 0)
		UIFontStyle.style_subheading(title_r, 17)
		title_r.add_theme_color_override("font_color", r_color)
		row.add_child(title_r)

		var r_obj: RoosterData = item.get("rooster", null)
		var name_lbl := Label.new()
		name_lbl.text = r_obj.display_name.to_upper() if r_obj else "TBD"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFontStyle.style_body(name_lbl, 17, true)
		if is_player:
			name_lbl.text += " [YOU]"
			name_lbl.add_theme_color_override("font_color", Color.GOLD)
		row.add_child(name_lbl)

		var badge := Label.new()
		badge.text = item.get("badge", "")
		UIFontStyle.style_body(badge, 14, true)
		badge.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0) if not is_player else Color.GOLD)
		row.add_child(badge)

		rank_box.add_child(row_panel)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(sp)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 24)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var btn_play_again := Button.new()
	btn_play_again.custom_minimum_size = Vector2(280, 48)
	btn_play_again.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pa_sb := StyleBoxFlat.new()
	pa_sb.bg_color = Color(0.24, 0.18, 0.08, 0.95)
	pa_sb.border_color = Color.GOLD
	pa_sb.set_border_width_all(2)
	pa_sb.set_corner_radius_all(8)
	pa_sb.content_margin_left = 16
	pa_sb.content_margin_right = 16
	pa_sb.content_margin_top = 6
	pa_sb.content_margin_bottom = 6
	btn_play_again.add_theme_stylebox_override("normal", pa_sb)
	var pa_hover := pa_sb.duplicate() as StyleBoxFlat
	pa_hover.bg_color = Color(0.36, 0.28, 0.12, 0.98)
	btn_play_again.add_theme_stylebox_override("hover", pa_hover)
	UIIcons.setup_centered_button(
		btn_play_again,
		"START NEW TOURNAMENT",
		"refresh",
		20,
		17,
		Color.GOLD,
		Color.WHITE,
		10
	)
	btn_play_again.pressed.connect(func():
		TournamentManager.start_new_tournament(TournamentManager.player_rooster, TournamentManager.current_format, TournamentManager.current_bot_count)
		leaderboard_panel.queue_free()
		leaderboard_panel = null
		_clear_podiums()
		_render_bracket()
	)
	btn_row.add_child(btn_play_again)

	var btn_menu := Button.new()
	btn_menu.custom_minimum_size = Vector2(180, 48)
	btn_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var mn_sb := StyleBoxFlat.new()
	mn_sb.bg_color = Color(0.10, 0.12, 0.18, 0.90)
	mn_sb.border_color = Color(0.30, 0.38, 0.52, 0.70)
	mn_sb.set_border_width_all(1)
	mn_sb.set_corner_radius_all(8)
	mn_sb.content_margin_left = 14
	mn_sb.content_margin_right = 14
	mn_sb.content_margin_top = 6
	mn_sb.content_margin_bottom = 6
	btn_menu.add_theme_stylebox_override("normal", mn_sb)
	var mn_hover := mn_sb.duplicate() as StyleBoxFlat
	mn_hover.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	btn_menu.add_theme_stylebox_override("hover", mn_hover)
	UIIcons.setup_centered_button(
		btn_menu,
		"MAIN MENU",
		"arrow_left",
		18,
		17,
		Color(0.80, 0.85, 0.95),
		Color(1.0, 0.85, 0.2),
		10
	)
	btn_menu.pressed.connect(func():
		TournamentManager.is_tournament_active = false
		GameManager.change_scene("res://scenes/main_menu.tscn")
	)
	btn_row.add_child(btn_menu)

func _clear_podiums() -> void:
	for c in podium_root.get_children():
		c.queue_free()

func _build_3d_podiums(leaderboard: Array[Dictionary]) -> void:
	_clear_podiums()

	if leaderboard.size() >= 1:
		_spawn_podium_step(leaderboard[0], Vector3(0.0, 0.60, -2.0), 0.58, Color.GOLD, "1ST PLACE - CHAMPION")

	if leaderboard.size() >= 2:
		_spawn_podium_step(leaderboard[1], Vector3(-5.2, 0.35, 0.0), 0.44, Color(0.85, 0.88, 0.95), "2ND PLACE - RUNNER UP")

	if leaderboard.size() >= 3:
		_spawn_podium_step(leaderboard[2], Vector3(5.2, 0.35, 0.0), 0.44, Color(0.85, 0.55, 0.25), "3RD PLACE")

func _spawn_podium_step(item: Dictionary, pos: Vector3, scale_factor: float, color: Color, label_str: String) -> void:
	var pod := Node3D.new()
	pod.position = pos
	podium_root.add_child(pod)

	if arena_packed:
		var a_inst: Node3D = arena_packed.instantiate()
		a_inst.scale = Vector3(scale_factor, scale_factor, scale_factor)
		pod.add_child(a_inst)

	var r: RoosterData = item.get("rooster", null)
	if r:
		var r_node := Node3D.new()
		r_node.position = Vector3(0, 0.30, 0)
		pod.add_child(r_node)
		_spawn_rooster_model(r_node, r, true, 1.25)

	var l3d := Label3D.new()
	l3d.text = "%s\n%s" % [label_str, (r.display_name.to_upper() if r else "")]
	var f_title = UIFontStyle.get_title_font()
	if f_title:
		l3d.font = f_title
	l3d.font_size = 34
	l3d.outline_size = 8
	l3d.outline_modulate = Color.BLACK
	l3d.modulate = color
	l3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l3d.position = Vector3(0, 1.6, -scale_factor * 2.5)
	pod.add_child(l3d)
