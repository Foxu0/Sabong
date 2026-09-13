extends Node3D
class_name MainMenu

## MainMenu — Manages 3D Countryside scene, smooth Camera1/Camera2 transitions, and Menu/Mode UI.

@onready var camera_1: Camera3D = $Camera3D
@onready var camera_2: Camera3D = $Camera3D2

var cam1_transform: Transform3D
var cam2_transform: Transform3D
var camera_tween: Tween

var ui_layer: CanvasLayer
var cam1_container: Control
var cam2_container: Control
var active_modal: Control = null

func _ready() -> void:
	if camera_1:
		cam1_transform = camera_1.transform
		camera_1.make_current()
	if camera_2:
		cam2_transform = camera_2.transform
		camera_2.current = false

	_build_menu_ui()

func _build_menu_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# --- Camera 1 View UI (Main Menu) ---
	cam1_container = Control.new()
	cam1_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam1_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(cam1_container)

	# Title Banner & Subtitle
	var title_box := VBoxContainer.new()
	title_box.position = Vector2(90, 45)
	title_box.add_theme_constant_override("separation", 6)
	cam1_container.add_child(title_box)

	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 18)
	title_box.add_child(title_hbox)

	var title_label := Label.new()
	title_label.text = "SABONG LEGENDS:"
	UIFontStyle.style_title(title_label, 92)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title_hbox.add_child(title_label)

	var sub_title_label := Label.new()
	sub_title_label.text = "CLUCK COCK"
	UIFontStyle.style_title(sub_title_label, 92)
	sub_title_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	title_hbox.add_child(sub_title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = "Sloppier version of the 2d one"
	UIFontStyle.style_body(subtitle_label, 26, true)
	subtitle_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0, 0.95))
	title_box.add_child(subtitle_label)

	# Menu Buttons List (Large, bold smooth text buttons)
	var btn_vbox := VBoxContainer.new()
	btn_vbox.position = Vector2(90, 230)
	btn_vbox.custom_minimum_size = Vector2(650, 0)
	btn_vbox.add_theme_constant_override("separation", 20)
	cam1_container.add_child(btn_vbox)

	var btn_start := _create_menu_button("START GAME", 46, "swords")
	btn_start.pressed.connect(_on_start_game_pressed)
	btn_vbox.add_child(btn_start)

	var btn_leader := _create_menu_button("LEADERBOARDS", 46, "trophy")
	btn_leader.pressed.connect(_open_leaderboard_modal)
	btn_vbox.add_child(btn_leader)

	var btn_settings := _create_menu_button("SETTINGS", 46, "key")
	btn_settings.pressed.connect(_open_settings_modal)
	btn_vbox.add_child(btn_settings)

	var btn_credits := _create_menu_button("CREDITS", 46, "users")
	btn_credits.pressed.connect(_open_credits_modal)
	btn_vbox.add_child(btn_credits)

	var btn_exit := _create_menu_button("EXIT", 46, "arrow_left")
	btn_exit.pressed.connect(func(): get_tree().quit())
	btn_vbox.add_child(btn_exit)

	# Version Badge
	var ver_label := Label.new()
	ver_label.text = "v1.0.0 • Google DeepMind & Antigravity"
	ver_label.position = Vector2(90, 750)
	UIFontStyle.style_body(ver_label, 16)
	ver_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.75))
	cam1_container.add_child(ver_label)


	# --- Camera 2 View UI (Game Mode Selection) ---
	cam2_container = Control.new()
	cam2_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam2_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam2_container.visible = false
	cam2_container.modulate.a = 0.0
	ui_layer.add_child(cam2_container)

	var mode_title_box := VBoxContainer.new()
	mode_title_box.position = Vector2(90, 45)
	mode_title_box.add_theme_constant_override("separation", 6)
	cam2_container.add_child(mode_title_box)

	var mode_title := Label.new()
	mode_title.text = "CHOOSE GAME MODE"
	UIFontStyle.style_title(mode_title, 84)
	mode_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mode_title_box.add_child(mode_title)

	var mode_subtitle := Label.new()
	mode_subtitle.text = "Select your battlefield challenge"
	UIFontStyle.style_body(mode_subtitle, 26, true)
	mode_subtitle.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0, 0.9))
	mode_title_box.add_child(mode_subtitle)

	# Menu Buttons List (Exact same bold, flat style as the main menu)
	var mode_vbox := VBoxContainer.new()
	mode_vbox.position = Vector2(90, 220)
	mode_vbox.custom_minimum_size = Vector2(850, 0)
	mode_vbox.add_theme_constant_override("separation", 20)
	cam2_container.add_child(mode_vbox)

	var default_hint := "Select your battlefield challenge"

	var btn_online := _create_menu_button("TOURNAMENT (ONLINE MATCHMAKING)", 44, "globe")
	btn_online.mouse_entered.connect(func():
		mode_subtitle.text = "Compete against live duelists in ranked online multiplayer over LAN or Global Relay."
	)
	btn_online.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_online.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.TOURNAMENT_ONLINE))
	mode_vbox.add_child(btn_online)

	var btn_casual := _create_menu_button("CASUAL (TOURNAMENT WITH BOTS)", 44, "trophy")
	btn_casual.mouse_entered.connect(func():
		mode_subtitle.text = "Battle through an 8-rooster anime bracket elimination ladder in 3D bird's-eye view."
	)
	btn_casual.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_casual.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.CASUAL_BOTS))
	mode_vbox.add_child(btn_casual)

	var btn_1v1 := _create_menu_button("1V1 QUICK DUEL", 44, "swords")
	btn_1v1.mouse_entered.connect(func():
		mode_subtitle.text = "Jump straight into a single cockpit duel against a random anime rooster."
	)
	btn_1v1.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_1v1.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.VERSUS_1V1))
	mode_vbox.add_child(btn_1v1)

	var btn_tutorial := _create_menu_button("TUTORIAL (TRAINING GROUND)", 44, "shield")
	btn_tutorial.mouse_entered.connect(func():
		mode_subtitle.text = "Master cockpit mechanics, card requirements, Taya energy betting, and bell timings."
	)
	btn_tutorial.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_tutorial.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.TUTORIAL))
	mode_vbox.add_child(btn_tutorial)

	var btn_back := _create_menu_button("BACK TO MAIN MENU", 44, "arrow_left")
	btn_back.mouse_entered.connect(func():
		mode_subtitle.text = "Return to the main title screen."
	)
	btn_back.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_back.pressed.connect(_on_back_to_menu_pressed)
	mode_vbox.add_child(btn_back)


func _create_menu_button(label_text: String, font_sz: int = 46, icon_name: String = "") -> Button:
	var btn := Button.new()
	btn.text = label_text
	if not icon_name.is_empty():
		btn.icon = UIIcons.get_icon(icon_name, int(font_sz * 0.70))
		btn.add_theme_constant_override("h_separation", 18)
		btn.add_theme_color_override("icon_normal_color", Color(0.95, 0.95, 1.0))
		btn.add_theme_color_override("icon_hover_color", Color(1.0, 0.85, 0.2))
		btn.add_theme_color_override("icon_pressed_color", Color(0.9, 0.7, 0.1))
	btn.flat = true
	btn.custom_minimum_size = Vector2(850, 64)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIFontStyle.style_button(btn, font_sz)

	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	return btn


# ---------------------------------------------------------------------------
# Camera 1 <-> Camera 2 Transitions
# ---------------------------------------------------------------------------

func _on_start_game_pressed() -> void:
	_dismiss_modal()
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()

	camera_tween = create_tween().set_parallel(true)
	camera_tween.tween_property(camera_1, "transform", cam2_transform, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(cam1_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
	
	camera_tween.chain().tween_callback(func():
		cam1_container.visible = false
		cam2_container.visible = true
		var tw2 := create_tween()
		tw2.tween_property(cam2_container, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	)

func _on_back_to_menu_pressed() -> void:
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()

	camera_tween = create_tween().set_parallel(true)
	camera_tween.tween_property(camera_1, "transform", cam1_transform, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(cam2_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
	
	camera_tween.chain().tween_callback(func():
		cam2_container.visible = false
		cam1_container.visible = true
		var tw2 := create_tween()
		tw2.tween_property(cam1_container, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	)

func _launch_game_mode(mode: GameManager.GameMode) -> void:
	GameManager.selected_game_mode = mode

	# Online Matchmaking → show LobbyUI overlay first (Blueprint §9 matchmaking flow)
	if mode == GameManager.GameMode.TOURNAMENT_ONLINE:
		_open_online_lobby()
		return

	# All other modes → smooth fade to character select scene
	GameManager.is_online_match = false
	var fade_rect := ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	ui_layer.add_child(fade_rect)
	
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		GameManager.change_scene("res://scenes/character_select.tscn")
	)

func _open_online_lobby() -> void:
	_dismiss_modal()
	cam2_container.visible = false
	var lobby := LobbyUI.new()
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.modulate.a = 0.0
	ui_layer.add_child(lobby)
	# Fade lobby in
	var tw := create_tween()
	tw.tween_property(lobby, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD)
	
	# Restore game mode selection when returning from lobby
	lobby.tree_exited.connect(func():
		if cam2_container and is_instance_valid(cam2_container):
			cam2_container.visible = true
			cam2_container.modulate.a = 1.0
	)
	
	# When both players are connected and matched, proceed to character select
	lobby.lobby_finished.connect(func():
		GameManager.is_online_match = true
		# Fade to black then load character select
		var fade_rect := ColorRect.new()
		fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_rect.color = Color.BLACK
		fade_rect.modulate.a = 0.0
		ui_layer.add_child(fade_rect)
		var tw2 := create_tween()
		tw2.tween_property(fade_rect, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD)
		tw2.chain().tween_callback(func():
			var nm = get_node_or_null("/root/NetworkManager")
			if nm and nm.get("current_match_mode") == nm.MatchMode.TOURNAMENT:
				GameManager.change_scene("res://scenes/bracketscene.tscn")
			else:
				GameManager.change_scene("res://scenes/character_select.tscn")
		)
	)


# ---------------------------------------------------------------------------
# Modals (Leaderboard, Settings, Credits)
# ---------------------------------------------------------------------------

func _dismiss_modal() -> void:
	if active_modal and is_instance_valid(active_modal):
		var m := active_modal
		active_modal = null
		var tw := create_tween()
		tw.tween_property(m, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD)
		tw.chain().tween_callback(m.queue_free)

func _create_modal_base(title: String, width: float = 640, height: float = 520) -> VBoxContainer:
	_dismiss_modal()
	
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	active_modal = overlay
	ui_layer.add_child(overlay)
	
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.05, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(backdrop)
	
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_dismiss_modal()
	)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.95)
	style.border_color = Color.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var title_lbl := Label.new()
	title_lbl.text = title
	UIFontStyle.style_title(title_lbl, 32)
	title_lbl.add_theme_color_override("font_color", Color.GOLD)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.flat = true
	var empty_style := StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", empty_style)
	close_btn.add_theme_stylebox_override("hover", empty_style)
	close_btn.add_theme_stylebox_override("pressed", empty_style)
	UIFontStyle.style_button(close_btn, 22)
	close_btn.pressed.connect(_dismiss_modal)
	header.add_child(close_btn)
	
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD)
	
	return vbox

func _open_leaderboard_modal() -> void:
	var vbox := _create_modal_base("COCKPIT LEADERBOARDS", 860, 620)
	
	var desc := Label.new()
	desc.text = "Top Sabong Champions across all regions"
	UIFontStyle.style_body(desc, 18)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 0.8))
	vbox.add_child(desc)
	
	var ranks := [
		{"rank": "1", "name": "Hen-Goku (Super Saiyan)", "wins": "1,420 Wins", "badge": "GRANDMASTER"},
		{"rank": "2", "name": "Cocktaro (Star Platinum)", "wins": "1,380 Wins", "badge": "MASTER"},
		{"rank": "3", "name": "Cluckey D Puffy (5th Gear)", "wins": "1,290 Wins", "badge": "DIAMOND"},
		{"rank": "4", "name": "Eren Pecker (Titan Stomp)", "wins": "1,150 Wins", "badge": "PLATINUM"},
		{"rank": "5", "name": "Decluck (All For One)", "wins": "1,040 Wins", "badge": "GOLD"},
	]
	
	for r in ranks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		
		var r_lbl := Label.new()
		r_lbl.text = "#%s" % r["rank"]
		r_lbl.custom_minimum_size = Vector2(50, 0)
		UIFontStyle.style_subheading(r_lbl, 24)
		r_lbl.add_theme_color_override("font_color", Color.GOLD if r["rank"] == "1" else Color.WHITE)
		row.add_child(r_lbl)
		
		var name_lbl := Label.new()
		name_lbl.text = r["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFontStyle.style_body(name_lbl, 20, true)
		row.add_child(name_lbl)
		
		var wins_lbl := Label.new()
		wins_lbl.text = r["wins"]
		UIFontStyle.style_body(wins_lbl, 18)
		wins_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		row.add_child(wins_lbl)
		
		var badge_lbl := Label.new()
		badge_lbl.text = r["badge"]
		UIFontStyle.style_subheading(badge_lbl, 18)
		badge_lbl.add_theme_color_override("font_color", Color.GOLD)
		row.add_child(badge_lbl)
		
		vbox.add_child(row)

func _open_settings_modal() -> void:
	var vbox := _create_modal_base("GAME SETTINGS", 780, 560)
	
	# Master Volume Slider
	var master_lbl := Label.new()
	master_lbl.text = "Master Volume: %d%%" % int(GameManager.master_volume * 100)
	UIFontStyle.style_body(master_lbl, 20, true)
	vbox.add_child(master_lbl)
	var master_slider := HSlider.new()
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.05
	master_slider.value = GameManager.master_volume
	master_slider.value_changed.connect(func(val: float):
		GameManager.master_volume = val
		master_lbl.text = "Master Volume: %d%%" % int(val * 100)
	)
	vbox.add_child(master_slider)
	
	# SFX Volume Slider
	var sfx_lbl := Label.new()
	sfx_lbl.text = "SFX Volume: %d%%" % int(GameManager.sfx_volume * 100)
	UIFontStyle.style_body(sfx_lbl, 20, true)
	vbox.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = GameManager.sfx_volume
	sfx_slider.value_changed.connect(func(val: float):
		GameManager.sfx_volume = val
		sfx_lbl.text = "SFX Volume: %d%%" % int(val * 100)
	)
	vbox.add_child(sfx_slider)
	
	# Fullscreen Toggle
	var fs_check := CheckBox.new()
	fs_check.text = "Fullscreen Mode"
	UIFontStyle.style_button(fs_check, 20)
	fs_check.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	fs_check.toggled.connect(func(is_on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if is_on else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	vbox.add_child(fs_check)

func _open_credits_modal() -> void:
	var vbox := _create_modal_base("GAME CREDITS", 820, 560)
	
	var rtext := RichTextLabel.new()
	rtext.bbcode_enabled = true
	rtext.fit_content = true
	rtext.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_rich_text(rtext, 18)
	rtext.text = """[b][color=gold]SABONG LEGENDS: CLUCK COCK[/color][/b]
[i]The Ultimate 3D Anime Cockpit Card Battler[/i]

[b]Game Architecture & Design:[/b]
Pair Programming with Google DeepMind & Antigravity Agentic AI

[b]Voxel Models & Visual Assets:[/b]
MagicaVoxel Anime Rooster Champions & Tabletop Arena Props

[b]Anime Inspirations:[/b]
Dragon Ball, JoJo's Bizarre Adventure, One Piece, Re:Zero,
My Hero Academia, Attack on Titan, Demon Slayer, Death Note.

[color=gray]Thank you for playing![/color]"""
	vbox.add_child(rtext)
