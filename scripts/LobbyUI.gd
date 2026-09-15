extends Control
class_name LobbyUI

## LobbyUI — Competitive Multiplayer & Tournament Lobby.
## Redesigned to strictly match the Main Menu visual language (Staatliches & PT Sans).
## Pure vector icons via UIIcons, zero emojis, solid cockpit backdrop.

signal lobby_finished

# Network manager reference (Node type to prevent autoload singleton conflicts)
var _nm: Node = null

# Active Tab: "online" or "lan"
var _active_tab: String = "online"

# UI Containers
var _tab_online_btn: Button
var _tab_lan_btn: Button

# Tournament Mode State
var _host_mode: String = "duel" # "duel" or "tournament"
var _host_max_players: int = 8
const TOURNAMENT_PLAYER_TIERS: Array[int] = [4, 8, 16]
var _mode_duel_btn: Button
var _mode_tourney_btn: Button
var _max_players_stepper: PanelContainer
var _max_players_label: Label
var _tournament_roster_card: PanelContainer
var _tournament_roster_list_vbox: VBoxContainer
var _tournament_start_btn: Button
var _tournament_player_count_label: Label
var _known_room_modes: Dictionary = {}

# Header & Network Status
var _status_dot: TextureRect
var _status_network_label: Label
var _spinner_holder: Control
var _status_label: Label

# Action Center — Online
var _host_online_btn: Button
var _cancel_online_host_btn: Button
var _online_code_display_box: PanelContainer
var _room_code_large_label: Label
var _online_code_input: LineEdit
var _join_online_btn: Button

# Action Center — LAN
var _host_lan_btn: Button
var _lan_ip_input: LineEdit
var _join_lan_btn: Button

# Room Browser Lists
var _online_list_vbox: VBoxContainer
var _online_empty_label: Control
var _lan_list_vbox: VBoxContainer
var _lan_empty_label: Control
var _refresh_btn: Button

var _selected_lan_ip: String = ""
var _selected_online_code: String = ""
var _is_hosting: bool = false

func _ready() -> void:
	_nm = get_node_or_null("/root/NetworkManager")
	if _nm:
		_nm.player_connected.connect(_on_player_connected)
		_nm.player_disconnected.connect(_on_player_disconnected)
		_nm.server_disconnected.connect(_on_server_disconnected)
		_nm.match_ready.connect(_on_match_ready)
		_nm.opponent_disconnected_forfeit.connect(_on_forfeit)
		_nm.host_discovered.connect(_on_host_discovered)
		_nm.hosts_cleared.connect(_on_hosts_cleared)
		_nm.room_code_received.connect(_on_room_code_received)
		_nm.online_rooms_updated.connect(_on_online_rooms_updated)
		_nm.online_connection_failed.connect(_on_online_connection_failed)
		_nm.tournament_roster_updated.connect(_on_tournament_roster_updated)
		_nm.tournament_bracket_received.connect(_on_tournament_bracket_received)

	_build_ui()
	_switch_tab("online")

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 1. Semi-Transparent Dark Glass Scrim (Softly reveals 3D arena behind)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06, 0.70)
	add_child(bg)

	var main_margin := MarginContainer.new()
	main_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 64)
	main_margin.add_theme_constant_override("margin_right", 64)
	main_margin.add_theme_constant_override("margin_top", 32)
	main_margin.add_theme_constant_override("margin_bottom", 32)
	add_child(main_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 20)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_child(root_vbox)

	# --- TOP HEADER BAR ---
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 68)
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(top_bar)

	# Back Button (Left: Flat style exactly matching Main Menu)
	var back_btn := Button.new()
	back_btn.text = "BACK TO MENU"
	back_btn.icon = UIIcons.get_icon("arrow_left", 22)
	back_btn.custom_minimum_size = Vector2(200, 48)
	back_btn.flat = true
	back_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_btn.add_theme_constant_override("h_separation", 14)
	back_btn.add_theme_color_override("icon_normal_color", Color(0.95, 0.95, 1.0))
	back_btn.add_theme_color_override("icon_hover_color", Color(1.0, 0.85, 0.2))
	back_btn.add_theme_color_override("icon_pressed_color", Color(0.9, 0.7, 0.1))
	UIFontStyle.style_button(back_btn, 28)

	var empty_style := StyleBoxEmpty.new()
	back_btn.add_theme_stylebox_override("normal", empty_style)
	back_btn.add_theme_stylebox_override("hover", empty_style)
	back_btn.add_theme_stylebox_override("pressed", empty_style)
	back_btn.add_theme_stylebox_override("focus", empty_style)
	back_btn.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_btn)

	var top_spacer1 := Control.new()
	top_spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer1)

	# Center Titles (Bold Staatliches like Main Menu title)
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	title_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "ONLINE TOURNAMENT ARENA"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(title_lbl, 48)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "AUTHORITATIVE 3D TURN-BASED MULTIPLAYER • GLOBAL RELAY & LAN"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(sub_lbl, 16)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 0.85))
	title_vbox.add_child(sub_lbl)

	var top_spacer2 := Control.new()
	top_spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer2)

	# Right: Network Status Indicator
	var status_box := HBoxContainer.new()
	status_box.custom_minimum_size = Vector2(180, 48)
	status_box.alignment = BoxContainer.ALIGNMENT_END
	status_box.add_theme_constant_override("separation", 10)
	top_bar.add_child(status_box)

	_status_dot = UIIcons.create_icon_rect("circle", 12, Color(0.2, 0.85, 0.4))
	status_box.add_child(_status_dot)

	_status_network_label = Label.new()
	_status_network_label.text = "NETWORK READY"
	UIFontStyle.style_title(_status_network_label, 18)
	_status_network_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	status_box.add_child(_status_network_label)

	# --- SEGMENTED MODE SELECTOR TABS (Flat, borderless) ---
	var tab_container := CenterContainer.new()
	tab_container.custom_minimum_size = Vector2(0, 52)
	root_vbox.add_child(tab_container)

	var tab_hbox := HBoxContainer.new()
	tab_hbox.add_theme_constant_override("separation", 24)
	tab_container.add_child(tab_hbox)

	_tab_online_btn = _make_tab_btn("GLOBAL MATCHMAKING (ONLINE)", "globe")
	_tab_online_btn.pressed.connect(func(): _switch_tab("online"))
	tab_hbox.add_child(_tab_online_btn)

	_tab_lan_btn = _make_tab_btn("LOCAL NETWORK (LAN)", "lan")
	_tab_lan_btn.pressed.connect(func(): _switch_tab("lan"))
	tab_hbox.add_child(_tab_lan_btn)

	# --- MAIN TACTICAL DASHBOARD (2-COLUMN GRID, FLAT & BORDERLESS) ---
	var dashboard_hbox := HBoxContainer.new()
	dashboard_hbox.add_theme_constant_override("separation", 36)
	dashboard_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dashboard_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(dashboard_hbox)

	# LEFT COLUMN: ACTION CENTER (Host & Direct Join)
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(500, 0)
	left_col.size_flags_horizontal = Control.SIZE_FILL
	left_col.add_theme_constant_override("separation", 24)
	dashboard_hbox.add_child(left_col)

	# Section 1: Host Room
	left_col.add_child(_build_host_card())

	# Section Divider Line
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(1.0, 1.0, 1.0, 0.08)
	left_col.add_child(div)

	# Section 2: Direct Connect
	left_col.add_child(_build_direct_join_card())

	# Vertical Divider Line between Left and Right columns
	var v_div := ColorRect.new()
	v_div.custom_minimum_size = Vector2(1, 0)
	v_div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v_div.color = Color(1.0, 1.0, 1.0, 0.08)
	dashboard_hbox.add_child(v_div)

	# RIGHT COLUMN: LIVE ROOM BROWSER
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dashboard_hbox.add_child(right_col)

	right_col.add_child(_build_room_browser_card())

	# --- BOTTOM STATUS & FOOTER BAR (Flat, borderless) ---
	var footer_hbox := HBoxContainer.new()
	footer_hbox.custom_minimum_size = Vector2(0, 44)
	footer_hbox.add_theme_constant_override("separation", 14)
	root_vbox.add_child(footer_hbox)

	_spinner_holder = UIIcons.create_spinner_node(22, Color.GOLD)
	_spinner_holder.visible = false
	footer_hbox.add_child(_spinner_holder)

	_status_label = Label.new()
	_status_label.text = "Select a battle room to join or create a new room to challenge an opponent."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_body(_status_label, 15)
	_status_label.add_theme_color_override("font_color", Color(0.80, 0.88, 1.0))
	footer_hbox.add_child(_status_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "1V1 SIMULTANEOUS TURN COMBAT • 3 TAYA ENERGY PER ROUND"
	UIFontStyle.style_subheading(hint_lbl, 15)
	hint_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65))
	footer_hbox.add_child(hint_lbl)

func _make_tab_btn(label_text: String, icon_name: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(340, 48)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.flat = true
	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	UIIcons.setup_centered_button(
		btn,
		label_text,
		icon_name,
		22,
		24,
		Color(0.65, 0.70, 0.80),
		Color(1.0, 0.85, 0.2),
		12
	)
	return btn

# ---------------------------------------------------------------------------
# CARDS BUILDERS (LEFT & RIGHT COLUMNS)
# ---------------------------------------------------------------------------

func _build_host_card() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Card Title Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	vbox.add_child(hdr)

	var plus_icon := UIIcons.create_icon_rect("plus", 22, Color.GOLD)
	hdr.add_child(plus_icon)

	var title := Label.new()
	title.text = "CREATE BATTLE ROOM"
	UIFontStyle.style_title(title, 28)
	title.add_theme_color_override("font_color", Color.GOLD)
	hdr.add_child(title)

	var desc := Label.new()
	desc.text = "Host an authoritative match or multi-player tournament with dynamic brackets and byes."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIFontStyle.style_body(desc, 15)
	desc.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90, 0.85))
	vbox.add_child(desc)

	# Mode Selection Segmented Toggle
	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(mode_hbox)

	var seg_active := StyleBoxFlat.new()
	seg_active.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	seg_active.border_color = Color(1.0, 1.0, 1.0, 0.35)
	seg_active.set_border_width_all(1)
	seg_active.set_corner_radius_all(6)

	_mode_duel_btn = Button.new()
	_mode_duel_btn.custom_minimum_size = Vector2(0, 42)
	_mode_duel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_duel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mode_duel_btn.add_theme_stylebox_override("normal", seg_active)
	UIIcons.setup_centered_button(_mode_duel_btn, "1V1 DUEL", "swords", 18, 16, Color.WHITE, Color.WHITE, 8)
	_mode_duel_btn.pressed.connect(func(): _set_host_mode("duel"))
	mode_hbox.add_child(_mode_duel_btn)

	var seg_inactive := StyleBoxFlat.new()
	seg_inactive.bg_color = Color(1.0, 1.0, 1.0, 0.03)
	seg_inactive.border_color = Color(1.0, 1.0, 1.0, 0.08)
	seg_inactive.set_border_width_all(1)
	seg_inactive.set_corner_radius_all(6)

	_mode_tourney_btn = Button.new()
	_mode_tourney_btn.custom_minimum_size = Vector2(0, 42)
	_mode_tourney_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_tourney_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mode_tourney_btn.add_theme_stylebox_override("normal", seg_inactive)
	UIIcons.setup_centered_button(_mode_tourney_btn, "TOURNAMENT", "crown", 18, 16, Color(0.65, 0.70, 0.80), Color.WHITE, 8)
	_mode_tourney_btn.pressed.connect(func(): _set_host_mode("tournament"))
	mode_hbox.add_child(_mode_tourney_btn)

	# Max bracket stepper
	_max_players_stepper = PanelContainer.new()
	var ms_sb := StyleBoxFlat.new()
	ms_sb.bg_color = Color(0.06, 0.08, 0.12, 0.85)
	ms_sb.border_color = Color(0.3, 0.4, 0.6, 0.6)
	ms_sb.set_border_width_all(1)
	ms_sb.set_corner_radius_all(6)
	ms_sb.content_margin_left = 12
	ms_sb.content_margin_right = 12
	ms_sb.content_margin_top = 4
	ms_sb.content_margin_bottom = 4
	_max_players_stepper.add_theme_stylebox_override("panel", ms_sb)
	_max_players_stepper.visible = false
	vbox.add_child(_max_players_stepper)

	var st_hbox := HBoxContainer.new()
	st_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	st_hbox.add_theme_constant_override("separation", 10)
	_max_players_stepper.add_child(st_hbox)

	var step_icon := UIIcons.create_icon_rect("users", 18, Color.GOLD)
	st_hbox.add_child(step_icon)

	var step_prev := Button.new()
	step_prev.text = "<"
	step_prev.custom_minimum_size = Vector2(28, 28)
	UIFontStyle.style_button(step_prev, 16)
	step_prev.pressed.connect(func(): _step_max_players(-1))
	st_hbox.add_child(step_prev)

	_max_players_label = Label.new()
	_max_players_label.text = "MAX BRACKET: 8 PLAYERS"
	_max_players_label.custom_minimum_size = Vector2(200, 0)
	_max_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(_max_players_label, 14, true)
	_max_players_label.add_theme_color_override("font_color", Color.GOLD)
	st_hbox.add_child(_max_players_label)

	var step_next := Button.new()
	step_next.text = ">"
	step_next.custom_minimum_size = Vector2(28, 28)
	UIFontStyle.style_button(step_next, 16)
	step_next.pressed.connect(func(): _step_max_players(1))
	st_hbox.add_child(step_next)

	# Online Host Button (Flat, bold action style)
	_host_online_btn = Button.new()
	_host_online_btn.custom_minimum_size = Vector2(0, 54)
	_host_online_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hb_style := StyleBoxFlat.new()
	hb_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	hb_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	hb_style.set_border_width_all(1)
	hb_style.set_corner_radius_all(8)
	hb_style.content_margin_left = 20
	hb_style.content_margin_right = 20
	hb_style.content_margin_top = 8
	hb_style.content_margin_bottom = 8
	_host_online_btn.add_theme_stylebox_override("normal", hb_style)
	var hb_hover := hb_style.duplicate() as StyleBoxFlat
	hb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	hb_hover.shadow_size = 8
	hb_hover.shadow_color = Color(0, 0, 0, 0.3)
	_host_online_btn.add_theme_stylebox_override("hover", hb_hover)
	UIIcons.setup_centered_button(
		_host_online_btn,
		"HOST ONLINE MATCH",
		"globe",
		24,
		24,
		Color.WHITE,
		Color.WHITE,
		14
	)
	_host_online_btn.pressed.connect(_on_host_online_pressed)
	vbox.add_child(_host_online_btn)

	# LAN Host Button
	_host_lan_btn = Button.new()
	_host_lan_btn.custom_minimum_size = Vector2(0, 54)
	_host_lan_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var lb_style := hb_style.duplicate() as StyleBoxFlat
	lb_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	lb_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	_host_lan_btn.add_theme_stylebox_override("normal", lb_style)
	var lb_hover := lb_style.duplicate() as StyleBoxFlat
	lb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	lb_hover.shadow_size = 8
	lb_hover.shadow_color = Color(0, 0, 0, 0.3)
	_host_lan_btn.add_theme_stylebox_override("hover", lb_hover)
	_host_lan_btn.visible = false
	UIIcons.setup_centered_button(
		_host_lan_btn,
		"HOST LAN MATCH (PORT 7777)",
		"lan",
		24,
		24,
		Color.WHITE,
		Color.WHITE,
		14
	)
	_host_lan_btn.pressed.connect(_on_host_lan_pressed)
	vbox.add_child(_host_lan_btn)

	# Online Room Code Display Box (appears when hosting online)
	_online_code_display_box = PanelContainer.new()
	var rcb := StyleBoxFlat.new()
	rcb.bg_color = Color(0.04, 0.05, 0.09, 0.80)
	rcb.border_color = Color.GOLD
	rcb.set_border_width_all(1)
	rcb.set_corner_radius_all(8)
	rcb.content_margin_top = 12
	rcb.content_margin_bottom = 12
	_online_code_display_box.add_theme_stylebox_override("panel", rcb)
	_online_code_display_box.visible = false
	vbox.add_child(_online_code_display_box)

	var code_vbox := VBoxContainer.new()
	code_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	code_vbox.add_theme_constant_override("separation", 4)
	_online_code_display_box.add_child(code_vbox)

	var code_desc := Label.new()
	code_desc.text = "SHARE THIS ROOM CODE WITH YOUR OPPONENT"
	code_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(code_desc, 13, true)
	code_desc.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	code_vbox.add_child(code_desc)

	_room_code_large_label = Label.new()
	_room_code_large_label.text = "----"
	_room_code_large_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(_room_code_large_label, 52)
	_room_code_large_label.add_theme_color_override("font_color", Color.GOLD)
	code_vbox.add_child(_room_code_large_label)

	# Cancel Host Button
	_cancel_online_host_btn = Button.new()
	_cancel_online_host_btn.custom_minimum_size = Vector2(0, 44)
	_cancel_online_host_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_cancel_online_host_btn.flat = true
	var empty_cb := StyleBoxEmpty.new()
	_cancel_online_host_btn.add_theme_stylebox_override("normal", empty_cb)
	_cancel_online_host_btn.add_theme_stylebox_override("hover", empty_cb)
	_cancel_online_host_btn.visible = false
	UIIcons.setup_centered_button(
		_cancel_online_host_btn,
		"CANCEL HOSTING",
		"arrow_left",
		18,
		18,
		Color(0.75, 0.80, 0.90),
		Color(1.0, 0.85, 0.2),
		10
	)
	_cancel_online_host_btn.pressed.connect(_on_cancel_host_pressed)
	vbox.add_child(_cancel_online_host_btn)

	# Tournament Live Roster Card
	_tournament_roster_card = PanelContainer.new()
	var tr_sb := StyleBoxFlat.new()
	tr_sb.bg_color = Color(0.04, 0.06, 0.10, 0.90)
	tr_sb.border_color = Color.GOLD
	tr_sb.set_border_width_all(1)
	tr_sb.set_corner_radius_all(8)
	tr_sb.content_margin_left = 16
	tr_sb.content_margin_right = 16
	tr_sb.content_margin_top = 12
	tr_sb.content_margin_bottom = 12
	_tournament_roster_card.add_theme_stylebox_override("panel", tr_sb)
	_tournament_roster_card.visible = false
	vbox.add_child(_tournament_roster_card)

	var tr_vbox := VBoxContainer.new()
	tr_vbox.add_theme_constant_override("separation", 8)
	_tournament_roster_card.add_child(tr_vbox)

	var tr_hdr := HBoxContainer.new()
	tr_vbox.add_child(tr_hdr)

	var tr_title := Label.new()
	tr_title.text = "TOURNAMENT CONTENDERS"
	UIFontStyle.style_title(tr_title, 20)
	tr_title.add_theme_color_override("font_color", Color.GOLD)
	tr_hdr.add_child(tr_title)

	var tr_sp := Control.new()
	tr_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_hdr.add_child(tr_sp)

	_tournament_player_count_label = Label.new()
	_tournament_player_count_label.text = "0 / 8 JOINED"
	UIFontStyle.style_body(_tournament_player_count_label, 14, true)
	_tournament_player_count_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	tr_hdr.add_child(_tournament_player_count_label)

	_tournament_roster_list_vbox = VBoxContainer.new()
	_tournament_roster_list_vbox.add_theme_constant_override("separation", 6)
	tr_vbox.add_child(_tournament_roster_list_vbox)

	_tournament_start_btn = Button.new()
	_tournament_start_btn.custom_minimum_size = Vector2(0, 48)
	_tournament_start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.24, 0.18, 0.06, 0.95)
	tsb.border_color = Color.GOLD
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(6)
	_tournament_start_btn.add_theme_stylebox_override("normal", tsb)
	UIIcons.setup_centered_button(
		_tournament_start_btn,
		"START TOURNAMENT (WAITING FOR PLAYERS)",
		"trophy",
		20,
		18,
		Color.GOLD,
		Color.WHITE,
		10
	)
	_tournament_start_btn.disabled = true
	_tournament_start_btn.pressed.connect(_on_start_tournament_pressed)
	tr_vbox.add_child(_tournament_start_btn)

	return vbox

func _build_direct_join_card() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	vbox.add_child(hdr)

	var key_icon := UIIcons.create_icon_rect("key", 22, Color(0.35, 0.80, 1.0))
	hdr.add_child(key_icon)

	var title := Label.new()
	title.text = "DIRECT ROOM CONNECT"
	UIFontStyle.style_title(title, 28)
	title.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0))
	hdr.add_child(title)

	# Online Direct Input Box
	var online_vbox := VBoxContainer.new()
	online_vbox.name = "OnlineInputContainer"
	online_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(online_vbox)

	var input_lbl := Label.new()
	input_lbl.text = "ENTER 4-LETTER ROOM CODE"
	UIFontStyle.style_body(input_lbl, 14, true)
	input_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	online_vbox.add_child(input_lbl)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	online_vbox.add_child(input_row)

	_online_code_input = LineEdit.new()
	_online_code_input.placeholder_text = "e.g. AX7F"
	_online_code_input.max_length = 4
	_online_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_code_input.custom_minimum_size = Vector2(0, 52)
	_online_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_line_edit(_online_code_input, 28, true)
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(0.04, 0.06, 0.10, 0.70)
	le_style.border_color = Color(0.3, 0.65, 0.95, 0.70)
	le_style.set_border_width_all(1)
	le_style.set_corner_radius_all(8)
	_online_code_input.add_theme_stylebox_override("normal", le_style)
	_online_code_input.text_changed.connect(func(new_text: String):
		_online_code_input.text = new_text.to_upper()
		_online_code_input.caret_column = _online_code_input.text.length()
	)
	_online_code_input.text_submitted.connect(func(_t: String): _on_join_online_pressed())
	input_row.add_child(_online_code_input)

	_join_online_btn = Button.new()
	_join_online_btn.custom_minimum_size = Vector2(140, 52)
	_join_online_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var jb_style := StyleBoxFlat.new()
	jb_style.bg_color = Color(0.10, 0.28, 0.45, 0.85)
	jb_style.border_color = Color(0.35, 0.80, 1.0)
	jb_style.set_border_width_all(1)
	jb_style.set_corner_radius_all(8)
	jb_style.content_margin_left = 16
	jb_style.content_margin_right = 16
	jb_style.content_margin_top = 6
	jb_style.content_margin_bottom = 6
	_join_online_btn.add_theme_stylebox_override("normal", jb_style)
	var jb_hover := jb_style.duplicate() as StyleBoxFlat
	jb_hover.bg_color = Color(0.18, 0.42, 0.65, 0.95)
	jb_hover.shadow_size = 12
	jb_hover.shadow_color = Color(0.35, 0.80, 1.0, 0.4)
	_join_online_btn.add_theme_stylebox_override("hover", jb_hover)
	UIIcons.setup_centered_button(
		_join_online_btn,
		"JOIN",
		"arrow_right",
		18,
		22,
		Color.WHITE,
		Color(1.0, 0.85, 0.2),
		10
	)
	_join_online_btn.pressed.connect(_on_join_online_pressed)
	input_row.add_child(_join_online_btn)

	# LAN Direct Input Box
	var lan_vbox := VBoxContainer.new()
	lan_vbox.name = "LANInputContainer"
	lan_vbox.add_theme_constant_override("separation", 8)
	lan_vbox.visible = false
	vbox.add_child(lan_vbox)

	var lan_lbl := Label.new()
	lan_lbl.text = "HOST IP ADDRESS"
	UIFontStyle.style_body(lan_lbl, 14, true)
	lan_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	lan_vbox.add_child(lan_lbl)

	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 10)
	lan_vbox.add_child(lan_row)

	_lan_ip_input = LineEdit.new()
	_lan_ip_input.text = "127.0.0.1"
	_lan_ip_input.placeholder_text = "e.g. 192.168.1.5"
	_lan_ip_input.custom_minimum_size = Vector2(0, 52)
	_lan_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_ip_input.add_theme_stylebox_override("normal", le_style)
	UIFontStyle.style_line_edit(_lan_ip_input, 17, false)
	lan_row.add_child(_lan_ip_input)

	_join_lan_btn = Button.new()
	_join_lan_btn.custom_minimum_size = Vector2(140, 52)
	_join_lan_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_join_lan_btn.add_theme_stylebox_override("normal", jb_style)
	_join_lan_btn.add_theme_stylebox_override("hover", jb_hover)
	UIIcons.setup_centered_button(
		_join_lan_btn,
		"CONNECT",
		"arrow_right",
		18,
		20,
		Color.WHITE,
		Color(1.0, 0.85, 0.2),
		10
	)
	_join_lan_btn.pressed.connect(_on_join_lan_pressed)
	lan_row.add_child(_join_lan_btn)

	return vbox


func _set_host_mode(mode: String) -> void:
	_host_mode = mode
	var is_tourney := (mode == "tournament")
	if _max_players_stepper:
		_max_players_stepper.visible = is_tourney

	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	active_sb.border_color = Color(1.0, 1.0, 1.0, 0.35)
	active_sb.set_border_width_all(1)
	active_sb.set_corner_radius_all(6)

	var inactive_sb := StyleBoxFlat.new()
	inactive_sb.bg_color = Color(1.0, 1.0, 1.0, 0.03)
	inactive_sb.border_color = Color(1.0, 1.0, 1.0, 0.08)
	inactive_sb.set_border_width_all(1)
	inactive_sb.set_corner_radius_all(6)

	if is_tourney:
		_mode_tourney_btn.add_theme_stylebox_override("normal", active_sb)
		_mode_duel_btn.add_theme_stylebox_override("normal", inactive_sb)
		UIIcons.set_centered_button_color(_mode_tourney_btn, Color.WHITE, Color.WHITE)
		UIIcons.set_centered_button_color(_mode_duel_btn, Color(0.65, 0.70, 0.80), Color(0.7, 0.7, 0.7))
		UIIcons.update_centered_button(_host_online_btn, "HOST ONLINE TOURNAMENT", "crown", 24)
		UIIcons.update_centered_button(_host_lan_btn, "HOST LAN TOURNAMENT (PORT 7777)", "crown", 24)
	else:
		_mode_duel_btn.add_theme_stylebox_override("normal", active_sb)
		_mode_tourney_btn.add_theme_stylebox_override("normal", inactive_sb)
		UIIcons.set_centered_button_color(_mode_duel_btn, Color.WHITE, Color.WHITE)
		UIIcons.set_centered_button_color(_mode_tourney_btn, Color(0.65, 0.70, 0.80), Color(0.7, 0.7, 0.7))
		UIIcons.update_centered_button(_host_online_btn, "HOST ONLINE MATCH", "globe", 24)
		UIIcons.update_centered_button(_host_lan_btn, "HOST LAN MATCH (PORT 7777)", "lan", 24)

func _step_max_players(dir: int) -> void:
	var idx := TOURNAMENT_PLAYER_TIERS.find(_host_max_players)
	if idx == -1: idx = 1
	var next_idx: int = clampi(idx + dir, 0, TOURNAMENT_PLAYER_TIERS.size() - 1)
	_host_max_players = TOURNAMENT_PLAYER_TIERS[next_idx]
	if _max_players_label:
		_max_players_label.text = "MAX BRACKET: %d PLAYERS" % _host_max_players

func _build_room_browser_card() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Browser Header
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(hdr)

	var users_icon := UIIcons.create_icon_rect("users", 24, Color.GOLD)
	hdr.add_child(users_icon)

	var title := Label.new()
	title.text = "OPEN BATTLE LOBBIES"
	UIFontStyle.style_title(title, 28)
	title.add_theme_color_override("font_color", Color.GOLD)
	hdr.add_child(title)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(h_spacer)

	_refresh_btn = Button.new()
	_refresh_btn.custom_minimum_size = Vector2(130, 42)
	_refresh_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_btn.flat = true
	var empty_rf := StyleBoxEmpty.new()
	_refresh_btn.add_theme_stylebox_override("normal", empty_rf)
	_refresh_btn.add_theme_stylebox_override("hover", empty_rf)
	UIIcons.setup_centered_button(
		_refresh_btn,
		"REFRESH",
		"refresh",
		18,
		18,
		Color(0.85, 0.90, 1.0),
		Color(1.0, 0.85, 0.2),
		10
	)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	hdr.add_child(_refresh_btn)

	# Subtitle / Hint
	var sub := Label.new()
	sub.text = "Select an open room to challenge or wait for incoming contenders."
	UIFontStyle.style_body(sub, 15)
	sub.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90, 0.85))
	vbox.add_child(sub)

	# Table Header Bar (Clean, flat divider style)
	var table_hdr := HBoxContainer.new()
	table_hdr.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(table_hdr)

	var col1 := Label.new()
	col1.text = "ROOM / HOST IDENTITY"
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFontStyle.style_subheading(col1, 16)
	col1.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
	table_hdr.add_child(col1)

	var col2 := Label.new()
	col2.text = "STATUS"
	col2.custom_minimum_size = Vector2(120, 0)
	col2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(col2, 16)
	col2.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
	table_hdr.add_child(col2)

	var col3 := Label.new()
	col3.text = "CONNECT"
	col3.custom_minimum_size = Vector2(110, 0)
	col3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(col3, 16)
	col3.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
	table_hdr.add_child(col3)

	# Scroll List Container
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	# Online Rooms VBox
	_online_list_vbox = VBoxContainer.new()
	_online_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_online_list_vbox)

	_online_empty_label = _create_empty_state_view("No open online rooms detected.\nHost a new room or enter a direct room code to connect.")
	_online_list_vbox.add_child(_online_empty_label)

	# LAN Rooms VBox
	_lan_list_vbox = VBoxContainer.new()
	_lan_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_list_vbox.add_theme_constant_override("separation", 8)
	_lan_list_vbox.visible = false
	scroll.add_child(_lan_list_vbox)

	_lan_empty_label = _create_empty_state_view("Scanning local network for active hosts...")
	_lan_list_vbox.add_child(_lan_empty_label)

	return vbox

func _create_empty_state_view(msg: String) -> Control:
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, 220)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var icon := UIIcons.create_icon_rect("globe", 44, Color(0.40, 0.50, 0.65, 0.65))
	vbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(lbl, 15)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	vbox.add_child(lbl)

	return center

# ---------------------------------------------------------------------------
# TAB SWITCHING
# ---------------------------------------------------------------------------

func _switch_tab(tab: String) -> void:
	_active_tab = tab

	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(1.0, 0.85, 0.2, 0.12)
	active_style.border_color = Color.GOLD
	active_style.border_width_bottom = 3
	active_style.content_margin_left = 18
	active_style.content_margin_right = 18

	var inactive_style := StyleBoxEmpty.new()

	var online_input = find_child("OnlineInputContainer", true, false)
	var lan_input = find_child("LANInputContainer", true, false)

	if tab == "online":
		_tab_online_btn.add_theme_stylebox_override("normal", active_style)
		_tab_online_btn.add_theme_stylebox_override("hover", active_style)
		UIIcons.set_centered_button_color(_tab_online_btn, Color.GOLD, Color(1.0, 0.95, 0.4))

		_tab_lan_btn.add_theme_stylebox_override("normal", inactive_style)
		_tab_lan_btn.add_theme_stylebox_override("hover", inactive_style)
		UIIcons.set_centered_button_color(_tab_lan_btn, Color(0.65, 0.70, 0.80), Color(1.0, 0.85, 0.2))

		_host_online_btn.visible = true
		_host_lan_btn.visible = false
		if online_input: online_input.visible = true
		if lan_input: lan_input.visible = false

		_online_list_vbox.visible = true
		_lan_list_vbox.visible = false

		if _nm:
			_nm.stop_lan_scan()
			_nm.start_online_room_fetch()

		_set_status("Online Relay mode: Enter a room code or choose from open lobbies.")
	else:
		_tab_lan_btn.add_theme_stylebox_override("normal", active_style)
		_tab_lan_btn.add_theme_stylebox_override("hover", active_style)
		UIIcons.set_centered_button_color(_tab_lan_btn, Color.GOLD, Color(1.0, 0.95, 0.4))

		_tab_online_btn.add_theme_stylebox_override("normal", inactive_style)
		_tab_online_btn.add_theme_stylebox_override("hover", inactive_style)
		UIIcons.set_centered_button_color(_tab_online_btn, Color(0.65, 0.70, 0.80), Color(1.0, 0.85, 0.2))

		_host_online_btn.visible = false
		_host_lan_btn.visible = true
		if online_input: online_input.visible = false
		if lan_input: lan_input.visible = true

		_online_list_vbox.visible = false
		_lan_list_vbox.visible = true

		if _nm:
			_nm.stop_online_room_fetch()
			_start_lan_scan()

		_set_status("Local LAN mode: Hosts on your local network will appear automatically.")

# ---------------------------------------------------------------------------
# ACTION HANDLERS — HOST & JOIN
# ---------------------------------------------------------------------------

func _on_host_online_pressed() -> void:
	if not _nm:
		_set_status("NetworkManager not found!", Color.RED)
		return
	_nm.stop_online_room_fetch()
	_set_buttons_disabled(true)
	_set_status("Connecting to global relay server...", Color.YELLOW, true)
	_is_hosting = true
	_host_online_btn.visible = false
	_cancel_online_host_btn.visible = true
	_online_code_display_box.visible = true
	_room_code_large_label.text = "GENERATING..."
	var mode_enum = _nm.MatchMode.TOURNAMENT if _host_mode == "tournament" else _nm.MatchMode.DUEL_1V1
	_nm.host_online_match(mode_enum, _host_max_players)
	if _host_mode == "tournament":
		_tournament_roster_card.visible = true
		var my_rooster := GameManager.selected_player_rooster.rooster_id if GameManager.selected_player_rooster else "hen_goku"
		var host_name: String = AuthManager.username if (AuthManager and AuthManager.is_logged_in) else "Host"
		_nm.register_local_tournament_player(host_name, my_rooster)

func _on_room_code_received(code: String) -> void:
	_stop_spinner()
	if is_instance_valid(_room_code_large_label):
		_room_code_large_label.text = code
	_set_status("Room ready! Share code [%s] with your challenger." % code, Color.GOLD, true)
	_status_network_label.text = "HOSTING: %s" % code
	_status_dot.modulate = Color.GOLD

func _on_host_lan_pressed() -> void:
	if not _nm:
		_set_status("NetworkManager not found!", Color.RED)
		return
	_nm.stop_lan_scan()
	_set_buttons_disabled(true)
	_set_status("Starting LAN host server...", Color.YELLOW, true)
	var mode_enum = _nm.MatchMode.TOURNAMENT if _host_mode == "tournament" else _nm.MatchMode.DUEL_1V1
	var err: int = _nm.host_match(NetworkManager.DEFAULT_PORT, mode_enum, _host_max_players)
	if _host_mode == "tournament":
		_tournament_roster_card.visible = true
		var my_rooster := GameManager.selected_player_rooster.rooster_id if GameManager.selected_player_rooster else "hen_goku"
		var host_name: String = AuthManager.username if (AuthManager and AuthManager.is_logged_in) else "Host"
		_nm.register_local_tournament_player(host_name, my_rooster)
	if err != OK:
		_set_status("Failed to create server on port %d (port may be in use)." % NetworkManager.DEFAULT_PORT, Color.RED)
		_set_buttons_disabled(false)
		return
	_is_hosting = true
	_host_lan_btn.visible = false
	_cancel_online_host_btn.visible = true
	_online_code_display_box.visible = true
	_room_code_large_label.text = "PORT %d" % NetworkManager.DEFAULT_PORT
	_set_status("Waiting for opponent on local port %d..." % NetworkManager.DEFAULT_PORT, Color.GOLD, true)
	_status_network_label.text = "LAN: HOSTING"
	_status_dot.modulate = Color.GOLD

func _on_cancel_host_pressed() -> void:
	_stop_spinner()
	_is_hosting = false
	if _nm:
		_nm.disconnect_from_match()
	_host_online_btn.visible = (_active_tab == "online")
	_host_lan_btn.visible = (_active_tab == "lan")
	_cancel_online_host_btn.visible = false
	_online_code_display_box.visible = false
	if _tournament_roster_card:
		_tournament_roster_card.visible = false
	_set_buttons_disabled(false)
	_set_status("Hosting cancelled. Ready to join or host.")
	_status_network_label.text = "NETWORK READY"
	_status_dot.modulate = Color(0.2, 0.85, 0.4)

func _on_join_online_pressed() -> void:
	if not _nm:
		_set_status("NetworkManager not found!", Color.RED)
		return
	var code := ""
	if _online_code_input and not _online_code_input.text.strip_edges().is_empty():
		code = _online_code_input.text.strip_edges().to_upper()
	elif not _selected_online_code.is_empty():
		code = _selected_online_code

	if code.is_empty():
		_set_status("Please enter a 4-letter room code to connect.", Color.YELLOW)
		return

	_set_buttons_disabled(true)
	_set_status("Connecting to room [%s] via Global Relay..." % code, Color.YELLOW, true)
	var r_mode: String = _known_room_modes.get(code, "duel")
	if r_mode == "tournament":
		_nm.current_match_mode = _nm.MatchMode.TOURNAMENT
		_tournament_roster_card.visible = true
		UIIcons.update_centered_button(_tournament_start_btn, "WAITING FOR HOST TO START...", "trophy", 18)
		_tournament_start_btn.disabled = true
	_nm.join_online_match(code)

func _on_join_lan_pressed() -> void:
	if not _nm:
		_set_status("NetworkManager not found!", Color.RED)
		return
	var ip := "127.0.0.1"
	if _lan_ip_input and not _lan_ip_input.text.strip_edges().is_empty():
		ip = _lan_ip_input.text.strip_edges()
	elif not _selected_lan_ip.is_empty():
		ip = _selected_lan_ip

	_set_buttons_disabled(true)
	_set_status("Connecting to LAN host %s..." % ip, Color.YELLOW, true)
	var err: int = _nm.join_match(ip)
	if err != OK:
		_set_status("Could not initialize connection to %s." % ip, Color.RED)
		_set_buttons_disabled(false)

func _on_refresh_pressed() -> void:
	if _active_tab == "online":
		if _nm:
			_set_status("Refreshing online lobbies...", Color.CYAN)
			_nm.start_online_room_fetch()
	else:
		_start_lan_scan()

func _start_lan_scan() -> void:
	if not _nm or _is_hosting: return
	_set_status("Scanning for local hosts on your network...", Color.CYAN, true)
	_nm.start_lan_scan()

# ---------------------------------------------------------------------------
# ROOM BROWSER LIST UPDATERS
# ---------------------------------------------------------------------------

func _on_online_rooms_updated(rooms: Array) -> void:
	for c in _online_list_vbox.get_children():
		c.queue_free()

	if rooms.is_empty():
		_online_empty_label = _create_empty_state_view("No open online rooms detected.\nHost a new room or enter a direct room code to connect.")
		_online_list_vbox.add_child(_online_empty_label)
		return

	for r in rooms:
		var code: String = r.get("code", "")
		var host_name: String = r.get("host", "Challenger")
		var mode: String = r.get("mode", "duel")
		var cur_p: int = r.get("current_players", 1)
		var max_p: int = r.get("max_players", 2)
		var status: String = r.get("status", "OPEN")
		var can_spectate: bool = r.get("can_spectate", true)
		var specs: int = r.get("spectators_count", 0)
		_known_room_modes[code] = mode

		var is_live: bool = (status == "IN_PROGRESS" or cur_p >= max_p)
		var m_odds: float = float(r.get("meron_odds", 1.95))
		var w_odds: float = float(r.get("wala_odds", 1.95))
		var mode_desc := "ONLINE RELAY • 1V1 DUEL" if mode == "duel" else "ONLINE RELAY • TOURNAMENT (%d/%d)" % [cur_p, max_p]
		if specs > 0:
			mode_desc += " • %d Spectating" % specs
		mode_desc += " • [%.2fx vs %.2fx]" % [m_odds, w_odds]

		if is_live and can_spectate:
			var row := _create_room_card(code, host_name, mode_desc, func():
				_on_spectate_room(r)
			, "[ LIVE MATCH ]", Color(0.3, 0.85, 1.0), "SPECTATE", "eye")
			_online_list_vbox.add_child(row)
		else:
			var row := _create_room_card(code, host_name, mode_desc, func():
				_selected_online_code = code
				if _online_code_input:
					_online_code_input.text = code
				_on_join_online_pressed()
			, "[ OPEN ]", Color(0.3, 1.0, 0.5), "JOIN", "arrow_right")
			_online_list_vbox.add_child(row)

func _on_spectate_room(room_data: Dictionary) -> void:
	var code: String = room_data.get("code", "")
	GameManager.is_spectator = true
	GameManager.is_online_match = true
	if BettingManager:
		BettingManager.reset_match_betting(code)
		var m_pool = int(room_data.get("meron_pool", 0))
		var w_pool = int(room_data.get("wala_pool", 0))
		var m_odds = float(room_data.get("meron_odds", 1.95))
		var w_odds = float(room_data.get("wala_odds", 1.95))
		BettingManager.update_pool_from_server(m_pool, w_pool, m_odds, w_odds)

	# Set up roosters if reported
	var m_id: String = room_data.get("meron_rooster", "")
	var w_id: String = room_data.get("wala_rooster", "")
	if not m_id.is_empty():
		var r1 = GameManager.get_rooster_by_id(m_id)
		if r1: GameManager.selected_player_rooster = r1
	if not w_id.is_empty():
		var r2 = GameManager.get_rooster_by_id(w_id)
		if r2: GameManager.selected_opponent_rooster = r2

	_set_status("Entering arena as live spectator...", Color.CYAN)
	if _nm and _nm.has_method("spectate_online"):
		_nm.spectate_online(code)
	await get_tree().create_timer(0.4).timeout
	GameManager.change_scene("res://scenes/arena.tscn")

func _on_host_discovered(host_info: Dictionary) -> void:
	if _lan_empty_label and is_instance_valid(_lan_empty_label):
		_lan_empty_label.queue_free()

	var ip: String = host_info.get("ip", "")
	var host_name: String = host_info.get("name", "Local Host")
	var row := _create_room_card(ip, host_name, "LOCAL LAN", func():
		_selected_lan_ip = ip
		if _lan_ip_input:
			_lan_ip_input.text = ip
		_on_join_lan_pressed()
	)
	_lan_list_vbox.add_child(row)

func _on_hosts_cleared() -> void:
	for c in _lan_list_vbox.get_children():
		c.queue_free()
	_lan_empty_label = _create_empty_state_view("Scanning local network for active hosts...")
	_lan_list_vbox.add_child(_lan_empty_label)

func _create_room_card(key: String, title_text: String, subtitle_text: String, on_action: Callable, status_str: String = "[ OPEN ]", status_col: Color = Color(0.3, 1.0, 0.5), action_text: String = "JOIN", action_icon: String = "arrow_right") -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 56)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(1.0, 1.0, 1.0, 0.04) # Soft transparent glass row
	ps.set_border_width_all(0) # No box borders!
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 16
	ps.content_margin_right = 16
	row.add_theme_stylebox_override("panel", ps)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	# Left: Room Identity
	var id_box := VBoxContainer.new()
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.add_theme_constant_override("separation", 2)
	id_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(id_box)

	var name_lbl := Label.new()
	name_lbl.text = "%s  [%s]" % [title_text.to_upper(), key.to_upper()]
	UIFontStyle.style_title(name_lbl, 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	id_box.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle_text
	UIFontStyle.style_body(sub_lbl, 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	id_box.add_child(sub_lbl)

	# Center: Status Text
	var p_lbl := Label.new()
	p_lbl.text = status_str
	p_lbl.custom_minimum_size = Vector2(130, 0)
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(p_lbl, 18)
	p_lbl.add_theme_color_override("font_color", status_col)
	hbox.add_child(p_lbl)

	# Right: Action Button
	var act_btn := Button.new()
	act_btn.custom_minimum_size = Vector2(120, 40)
	act_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	act_btn.flat = true
	var empty_jb := StyleBoxEmpty.new()
	act_btn.add_theme_stylebox_override("normal", empty_jb)
	act_btn.add_theme_stylebox_override("hover", empty_jb)
	UIIcons.setup_centered_button(
		act_btn,
		action_text,
		action_icon,
		16,
		18,
		Color.WHITE,
		Color(1.0, 0.85, 0.2),
		8
	)
	act_btn.pressed.connect(on_action)
	hbox.add_child(act_btn)

	return row

# ---------------------------------------------------------------------------
# NETWORK SIGNALS & TRANSITION FLOW
# ---------------------------------------------------------------------------

func _on_player_connected(_peer_id: int) -> void:
	_stop_spinner()
	_status_network_label.text = "CONNECTED"
	_status_dot.modulate = Color(0.2, 1.0, 0.4)

	if _nm and _nm.current_match_mode == _nm.MatchMode.TOURNAMENT:
		_tournament_roster_card.visible = true
		if not _nm.is_host:
			var my_rooster := GameManager.selected_player_rooster.rooster_id if GameManager.selected_player_rooster else "rooster_vegeta"
			var cont_name: String = AuthManager.username if (AuthManager and AuthManager.is_logged_in) else ("Contender %d" % _nm.local_peer_id)
			_nm.register_local_tournament_player(cont_name, my_rooster)
		_set_status("Contender connected to tournament lobby!", Color(0.3, 1.0, 0.5))
		return

	_set_status("Challenger connected! Proceeding to character select...", Color(0.3, 1.0, 0.5))
	await get_tree().create_timer(0.6).timeout
	lobby_finished.emit()

func _on_player_disconnected(_peer_id: int) -> void:
	_stop_spinner()
	_set_status("Player disconnected from room.", Color.RED)
	_status_network_label.text = "DISCONNECTED"
	_status_dot.modulate = Color.RED
	_set_buttons_disabled(false)

func _on_server_disconnected() -> void:
	_stop_spinner()
	_set_status("Disconnected from match server.", Color.RED)
	_status_network_label.text = "OFFLINE"
	_status_dot.modulate = Color.RED
	_set_buttons_disabled(false)

func _on_match_ready(_p1_rooster_id: String, _p2_rooster_id: String) -> void:
	_stop_spinner()
	lobby_finished.emit()

func _on_forfeit() -> void:
	_stop_spinner()
	_set_status("Opponent forfeited or left.", Color.YELLOW)
	_set_buttons_disabled(false)

func _on_online_connection_failed(reason: String) -> void:
	_stop_spinner()
	_set_status("Connection failed: %s" % reason, Color.RED)
	_status_network_label.text = "ERROR"
	_status_dot.modulate = Color.RED
	_set_buttons_disabled(false)

func _on_back_pressed() -> void:
	_stop_spinner()
	if _nm:
		_nm.stop_lan_scan()
		_nm.stop_online_room_fetch()
		_nm.disconnect_from_match()
	queue_free()

# ---------------------------------------------------------------------------
# STATUS & SPINNER HELPERS
# ---------------------------------------------------------------------------

func _set_status(text: String, col: Color = Color.CYAN, show_spinner: bool = false) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", col)
	if _spinner_holder:
		_spinner_holder.visible = show_spinner

func _stop_spinner() -> void:
	if _spinner_holder:
		_spinner_holder.visible = false

func _set_buttons_disabled(d: bool) -> void:
	for btn in [_host_online_btn, _host_lan_btn, _join_online_btn, _join_lan_btn, _refresh_btn]:
		if btn:
			btn.disabled = d
			var content := btn.get_node_or_null("CenteredButtonContent") as Control
			if content:
				content.modulate = Color(0.5, 0.5, 0.5, 0.6) if d else Color.WHITE


func _on_tournament_roster_updated(roster: Dictionary) -> void:
	if _tournament_roster_card:
		_tournament_roster_card.visible = true
	if _tournament_roster_list_vbox:
		for c in _tournament_roster_list_vbox.get_children():
			c.queue_free()

	var count: int = roster.size()
	var max_p: int = _nm.max_tournament_players if _nm else 8
	if _tournament_player_count_label:
		_tournament_player_count_label.text = "%d / %d JOINED" % [count, max_p]

	for pid in roster:
		var pdata: Dictionary = roster[pid]
		var pname: String = pdata.get("name", "Player %d" % pid)
		var r_id: String = pdata.get("rooster_id", "hen_goku")
		var r_data = GameManager.get_rooster_by_id(r_id)
		var r_name: String = r_data.display_name if r_data else r_id.to_upper()

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var icon := UIIcons.create_icon_rect("crown" if pid == 1 else "user", 16, Color.GOLD if pid == 1 else Color(0.7, 0.8, 1.0))
		row.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [pname, r_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFontStyle.style_body(name_lbl, 14, pid == 1)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(name_lbl)

		var rdy_lbl := Label.new()
		rdy_lbl.text = "[ READY ]"
		UIFontStyle.style_body(rdy_lbl, 13, true)
		rdy_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		row.add_child(rdy_lbl)

		if _tournament_roster_list_vbox:
			_tournament_roster_list_vbox.add_child(row)

	if _tournament_start_btn:
		if _nm and _nm.is_host:
			if count >= 2:
				_tournament_start_btn.disabled = false
				UIIcons.update_centered_button(_tournament_start_btn, "START TOURNAMENT (%d PLAYERS)" % count, "swords", 20)
			else:
				_tournament_start_btn.disabled = true
				UIIcons.update_centered_button(_tournament_start_btn, "WAITING FOR MORE PLAYERS (MIN 2)", "crown", 20)
		else:
			_tournament_start_btn.disabled = true
			UIIcons.update_centered_button(_tournament_start_btn, "WAITING FOR HOST TO START...", "spinner", 20)

func _on_start_tournament_pressed() -> void:
	if not _nm or not _nm.is_host:
		return
	var roster_dict: Dictionary = _nm.tournament_roster
	if roster_dict.size() < 2:
		_set_status("Need at least 2 contenders to begin tournament!", Color.YELLOW)
		return

	_set_status("Building tournament bracket with %d players..." % roster_dict.size(), Color.GOLD, true)
	var participants: Array[Dictionary] = []
	for pid in roster_dict:
		var pdata: Dictionary = roster_dict[pid]
		participants.append({
			"peer_id": pdata.get("peer_id", pid),
			"name": pdata.get("name", "Fighter %d" % pid),
			"rooster_id": pdata.get("rooster_id", "hen_goku")
		})

	TournamentManager.build_dynamic_online_tournament(participants, TournamentManager.Format.SINGLE_ELIMINATION)
	var bracket_data := TournamentManager.serialize_bracket()
	_nm.broadcast_start_tournament(bracket_data)
	await get_tree().create_timer(0.4).timeout
	lobby_finished.emit()

func _on_tournament_bracket_received(_bracket_data: Dictionary) -> void:
	_stop_spinner()
	_set_status("Tournament started! Loading championship bracket...", Color(0.3, 1.0, 0.5))
	await get_tree().create_timer(0.4).timeout
	lobby_finished.emit()
