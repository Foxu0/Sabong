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
var cam1_margin: MarginContainer
var cam2_margin: MarginContainer
var title_label: Label
var sub_title_label: Label
var subtitle_label: Label
var mode_title: Label
var ver_label: Label
var menu_buttons: Array[Button] = []
var active_modal: Control = null
var profile_bar: Control = null
var btn_online_menu: Button = null
var _pending_launch_online_after_login: bool = false

func _ready() -> void:
	if camera_1:
		cam1_transform = camera_1.transform
		camera_1.make_current()
	if camera_2:
		cam2_transform = camera_2.transform
		camera_2.current = false

	if AuthManager:
		if not AuthManager.login_succeeded.is_connected(_on_auth_state_updated):
			AuthManager.login_succeeded.connect(_on_auth_state_updated)
			AuthManager.taya_balance_updated.connect(_on_taya_balance_updated)
			AuthManager.rank_tier_changed.connect(_on_rank_tier_changed)
			AuthManager.logged_out.connect(_on_auth_state_updated)

	_build_menu_ui()

	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

	var mm = get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("play_menu_theme"):
		mm.play_menu_theme()

	var gm = get_node_or_null("/root/GraphicsManager")
	if gm and gm.has_method("apply_to_active_scene"):
		gm.apply_to_active_scene()

func _build_menu_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# --- Camera 1 View UI (Main Menu) ---
	cam1_container = Control.new()
	cam1_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam1_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(cam1_container)

	cam1_margin = MarginContainer.new()
	cam1_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam1_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam1_container.add_child(cam1_margin)

	var cam1_vbox := VBoxContainer.new()
	cam1_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam1_vbox.add_theme_constant_override("separation", 24)
	cam1_margin.add_child(cam1_vbox)

	# Title Banner & Subtitle
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 6)
	cam1_vbox.add_child(title_box)

	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 18)
	title_box.add_child(title_hbox)

	title_label = Label.new()
	title_label.text = "SABONG LEGENDS:"
	UIFontStyle.style_title(title_label, 92)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title_hbox.add_child(title_label)

	sub_title_label = Label.new()
	sub_title_label.text = "CLUCK COCK"
	UIFontStyle.style_title(sub_title_label, 92)
	sub_title_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	title_hbox.add_child(sub_title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Sloppier version of the 2d one"
	UIFontStyle.style_body(subtitle_label, 26, true)
	subtitle_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0, 0.95))
	title_box.add_child(subtitle_label)

	# Menu Buttons List (Large, bold smooth text buttons)
	var btn_vbox := VBoxContainer.new()
	btn_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn_vbox.add_theme_constant_override("separation", 16)
	cam1_vbox.add_child(btn_vbox)

	var btn_start := _create_menu_button("START GAME", 46, "gamepad")
	btn_start.pressed.connect(_on_start_game_pressed)
	btn_vbox.add_child(btn_start)
	menu_buttons.append(btn_start)

	var btn_leader := _create_menu_button("LEADERBOARDS", 46, "trophy")
	btn_leader.pressed.connect(_open_leaderboard_modal)
	btn_vbox.add_child(btn_leader)
	menu_buttons.append(btn_leader)

	var btn_settings := _create_menu_button("SETTINGS", 46, "gear")
	btn_settings.pressed.connect(_open_settings_modal)
	btn_vbox.add_child(btn_settings)
	menu_buttons.append(btn_settings)

	var btn_credits := _create_menu_button("CREDITS", 46, "award")
	btn_credits.pressed.connect(_open_credits_modal)
	btn_vbox.add_child(btn_credits)
	menu_buttons.append(btn_credits)

	var btn_exit := _create_menu_button("EXIT", 46, "power")
	btn_exit.pressed.connect(func(): get_tree().quit())
	btn_vbox.add_child(btn_exit)
	menu_buttons.append(btn_exit)

	# Version Badge (Anchored cleanly to PRESET_BOTTOM_LEFT)
	ver_label = Label.new()
	ver_label.text = "v1.0.0"
	ver_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	UIFontStyle.style_body(ver_label, 15)
	ver_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.75))
	cam1_container.add_child(ver_label)


	# --- Camera 2 View UI (Game Mode Selection) ---
	cam2_container = Control.new()
	cam2_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam2_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam2_container.visible = false
	cam2_container.modulate.a = 0.0
	ui_layer.add_child(cam2_container)

	cam2_margin = MarginContainer.new()
	cam2_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam2_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam2_container.add_child(cam2_margin)

	var cam2_vbox := VBoxContainer.new()
	cam2_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam2_vbox.add_theme_constant_override("separation", 20)
	cam2_margin.add_child(cam2_vbox)

	var mode_title_box := VBoxContainer.new()
	mode_title_box.add_theme_constant_override("separation", 6)
	cam2_vbox.add_child(mode_title_box)

	mode_title = Label.new()
	mode_title.text = "CHOOSE GAME MODE"
	UIFontStyle.style_title(mode_title, 84)
	mode_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mode_title_box.add_child(mode_title)

	var mode_subtitle := Label.new()
	mode_subtitle.text = "Select your battlefield challenge"
	mode_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIFontStyle.style_body(mode_subtitle, 26, true)
	mode_subtitle.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0, 0.9))
	mode_title_box.add_child(mode_subtitle)

	# Menu Buttons List (Organized into ONLINE PLAY and OFFLINE PLAY)
	var mode_vbox := VBoxContainer.new()
	mode_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mode_vbox.add_theme_constant_override("separation", 16)
	cam2_vbox.add_child(mode_vbox)

	var default_hint := "Select your battlefield challenge"

	# =========================================================================
	# SECTION 1: ONLINE PLAY
	# =========================================================================
	var online_sec := VBoxContainer.new()
	online_sec.add_theme_constant_override("separation", 8)
	mode_vbox.add_child(online_sec)

	var online_hdr := _create_mode_section_header("ONLINE PLAY", "MULTIPLAYER / RANKED", Color(0.35, 0.85, 1.0))
	online_sec.add_child(online_hdr)

	var online_btn_box := VBoxContainer.new()
	online_btn_box.add_theme_constant_override("separation", 6)
	online_sec.add_child(online_btn_box)

	btn_online_menu = _create_menu_button("TOURNAMENT (ONLINE MATCHMAKING)", 42, "globe")
	btn_online_menu.mouse_entered.connect(func():
		if AuthManager and AuthManager.is_logged_in:
			mode_subtitle.text = "Compete against live duelists in ranked online multiplayer over LAN or Global Relay."
		else:
			mode_subtitle.text = "Sign In Required! Create an account or sign in to join online tournaments & rank ladder."
	)
	btn_online_menu.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_online_menu.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.TOURNAMENT_ONLINE))
	online_btn_box.add_child(btn_online_menu)
	menu_buttons.append(btn_online_menu)

	# =========================================================================
	# SECTION 2: OFFLINE PLAY
	# =========================================================================
	var offline_sec := VBoxContainer.new()
	offline_sec.add_theme_constant_override("separation", 8)
	mode_vbox.add_child(offline_sec)

	var offline_hdr := _create_mode_section_header("OFFLINE PLAY", "SINGLEPLAYER / PRACTICE", Color(1.0, 0.82, 0.25))
	offline_sec.add_child(offline_hdr)

	var offline_btn_box := VBoxContainer.new()
	offline_btn_box.add_theme_constant_override("separation", 6)
	offline_sec.add_child(offline_btn_box)

	var btn_casual := _create_menu_button("CASUAL (TOURNAMENT WITH BOTS)", 42, "bot")
	btn_casual.mouse_entered.connect(func():
		mode_subtitle.text = "Battle through an 8-rooster anime bracket elimination ladder in 3D bird's-eye view."
	)
	btn_casual.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_casual.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.CASUAL_BOTS))
	offline_btn_box.add_child(btn_casual)
	menu_buttons.append(btn_casual)

	var btn_1v1 := _create_menu_button("1V1 QUICK DUEL", 42, "swords")
	btn_1v1.mouse_entered.connect(func():
		mode_subtitle.text = "Jump straight into a single cockpit duel against a random anime rooster."
	)
	btn_1v1.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_1v1.pressed.connect(func(): _launch_game_mode(GameManager.GameMode.VERSUS_1V1))
	offline_btn_box.add_child(btn_1v1)
	menu_buttons.append(btn_1v1)

	# =========================================================================
	# NAVIGATION: BACK TO MAIN MENU
	# =========================================================================
	var nav_box := VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 8)
	mode_vbox.add_child(nav_box)

	var nav_sep := ColorRect.new()
	nav_sep.custom_minimum_size = Vector2(220, 1)
	nav_sep.color = Color(1.0, 1.0, 1.0, 0.14)
	nav_box.add_child(nav_sep)

	var btn_back := _create_menu_button("BACK TO MAIN MENU", 38, "arrow_left")
	btn_back.mouse_entered.connect(func():
		mode_subtitle.text = "Return to the main title screen."
	)
	btn_back.mouse_exited.connect(func(): mode_subtitle.text = default_hint)
	btn_back.pressed.connect(_on_back_to_menu_pressed)
	nav_box.add_child(btn_back)
	menu_buttons.append(btn_back)

	# Build top profile bar AFTER camera containers so it's always top-layered
	_build_top_profile_bar()
	_update_online_button_state()
	_update_responsive_layout()

func _create_mode_section_header(title_text: String, tag_text: String, accent_color: Color) -> Control:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 12)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Decorative vertical accent bar
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(4, 18)
	bar.color = accent_color
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(bar)

	# Section Title Label
	var lbl := Label.new()
	lbl.text = title_text
	UIFontStyle.style_subheading(lbl, 20)
	lbl.add_theme_color_override("font_color", accent_color)
	lbl.add_theme_constant_override("outline_size", 0)
	container.add_child(lbl)

	# Category tag pill
	if not tag_text.is_empty():
		var tag_panel := PanelContainer.new()
		var t_style := StyleBoxFlat.new()
		t_style.bg_color = accent_color.lerp(Color.BLACK, 0.78)
		t_style.border_color = accent_color
		t_style.set_border_width_all(1)
		t_style.set_corner_radius_all(6)
		t_style.content_margin_left = 10
		t_style.content_margin_right = 10
		t_style.content_margin_top = 2
		t_style.content_margin_bottom = 2
		tag_panel.add_theme_stylebox_override("panel", t_style)

		var tag_lbl := Label.new()
		tag_lbl.text = tag_text
		UIFontStyle.style_body(tag_lbl, 11, true)
		tag_lbl.add_theme_color_override("font_color", accent_color)
		tag_lbl.add_theme_constant_override("outline_size", 0)
		tag_panel.add_child(tag_lbl)
		container.add_child(tag_panel)

	# Decorative horizontal extending line
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(80, 1)
	line.color = accent_color.lerp(Color.BLACK, 0.5)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(line)

	return container


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
	btn.custom_minimum_size = Vector2(0, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIFontStyle.style_button(btn, font_sz)

	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	return btn


func _on_viewport_size_changed() -> void:
	_update_responsive_layout()


func _update_responsive_layout() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	var margin_x: float = clampf(vp_size.x * 0.055, 48.0, 140.0)
	var margin_y: float = clampf(vp_size.y * 0.045, 28.0, 60.0)

	var title_sz: int = int(clampf(vp_size.x * 0.046, 40.0, 88.0))
	var sub_sz: int = int(clampf(vp_size.x * 0.015, 18.0, 26.0))
	var btn_sz: int = int(clampf(vp_size.y * 0.042, 26.0, 44.0))

	if is_instance_valid(cam1_margin):
		cam1_margin.add_theme_constant_override("margin_left", int(margin_x))
		cam1_margin.add_theme_constant_override("margin_top", int(margin_y))
		cam1_margin.add_theme_constant_override("margin_bottom", int(margin_y))
		cam1_margin.add_theme_constant_override("margin_right", int(margin_x))

	if is_instance_valid(cam2_margin):
		cam2_margin.add_theme_constant_override("margin_left", int(margin_x))
		cam2_margin.add_theme_constant_override("margin_top", int(margin_y))
		cam2_margin.add_theme_constant_override("margin_bottom", int(margin_y))
		cam2_margin.add_theme_constant_override("margin_right", int(margin_x))

	if is_instance_valid(title_label):
		UIFontStyle.style_title(title_label, title_sz)
	if is_instance_valid(sub_title_label):
		UIFontStyle.style_title(sub_title_label, title_sz)
	if is_instance_valid(subtitle_label):
		UIFontStyle.style_body(subtitle_label, sub_sz, true)
	if is_instance_valid(mode_title):
		UIFontStyle.style_title(mode_title, int(title_sz * 0.90))

	for btn in menu_buttons:
		if is_instance_valid(btn):
			UIFontStyle.style_button(btn, btn_sz)

	if is_instance_valid(ver_label):
		ver_label.offset_left = margin_x
		ver_label.offset_bottom = -22.0
		ver_label.offset_top = -52.0
		ver_label.offset_right = margin_x + 450.0

	_update_profile_chip()


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

	# Online Matchmaking → require sign in before letting into online tournament!
	if mode == GameManager.GameMode.TOURNAMENT_ONLINE:
		if not AuthManager or not AuthManager.is_logged_in:
			_prompt_login_required_for_tournament()
			return
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

func _prompt_login_required_for_tournament() -> void:
	_pending_launch_online_after_login = true
	_open_account_modal("SIGN IN REQUIRED TO ENTER ONLINE TOURNAMENT\nOnline matchmaking, spectator betting, and Prestige Rank ladder stats require an authenticated account.\nPlease create an account or sign in below to enter the multiplayer arena!")

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
	backdrop.color = Color(0.01, 0.02, 0.04, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(backdrop)
	
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_pending_launch_online_after_login = false
			_dismiss_modal()
	)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	
	var vp_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	var final_w: float = minf(width, vp_size.x - 48.0)
	var final_h: float = minf(height, vp_size.y - 48.0)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(final_w, final_h)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.84)
	style.border_color = Color(1.0, 1.0, 1.0, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var title_lbl := Label.new()
	title_lbl.text = title
	UIFontStyle.style_title(title_lbl, 32)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.flat = true
	var empty_style := StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", empty_style)
	close_btn.add_theme_stylebox_override("hover", empty_style)
	close_btn.add_theme_stylebox_override("pressed", empty_style)
	close_btn.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	UIFontStyle.style_button(close_btn, 22)
	close_btn.pressed.connect(func():
		_pending_launch_online_after_login = false
		_dismiss_modal()
	)
	header.add_child(close_btn)
	
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD)
	
	return vbox

# ---------------------------------------------------------------------------
# Top-Right Profile & Authentication Bar
# ---------------------------------------------------------------------------

func _on_auth_state_updated(_data = null) -> void:
	_update_profile_chip()
	_update_online_button_state()
	if _pending_launch_online_after_login and AuthManager and AuthManager.is_logged_in:
		_pending_launch_online_after_login = false
		_dismiss_modal()
		_launch_game_mode(GameManager.GameMode.TOURNAMENT_ONLINE)

func _on_taya_balance_updated(_new_balance: int) -> void:
	_update_profile_chip()

func _on_rank_tier_changed(new_tier: String, _old_tier: String) -> void:
	_update_profile_chip()
	_show_rank_up_toast(new_tier)

func _update_online_button_state() -> void:
	if not btn_online_menu or not is_instance_valid(btn_online_menu):
		return
	if AuthManager and AuthManager.is_logged_in:
		btn_online_menu.text = "TOURNAMENT (ONLINE MATCHMAKING)"
		btn_online_menu.icon = UIIcons.get_icon("globe", 30)
	else:
		btn_online_menu.text = "TOURNAMENT (ONLINE - SIGN IN REQUIRED)"
		btn_online_menu.icon = UIIcons.get_icon("lock", 30)

func _show_rank_up_toast(new_tier: String) -> void:
	var toast := PanelContainer.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 40.0
	var style := StyleBoxFlat.new()
	var tier_color := AuthManager.get_rank_color(new_tier) if AuthManager else Color.GOLD
	style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	style.border_color = tier_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	toast.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(toast)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	toast.add_child(vb)

	var lbl1 := Label.new()
	lbl1.text = "RANK TIER ELEVATION!"
	UIFontStyle.style_subheading(lbl1, 16)
	lbl1.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl1)

	var lbl2 := Label.new()
	lbl2.text = new_tier.to_upper()
	UIFontStyle.style_title(lbl2, 36)
	lbl2.add_theme_color_override("font_color", tier_color)
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl2)

	toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.3)
	tw.tween_interval(2.5)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(toast.queue_free)

func _build_top_profile_bar() -> void:
	if profile_bar and is_instance_valid(profile_bar):
		profile_bar.queue_free()

	profile_bar = MarginContainer.new()
	profile_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	profile_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	profile_bar.grow_vertical = Control.GROW_DIRECTION_END
	profile_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(profile_bar)
	profile_bar.move_to_front()

	_update_profile_chip()

func _update_profile_chip() -> void:
	if not profile_bar or not is_instance_valid(profile_bar):
		return
	for c in profile_bar.get_children():
		c.queue_free()

	var vp_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	var margin_x: int = int(clampf(vp_size.x * 0.045, 32.0, 96.0))
	var margin_y: int = int(clampf(vp_size.y * 0.035, 20.0, 44.0))

	profile_bar.add_theme_constant_override("margin_right", margin_x)
	profile_bar.add_theme_constant_override("margin_top", margin_y)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_END
	profile_bar.add_child(hbox)

	var is_logged: bool = AuthManager and AuthManager.is_logged_in
	var current_user: String = AuthManager.username if AuthManager else "Guest"
	var current_tier: String = AuthManager.rank_tier if AuthManager else "SILVER"
	var current_taya: int = AuthManager.taya_points if AuthManager else 500
	var tier_color: Color = AuthManager.get_rank_color(current_tier) if AuthManager else Color.SILVER

	if is_logged:
		var chip_panel := PanelContainer.new()
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(0.08, 0.10, 0.16, 0.88)
		ps.border_color = Color(1.0, 1.0, 1.0, 0.22)
		ps.set_border_width_all(1)
		ps.set_corner_radius_all(10)
		ps.content_margin_left = 14
		ps.content_margin_right = 16
		ps.content_margin_top = 6
		ps.content_margin_bottom = 6
		ps.shadow_size = 0
		chip_panel.add_theme_stylebox_override("panel", ps)

		var chip_hbox := HBoxContainer.new()
		chip_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_hbox.add_theme_constant_override("separation", 10)
		chip_panel.add_child(chip_hbox)

		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b_style := StyleBoxFlat.new()
		b_style.bg_color = tier_color.lerp(Color.BLACK, 0.70)
		b_style.border_color = tier_color
		b_style.set_border_width_all(1)
		b_style.set_corner_radius_all(8)
		b_style.content_margin_left = 12
		b_style.content_margin_right = 12
		b_style.content_margin_top = 4
		b_style.content_margin_bottom = 4
		badge.add_theme_stylebox_override("panel", b_style)
		chip_hbox.add_child(badge)

		var badge_lbl := Label.new()
		badge_lbl.text = current_tier.to_upper()
		UIFontStyle.style_body(badge_lbl, 16, true)
		badge_lbl.add_theme_color_override("font_color", tier_color)
		badge_lbl.add_theme_constant_override("outline_size", 0)
		badge.add_child(badge_lbl)

		var name_lbl := Label.new()
		name_lbl.text = current_user
		UIFontStyle.style_body(name_lbl, 17, true)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		chip_hbox.add_child(name_lbl)

		var div_lbl := Label.new()
		div_lbl.text = "|"
		UIFontStyle.style_body(div_lbl, 16)
		div_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		chip_hbox.add_child(div_lbl)

		var c_icon := UIIcons.create_icon_rect("coin", 18, Color(1.0, 0.85, 0.25))
		chip_hbox.add_child(c_icon)

		var coin_lbl := Label.new()
		coin_lbl.text = "%s TAYA" % _format_number(current_taya)
		UIFontStyle.style_body(coin_lbl, 17, true)
		coin_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		chip_hbox.add_child(coin_lbl)

		# Transparent button overlay for smooth clicking and hover highlight
		var chip_btn := Button.new()
		chip_btn.flat = true
		chip_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		chip_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var hover_ps := ps.duplicate()
		hover_ps.bg_color = Color(0.14, 0.18, 0.26, 0.94)
		hover_ps.border_color = Color(1.0, 1.0, 1.0, 0.50)
		hover_ps.shadow_size = 0
		chip_btn.add_theme_stylebox_override("hover", hover_ps)
		chip_btn.add_theme_stylebox_override("pressed", hover_ps)
		chip_btn.pressed.connect(func(): _open_account_modal())
		chip_panel.add_child(chip_btn)

		hbox.add_child(chip_panel)

	else:
		var btn_auth := Button.new()
		btn_auth.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_auth.custom_minimum_size = Vector2(200, 42)

		# Clean, simple dark card with subtle 1px border and no loud neon outline or shadow
		var a_style := StyleBoxFlat.new()
		a_style.bg_color = Color(0.08, 0.10, 0.16, 0.88)
		a_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
		a_style.set_border_width_all(1)
		a_style.set_corner_radius_all(10)
		a_style.content_margin_left = 18
		a_style.content_margin_right = 18
		a_style.shadow_size = 0
		btn_auth.add_theme_stylebox_override("normal", a_style)

		var a_hover := a_style.duplicate()
		a_hover.bg_color = Color(0.14, 0.18, 0.26, 0.94)
		a_hover.border_color = Color(1.0, 1.0, 1.0, 0.50)
		btn_auth.add_theme_stylebox_override("hover", a_hover)

		var a_pressed := a_style.duplicate()
		a_pressed.bg_color = Color(0.05, 0.07, 0.11, 0.96)
		a_pressed.border_color = Color(1.0, 1.0, 1.0, 0.15)
		btn_auth.add_theme_stylebox_override("pressed", a_pressed)

		btn_auth.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		# Clean centered button with white user icon and clean readable label
		UIIcons.setup_centered_button(
			btn_auth,
			"SIGN IN / REGISTER",
			"user",
			18,
			14,
			Color.WHITE,
			Color.WHITE,
			8
		)

		btn_auth.pressed.connect(func(): _open_account_modal("", "login"))
		hbox.add_child(btn_auth)

static func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result

func _start_otp_cooldown(btn: Button, default_text: String, cooldown_secs: int = 30) -> void:
	btn.disabled = true
	var remaining: int = cooldown_secs
	var lbl_node: Label = btn.get_node_or_null("CenteredButtonContent/ButtonLabel") as Label
	if lbl_node:
		lbl_node.text = "%ds" % remaining
	else:
		btn.text = "%ds" % remaining

	var timer := get_tree().create_timer(1.0)
	var tick: Callable
	tick = func():
		remaining -= 1
		if not is_instance_valid(btn):
			return
		if remaining > 0:
			var l: Label = btn.get_node_or_null("CenteredButtonContent/ButtonLabel") as Label
			if l:
				l.text = "%ds" % remaining
			else:
				btn.text = "%ds" % remaining
			get_tree().create_timer(1.0).timeout.connect(tick)
		else:
			btn.disabled = false
			var l: Label = btn.get_node_or_null("CenteredButtonContent/ButtonLabel") as Label
			if l:
				l.text = default_text
			else:
				btn.text = default_text
	timer.timeout.connect(tick)

func _create_password_input_row(placeholder: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 44)
	UIFontStyle.style_line_edit(edit, 16)
	row.add_child(edit)

	var eye_btn := Button.new()
	eye_btn.custom_minimum_size = Vector2(40, 44)
	eye_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var eye_style := StyleBoxFlat.new()
	eye_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	eye_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	eye_style.set_border_width_all(1)
	eye_style.set_corner_radius_all(6)
	eye_btn.add_theme_stylebox_override("normal", eye_style)
	var eye_hover := eye_style.duplicate()
	eye_hover.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	eye_hover.border_color = Color(1.0, 1.0, 1.0, 0.40)
	eye_btn.add_theme_stylebox_override("hover", eye_hover)
	eye_btn.add_theme_stylebox_override("pressed", eye_hover)
	eye_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eye_btn.add_child(center)

	var icon_rect := TextureRect.new()
	icon_rect.texture = UIIcons.get_icon("eye_off", 18)
	icon_rect.custom_minimum_size = Vector2(18, 18)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.modulate = Color(0.75, 0.80, 0.90)
	center.add_child(icon_rect)

	var update_eye: Callable
	update_eye = func():
		if edit.secret:
			icon_rect.texture = UIIcons.get_icon("eye_off", 18)
			icon_rect.modulate = Color(0.75, 0.80, 0.90)
			eye_btn.tooltip_text = "Show password"
		else:
			icon_rect.texture = UIIcons.get_icon("eye", 18)
			icon_rect.modulate = Color(1.0, 0.85, 0.2)
			eye_btn.tooltip_text = "Hide password"

	update_eye.call()

	eye_btn.mouse_entered.connect(func():
		if edit.secret:
			icon_rect.modulate = Color.WHITE
		else:
			icon_rect.modulate = Color(1.0, 0.95, 0.4)
	)
	eye_btn.mouse_exited.connect(func():
		update_eye.call()
	)
	eye_btn.pressed.connect(func():
		edit.secret = not edit.secret
		update_eye.call()
	)
	row.add_child(eye_btn)

	return {"row": row, "edit": edit, "button": eye_btn}

func _open_account_modal(required_banner: String = "", default_tab: String = "register") -> void:
	var is_logged: bool = AuthManager and AuthManager.is_logged_in
	var modal_w: float = 980.0 if is_logged else 720.0
	var modal_h: float = 680.0 if not required_banner.is_empty() else (580.0 if is_logged else 650.0)
	var vbox := _create_modal_base("PLAYER ACCOUNT & IDENTITY", modal_w, modal_h)

	if not required_banner.is_empty():
		var warn_box := PanelContainer.new()
		var ws := StyleBoxFlat.new()
		ws.bg_color = Color(0.6, 0.15, 0.15, 0.20)
		ws.border_color = Color(0.9, 0.35, 0.35, 0.40)
		ws.set_border_width_all(1)
		ws.set_corner_radius_all(8)
		ws.content_margin_left = 16
		ws.content_margin_right = 16
		ws.content_margin_top = 10
		ws.content_margin_bottom = 10
		warn_box.add_theme_stylebox_override("panel", ws)
		vbox.add_child(warn_box)

		var wh := HBoxContainer.new()
		wh.add_theme_constant_override("separation", 12)
		warn_box.add_child(wh)

		var w_icon := UIIcons.create_icon_rect("alert", 28, Color(1.0, 0.4, 0.4))
		wh.add_child(w_icon)

		var w_lbl := Label.new()
		w_lbl.text = required_banner
		w_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFontStyle.style_body(w_lbl, 14, true)
		w_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.92))
		w_lbl.add_theme_constant_override("outline_size", 0)
		wh.add_child(w_lbl)

	if is_logged:
		var tier_str: String = AuthManager.rank_tier
		var tier_col: Color = AuthManager.get_rank_color(tier_str)

		var card := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(1.0, 1.0, 1.0, 0.04)
		cs.border_color = Color(1.0, 1.0, 1.0, 0.10)
		cs.set_border_width_all(1)
		cs.set_corner_radius_all(12)
		cs.content_margin_left = 22
		cs.content_margin_right = 22
		cs.content_margin_top = 20
		cs.content_margin_bottom = 20
		card.add_theme_stylebox_override("panel", cs)
		vbox.add_child(card)

		var card_split := HBoxContainer.new()
		card_split.add_theme_constant_override("separation", 28)
		card.add_child(card_split)

		# Left column: Interactive Rank Card Preview (Significantly enlarged)
		var rank_card_panel := PanelContainer.new()
		rank_card_panel.custom_minimum_size = Vector2(286, 406)
		var rcp_style := StyleBoxFlat.new()
		rcp_style.bg_color = Color(1.0, 1.0, 1.0, 0.03)
		rcp_style.border_color = Color(1.0, 1.0, 1.0, 0.20)
		rcp_style.set_border_width_all(1)
		rcp_style.set_corner_radius_all(12)
		rcp_style.shadow_color = Color(0, 0, 0, 0.45)
		rcp_style.shadow_size = 12
		rcp_style.content_margin_left = 8
		rcp_style.content_margin_right = 8
		rcp_style.content_margin_top = 8
		rcp_style.content_margin_bottom = 8
		rank_card_panel.add_theme_stylebox_override("panel", rcp_style)
		card_split.add_child(rank_card_panel)

		var rank_card_img := TextureRect.new()
		var card_tex = AuthManager.get_rank_card_texture(tier_str)
		rank_card_img.texture = card_tex
		rank_card_img.custom_minimum_size = Vector2(270, 390)
		rank_card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rank_card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rank_card_panel.add_child(rank_card_img)

		var rank_card_btn := Button.new()
		rank_card_btn.flat = true
		rank_card_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		rank_card_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rank_card_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		rank_card_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var rcb_hover := StyleBoxFlat.new()
		rcb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		rcb_hover.border_color = Color.WHITE
		rcb_hover.set_border_width_all(1)
		rcb_hover.set_corner_radius_all(12)
		rank_card_btn.add_theme_stylebox_override("hover", rcb_hover)
		rank_card_btn.add_theme_stylebox_override("pressed", rcb_hover)
		rank_card_btn.tooltip_text = "Click to inspect all 7 Prestige Rank Cards"
		rank_card_btn.pressed.connect(func(): _open_rank_cards_modal())
		rank_card_panel.add_child(rank_card_btn)

		# Right column: Player identity, stats, and tier progression
		var cvb := VBoxContainer.new()
		cvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cvb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cvb.alignment = BoxContainer.ALIGNMENT_CENTER
		cvb.add_theme_constant_override("separation", 18)
		card_split.add_child(cvb)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 16)
		cvb.add_child(top_row)

		var p_name := Label.new()
		p_name.text = AuthManager.username
		UIFontStyle.style_title(p_name, 30)
		p_name.add_theme_color_override("font_color", Color.WHITE)
		p_name.add_theme_constant_override("outline_size", 0)
		p_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(p_name)

		var badge_panel := PanelContainer.new()
		var bps := StyleBoxFlat.new()
		bps.bg_color = tier_col.lerp(Color.BLACK, 0.70)
		bps.border_color = tier_col
		bps.set_border_width_all(1)
		bps.set_corner_radius_all(8)
		bps.content_margin_left = 16
		bps.content_margin_right = 16
		bps.content_margin_top = 6
		bps.content_margin_bottom = 6
		badge_panel.add_theme_stylebox_override("panel", bps)
		top_row.add_child(badge_panel)

		var b_lbl := Label.new()
		b_lbl.text = tier_str.to_upper()
		UIFontStyle.style_body(b_lbl, 18, true)
		b_lbl.add_theme_color_override("font_color", tier_col)
		b_lbl.add_theme_constant_override("outline_size", 0)
		badge_panel.add_child(b_lbl)

		var stats_row := HBoxContainer.new()
		stats_row.add_theme_constant_override("separation", 24)
		cvb.add_child(stats_row)

		var taya_box := HBoxContainer.new()
		taya_box.add_theme_constant_override("separation", 10)
		stats_row.add_child(taya_box)

		var t_icon := UIIcons.create_icon_rect("coin", 26, Color(1.0, 0.85, 0.25))
		taya_box.add_child(t_icon)

		var taya_lbl := Label.new()
		taya_lbl.text = "%s TAYA" % _format_number(AuthManager.taya_points)
		UIFontStyle.style_body(taya_lbl, 20, true)
		taya_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		taya_lbl.add_theme_constant_override("outline_size", 0)
		taya_box.add_child(taya_lbl)

		var rec_box := HBoxContainer.new()
		rec_box.add_theme_constant_override("separation", 8)
		stats_row.add_child(rec_box)

		var r_icon := UIIcons.create_icon_rect("swords", 20, Color(0.7, 0.8, 0.95))
		rec_box.add_child(r_icon)

		var record_lbl := Label.new()
		record_lbl.text = "%d Wins / %d Losses" % [AuthManager.wins, AuthManager.losses]
		UIFontStyle.style_body(record_lbl, 17)
		record_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
		record_lbl.add_theme_constant_override("outline_size", 0)
		rec_box.add_child(record_lbl)

		var prog_vb := VBoxContainer.new()
		prog_vb.add_theme_constant_override("separation", 6)
		cvb.add_child(prog_vb)

		var prog_hint := Label.new()
		if AuthManager and AuthManager.rank_tier == "UNRANK":
			prog_hint.text = "System Authority Status:"
		else:
			prog_hint.text = "Competitive Ladder Progression:"
		UIFontStyle.style_body(prog_hint, 13)
		prog_hint.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
		prog_hint.add_theme_constant_override("outline_size", 0)
		prog_vb.add_child(prog_hint)

		var next_tier_info := _get_next_tier_info(AuthManager.taya_points)
		var p_bar := ProgressBar.new()
		p_bar.custom_minimum_size = Vector2(0, 20)
		p_bar.show_percentage = false
		if AuthManager and AuthManager.rank_tier == "UNRANK":
			p_bar.min_value = 0
			p_bar.max_value = 1
			p_bar.value = 1
		else:
			p_bar.min_value = next_tier_info["min"]
			p_bar.max_value = next_tier_info["max"]
			p_bar.value = clampf(AuthManager.taya_points, next_tier_info["min"], next_tier_info["max"])
		prog_vb.add_child(p_bar)

		var p_label := Label.new()
		p_label.text = next_tier_info["text"]
		UIFontStyle.style_body(p_label, 13)
		p_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
		p_label.add_theme_constant_override("outline_size", 0)
		p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog_vb.add_child(p_label)

		# Action buttons row
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 12)
		cvb.add_child(action_row)

		var btn_show_ranks := Button.new()
		btn_show_ranks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_show_ranks.custom_minimum_size = Vector2(0, 44)
		btn_show_ranks.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bsr_style := StyleBoxFlat.new()
		bsr_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
		bsr_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
		bsr_style.set_border_width_all(1)
		bsr_style.set_corner_radius_all(8)
		btn_show_ranks.add_theme_stylebox_override("normal", bsr_style)
		var bsr_h := bsr_style.duplicate()
		bsr_h.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		btn_show_ranks.add_theme_stylebox_override("hover", bsr_h)
		btn_show_ranks.add_theme_stylebox_override("pressed", bsr_h)
		btn_show_ranks.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_show_ranks, "VIEW ALL 7 RANK CARDS", "crown", 18, 14, Color.WHITE, Color.WHITE)
		btn_show_ranks.pressed.connect(func(): _open_rank_cards_modal())
		action_row.add_child(btn_show_ranks)

		var btn_logout := Button.new()
		btn_logout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_logout.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_logout.custom_minimum_size = Vector2(0, 44)
		var lo_style := StyleBoxFlat.new()
		lo_style.bg_color = Color(0.80, 0.20, 0.20, 0.12)
		lo_style.border_color = Color(0.90, 0.35, 0.35, 0.35)
		lo_style.set_border_width_all(1)
		lo_style.set_corner_radius_all(8)
		btn_logout.add_theme_stylebox_override("normal", lo_style)
		var lo_hover := lo_style.duplicate()
		lo_hover.bg_color = Color(0.80, 0.20, 0.20, 0.22)
		btn_logout.add_theme_stylebox_override("hover", lo_hover)
		btn_logout.add_theme_stylebox_override("pressed", lo_hover)
		btn_logout.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_logout, "SIGN OUT / SWITCH", "log_out", 18, 14, Color(1.0, 0.8, 0.8), Color.WHITE)
		btn_logout.pressed.connect(func():
			if AuthManager:
				AuthManager.logout()
			_dismiss_modal()
			_open_account_modal("", "register")
		)
		action_row.add_child(btn_logout)

	else:
		# Logged out: Button to inspect ranks + Tabs for Register and Login
		var btn_view_ranks_tab := Button.new()
		btn_view_ranks_tab.custom_minimum_size = Vector2(0, 40)
		btn_view_ranks_tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bvr_style := StyleBoxFlat.new()
		bvr_style.bg_color = Color(1.0, 1.0, 1.0, 0.05)
		bvr_style.border_color = Color(1.0, 1.0, 1.0, 0.14)
		bvr_style.set_border_width_all(1)
		bvr_style.set_corner_radius_all(8)
		btn_view_ranks_tab.add_theme_stylebox_override("normal", bvr_style)
		var bvr_h := bvr_style.duplicate()
		bvr_h.bg_color = Color(1.0, 1.0, 1.0, 0.10)
		btn_view_ranks_tab.add_theme_stylebox_override("hover", bvr_h)
		btn_view_ranks_tab.add_theme_stylebox_override("pressed", bvr_h)
		btn_view_ranks_tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_view_ranks_tab, "VIEW ALL 7 PRESTIGE RANK CARDS", "crown", 18, 14, Color.WHITE, Color.WHITE)
		btn_view_ranks_tab.pressed.connect(func(): _open_rank_cards_modal())
		vbox.add_child(btn_view_ranks_tab)

		var tab_hbox := HBoxContainer.new()
		tab_hbox.add_theme_constant_override("separation", 12)
		vbox.add_child(tab_hbox)

		var tab_btn_reg := Button.new()
		tab_btn_reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_reg.custom_minimum_size = Vector2(0, 46)
		tab_btn_reg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab_btn_reg.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var reg_tab_ui := UIIcons.setup_centered_button(tab_btn_reg, "CREATE NEW ACCOUNT", "user_plus", 18, 15, Color.GOLD, Color.WHITE)
		tab_hbox.add_child(tab_btn_reg)

		var tab_btn_log := Button.new()
		tab_btn_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_log.custom_minimum_size = Vector2(0, 46)
		tab_btn_log.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab_btn_log.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var log_tab_ui := UIIcons.setup_centered_button(tab_btn_log, "SIGN IN / LOGIN", "log_in", 18, 15, Color(0.7, 0.75, 0.85), Color.WHITE)
		tab_hbox.add_child(tab_btn_log)

		# ScrollContainer to accommodate OTP fields smoothly on all displays
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		UIFontStyle.style_scroll_container(scroll, true)
		vbox.add_child(scroll)

		var content_box := VBoxContainer.new()
		content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_box.add_theme_constant_override("separation", 10)
		scroll.add_child(content_box)

		# Tab Panels
		var reg_panel := VBoxContainer.new()
		reg_panel.add_theme_constant_override("separation", 8)
		reg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_box.add_child(reg_panel)

		var log_panel := VBoxContainer.new()
		log_panel.add_theme_constant_override("separation", 12)
		log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		log_panel.visible = false
		content_box.add_child(log_panel)

		var forgot_panel := VBoxContainer.new()
		forgot_panel.add_theme_constant_override("separation", 10)
		forgot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		forgot_panel.visible = false
		content_box.add_child(forgot_panel)

		# Tab Switcher Styling
		var style_tab_active := StyleBoxFlat.new()
		style_tab_active.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		style_tab_active.border_color = Color(1.0, 1.0, 1.0, 0.35)
		style_tab_active.set_border_width_all(1)
		style_tab_active.set_corner_radius_all(8)

		var style_tab_inactive := StyleBoxFlat.new()
		style_tab_inactive.bg_color = Color(1.0, 1.0, 1.0, 0.03)
		style_tab_inactive.border_color = Color(1.0, 1.0, 1.0, 0.08)
		style_tab_inactive.set_border_width_all(1)
		style_tab_inactive.set_corner_radius_all(8)

		var update_tabs = func(tab_mode: String):
			reg_panel.visible = (tab_mode == "register")
			log_panel.visible = (tab_mode == "login")
			forgot_panel.visible = (tab_mode == "forgot")
			if tab_mode == "register":
				tab_btn_reg.add_theme_stylebox_override("normal", style_tab_active)
				if reg_tab_ui.get("label"): (reg_tab_ui["label"] as Label).add_theme_color_override("font_color", Color.WHITE)
				if reg_tab_ui.get("icon"): (reg_tab_ui["icon"] as TextureRect).modulate = Color.WHITE
				tab_btn_log.add_theme_stylebox_override("normal", style_tab_inactive)
				if log_tab_ui.get("label"): (log_tab_ui["label"] as Label).add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
				if log_tab_ui.get("icon"): (log_tab_ui["icon"] as TextureRect).modulate = Color(0.65, 0.70, 0.80)
			else:
				tab_btn_log.add_theme_stylebox_override("normal", style_tab_active)
				if log_tab_ui.get("label"): (log_tab_ui["label"] as Label).add_theme_color_override("font_color", Color.WHITE)
				if log_tab_ui.get("icon"): (log_tab_ui["icon"] as TextureRect).modulate = Color.WHITE
				tab_btn_reg.add_theme_stylebox_override("normal", style_tab_inactive)
				if reg_tab_ui.get("label"): (reg_tab_ui["label"] as Label).add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
				if reg_tab_ui.get("icon"): (reg_tab_ui["icon"] as TextureRect).modulate = Color(0.65, 0.70, 0.80)

		tab_btn_reg.pressed.connect(func(): update_tabs.call("register"))
		tab_btn_log.pressed.connect(func(): update_tabs.call("login"))

		# Shared button styles for OTP send buttons
		var s_btn_style := StyleBoxFlat.new()
		s_btn_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		s_btn_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
		s_btn_style.set_border_width_all(1)
		s_btn_style.set_corner_radius_all(6)
		var s_btn_hover := s_btn_style.duplicate()
		s_btn_hover.bg_color = Color(1.0, 1.0, 1.0, 0.15)

		# --- REGISTER TAB ---
		var reg_sub := Label.new()
		reg_sub.text = "Choose your fighter username, verify your email, and receive 500 starter Taya coins in the SILVER tier."
		reg_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(reg_sub, 14)
		reg_sub.add_theme_color_override("font_color", Color(0.80, 0.85, 0.95, 0.85))
		reg_sub.add_theme_constant_override("outline_size", 0)
		reg_panel.add_child(reg_sub)

		var reg_grid := VBoxContainer.new()
		reg_grid.add_theme_constant_override("separation", 8)
		reg_panel.add_child(reg_grid)

		var u_lbl := Label.new()
		u_lbl.text = "FIGHTER USERNAME *"
		UIFontStyle.style_body(u_lbl, 13, true)
		u_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		u_lbl.add_theme_constant_override("outline_size", 0)
		reg_grid.add_child(u_lbl)

		var reg_user_edit := LineEdit.new()
		reg_user_edit.placeholder_text = "Fighter name (3-20 letters, numbers, underscores)"
		reg_user_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(reg_user_edit, 16)
		reg_grid.add_child(reg_user_edit)

		var em_lbl := Label.new()
		em_lbl.text = "EMAIL ADDRESS (OTP VERIFICATION REQUIRED) *"
		UIFontStyle.style_body(em_lbl, 13, true)
		em_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		em_lbl.add_theme_constant_override("outline_size", 0)
		reg_grid.add_child(em_lbl)

		var email_row := HBoxContainer.new()
		email_row.add_theme_constant_override("separation", 8)
		reg_grid.add_child(email_row)

		var reg_email_edit := LineEdit.new()
		reg_email_edit.placeholder_text = "yourname@example.com"
		reg_email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reg_email_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(reg_email_edit, 16)
		email_row.add_child(reg_email_edit)

		var btn_send_reg_otp := Button.new()
		btn_send_reg_otp.custom_minimum_size = Vector2(130, 44)
		btn_send_reg_otp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_send_reg_otp.add_theme_stylebox_override("normal", s_btn_style)
		btn_send_reg_otp.add_theme_stylebox_override("hover", s_btn_hover)
		btn_send_reg_otp.add_theme_stylebox_override("pressed", s_btn_hover)
		btn_send_reg_otp.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_send_reg_otp, "SEND CODE", "mail", 16, 13, Color.WHITE, Color.WHITE)
		email_row.add_child(btn_send_reg_otp)

		var otp_lbl := Label.new()
		otp_lbl.text = "VERIFICATION CODE (OTP) *"
		UIFontStyle.style_body(otp_lbl, 13, true)
		otp_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		otp_lbl.add_theme_constant_override("outline_size", 0)
		reg_grid.add_child(otp_lbl)

		var reg_otp_edit := LineEdit.new()
		reg_otp_edit.placeholder_text = "Enter 6-digit code sent to your email"
		reg_otp_edit.max_length = 6
		reg_otp_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(reg_otp_edit, 16)
		reg_grid.add_child(reg_otp_edit)

		var p_lbl := Label.new()
		p_lbl.text = "PASSWORD (MIN. 6 CHARACTERS) *"
		UIFontStyle.style_body(p_lbl, 13, true)
		p_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		p_lbl.add_theme_constant_override("outline_size", 0)
		reg_grid.add_child(p_lbl)

		var reg_pass_data := _create_password_input_row("Create a secure password")
		var reg_pass_edit: LineEdit = reg_pass_data["edit"]
		reg_grid.add_child(reg_pass_data["row"])

		var cp_lbl := Label.new()
		cp_lbl.text = "CONFIRM PASSWORD *"
		UIFontStyle.style_body(cp_lbl, 13, true)
		cp_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		cp_lbl.add_theme_constant_override("outline_size", 0)
		reg_grid.add_child(cp_lbl)

		var reg_confirm_data := _create_password_input_row("Re-enter your password")
		var reg_confirm_edit: LineEdit = reg_confirm_data["edit"]
		reg_grid.add_child(reg_confirm_data["row"])

		var reg_status_lbl := Label.new()
		reg_status_lbl.text = ""
		reg_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(reg_status_lbl, 14)
		reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
		reg_status_lbl.add_theme_constant_override("outline_size", 0)
		reg_panel.add_child(reg_status_lbl)

		var btn_submit_reg := Button.new()
		btn_submit_reg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_submit_reg.custom_minimum_size = Vector2(0, 48)
		var sreg_style := StyleBoxFlat.new()
		sreg_style.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		sreg_style.border_color = Color(1.0, 1.0, 1.0, 0.35)
		sreg_style.set_border_width_all(1)
		sreg_style.set_corner_radius_all(8)
		btn_submit_reg.add_theme_stylebox_override("normal", sreg_style)
		var sreg_hover := sreg_style.duplicate()
		sreg_hover.bg_color = Color(1.0, 1.0, 1.0, 0.20)
		btn_submit_reg.add_theme_stylebox_override("hover", sreg_hover)
		btn_submit_reg.add_theme_stylebox_override("pressed", sreg_hover)
		btn_submit_reg.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_submit_reg, "CREATE ACCOUNT & ENTER ARENA", "user_plus", 20, 16, Color.WHITE, Color.WHITE)
		reg_panel.add_child(btn_submit_reg)

		# OTP send button handler
		btn_send_reg_otp.pressed.connect(func():
			var em := reg_email_edit.text.strip_edges()
			if em.is_empty() or not ("@" in em and "." in em):
				reg_status_lbl.text = "Please enter a valid email address first."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			reg_status_lbl.text = "Sending verification code..."
			reg_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			btn_send_reg_otp.disabled = true

			var on_reg_otp_sent: Callable
			var on_reg_otp_fail: Callable
			on_reg_otp_sent = func(msg: String, _dev_otp: String):
				if AuthManager.otp_sent.is_connected(on_reg_otp_sent): AuthManager.otp_sent.disconnect(on_reg_otp_sent)
				if AuthManager.otp_failed.is_connected(on_reg_otp_fail): AuthManager.otp_failed.disconnect(on_reg_otp_fail)
				reg_status_lbl.text = msg
				reg_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				_start_otp_cooldown(btn_send_reg_otp, "SEND CODE", 30)
				reg_otp_edit.grab_focus()

			on_reg_otp_fail = func(err: String):
				if AuthManager.otp_sent.is_connected(on_reg_otp_sent): AuthManager.otp_sent.disconnect(on_reg_otp_sent)
				if AuthManager.otp_failed.is_connected(on_reg_otp_fail): AuthManager.otp_failed.disconnect(on_reg_otp_fail)
				reg_status_lbl.text = str(err)
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				btn_send_reg_otp.disabled = false

			AuthManager.otp_sent.connect(on_reg_otp_sent)
			AuthManager.otp_failed.connect(on_reg_otp_fail)
			AuthManager.send_otp(em, "register")
		)

		btn_submit_reg.pressed.connect(func():
			var u := reg_user_edit.text.strip_edges()
			var em := reg_email_edit.text.strip_edges()
			var otp := reg_otp_edit.text.strip_edges()
			var p := reg_pass_edit.text.strip_edges()
			var cp := reg_confirm_edit.text.strip_edges()
			if u.length() < 3:
				reg_status_lbl.text = "Username must be at least 3 characters long."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if em.is_empty() or not ("@" in em and "." in em):
				reg_status_lbl.text = "A valid email address is required to register."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if otp.length() < 6:
				reg_status_lbl.text = "Please enter the 6-digit verification code sent to your email."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if p.length() < 6:
				reg_status_lbl.text = "Password must be at least 6 characters long."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if p != cp:
				reg_status_lbl.text = "Passwords do not match. Please re-enter."
				reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			reg_status_lbl.text = "Verifying code and creating account in TiDB Cloud..."
			reg_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			btn_submit_reg.disabled = true
			if AuthManager:
				var on_succ: Callable
				var on_fail: Callable
				on_succ = func(_d):
					if AuthManager.login_succeeded.is_connected(on_succ): AuthManager.login_succeeded.disconnect(on_succ)
					if AuthManager.login_failed.is_connected(on_fail): AuthManager.login_failed.disconnect(on_fail)
					_dismiss_modal()
				on_fail = func(err):
					if AuthManager.login_succeeded.is_connected(on_succ): AuthManager.login_succeeded.disconnect(on_succ)
					if AuthManager.login_failed.is_connected(on_fail): AuthManager.login_failed.disconnect(on_fail)
					reg_status_lbl.text = str(err)
					reg_status_lbl.add_theme_color_override("font_color", Color.SALMON)
					btn_submit_reg.disabled = false
				AuthManager.login_succeeded.connect(on_succ)
				AuthManager.login_failed.connect(on_fail)
				AuthManager.register_account(u, em, p, otp)
		)

		# --- LOGIN TAB ---
		var log_sub := Label.new()
		log_sub.text = "Enter your registered username/email and password to restore your Taya wallet and stats."
		log_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(log_sub, 14)
		log_sub.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 0.9))
		log_sub.add_theme_constant_override("outline_size", 0)
		log_panel.add_child(log_sub)

		var log_grid := VBoxContainer.new()
		log_grid.add_theme_constant_override("separation", 8)
		log_panel.add_child(log_grid)

		var lu_lbl := Label.new()
		lu_lbl.text = "USERNAME OR EMAIL *"
		UIFontStyle.style_body(lu_lbl, 13, true)
		lu_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		lu_lbl.add_theme_constant_override("outline_size", 0)
		log_grid.add_child(lu_lbl)

		var log_user_edit := LineEdit.new()
		log_user_edit.placeholder_text = "Your registered username or email"
		log_user_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(log_user_edit, 16)
		log_grid.add_child(log_user_edit)

		var lp_lbl := Label.new()
		lp_lbl.text = "PASSWORD *"
		UIFontStyle.style_body(lp_lbl, 13, true)
		lp_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		lp_lbl.add_theme_constant_override("outline_size", 0)
		log_grid.add_child(lp_lbl)

		var log_pass_data := _create_password_input_row("Your password")
		var log_pass_edit: LineEdit = log_pass_data["edit"]
		log_grid.add_child(log_pass_data["row"])

		var forgot_row := HBoxContainer.new()
		forgot_row.alignment = BoxContainer.ALIGNMENT_END
		log_grid.add_child(forgot_row)

		var btn_forgot := Button.new()
		btn_forgot.text = "Forgot Password?"
		btn_forgot.flat = true
		btn_forgot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_forgot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn_forgot.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
		UIFontStyle.style_button(btn_forgot, 13)
		btn_forgot.add_theme_constant_override("outline_size", 0)
		btn_forgot.pressed.connect(func(): update_tabs.call("forgot"))
		forgot_row.add_child(btn_forgot)

		var log_status_lbl := Label.new()
		log_status_lbl.text = ""
		log_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(log_status_lbl, 14)
		log_status_lbl.add_theme_color_override("font_color", Color.SALMON)
		log_status_lbl.add_theme_constant_override("outline_size", 0)
		log_panel.add_child(log_status_lbl)

		var btn_submit_log := Button.new()
		btn_submit_log.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_submit_log.custom_minimum_size = Vector2(0, 48)
		var slog_style := StyleBoxFlat.new()
		slog_style.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		slog_style.border_color = Color(1.0, 1.0, 1.0, 0.35)
		slog_style.set_border_width_all(1)
		slog_style.set_corner_radius_all(8)
		btn_submit_log.add_theme_stylebox_override("normal", slog_style)
		var slog_hover := slog_style.duplicate()
		slog_hover.bg_color = Color(1.0, 1.0, 1.0, 0.20)
		btn_submit_log.add_theme_stylebox_override("hover", slog_hover)
		btn_submit_log.add_theme_stylebox_override("pressed", slog_hover)
		btn_submit_log.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_submit_log, "SIGN IN TO COCKPIT", "log_in", 20, 16, Color.WHITE, Color.WHITE)
		log_panel.add_child(btn_submit_log)

		btn_submit_log.pressed.connect(func():
			var u := log_user_edit.text.strip_edges()
			var p := log_pass_edit.text.strip_edges()
			if u.is_empty() or p.is_empty():
				log_status_lbl.text = "Please enter both username/email and password."
				log_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			log_status_lbl.text = "Authenticating with server..."
			log_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			if AuthManager:
				var on_succ: Callable
				var on_fail: Callable
				on_succ = func(_d):
					if AuthManager.login_succeeded.is_connected(on_succ): AuthManager.login_succeeded.disconnect(on_succ)
					if AuthManager.login_failed.is_connected(on_fail): AuthManager.login_failed.disconnect(on_fail)
					_dismiss_modal()
				on_fail = func(err):
					if AuthManager.login_succeeded.is_connected(on_succ): AuthManager.login_succeeded.disconnect(on_succ)
					if AuthManager.login_failed.is_connected(on_fail): AuthManager.login_failed.disconnect(on_fail)
					log_status_lbl.text = str(err)
					log_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				AuthManager.login_succeeded.connect(on_succ)
				AuthManager.login_failed.connect(on_fail)
				AuthManager.login_email(u, p)
		)

		# --- FORGOT PASSWORD TAB / PANEL ---
		var forgot_sub := Label.new()
		forgot_sub.text = "Enter your registered email address to receive a secure password-reset verification code."
		forgot_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(forgot_sub, 14)
		forgot_sub.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 0.9))
		forgot_sub.add_theme_constant_override("outline_size", 0)
		forgot_panel.add_child(forgot_sub)

		var forgot_grid := VBoxContainer.new()
		forgot_grid.add_theme_constant_override("separation", 8)
		forgot_panel.add_child(forgot_grid)

		var fe_lbl := Label.new()
		fe_lbl.text = "REGISTERED EMAIL ADDRESS *"
		UIFontStyle.style_body(fe_lbl, 13, true)
		fe_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		fe_lbl.add_theme_constant_override("outline_size", 0)
		forgot_grid.add_child(fe_lbl)

		var forgot_email_row := HBoxContainer.new()
		forgot_email_row.add_theme_constant_override("separation", 8)
		forgot_grid.add_child(forgot_email_row)

		var forgot_email_edit := LineEdit.new()
		forgot_email_edit.placeholder_text = "yourname@example.com"
		forgot_email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		forgot_email_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(forgot_email_edit, 16)
		forgot_email_row.add_child(forgot_email_edit)

		var btn_send_forgot_otp := Button.new()
		btn_send_forgot_otp.custom_minimum_size = Vector2(130, 44)
		btn_send_forgot_otp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_send_forgot_otp.add_theme_stylebox_override("normal", s_btn_style)
		btn_send_forgot_otp.add_theme_stylebox_override("hover", s_btn_hover)
		btn_send_forgot_otp.add_theme_stylebox_override("pressed", s_btn_hover)
		btn_send_forgot_otp.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_send_forgot_otp, "SEND CODE", "mail", 16, 13, Color.WHITE, Color.WHITE)
		forgot_email_row.add_child(btn_send_forgot_otp)

		var fo_lbl := Label.new()
		fo_lbl.text = "VERIFICATION CODE (OTP) *"
		UIFontStyle.style_body(fo_lbl, 13, true)
		fo_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		fo_lbl.add_theme_constant_override("outline_size", 0)
		forgot_grid.add_child(fo_lbl)

		var forgot_otp_edit := LineEdit.new()
		forgot_otp_edit.placeholder_text = "6-digit code sent to your email"
		forgot_otp_edit.max_length = 6
		forgot_otp_edit.custom_minimum_size = Vector2(0, 44)
		UIFontStyle.style_line_edit(forgot_otp_edit, 16)
		forgot_grid.add_child(forgot_otp_edit)

		var fnp_lbl := Label.new()
		fnp_lbl.text = "NEW PASSWORD (MIN. 6 CHARACTERS) *"
		UIFontStyle.style_body(fnp_lbl, 13, true)
		fnp_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		fnp_lbl.add_theme_constant_override("outline_size", 0)
		forgot_grid.add_child(fnp_lbl)

		var forgot_pass_data := _create_password_input_row("Enter your new password")
		var forgot_pass_edit: LineEdit = forgot_pass_data["edit"]
		forgot_grid.add_child(forgot_pass_data["row"])

		var fcp_lbl := Label.new()
		fcp_lbl.text = "CONFIRM NEW PASSWORD *"
		UIFontStyle.style_body(fcp_lbl, 13, true)
		fcp_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
		fcp_lbl.add_theme_constant_override("outline_size", 0)
		forgot_grid.add_child(fcp_lbl)

		var forgot_confirm_data := _create_password_input_row("Re-enter your new password")
		var forgot_confirm_edit: LineEdit = forgot_confirm_data["edit"]
		forgot_grid.add_child(forgot_confirm_data["row"])

		var forgot_status_lbl := Label.new()
		forgot_status_lbl.text = ""
		forgot_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIFontStyle.style_body(forgot_status_lbl, 14)
		forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
		forgot_status_lbl.add_theme_constant_override("outline_size", 0)
		forgot_panel.add_child(forgot_status_lbl)

		var btn_submit_reset := Button.new()
		btn_submit_reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_submit_reset.custom_minimum_size = Vector2(0, 48)
		btn_submit_reset.add_theme_stylebox_override("normal", sreg_style)
		btn_submit_reset.add_theme_stylebox_override("hover", sreg_hover)
		btn_submit_reset.add_theme_stylebox_override("pressed", sreg_hover)
		btn_submit_reset.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_submit_reset, "RESET PASSWORD & SIGN IN", "lock", 20, 16, Color.WHITE, Color.WHITE)
		forgot_panel.add_child(btn_submit_reset)

		var btn_back_to_log := Button.new()
		btn_back_to_log.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_back_to_log.custom_minimum_size = Vector2(0, 42)
		var back_style := StyleBoxFlat.new()
		back_style.bg_color = Color(1.0, 1.0, 1.0, 0.05)
		back_style.border_color = Color(1.0, 1.0, 1.0, 0.14)
		back_style.set_border_width_all(1)
		back_style.set_corner_radius_all(8)
		btn_back_to_log.add_theme_stylebox_override("normal", back_style)
		var back_hover := back_style.duplicate()
		back_hover.bg_color = Color(1.0, 1.0, 1.0, 0.10)
		btn_back_to_log.add_theme_stylebox_override("hover", back_hover)
		btn_back_to_log.add_theme_stylebox_override("pressed", back_hover)
		btn_back_to_log.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIIcons.setup_centered_button(btn_back_to_log, "BACK TO SIGN IN", "arrow_left", 18, 14, Color.WHITE, Color.WHITE)
		btn_back_to_log.pressed.connect(func(): update_tabs.call("login"))
		forgot_panel.add_child(btn_back_to_log)

		# Forgot OTP send handler
		btn_send_forgot_otp.pressed.connect(func():
			var em := forgot_email_edit.text.strip_edges()
			if em.is_empty() or not ("@" in em and "." in em):
				forgot_status_lbl.text = "Please enter your registered email address."
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			forgot_status_lbl.text = "Sending password reset code..."
			forgot_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			btn_send_forgot_otp.disabled = true

			var on_f_sent: Callable
			var on_f_fail: Callable
			on_f_sent = func(msg: String, dev_otp: String):
				if AuthManager.otp_sent.is_connected(on_f_sent): AuthManager.otp_sent.disconnect(on_f_sent)
				if AuthManager.otp_failed.is_connected(on_f_fail): AuthManager.otp_failed.disconnect(on_f_fail)
				forgot_status_lbl.text = msg
				forgot_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				_start_otp_cooldown(btn_send_forgot_otp, "SEND CODE", 30)

			on_f_fail = func(err: String):
				if AuthManager.otp_sent.is_connected(on_f_sent): AuthManager.otp_sent.disconnect(on_f_sent)
				if AuthManager.otp_failed.is_connected(on_f_fail): AuthManager.otp_failed.disconnect(on_f_fail)
				forgot_status_lbl.text = err
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				btn_send_forgot_otp.disabled = false

			AuthManager.otp_sent.connect(on_f_sent)
			AuthManager.otp_failed.connect(on_f_fail)
			AuthManager.send_otp(em, "forgot_password")
		)

		btn_submit_reset.pressed.connect(func():
			var em := forgot_email_edit.text.strip_edges()
			var otp := forgot_otp_edit.text.strip_edges()
			var p := forgot_pass_edit.text.strip_edges()
			var cp := forgot_confirm_edit.text.strip_edges()
			if em.is_empty() or not ("@" in em and "." in em):
				forgot_status_lbl.text = "Please enter your registered email address."
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if otp.length() < 4:
				forgot_status_lbl.text = "Please enter the verification code sent to your email."
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if p.length() < 6:
				forgot_status_lbl.text = "New password must be at least 6 characters long."
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return
			if p != cp:
				forgot_status_lbl.text = "Passwords do not match. Please re-enter."
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)
				return

			forgot_status_lbl.text = "Resetting password..."
			forgot_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))

			var on_rst_succ: Callable
			var on_rst_fail: Callable
			on_rst_succ = func(_msg: String):
				if AuthManager.password_reset_succeeded.is_connected(on_rst_succ): AuthManager.password_reset_succeeded.disconnect(on_rst_succ)
				if AuthManager.password_reset_failed.is_connected(on_rst_fail): AuthManager.password_reset_failed.disconnect(on_rst_fail)
				forgot_status_lbl.text = "Password reset successfully! Signing in..."
				forgot_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				var on_log_succ: Callable
				var on_log_fail: Callable
				on_log_succ = func(_d):
					if AuthManager.login_succeeded.is_connected(on_log_succ): AuthManager.login_succeeded.disconnect(on_log_succ)
					if AuthManager.login_failed.is_connected(on_log_fail): AuthManager.login_failed.disconnect(on_log_fail)
					_dismiss_modal()
				on_log_fail = func(err):
					if AuthManager.login_succeeded.is_connected(on_log_succ): AuthManager.login_succeeded.disconnect(on_log_succ)
					if AuthManager.login_failed.is_connected(on_log_fail): AuthManager.login_failed.disconnect(on_log_fail)
					update_tabs.call("login")
					log_status_lbl.text = "Password reset successfully. Please sign in."
					log_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				AuthManager.login_succeeded.connect(on_log_succ)
				AuthManager.login_failed.connect(on_log_fail)
				AuthManager.login_email(em, p)

			on_rst_fail = func(err: String):
				if AuthManager.password_reset_succeeded.is_connected(on_rst_succ): AuthManager.password_reset_succeeded.disconnect(on_rst_succ)
				if AuthManager.password_reset_failed.is_connected(on_rst_fail): AuthManager.password_reset_failed.disconnect(on_rst_fail)
				forgot_status_lbl.text = err
				forgot_status_lbl.add_theme_color_override("font_color", Color.SALMON)

			AuthManager.password_reset_succeeded.connect(on_rst_succ)
			AuthManager.password_reset_failed.connect(on_rst_fail)
			AuthManager.reset_password(em, otp, p)
		)

		update_tabs.call(default_tab if default_tab in ["register", "login", "forgot"] else "register")

func _get_next_tier_info(taya: int) -> Dictionary:
	if AuthManager and AuthManager.rank_tier == "UNRANK":
		return {"min": 0, "max": 1, "text": "OPERATOR STATUS: UNRANK (Administrator Privileges)"}
	if taya < 500:
		return {"min": 0, "max": 500, "text": "%d / 500 Taya for SILVER" % taya}
	elif taya < 1000:
		return {"min": 500, "max": 1000, "text": "%d / 1,000 Taya for GOLD" % taya}
	elif taya < 2500:
		return {"min": 1000, "max": 2500, "text": "%d / 2,500 Taya for PLATINUM" % taya}
	elif taya < 5000:
		return {"min": 2500, "max": 5000, "text": "%d / 5,000 Taya for DIAMOND" % taya}
	elif taya < 10000:
		return {"min": 5000, "max": 10000, "text": "%d / 10,000 Taya for MASTER" % taya}
	elif taya < 20000:
		return {"min": 10000, "max": 20000, "text": "%d / 20,000 Taya for GRANDMASTER" % taya}
	else:
		return {"min": 20000, "max": 20000, "text": "MAX TIER: GRANDMASTER (Apex Champion)"}

func _open_rank_cards_modal(origin: String = "account") -> void:
	var vbox := _create_modal_base("PRESTIGE RANK LADDER & CARDS", 1180, 640)

	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 16)
	vbox.add_child(sub_row)

	var subtitle := Label.new()
	subtitle.text = "Ascend the Taya Ladder to unlock prestige fighting cards, cockpit status, and arena privileges."
	UIFontStyle.style_body(subtitle, 15)
	subtitle.add_theme_color_override("font_color", Color(0.80, 0.85, 0.95, 0.85))
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_row.add_child(subtitle)

	# Horizontal scroll gallery showing all 7 rank cards
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 455)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	UIFontStyle.style_scroll_container(scroll, false)
	vbox.add_child(scroll)

	var _on_scroll_wheel := func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN or ev.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				scroll.scroll_horizontal += 120
				scroll.accept_event()
			elif ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_LEFT:
				scroll.scroll_horizontal -= 120
				scroll.accept_event()

	scroll.gui_input.connect(_on_scroll_wheel)
	vbox.gui_input.connect(_on_scroll_wheel)

	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 18)
	card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_row)

	var player_taya: int = AuthManager.taya_points if (AuthManager and AuthManager.is_logged_in) else 0
	var player_tier: String = AuthManager.rank_tier if (AuthManager and AuthManager.is_logged_in) else ""
	var is_admin_viewing: bool = (AuthManager != null and AuthManager.is_logged_in and AuthManager.rank_tier == "UNRANK")

	var rank_defs = AuthManager.get_rank_definitions()
	for r in rank_defs:
		var tier_str: String = str(r["tier"])
		var is_current: bool = (AuthManager != null and AuthManager.is_logged_in and player_tier.to_upper() == tier_str)
		var is_unlocked: bool = is_admin_viewing or (AuthManager != null and AuthManager.is_logged_in and player_taya >= int(r["min_taya"]))
		var needed: int = (int(r["min_taya"]) - player_taya) if (AuthManager != null and AuthManager.is_logged_in and not is_admin_viewing) else 0

		var card_col := VBoxContainer.new()
		card_col.custom_minimum_size = Vector2(256, 0)
		card_col.add_theme_constant_override("separation", 8)
		card_row.add_child(card_col)

		# Top status badge: Only highlight CURRENT RANK or +X TAYA NEEDED
		if is_current:
			var badge_panel := PanelContainer.new()
			var b_style := StyleBoxFlat.new()
			b_style.set_corner_radius_all(6)
			b_style.content_margin_left = 8
			b_style.content_margin_right = 8
			b_style.content_margin_top = 4
			b_style.content_margin_bottom = 4
			b_style.bg_color = Color(1.0, 1.0, 1.0, 0.16)
			b_style.border_color = Color.WHITE
			b_style.set_border_width_all(1)
			badge_panel.add_theme_stylebox_override("panel", b_style)

			var badge_lbl := Label.new()
			UIFontStyle.style_body(badge_lbl, 13, true)
			badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_lbl.add_theme_constant_override("outline_size", 0)
			badge_lbl.text = "CURRENT RANK"
			badge_lbl.add_theme_color_override("font_color", Color.WHITE)
			badge_panel.add_child(badge_lbl)
			card_col.add_child(badge_panel)
		elif not is_unlocked and AuthManager != null and AuthManager.is_logged_in:
			var badge_panel := PanelContainer.new()
			var b_style := StyleBoxFlat.new()
			b_style.set_corner_radius_all(6)
			b_style.content_margin_left = 8
			b_style.content_margin_right = 8
			b_style.content_margin_top = 4
			b_style.content_margin_bottom = 4
			b_style.bg_color = Color(1.0, 1.0, 1.0, 0.04)
			b_style.border_color = Color(1.0, 1.0, 1.0, 0.12)
			b_style.set_border_width_all(1)
			badge_panel.add_theme_stylebox_override("panel", b_style)

			var badge_lbl := Label.new()
			UIFontStyle.style_body(badge_lbl, 13, true)
			badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_lbl.add_theme_constant_override("outline_size", 0)
			badge_lbl.text = "+%s TAYA" % _format_number(needed)
			badge_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88))
			badge_panel.add_child(badge_lbl)
			card_col.add_child(badge_panel)
		else:
			# Clean alignment spacer without repeating redundant "UNLOCKED" badges
			var badge_spacer := Control.new()
			badge_spacer.custom_minimum_size = Vector2(0, 26)
			card_col.add_child(badge_spacer)

		# Card artwork frame (Significantly enlarged)
		var img_panel := PanelContainer.new()
		var ip_style := StyleBoxFlat.new()
		ip_style.bg_color = Color(1.0, 1.0, 1.0, 0.04)
		ip_style.border_color = Color.WHITE if is_current else Color(1.0, 1.0, 1.0, 0.12)
		ip_style.set_border_width_all(2 if is_current else 1)
		ip_style.set_corner_radius_all(12)
		ip_style.shadow_color = Color(0, 0, 0, 0.40)
		ip_style.shadow_size = 10 if is_current else 4
		ip_style.content_margin_left = 6
		ip_style.content_margin_right = 6
		ip_style.content_margin_top = 6
		ip_style.content_margin_bottom = 6
		img_panel.add_theme_stylebox_override("panel", ip_style)
		card_col.add_child(img_panel)

		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(244, 352)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = AuthManager.get_rank_card_texture(tier_str)
		if not is_unlocked and AuthManager != null and AuthManager.is_logged_in:
			tex_rect.modulate = Color(0.48, 0.48, 0.52, 0.75)
		img_panel.add_child(tex_rect)

		# Taya requirement range pill (the card art already has the title and flavor text)
		var req_str: String = ""
		if int(r["max_taya"]) >= 999999:
			req_str = "%s+ TAYA" % _format_number(int(r["min_taya"]))
		else:
			req_str = "%s – %s TAYA" % [_format_number(int(r["min_taya"])), _format_number(int(r["max_taya"]))]

		var req_panel := PanelContainer.new()
		var rp_style := StyleBoxFlat.new()
		rp_style.set_corner_radius_all(6)
		rp_style.content_margin_left = 8
		rp_style.content_margin_right = 8
		rp_style.content_margin_top = 5
		rp_style.content_margin_bottom = 5
		rp_style.bg_color = Color(1.0, 1.0, 1.0, 0.09) if is_current else Color(1.0, 1.0, 1.0, 0.03)
		rp_style.border_color = Color.WHITE if is_current else Color(1.0, 1.0, 1.0, 0.10)
		rp_style.set_border_width_all(1)
		req_panel.add_theme_stylebox_override("panel", rp_style)

		var req_lbl := Label.new()
		req_lbl.text = req_str
		UIFontStyle.style_body(req_lbl, 13, true)
		req_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		req_lbl.add_theme_color_override("font_color", Color.WHITE if is_current else Color(0.85, 0.90, 0.96))
		req_lbl.add_theme_constant_override("outline_size", 0)
		req_panel.add_child(req_lbl)
		card_col.add_child(req_panel)

	# Bottom action bar: Single clean navigation button (header already has CLOSE)
	var bot_row := HBoxContainer.new()
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_row.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(bot_row)

	var btn_back := Button.new()
	btn_back.custom_minimum_size = Vector2(230, 42)
	btn_back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bb_style := StyleBoxFlat.new()
	bb_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	bb_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	bb_style.set_border_width_all(1)
	bb_style.set_corner_radius_all(8)
	btn_back.add_theme_stylebox_override("normal", bb_style)
	var bb_hover := bb_style.duplicate()
	bb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	btn_back.add_theme_stylebox_override("hover", bb_hover)
	btn_back.add_theme_stylebox_override("pressed", bb_hover)
	btn_back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if origin == "leaderboard":
		UIIcons.setup_centered_button(btn_back, "BACK TO LEADERBOARDS", "trophy", 16, 14, Color.WHITE, Color.WHITE)
		btn_back.pressed.connect(func(): _open_leaderboard_modal())
	else:
		UIIcons.setup_centered_button(btn_back, "BACK TO ACCOUNT", "user", 16, 14, Color.WHITE, Color.WHITE)
		btn_back.pressed.connect(func(): _open_account_modal())
	bot_row.add_child(btn_back)

func _open_leaderboard_modal() -> void:
	var vbox := _create_modal_base("COCKPIT LEADERBOARDS", 900, 640)

	var desc_row := HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 16)
	vbox.add_child(desc_row)

	var desc := Label.new()
	desc.text = "Real-time TiDB Cloud Standings • Ranked strictly by Taya Points"
	UIFontStyle.style_body(desc, 16)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 0.8))
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(desc)

	var btn_show_tiers := Button.new()
	btn_show_tiers.custom_minimum_size = Vector2(210, 36)
	btn_show_tiers.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bst_style := StyleBoxFlat.new()
	bst_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	bst_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	bst_style.set_border_width_all(1)
	bst_style.set_corner_radius_all(6)
	btn_show_tiers.add_theme_stylebox_override("normal", bst_style)
	var bst_hover := bst_style.duplicate()
	bst_hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	btn_show_tiers.add_theme_stylebox_override("hover", bst_hover)
	btn_show_tiers.add_theme_stylebox_override("pressed", bst_hover)
	btn_show_tiers.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UIIcons.setup_centered_button(btn_show_tiers, "RANK TIERS & CARDS", "crown", 16, 13, Color.WHITE, Color.WHITE)
	btn_show_tiers.pressed.connect(func(): _open_rank_cards_modal())
	desc_row.add_child(btn_show_tiers)

	var th_margin := MarginContainer.new()
	th_margin.add_theme_constant_override("margin_left", 14)
	th_margin.add_theme_constant_override("margin_right", 28) # 14px row margin + 14px vertical scrollbar gutter
	vbox.add_child(th_margin)

	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	th_margin.add_child(th)

	var th_rank := Label.new()
	th_rank.text = "RANK"
	th_rank.custom_minimum_size = Vector2(70, 0)
	UIFontStyle.style_subheading(th_rank, 15)
	th_rank.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	th.add_child(th_rank)

	var th_name := Label.new()
	th_name.text = "PLAYER IDENTITY"
	th_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_subheading(th_name, 15)
	th_name.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	th.add_child(th_name)

	var th_taya := Label.new()
	th_taya.text = "TAYA POINTS"
	th_taya.custom_minimum_size = Vector2(170, 0)
	th_taya.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(th_taya, 15)
	th_taya.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	th.add_child(th_taya)

	var th_tier := Label.new()
	th_tier.text = "TIER"
	th_tier.custom_minimum_size = Vector2(130, 0)
	th_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(th_tier, 15)
	th_tier.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	th.add_child(th_tier)

	var th_wins := Label.new()
	th_wins.text = "RECORD"
	th_wins.custom_minimum_size = Vector2(90, 0)
	th_wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIFontStyle.style_subheading(th_wins, 15)
	th_wins.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	th.add_child(th_wins)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	UIFontStyle.style_scroll_container(scroll, false)
	vbox.add_child(scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(rows_vbox)

	var loading_lbl := Label.new()
	loading_lbl.text = "Connecting to Cloud Leaderboards..."
	UIFontStyle.style_body(loading_lbl, 18)
	loading_lbl.add_theme_color_override("font_color", Color.CYAN)
	rows_vbox.add_child(loading_lbl)

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers, body: PackedByteArray):
		http.queue_free()
		if not is_instance_valid(rows_vbox):
			return
		for c in rows_vbox.get_children():
			c.queue_free()

		var arr: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json is Array:
				arr = json

		if arr.is_empty():
			var emp := Label.new()
			emp.text = "No champions recorded yet. Play ranked matches to take the throne!"
			UIFontStyle.style_body(emp, 18)
			emp.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
			rows_vbox.add_child(emp)
			return

		for item in arr:
			var rank_num: int = int(item.get("rank", 0))
			var username_str: String = str(item.get("username", "Challenger"))
			var taya_val: int = int(item.get("taya_coins", 0))
			var tier_str: String = str(item.get("rank_tier", "SILVER"))
			var wins_val: int = int(item.get("wins", 0))

			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(1.0, 1.0, 1.0, 0.04 if rank_num % 2 == 0 else 0.07)
			rs.border_color = Color(1.0, 1.0, 1.0, 0.08)
			rs.set_border_width_all(1)
			rs.set_corner_radius_all(8)
			rs.content_margin_left = 14
			rs.content_margin_right = 14
			rs.content_margin_top = 8
			rs.content_margin_bottom = 8
			row.add_theme_stylebox_override("panel", rs)
			rows_vbox.add_child(row)

			var rh := HBoxContainer.new()
			rh.add_theme_constant_override("separation", 16)
			row.add_child(rh)

			var r_lbl := Label.new()
			r_lbl.text = "#%d" % rank_num
			r_lbl.custom_minimum_size = Vector2(70, 0)
			UIFontStyle.style_subheading(r_lbl, 20)
			var r_col := Color.GOLD if rank_num == 1 else (Color(0.85, 0.88, 0.95) if rank_num == 2 else (Color(0.80, 0.55, 0.35) if rank_num == 3 else Color.WHITE))
			r_lbl.add_theme_color_override("font_color", r_col)
			rh.add_child(r_lbl)

			var n_lbl := Label.new()
			n_lbl.text = username_str
			n_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UIFontStyle.style_body(n_lbl, 18, true)
			n_lbl.add_theme_color_override("font_color", Color.WHITE)
			rh.add_child(n_lbl)

			var t_lbl := Label.new()
			t_lbl.text = "%s TAYA" % _format_number(taya_val)
			t_lbl.custom_minimum_size = Vector2(170, 0)
			t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UIFontStyle.style_subheading(t_lbl, 18)
			t_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
			rh.add_child(t_lbl)

			var tier_cell := CenterContainer.new()
			tier_cell.custom_minimum_size = Vector2(130, 0)
			rh.add_child(tier_cell)

			var t_col: Color = AuthManager.get_rank_color(tier_str) if AuthManager else Color.SILVER
			var bp := PanelContainer.new()
			var bps := StyleBoxFlat.new()
			bps.bg_color = t_col.lerp(Color.BLACK, 0.7)
			bps.border_color = t_col
			bps.set_border_width_all(1)
			bps.set_corner_radius_all(6)
			bps.content_margin_left = 12
			bps.content_margin_right = 12
			bps.content_margin_top = 4
			bps.content_margin_bottom = 4
			bp.add_theme_stylebox_override("panel", bps)
			tier_cell.add_child(bp)

			var b_lbl := Label.new()
			b_lbl.text = tier_str.to_upper()
			UIFontStyle.style_subheading(b_lbl, 13)
			b_lbl.add_theme_color_override("font_color", t_col)
			bp.add_child(b_lbl)

			var w_lbl := Label.new()
			w_lbl.text = "%d W" % wins_val
			w_lbl.custom_minimum_size = Vector2(90, 0)
			w_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UIFontStyle.style_body(w_lbl, 18)
			w_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
			rh.add_child(w_lbl)
	)
	var base_api := AuthManager.get_api_base_url() if (AuthManager and AuthManager.has_method("get_api_base_url")) else "http://localhost:10006"
	var url: String = base_api + "/leaderboard"
	http.request(url)

func _open_settings_modal() -> void:
	var vbox := _create_modal_base("SETTINGS & PREFERENCES", 760, 580)

	# Tab Buttons (Audio vs Graphics)
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 16)
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tab_bar)

	var btn_audio_tab := Button.new()
	btn_audio_tab.custom_minimum_size = Vector2(240, 44)
	UIIcons.setup_centered_button(btn_audio_tab, "AUDIO SETTINGS", "volume", 20, 18, Color.WHITE, Color.WHITE)
	tab_bar.add_child(btn_audio_tab)

	var btn_gfx_tab := Button.new()
	btn_gfx_tab.custom_minimum_size = Vector2(280, 44)
	UIIcons.setup_centered_button(btn_gfx_tab, "GRAPHICS & PERFORMANCE", "zap", 20, 18, Color(0.7, 0.7, 0.8), Color.WHITE)
	tab_bar.add_child(btn_gfx_tab)

	# Scroll Container for settings content
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 440)
	UIFontStyle.style_scroll_container(scroll, false)
	vbox.add_child(scroll)

	var content_box := VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 14)
	scroll.add_child(content_box)

	# --- 1. AUDIO SETTINGS CONTAINER ---
	var audio_vbox := VBoxContainer.new()
	audio_vbox.add_theme_constant_override("separation", 14)
	content_box.add_child(audio_vbox)

	var master_lbl := Label.new()
	master_lbl.text = "Master Volume: %d%%" % int(GameManager.master_volume * 100)
	UIFontStyle.style_body(master_lbl, 18, true)
	audio_vbox.add_child(master_lbl)
	var master_slider := HSlider.new()
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.05
	master_slider.value = GameManager.master_volume
	master_slider.value_changed.connect(func(val: float):
		GameManager.master_volume = val
		master_lbl.text = "Master Volume: %d%%" % int(val * 100)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(val) if val > 0.0 else -80.0)
	)
	audio_vbox.add_child(master_slider)

	var music_lbl := Label.new()
	music_lbl.text = "Music Volume: %d%%" % int(GameManager.music_volume * 100)
	UIFontStyle.style_body(music_lbl, 18, true)
	audio_vbox.add_child(music_lbl)
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = GameManager.music_volume
	music_slider.value_changed.connect(func(val: float):
		GameManager.music_volume = val
		music_lbl.text = "Music Volume: %d%%" % int(val * 100)
		var mm = get_node_or_null("/root/MusicManager")
		if mm and mm.has_method("set_volume"):
			mm.set_volume(val)
	)
	audio_vbox.add_child(music_slider)

	var sfx_lbl := Label.new()
	sfx_lbl.text = "SFX Volume: %d%%" % int(GameManager.sfx_volume * 100)
	UIFontStyle.style_body(sfx_lbl, 18, true)
	audio_vbox.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = GameManager.sfx_volume
	sfx_slider.value_changed.connect(func(val: float):
		GameManager.sfx_volume = val
		sfx_lbl.text = "SFX Volume: %d%%" % int(val * 100)
	)
	audio_vbox.add_child(sfx_slider)

	var track_box := PanelContainer.new()
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.12, 0.15, 0.22, 0.8)
	track_style.set_corner_radius_all(8)
	track_style.content_margin_left = 16
	track_style.content_margin_right = 16
	track_style.content_margin_top = 10
	track_style.content_margin_bottom = 10
	track_box.add_theme_stylebox_override("panel", track_style)
	audio_vbox.add_child(track_box)

	var track_hbox := HBoxContainer.new()
	track_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var mm = get_node_or_null("/root/MusicManager")
	var track_lbl := Label.new()
	track_lbl.text = "Track: " + (mm.get_current_track_title() if mm else "Retro Lounge")
	track_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_body(track_lbl, 18, true)
	track_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	track_hbox.add_child(track_lbl)

	var btn_prev := Button.new()
	btn_prev.text = "<< Prev"
	UIFontStyle.style_button(btn_prev, 16)
	btn_prev.pressed.connect(func():
		if mm and mm.has_method("prev_track"):
			mm.prev_track()
			track_lbl.text = "Track: " + mm.get_current_track_title()
	)
	track_hbox.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = "Next >>"
	UIFontStyle.style_button(btn_next, 16)
	btn_next.pressed.connect(func():
		if mm and mm.has_method("next_track"):
			mm.next_track()
			track_lbl.text = "Track: " + mm.get_current_track_title()
	)
	track_hbox.add_child(btn_next)
	track_box.add_child(track_hbox)

	# --- 2. GRAPHICS & PERFORMANCE SETTINGS CONTAINER ---
	var gfx_vbox := VBoxContainer.new()
	gfx_vbox.add_theme_constant_override("separation", 16)
	gfx_vbox.visible = false
	content_box.add_child(gfx_vbox)

	var gm_node = get_node_or_null("/root/GraphicsManager")

	# Quality Preset Selection
	var preset_hdr := Label.new()
	preset_hdr.text = "QUALITY PRESET"
	UIFontStyle.style_subheading(preset_hdr, 18)
	preset_hdr.add_theme_color_override("font_color", Color.GOLD)
	gfx_vbox.add_child(preset_hdr)

	var preset_hbox := HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 10)
	gfx_vbox.add_child(preset_hbox)

	var preset_btns: Array[Button] = []
	var presets := [
		{"name": "POTATO (MAX FPS)", "id": 0},
		{"name": "LOW", "id": 1},
		{"name": "MEDIUM", "id": 2},
		{"name": "HIGH", "id": 3},
		{"name": "ULTRA", "id": 4}
	]

	# Resolution Scale references
	var fsr_scale_lbl := Label.new()
	var fsr_scale_slider := HSlider.new()
	var shadow_chk: CheckBox = null
	var ssao_chk: CheckBox = null

	var _update_preset_buttons_visual = func():
		var cur_p = gm_node.current_preset if gm_node else 3
		for b in preset_btns:
			var pid: int = b.get_meta("preset_id", -1)
			var b_style := StyleBoxFlat.new()
			if pid == cur_p:
				b_style.bg_color = Color(0.70, 0.50, 0.10, 0.90)
				b_style.border_color = Color.GOLD
				b_style.set_border_width_all(2)
			else:
				b_style.bg_color = Color(0.12, 0.16, 0.24, 0.85)
				b_style.border_color = Color(0.3, 0.35, 0.45)
				b_style.set_border_width_all(1)
			b_style.set_corner_radius_all(6)
			b.add_theme_stylebox_override("normal", b_style)

	for p_info in presets:
		var p_btn := Button.new()
		p_btn.text = p_info["name"]
		p_btn.custom_minimum_size = Vector2(130, 42)
		p_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p_btn.set_meta("preset_id", p_info["id"])
		UIFontStyle.style_button(p_btn, 13)
		p_btn.pressed.connect(func():
			if gm_node:
				gm_node.set_preset(p_info["id"], true)
				fsr_scale_slider.value = gm_node.scaling_3d_scale
				var pct: int = int(gm_node.scaling_3d_scale * 100)
				fsr_scale_lbl.text = "3D Resolution Scale: %d%%" % pct
				_update_preset_buttons_visual.call()
				if shadow_chk and is_instance_valid(shadow_chk):
					shadow_chk.button_pressed = gm_node.shadows_enabled
				if ssao_chk and is_instance_valid(ssao_chk):
					ssao_chk.button_pressed = gm_node.ssao_enabled
		)
		preset_hbox.add_child(p_btn)
		preset_btns.append(p_btn)

	_update_preset_buttons_visual.call()

	# 3D Resolution Scale
	var cur_scale: float = gm_node.scaling_3d_scale if gm_node else 1.0
	fsr_scale_lbl.text = "3D Resolution Scale: %d%%" % int(cur_scale * 100)
	UIFontStyle.style_body(fsr_scale_lbl, 17, true)
	gfx_vbox.add_child(fsr_scale_lbl)

	fsr_scale_slider.min_value = 0.50
	fsr_scale_slider.max_value = 1.00
	fsr_scale_slider.step = 0.05
	fsr_scale_slider.value = cur_scale
	fsr_scale_slider.value_changed.connect(func(val: float):
		if gm_node:
			gm_node.scaling_3d_scale = val
			gm_node.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			gm_node.current_preset = gm_node.QualityPreset.CUSTOM
			gm_node.apply_all_settings()
			gm_node.save_settings()
			fsr_scale_lbl.text = "3D Resolution Scale: %d%%" % int(val * 100)
			_update_preset_buttons_visual.call()
	)
	gfx_vbox.add_child(fsr_scale_slider)

	# Framerate Limit Selector
	var fps_cap_lbl := Label.new()
	fps_cap_lbl.text = "TARGET FRAMERATE CAP (BROWSER V-SYNC)" if OS.has_feature("web") else "TARGET FRAMERATE CAP"
	UIFontStyle.style_subheading(fps_cap_lbl, 16)
	fps_cap_lbl.add_theme_color_override("font_color", Color.GOLD)
	gfx_vbox.add_child(fps_cap_lbl)

	var fps_hbox := HBoxContainer.new()
	fps_hbox.add_theme_constant_override("separation", 10)
	gfx_vbox.add_child(fps_hbox)

	var fps_options := [
		{"label": "30 FPS", "val": 30},
		{"label": "60 FPS", "val": 60},
		{"label": "120 FPS", "val": 120},
		{"label": "UNCAPPED", "val": 0}
	]
	var fps_btns: Array[Button] = []

	var _update_fps_buttons = func():
		var cur_fps_val = gm_node.max_fps if gm_node else 60
		for fb in fps_btns:
			var val: int = fb.get_meta("fps_val", 60)
			var b_style := StyleBoxFlat.new()
			if val == cur_fps_val:
				b_style.bg_color = Color(0.20, 0.55, 0.35, 0.90)
				b_style.border_color = Color(0.4, 1.0, 0.6)
				b_style.set_border_width_all(2)
			else:
				b_style.bg_color = Color(0.12, 0.16, 0.24, 0.85)
				b_style.border_color = Color(0.3, 0.35, 0.45)
				b_style.set_border_width_all(1)
			b_style.set_corner_radius_all(6)
			fb.add_theme_stylebox_override("normal", b_style)

	for opt in fps_options:
		var fb := Button.new()
		fb.text = opt["label"]
		fb.custom_minimum_size = Vector2(120, 38)
		fb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		fb.set_meta("fps_val", opt["val"])
		UIFontStyle.style_button(fb, 14)
		fb.pressed.connect(func():
			if gm_node:
				gm_node.max_fps = opt["val"]
				Engine.max_fps = 0 if OS.has_feature("web") else opt["val"]
				gm_node.save_settings()
				_update_fps_buttons.call()
		)
		fps_hbox.add_child(fb)
		fps_btns.append(fb)

	_update_fps_buttons.call()

	# Checkbox Features Box
	var chk_grid := GridContainer.new()
	chk_grid.columns = 2
	chk_grid.add_theme_constant_override("h_separation", 24)
	chk_grid.add_theme_constant_override("v_separation", 10)
	gfx_vbox.add_child(chk_grid)

	# 1. FPS Counter
	var fps_chk := CheckBox.new()
	fps_chk.text = "Show FPS & Frame Time"
	UIFontStyle.style_button(fps_chk, 16)
	fps_chk.button_pressed = gm_node.show_fps_counter if gm_node else false
	fps_chk.toggled.connect(func(is_on: bool):
		if gm_node:
			gm_node.toggle_fps_counter(is_on)
	)
	chk_grid.add_child(fps_chk)

	# 2. Dynamic Shadows Toggle (Major Performance Lever)
	shadow_chk = CheckBox.new()
	shadow_chk.text = "Dynamic 3D Shadows"
	UIFontStyle.style_button(shadow_chk, 16)
	shadow_chk.button_pressed = gm_node.shadows_enabled if gm_node else false
	shadow_chk.toggled.connect(func(is_on: bool):
		if gm_node:
			gm_node.set_shadows_enabled(is_on)
	)
	chk_grid.add_child(shadow_chk)

	# 3. Fullscreen
	var fs_check := CheckBox.new()
	fs_check.text = "Fullscreen Mode"
	UIFontStyle.style_button(fs_check, 16)
	fs_check.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	fs_check.toggled.connect(func(is_on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if is_on else DisplayServer.WINDOW_MODE_WINDOWED)
		if gm_node:
			gm_node.fullscreen = is_on
			gm_node.save_settings()
	)
	chk_grid.add_child(fs_check)

	# 4. SSAO
	ssao_chk = CheckBox.new()
	ssao_chk.text = "Ambient Occlusion (SSAO)"
	UIFontStyle.style_button(ssao_chk, 16)
	ssao_chk.button_pressed = gm_node.ssao_enabled if gm_node else false
	ssao_chk.toggled.connect(func(is_on: bool):
		if gm_node:
			gm_node.ssao_enabled = is_on
			gm_node.apply_to_active_scene()
			gm_node.save_settings()
	)
	chk_grid.add_child(ssao_chk)

	# 5. V-Sync (if desktop)
	if not OS.has_feature("web"):
		var vsync_chk := CheckBox.new()
		vsync_chk.text = "V-Sync (Prevent Screen Tearing)"
		UIFontStyle.style_button(vsync_chk, 16)
		vsync_chk.button_pressed = gm_node.vsync_enabled if gm_node else true
		vsync_chk.toggled.connect(func(is_on: bool):
			if gm_node:
				gm_node.vsync_enabled = is_on
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_on else DisplayServer.VSYNC_DISABLED)
				gm_node.save_settings()
		)
		chk_grid.add_child(vsync_chk)

	# Tab Switching Logic
	var active_tab_style := StyleBoxFlat.new()
	active_tab_style.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	active_tab_style.border_color = Color(1.0, 1.0, 1.0, 0.35)
	active_tab_style.set_border_width_all(1)
	active_tab_style.set_corner_radius_all(8)

	var inactive_tab_style := StyleBoxFlat.new()
	inactive_tab_style.bg_color = Color(1.0, 1.0, 1.0, 0.03)
	inactive_tab_style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	inactive_tab_style.set_border_width_all(1)
	inactive_tab_style.set_corner_radius_all(8)

	var _switch_settings_tab = func(is_audio: bool):
		audio_vbox.visible = is_audio
		gfx_vbox.visible = not is_audio
		btn_audio_tab.add_theme_stylebox_override("normal", active_tab_style if is_audio else inactive_tab_style)
		btn_gfx_tab.add_theme_stylebox_override("normal", inactive_tab_style if is_audio else active_tab_style)
		UIIcons.set_centered_button_color(btn_audio_tab, Color.WHITE if is_audio else Color(0.65, 0.70, 0.80))
		UIIcons.set_centered_button_color(btn_gfx_tab, Color.WHITE if not is_audio else Color(0.65, 0.70, 0.80))

	btn_audio_tab.pressed.connect(func(): _switch_settings_tab.call(true))
	btn_gfx_tab.pressed.connect(func(): _switch_settings_tab.call(false))
	_switch_settings_tab.call(true)

func _open_credits_modal() -> void:
	var vbox := _create_modal_base("GAME CREDITS", 860, 680)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIFontStyle.style_scroll_container(scroll, false)
	
	var rtext := RichTextLabel.new()
	rtext.bbcode_enabled = true
	rtext.fit_content = true
	rtext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIFontStyle.style_rich_text(rtext, 17)
	rtext.text = """[center][b][color=#FFFFFF]SABONG LEGENDS: CLUCK COCK[/color][/b]
[i][color=#A0B4C8]The Ultimate 3D Anime Cockpit Card Battler[/color][/i][/center]

[color=#FFFFFF][b]3D VOXEL ASSETS & ENVIRONMENT[/b][/color]
• [b]Max Parata[/b] — Voxel Country Side 3D Props Pack (Environment & Scenery)
• [b]Vedia Games[/b] — Fantasy Voxel Furniture & Props Pack (Arena & Tabletop Props)
• [b]Jublian[/b] — Rocky Voxel Pack (Cliff with Grass, Mossy Boulders, Stone Stairs)
• [b]CraftPix.net[/b] — 3D Voxel World Models & Environment Kit
• [b]Kenney (Kenney.nl)[/b] — Retro Urban & Tabletop Props

[color=#FFFFFF][b]ORIGINAL SOUNDTRACK & AUDIO[/b][/color]
• [b]Abstraction Music / Tallbeard Studios (Benjamin Burnes)[/b]
  Music Loop Bundle (CC-0) — [i]abstractionmusic.com[/i]
  - [i]Retro Lounge (Melody)[/i] — Main Menu & Character Select Theme
  - [i]Ruined Lands (Wasteland)[/i] — 3D Arena Battle Theme
  - [i]Lost in Space[/i] — Tournament Bracket & Standings Theme

[color=#FFFFFF][b]TYPOGRAPHY & DIGITAL FONTS[/b][/color]
• [b]Google Fonts (SIL Open Font License)[/b]
  - Anton & Staatliches — Action Headers, Mode Selector & Menu Buttons
  - Bangers — Combat Damage, Critical Strikes & Battle Overlays
  - PT Sans (Regular & Bold) — Card Stats, Moveset Descriptions & UI Body
  - Silkscreen & Press Start 2P — Digital Billboards & Retroware Badges
• [b]Digital 7-Segment[/b] — Cockpit Match Timer & HP Display

[color=#FFFFFF][b]TOOLS & OPEN SOURCE SOFTWARE[/b][/color]
• [b]Godot Engine 4.7[/b] — Juan Linietsky, Ariel Manzur & the Godot Community
• [b]MagicaVoxel Importer with Extensions (MIT)[/b] — Scayze, n3rdw1z4rd & contributors
• [b]MagicaVoxel[/b] — Ephtracy (Voxel Modeling Suite)

[center][b][color=#FFFFFF]Thank you for playing Sabong Legends: Cluck Cock![/color][/b][/center]"""
	scroll.add_child(rtext)
	vbox.add_child(scroll)
