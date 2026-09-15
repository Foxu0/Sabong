extends Control
class_name MatchUI

## MatchUI — Full Sabong Cockpit UI with UNO fanned hand, animated HP bars, 3D dice rolls, and combat sequencing.

const UNIVERSAL_CARD_PATHS: Array[String] = [
	"res://resources/cards/claw_slash.tres",
	"res://resources/cards/t_claw_slash.tres",
	"res://resources/cards/feather_block.tres",
	"res://resources/cards/feather_flock.tres",
	"res://resources/cards/nugget.tres",
	"res://resources/cards/fried_chicken.tres",
	"res://resources/cards/poop_burst.tres",
	"res://resources/cards/chickn_turd.tres",
]

@export var arena_controller: ArenaController

var universal_cards: Array[CardData] = []
var player: Duelist
var opponent: Duelist
var turn_number: int = 1
var is_resolving_turn: bool = false
var match_over: bool = false
var is_vs_ai: bool = true

# Duel Phase Manager & Screen-Centered Phase Notification
var phase_manager: DuelPhaseManager = null
var phase_panel: Control = null
var phase_backdrop: ColorRect = null
var phase_center_box: VBoxContainer = null
var round_badge_label: Label = null
var phase_title_label: Label = null
var phase_sub_label: Label = null
var btn_phase_action: Button = null
var priority_pop_label: Label = null

# UI Nodes
var log_label: RichTextLabel
var rooster_select_ui: RoosterSelectUI
var _game_over_modal: Control = null
var spectator_betting_panel: Control = null
var spectator_bet_ticket_lbl: Label = null
var spectator_taya_bal_lbl: Label = null
var selected_bet_chip: int = 50
var _chip_buttons: Array[Button] = []
var _meron_bet_btn: Button = null
var _wala_bet_btn: Button = null

# Live Spectator Arena HUD & Dynamic Odds
var _live_odds_bar: PanelContainer = null
var _live_spectator_lbl: Label = null
var _live_meron_odds_lbl: Label = null
var _live_wala_odds_lbl: Label = null
var _live_pool_progress: ProgressBar = null
var _live_pool_text_lbl: Label = null

func _ready() -> void:
	for path in UNIVERSAL_CARD_PATHS:
		if ResourceLoader.exists(path):
			var c: CardData = load(path)
			universal_cards.append(c)

	_build_cockpit_ui()

	if GameManager and (GameManager.is_spectator or GameManager.is_online_match):
		_build_live_odds_bar()

	if GameManager and GameManager.is_spectator:
		_build_spectator_betting_ui()

	if BettingManager:
		if not BettingManager.odds_updated.is_connected(_on_odds_updated):
			BettingManager.odds_updated.connect(_on_odds_updated)
		if not BettingManager.pool_updated.is_connected(_on_pool_updated):
			BettingManager.pool_updated.connect(_on_pool_updated)
		if not BettingManager.spectator_count_changed.is_connected(_on_spectator_count_changed):
			BettingManager.spectator_count_changed.connect(_on_spectator_count_changed)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		if nm.has_signal("bet_pool_updated") and not nm.bet_pool_updated.is_connected(_on_network_bet_pool_updated):
			nm.bet_pool_updated.connect(_on_network_bet_pool_updated)
		if nm.has_signal("spectator_count_updated") and not nm.spectator_count_updated.is_connected(_on_spectator_count_changed):
			nm.spectator_count_updated.connect(_on_spectator_count_changed)
		if nm.has_signal("match_finished_received") and not nm.match_finished_received.is_connected(_on_network_match_finished):
			nm.match_finished_received.connect(_on_network_match_finished)
	
	await get_tree().process_frame

	if not arena_controller:
		arena_controller = get_node_or_null("../..") as ArenaController
		if not arena_controller:
			arena_controller = get_tree().root.find_child("Arena", true, false) as ArenaController

	_connect_phase_manager()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.get("selected_player_rooster"):
		var p1: RoosterData = gm.get("selected_player_rooster")
		var p2: RoosterData = gm.get("selected_opponent_rooster")
		if not p2:
			p2 = gm.get_random_opponent(p1)
		_on_battle_started(p1, p2, true)
	else:
		_open_character_selection()

func _open_character_selection() -> void:
	rooster_select_ui = RoosterSelectUI.new()
	add_child(rooster_select_ui)
	rooster_select_ui.battle_started.connect(_on_battle_started)

func _connect_phase_manager() -> void:
	if not phase_manager and arena_controller:
		phase_manager = arena_controller.phase_manager
	if not phase_manager:
		phase_manager = get_tree().root.find_child("DuelPhaseManager", true, false) as DuelPhaseManager
	if not phase_manager:
		return

	if not phase_manager.phase_changed.is_connected(_on_phase_changed):
		phase_manager.phase_changed.connect(_on_phase_changed)
		phase_manager.round_started.connect(_on_round_started)
		phase_manager.round_ended.connect(_on_round_ended)
		phase_manager.dice_rolled.connect(_on_dice_rolled)
		phase_manager.priority_determined.connect(_on_priority_determined)
		phase_manager.discard_required.connect(_on_discard_required)
		phase_manager.cards_drawn.connect(_on_cards_drawn)
		phase_manager.duel_finished.connect(_on_duel_finished)
		phase_manager.card_rerolled.connect(_on_card_rerolled)
		phase_manager.roll_manipulated.connect(_on_roll_manipulated)
		phase_manager.combat_resolved.connect(_on_combat_resolved)
		phase_manager.auto_discarded.connect(_on_auto_discarded)

func _on_battle_started(p1_rooster: RoosterData, p2_rooster: RoosterData, vs_ai: bool) -> void:
	is_vs_ai = vs_ai
	player = Duelist.new(1, "MERON (You)", p1_rooster)
	opponent = Duelist.new(2, "WALA (CPU)", p2_rooster)

	player.setup_deck(universal_cards)
	opponent.setup_deck(universal_cards)

	if arena_controller:
		arena_controller.setup_match(p1_rooster, p2_rooster, 1)

	turn_number = 1
	match_over = false
	is_resolving_turn = false

	_connect_phase_manager()

	_log("[b][color=gold]SABONG DUEL COMMENCED![/color][/b]")
	_log("[color=red]%s[/color] vs [color=cyan]%s[/color]" % [player.display_name, opponent.display_name])

	# Arena Phase Notification for Match Start in ARENA_VIEW
	var p1_name: String = p1_rooster.display_name if p1_rooster else "MERON"
	var p2_name: String = p2_rooster.display_name if p2_rooster else "WALA"
	_show_phase_notification("MATCH START", "%s VS %s" % [p1_name, p2_name], Color.GOLD, false, 0.55)

	# Hold camera looking up at the arena so players can appreciate the arena phase banner & roosters
	if is_inside_tree():
		await get_tree().create_timer(2.2).timeout

	if phase_manager:
		phase_manager.start_duel(player, opponent, vs_ai, arena_controller)
	else:
		# Fallback legacy initialization
		player.draw_cards_up_to_max(6)
		opponent.draw_cards_up_to_max(6)
		player.roll_dice()
		opponent.roll_dice()
		_trigger_dice_roll_animation()
		_refresh_all_ui(true)

func _trigger_dice_roll_animation() -> void:
	if arena_controller and player.rooster_data and opponent.rooster_data:
		DiceRoller3D.roll_duel_dice(
			arena_controller,
			player.rooster_data.dice_model_path,
			opponent.rooster_data.dice_model_path,
			player.current_dice_roll,
			opponent.current_dice_roll
		)

# ---------------------------------------------------------------------------
# UI Construction & Styling
# ---------------------------------------------------------------------------

func _build_cockpit_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Top-left Menu button
	var btn_menu := Button.new()
	btn_menu.text = "≡ MENU"
	btn_menu.position = Vector2(28, 22)
	btn_menu.custom_minimum_size = Vector2(130, 46)
	UIFontStyle.style_button(btn_menu, 18)
	var m_style := StyleBoxFlat.new()
	m_style.bg_color = Color(0.08, 0.1, 0.15, 0.85)
	m_style.border_color = Color.GOLD
	m_style.set_border_width_all(1)
	m_style.set_corner_radius_all(8)
	btn_menu.add_theme_stylebox_override("normal", m_style)
	btn_menu.pressed.connect(_on_pause_menu_pressed)
	add_child(btn_menu)

	# --- Bottom HUD: fully transparent, cards + taya dots + End Turn only ---
	var bottom_panel: PanelContainer = PanelContainer.new()
	bottom_panel.anchor_left = 0.0
	bottom_panel.anchor_right = 1.0
	bottom_panel.anchor_top = 1.0
	bottom_panel.anchor_bottom = 1.0
	bottom_panel.offset_left = 0
	bottom_panel.offset_top = -330
	bottom_panel.offset_right = 0
	bottom_panel.offset_bottom = 0
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fully transparent — no background panel
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	bot_style.content_margin_left = 20
	bot_style.content_margin_right = 20
	bot_style.content_margin_top = 8
	bot_style.content_margin_bottom = 8
	bottom_panel.add_theme_stylebox_override("panel", bot_style)
	add_child(bottom_panel)

	# log_label kept as hidden buffer so _log() doesn't crash
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.visible = false
	bottom_panel.add_child(log_label)

	_build_phase_hud()

func _build_phase_hud() -> void:
	phase_panel = Control.new()
	phase_panel.name = "PhaseScreenNotification"
	phase_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(phase_panel)

	# 1. Full-screen backdrop (hidden — 3D stadium banner handles visuals)
	phase_backdrop = ColorRect.new()
	phase_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_backdrop.color = Color(0.01, 0.02, 0.04, 0.0)
	phase_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_backdrop.visible = false
	phase_panel.add_child(phase_backdrop)

	# 2. Hidden 2D labels (kept in memory so script references & tests continue to function, screen center stays clear)
	phase_center_box = VBoxContainer.new()
	phase_center_box.name = "PhaseCenterBox"
	phase_center_box.visible = false
	phase_panel.add_child(phase_center_box)

	round_badge_label = Label.new()
	round_badge_label.text = "--- ROUND 1 ---"
	phase_center_box.add_child(round_badge_label)

	phase_title_label = Label.new()
	phase_title_label.text = "DICE ROLL"
	phase_center_box.add_child(phase_title_label)

	phase_sub_label = Label.new()
	phase_sub_label.text = "Rolling 3D Cockpit Dice..."
	phase_center_box.add_child(phase_sub_label)



	# 4. Subtle notice badge in bottom-right corner reminding player to ring the table bell to confirm / end turn
	btn_phase_action = Button.new()
	btn_phase_action.name = "PhaseActionNotice"
	btn_phase_action.text = "RING THE BELL TO CONFIRM / END TURN"
	btn_phase_action.anchor_left = 1.0
	btn_phase_action.anchor_right = 1.0
	btn_phase_action.anchor_top = 1.0
	btn_phase_action.anchor_bottom = 1.0
	btn_phase_action.offset_left = -380
	btn_phase_action.offset_top = -68
	btn_phase_action.offset_right = -30
	btn_phase_action.offset_bottom = -28
	var act_style := StyleBoxFlat.new()
	act_style.bg_color = Color(0.04, 0.06, 0.10, 0.50) # Subtle dark translucent glass
	act_style.border_color = Color(1.0, 1.0, 1.0, 0.35) # Clean subtle white accent
	act_style.set_border_width_all(1)
	act_style.set_corner_radius_all(10)
	act_style.shadow_size = 6
	act_style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	btn_phase_action.add_theme_stylebox_override("normal", act_style)
	var act_hov := act_style.duplicate() as StyleBoxFlat
	act_hov.bg_color = Color(0.08, 0.12, 0.18, 0.75)
	act_hov.border_color = Color(1.0, 1.0, 1.0, 0.75)
	btn_phase_action.add_theme_stylebox_override("hover", act_hov)
	btn_phase_action.add_theme_stylebox_override("pressed", act_hov)
	UIFontStyle.style_anton(btn_phase_action, 18)
	btn_phase_action.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 0.85))
	btn_phase_action.add_theme_color_override("font_hover_color", Color.GOLD)
	btn_phase_action.pressed.connect(_on_phase_action_pressed)
	btn_phase_action.visible = false
	phase_panel.add_child(btn_phase_action)

	# 5. Screen Pop Announcement for Turn Priority Result ("YOU FIRST" / "YOU LAST")
	priority_pop_label = Label.new()
	priority_pop_label.name = "PriorityPopLabel"
	priority_pop_label.text = "YOU FIRST"
	priority_pop_label.anchor_left = 0.5
	priority_pop_label.anchor_right = 0.5
	priority_pop_label.anchor_top = 0.5
	priority_pop_label.anchor_bottom = 0.5
	priority_pop_label.offset_left = -450
	priority_pop_label.offset_right = 450
	priority_pop_label.offset_top = -140
	priority_pop_label.offset_bottom = 140
	priority_pop_label.pivot_offset = Vector2(450, 140)
	priority_pop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	priority_pop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIFontStyle.style_anton(priority_pop_label, 120)
	priority_pop_label.add_theme_constant_override("outline_size", 22)
	priority_pop_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.98))
	priority_pop_label.add_theme_constant_override("shadow_offset_x", 6)
	priority_pop_label.add_theme_constant_override("shadow_offset_y", 6)
	priority_pop_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	priority_pop_label.visible = false
	phase_panel.add_child(priority_pop_label)

func _show_phase_notification(title_text: String, sub_text: String, _title_color: Color = Color.WHITE, _is_action_visible: bool = false, _dim_alpha: float = 0.55) -> void:
	if round_badge_label:
		round_badge_label.text = ("--- ROUND %d ---" % turn_number).to_upper()

	if phase_title_label:
		phase_title_label.text = title_text.to_upper()
		phase_title_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))

	if phase_sub_label:
		phase_sub_label.text = sub_text.to_upper()

	if btn_phase_action:
		btn_phase_action.visible = false
		btn_phase_action.disabled = false

	# Update 3D stadium text in the arena
	if arena_controller and arena_controller.has_method("update_3d_phase_banner"):
		arena_controller.update_3d_phase_banner(title_text.to_upper(), sub_text.to_upper(), Color(0.96, 0.96, 0.98), turn_number)

func _show_priority_result_pop(pop_text: String, _pop_color: Color = Color.WHITE) -> void:
	if not is_instance_valid(priority_pop_label):
		return
	priority_pop_label.text = pop_text.to_upper()
	priority_pop_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98)) # Clean white only — strictly never colored!
	priority_pop_label.scale = Vector2(0.2, 0.2)
	priority_pop_label.modulate.a = 0.0
	priority_pop_label.visible = true

	var tw: Tween = create_tween()
	if tw:
		# Rapid punchy pop-in to camera
		tw.set_parallel(true)
		tw.tween_property(priority_pop_label, "scale", Vector2(1.15, 1.15), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(priority_pop_label, "modulate:a", 1.0, 0.15)
		
		# Settle to standard scale
		tw.chain().tween_property(priority_pop_label, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
		
		# Hold for ~1.0s
		tw.tween_interval(1.0)
		
		# Fade away with subtle expansion
		tw.chain().set_parallel(true)
		tw.tween_property(priority_pop_label, "modulate:a", 0.0, 0.45)
		tw.tween_property(priority_pop_label, "scale", Vector2(1.25, 1.25), 0.45)
		
		# Hide when finished
		tw.chain().tween_callback(func():
			if is_instance_valid(priority_pop_label):
				priority_pop_label.visible = false
		)

func _process(_delta: float) -> void:
	if not phase_manager:
		return

	var current_phase: DuelPhase.Phase = phase_manager.current_phase
	var is_fighting_or_end: bool = (current_phase == DuelPhase.Phase.FIGHTING or current_phase == DuelPhase.Phase.ROUND_END)
	var time_left: float = phase_manager.get_time_remaining("MERON")

	if is_fighting_or_end:
		# In Fighting / Round End, the 3D clock screens display HP
		if arena_controller and arena_controller.has_method("update_hp_clocks") and player and opponent:
			arena_controller.update_hp_clocks(player.hp, opponent.hp)
	else:
		# In other phases (DICE_ROLL, DISCARD, DRAW, REROLL), the 3D clock screens display the countdown timer!
		if time_left > 0.0:
			var mins: int = int(ceil(time_left) / 60.0)
			var secs: int = int(ceil(time_left)) % 60
			var time_str: String = "%02d : %02d" % [mins, secs]
			var glow_col: Color = Color(3.5, 0.15, 0.15, 1.0) if time_left <= 10.0 else Color(2.5, 0.25, 0.25, 1.0)
			if arena_controller and arena_controller.has_method("update_table_clock_display"):
				arena_controller.update_table_clock_display(time_str, glow_col)
		else:
			if arena_controller and arena_controller.has_method("update_table_clock_display"):
				arena_controller.update_table_clock_display("-- : --", Color(1.2, 0.2, 0.2, 0.6))



# ---------------------------------------------------------------------------
# Phase System Callbacks & Signals
# ---------------------------------------------------------------------------

func _on_phase_changed(new_phase: DuelPhase.Phase) -> void:
	if not phase_title_label:
		return

	_cancel_taya_priming()
	# Clear previous table notice to ensure no leftover text from past phases
	if arena_controller and arena_controller.has_method("update_table_notice"):
		arena_controller.update_table_notice("", false)

	match new_phase:
		DuelPhase.Phase.DICE_ROLL:
			_show_phase_notification("DICE ROLL", "ROLLING TABLE DICE...", Color(0.96, 0.96, 0.98), false, 0.55)
			_refresh_all_ui(false)
			# Transition to TABLE_VIEW so player watches both roosters' dice roll onto the table!
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.35)

		DuelPhase.Phase.DISCARD:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.45)
			var needed: int = 0
			if phase_manager and phase_manager.meron_state:
				needed = mini(phase_manager.meron_state.discard_count, player.hand.size())
			var dice_res: int = phase_manager.meron_state.dice_result if (phase_manager and phase_manager.meron_state) else 0
			_show_phase_notification("DISCARD PHASE", "DISCARD %d CARD%s BASED ON YOUR DICE ROLL (%d)." % [needed, "S" if needed != 1 else "", dice_res], Color(0.96, 0.96, 0.98), true, 0.35)
			_update_discard_visuals()
			_refresh_all_ui(false)

		DuelPhase.Phase.DRAW:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.45)
			var target: int = 6 # Always 6 cards on start of round and every round
			_show_phase_notification("DRAW PHASE", "DRAWING CARDS UP TO %d..." % target, Color(0.96, 0.96, 0.98), false, 0.50)
			_refresh_all_ui(false)

		DuelPhase.Phase.REROLL:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.45)
			var remaining: int = DuelPhaseManager.FREE_REROLLS_PER_ROUND
			if phase_manager and phase_manager.meron_state:
				remaining -= phase_manager.meron_state.free_rerolls_used
			_show_phase_notification("CARD REROLL", "CLICK A CARD IN HAND TO REROLL IT FROM DECK (%d FREE REROLL%s LEFT)" % [remaining, "S" if remaining != 1 else ""], Color(0.96, 0.96, 0.98), true, 0.35)
			if arena_controller and arena_controller.has_method("update_table_notice"):
				arena_controller.update_table_notice("RING BELL\nTO FINISH REROLL", true, Color(0.96, 0.96, 0.98))
			_refresh_all_ui(false)

		DuelPhase.Phase.FIGHTING:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW, 0.45)
			var prio_text: String = "MERON FIRST" if (phase_manager and phase_manager.meron_state and phase_manager.meron_state.has_priority) else ("CLASH (SIMULTANEOUS)" if (phase_manager and phase_manager.is_clash_round) else "WALA FIRST")
			_show_phase_notification("FIGHTING PHASE", "QUEUE YOUR COMBAT CARDS! [%s]" % prio_text, Color(0.96, 0.96, 0.98), true, 0.30)
			if arena_controller and arena_controller.has_method("update_table_notice"):
				arena_controller.update_table_notice("RING BELL\nTO LOCK IN & FIGHT", true, Color(0.96, 0.96, 0.98))
			_refresh_all_ui(false)

		DuelPhase.Phase.ROUND_END:
			_show_phase_notification("ROUND END", "EVALUATING COMBAT RESULTS...", Color.WHITE, false, 0.50)
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.ARENA_VIEW, 0.35)
			_refresh_all_ui(false)

func _on_round_started(round_number: int) -> void:
	turn_number = round_number
	_log("[b][color=gold]--- ROUND %d ---[/color][/b]" % round_number)
	if GameManager and GameManager.is_spectator and BettingManager:
		BettingManager.lock_betting()
		if _meron_bet_btn and is_instance_valid(_meron_bet_btn): _meron_bet_btn.disabled = true
		if _wala_bet_btn and is_instance_valid(_wala_bet_btn): _wala_bet_btn.disabled = true
		if spectator_bet_ticket_lbl and is_instance_valid(spectator_bet_ticket_lbl):
			if not BettingManager.has_active_bet:
				spectator_bet_ticket_lbl.text = "Combat underway — Betting closed for Round %d." % round_number

func _on_round_ended(round_number: int) -> void:
	_log("[color=gray]Round %d concluded.[/color]" % round_number)

func _on_dice_rolled(meron_val: int, wala_val: int, is_clash: bool) -> void:
	if player:
		player.current_dice_roll = meron_val
	if opponent:
		opponent.current_dice_roll = wala_val
	_log("[color=yellow]Dice Revealed! Meron: [b]%d[/b] | Wala: [b]%d[/b][/color]" % [meron_val, wala_val])
	if is_clash:
		_log("[b][color=coral]IT'S A CLASH! Identical rolls -> Simultaneous attack phase![/color][/b]")
	else:
		var winner: String = "You (Meron) take Priority!" if meron_val > wala_val else "Opponent (Wala) takes Priority!"
		_log("[color=cyan]%s[/color]" % winner)
	# Do NOT show a banner notification for dice rolled; priority result is popped to camera via YOU FIRST / YOU LAST.
	_refresh_all_ui(false)

func _on_priority_determined(priority_player_id: String) -> void:
	var name_str: String = "Meron (You)" if priority_player_id == "MERON" else "Wala (CPU)"
	_log("[color=gold]Turn Priority: [b]%s[/b][/color]" % name_str)
	if priority_player_id == "MERON":
		_show_priority_result_pop("YOU FIRST", Color.WHITE)
	elif priority_player_id == "WALA":
		_show_priority_result_pop("YOU LAST", Color.WHITE)
	else:
		_show_priority_result_pop("CLASH!", Color.WHITE)

func _on_discard_required(player_id: String, count: int) -> void:
	if player_id == "MERON":
		if phase_manager and phase_manager.meron_state and phase_manager.meron_state.discard_count >= player.hand.size() and player.hand.size() > 0:
			# Automatically handled by _on_auto_discarded
			pass
		elif player.hand.is_empty():
			pass
		else:
			_log("[color=orange]Discard required: Select %d card%s to discard.[/color]" % [count, "s" if count != 1 else ""])
			_update_discard_visuals()

func _on_auto_discarded(player_id: String, discarded_cards: Array) -> void:
	if player_id == "MERON":
		var card_names: Array[String] = []
		for c in discarded_cards:
			if c is CardData:
				card_names.append(c.display_name)
		var names_str: String = ", ".join(card_names) if card_names.size() > 0 else "%d cards" % discarded_cards.size()
		_log("[color=orange]Auto-discarded: %s[/color]" % names_str)
		if arena_controller:
			# 1. Animate physical cards cleanly sliding away into the deck
			if arena_controller.has_method("animate_discard_cards") and player and discarded_cards.size() < player.hand.size():
				arena_controller.animate_discard_cards(discarded_cards)
			elif arena_controller.has_method("animate_discard_all_cards"):
				arena_controller.animate_discard_all_cards(discarded_cards)
			# 2. Automatically press and ring the 3D Voxel Bell
			if arena_controller.has_method("ring_bell"):
				arena_controller.ring_bell(1)
			if arena_controller.has_method("update_table_notice"):
				var notice_cards: String = names_str if names_str.length() <= 28 else ("%d CARDS" % discarded_cards.size())
				arena_controller.update_table_notice("AUTO-DISCARDED (%s)\nPROCEEDING TO DRAW..." % notice_cards, true, Color.WHITE)
			if arena_controller.has_method("update_3d_phase_banner"):
				arena_controller.update_3d_phase_banner("DISCARD PHASE", "Auto-discarded (%s) — proceeding to Draw." % names_str, Color(0.96, 0.96, 0.98), turn_number)
		if btn_phase_action:
			btn_phase_action.disabled = true
		_refresh_all_ui(false)

func _update_discard_visuals() -> void:
	if not phase_manager or not phase_manager.meron_state:
		return
	var needed: int = mini(phase_manager.meron_state.discard_count, player.hand.size())
	var selected_count: int = phase_manager.get_selected_discards("MERON").size()
	if phase_manager.meron_state.discard_count >= player.hand.size():
		selected_count = needed
	if phase_sub_label:
		phase_sub_label.text = "Select %d cards to discard (%d / %d selected)" % [needed, selected_count, needed]
	if arena_controller and arena_controller.has_method("update_3d_phase_banner"):
		arena_controller.update_3d_phase_banner("DISCARD PHASE", phase_sub_label.text, Color(0.96, 0.96, 0.98), turn_number)
	if arena_controller and arena_controller.has_method("update_table_discard_notice"):
		if phase_manager.meron_state.discard_count >= player.hand.size() and player.hand.size() > 0:
			arena_controller.update_table_notice("ALL CARDS AUTO-DISCARDED\nDRAWING CARDS...", true, Color.WHITE)
		else:
			arena_controller.update_table_discard_notice(needed, selected_count, true)
	if btn_phase_action:
		btn_phase_action.disabled = (selected_count < needed)

func _on_cards_drawn(player_id: String, count: int) -> void:
	if player_id == "MERON":
		_log("[color=cyan]Drew %d card%s from deck.[/color]" % [count, "s" if count != 1 else ""])
		_refresh_all_ui(true)

func _on_card_rerolled(player_id: String, card: CardData, remaining_rerolls: int, slot_index: int = -1) -> void:
	var name_str: String = "You" if player_id == "MERON" else "CPU"
	_log("%s rerolled [b]%s[/b] (%d free reroll%s left)" % [name_str, card.display_name, remaining_rerolls, "s" if remaining_rerolls != 1 else ""])
	if player_id == "MERON":
		if phase_sub_label:
			phase_sub_label.text = "Rerolled %s! (%d free reroll%s left)" % [card.display_name, remaining_rerolls, "s" if remaining_rerolls != 1 else ""]
		if arena_controller and arena_controller.has_method("update_3d_phase_banner"):
			arena_controller.update_3d_phase_banner("CARD REROLL", phase_sub_label.text, Color(0.96, 0.96, 0.98), turn_number)
		if arena_controller and arena_controller.has_method("update_table_notice"):
			arena_controller.update_table_notice("RING BELL\nTO FINISH REROLL\n(%d LEFT)" % remaining_rerolls, true, Color(0.96, 0.96, 0.98))
		if arena_controller and arena_controller.has_method("update_taya_coins"):
			arena_controller.update_taya_coins(player.taya_remaining, opponent.taya_remaining)
		if slot_index >= 0 and arena_controller and arena_controller.has_method("animate_reroll_draw") and slot_index < player.hand.size():
			arena_controller.animate_reroll_draw(slot_index, player.hand[slot_index])
		else:
			_refresh_all_ui(true)

func _on_roll_manipulated(player_id: String, new_roll: int) -> void:
	var target_duelist: Duelist = player if player_id == "MERON" else opponent
	if target_duelist:
		target_duelist.current_dice_roll = new_roll
	var name_str: String = "You" if player_id == "MERON" else "CPU"
	_log("[color=gold]%s manipulated dice roll -> [b]%d[/b]![/color]" % [name_str, new_roll])
	_refresh_all_ui(false)

func _on_combat_resolved(events: Array[Dictionary]) -> void:
	_log_events(events)
	_check_match_status()

func _on_duel_finished(winner_id: String) -> void:
	match_over = true
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("notify_duel_finished"):
		nm.notify_duel_finished(winner_id)

	if BettingManager and BettingManager.has_active_bet:
		var won_bet: bool = (BettingManager.player_bet_side == winner_id)
		var payout_odds: float = BettingManager.meron_odds if winner_id == "MERON" else BettingManager.wala_odds
		BettingManager.resolve_winner(winner_id, [], payout_odds)
		if won_bet:
			var payout: int = int(round(BettingManager.player_bet_amount * payout_odds))
			_show_bet_victory_celebration(winner_id, payout, payout_odds)
		else:
			_show_phase_notification("BET RESOLVED", "%s won the match. Better luck next duel!" % winner_id, Color.WHITE, false, 0.70)
	if winner_id == "DRAW":
		_show_phase_notification("DRAW!", "Mutual Knockout — It's a Draw!", Color.WHITE, false, 0.70)
		_log("[b][color=yellow]DOUBLE KO — IT'S A DRAW![/color][/b]")
	elif winner_id == "MERON":
		_show_phase_notification("VICTORY!", "You are the Champion of the Cockpit!", Color.WHITE, false, 0.70)
		_log("[b][color=green]VICTORY — You are the Champion of the Cockpit![/color][/b]")
	else:
		_show_phase_notification("DEFEAT!", "Opponent won the duel.", Color.WHITE, false, 0.70)
		_log("[b][color=red]DEFEAT — Opponent wins the Sabong match![/color][/b]")
	_refresh_all_ui(false)
	_show_game_over_modal(winner_id)

func _show_game_over_modal(winner_id: String) -> void:
	if _game_over_modal != null and is_instance_valid(_game_over_modal):
		return

	# Dramatic pause so death VFX and victor celebrations play in the arena
	await get_tree().create_timer(1.8).timeout

	if _game_over_modal != null and is_instance_valid(_game_over_modal):
		return

	var overlay := Control.new()
	overlay.name = "GameOverOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_modal = overlay
	add_child(overlay)

	# Translucent dark cockpit backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.03, 0.06, 0.85)
	overlay.add_child(backdrop)

	# Center Glassmorphism Card
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(
		(get_viewport_rect().size.x - 720) * 0.5,
		(get_viewport_rect().size.y - 520) * 0.5
	)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.07, 0.11, 0.96)
	p_style.border_color = Color.GOLD if winner_id == "MERON" else (Color(0.95, 0.25, 0.25) if winner_id == "WALA" else Color.ORANGE)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(16)
	p_style.shadow_color = Color(0, 0, 0, 0.75)
	p_style.shadow_size = 22
	p_style.content_margin_left = 36
	p_style.content_margin_right = 36
	p_style.content_margin_top = 32
	p_style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", p_style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	# Outcome Title (Anton font)
	var title_lbl := Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var outcome_title: String = "VICTORY" if winner_id == "MERON" else ("DEFEAT" if winner_id == "WALA" else "DOUBLE KNOCKOUT")
	title_lbl.text = outcome_title
	UIFontStyle.style_anton(title_lbl, 58)
	title_lbl.add_theme_color_override("font_color", Color.GOLD if winner_id == "MERON" else (Color(0.95, 0.25, 0.25) if winner_id == "WALA" else Color.ORANGE))
	vbox.add_child(title_lbl)

	# Subtitle
	var sub_lbl := Label.new()
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub_text: String = "You are the Champion of the Cockpit!" if winner_id == "MERON" else ("Your Rooster was Turned into Fried Chicken!" if winner_id == "WALA" else "Mutual Knockout — It's a Draw!")
	sub_lbl.text = sub_text
	UIFontStyle.style_body(sub_lbl, 20, true)
	sub_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 0.9))
	vbox.add_child(sub_lbl)

	# Horizontal stats box
	var stats_box := HBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 28)
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stats_box)

	# Player Column
	var p_col := VBoxContainer.new()
	p_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var p_name_lbl := Label.new()
	p_name_lbl.text = player.rooster_data.display_name.to_upper() if player and player.rooster_data else "MERON"
	UIFontStyle.style_subheading(p_name_lbl, 22)
	p_name_lbl.add_theme_color_override("font_color", Color.GOLD)
	p_col.add_child(p_name_lbl)
	var p_hp_lbl := Label.new()
	p_hp_lbl.text = "HP: %d / %d" % [max(0, player.hp if player else 0), player.max_hp if player else 20]
	UIFontStyle.style_body(p_hp_lbl, 18)
	p_col.add_child(p_hp_lbl)
	var p_status := Label.new()
	p_status.text = "SURVIVOR" if winner_id == "MERON" else "FRIED CHICKEN"
	UIFontStyle.style_body(p_status, 16, true)
	p_status.add_theme_color_override("font_color", Color.GREEN if winner_id == "MERON" else Color.CRIMSON)
	p_col.add_child(p_status)
	stats_box.add_child(p_col)

	# Center VS / Round Info
	var vs_col := VBoxContainer.new()
	vs_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var vs_lbl := Label.new()
	vs_lbl.text = "VS"
	UIFontStyle.style_anton(vs_lbl, 28)
	vs_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	vs_col.add_child(vs_lbl)
	var rnd_lbl := Label.new()
	rnd_lbl.text = "Rounds: %d" % turn_number
	UIFontStyle.style_body(rnd_lbl, 16)
	vs_col.add_child(rnd_lbl)
	stats_box.add_child(vs_col)

	# Opponent Column
	var o_col := VBoxContainer.new()
	o_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var o_name_lbl := Label.new()
	o_name_lbl.text = opponent.rooster_data.display_name.to_upper() if opponent and opponent.rooster_data else "WALA"
	UIFontStyle.style_subheading(o_name_lbl, 22)
	o_name_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	o_col.add_child(o_name_lbl)
	var o_hp_lbl := Label.new()
	o_hp_lbl.text = "HP: %d / %d" % [max(0, opponent.hp if opponent else 0), opponent.max_hp if opponent else 20]
	UIFontStyle.style_body(o_hp_lbl, 18)
	o_col.add_child(o_hp_lbl)
	var o_status := Label.new()
	o_status.text = "SURVIVOR" if winner_id == "WALA" else "FRIED CHICKEN"
	UIFontStyle.style_body(o_status, 16, true)
	o_status.add_theme_color_override("font_color", Color.GREEN if winner_id == "WALA" else Color.CRIMSON)
	o_col.add_child(o_status)
	stats_box.add_child(o_col)

	# Spacer
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(sp)

	# Spectator Game Over View
	if GameManager and GameManager.is_spectator:
		var spec_card := PanelContainer.new()
		var sc_style := StyleBoxFlat.new()
		sc_style.bg_color = Color(0.12, 0.15, 0.22, 0.9)
		sc_style.set_corner_radius_all(10)
		sc_style.content_margin_left = 20
		sc_style.content_margin_right = 20
		sc_style.content_margin_top = 12
		sc_style.content_margin_bottom = 12
		spec_card.add_theme_stylebox_override("panel", sc_style)
		vbox.add_child(spec_card)

		var spec_vb := VBoxContainer.new()
		spec_vb.add_theme_constant_override("separation", 6)
		spec_card.add_child(spec_vb)

		var bet_res_lbl := Label.new()
		bet_res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if BettingManager and BettingManager.player_bet_side != "":
			if BettingManager.player_bet_side == winner_id:
				var payout_odds: float = BettingManager.meron_odds if winner_id == "MERON" else BettingManager.wala_odds
				var win_pay: int = int(round(BettingManager.player_bet_amount * payout_odds))
				bet_res_lbl.text = "SPECTATOR BET WON: +%d TAYA (%.2fx)!" % [win_pay, payout_odds]
				UIFontStyle.style_subheading(bet_res_lbl, 20)
				bet_res_lbl.add_theme_color_override("font_color", Color.GOLD)
			else:
				bet_res_lbl.text = "Wager of %d Taya on %s settled." % [BettingManager.player_bet_amount, BettingManager.player_bet_side]
				UIFontStyle.style_body(bet_res_lbl, 16)
				bet_res_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		else:
			bet_res_lbl.text = "Spectator Match Concluded."
			UIFontStyle.style_body(bet_res_lbl, 16)
		spec_vb.add_child(bet_res_lbl)

		var bal_hb := HBoxContainer.new()
		bal_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		bal_hb.add_theme_constant_override("separation", 8)
		spec_vb.add_child(bal_hb)

		var coin_icon := UIIcons.create_icon_rect("coin", 18, Color(1.0, 0.85, 0.3))
		bal_hb.add_child(coin_icon)

		var bal_lbl := Label.new()
		var cur_taya: int = AuthManager.taya_points if AuthManager else 500
		var cur_rank: String = AuthManager.rank_tier if AuthManager else "SILVER"
		bal_lbl.text = "Wallet Balance: %d Taya • Rank: %s" % [cur_taya, cur_rank]
		UIFontStyle.style_subheading(bal_lbl, 16)
		bal_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		bal_hb.add_child(bal_lbl)

		var btn_spec_lobby := Button.new()
		btn_spec_lobby.text = "RETURN TO LOBBY"
		btn_spec_lobby.custom_minimum_size = Vector2(0, 52)
		UIFontStyle.style_button(btn_spec_lobby, 20)
		btn_spec_lobby.pressed.connect(func():
			GameManager.reset_online_state()
			GameManager.change_scene("res://scenes/main_menu.tscn")
		)
		vbox.add_child(btn_spec_lobby)
		return

	# Action Buttons
	var tm_node: Node = get_node_or_null("/root/TournamentManager")
	var is_tourney: bool = tm_node != null and tm_node.get("is_tournament_active") == true

	if is_tourney:
		var btn_bracket := Button.new()
		btn_bracket.text = "CONTINUE TO TOURNAMENT BRACKET"
		btn_bracket.custom_minimum_size = Vector2(0, 54)
		UIFontStyle.style_button(btn_bracket, 22)
		var b_style := StyleBoxFlat.new()
		b_style.bg_color = Color(0.20, 0.16, 0.08, 0.95)
		b_style.border_color = Color.GOLD
		b_style.set_border_width_all(2)
		b_style.set_corner_radius_all(10)
		btn_bracket.add_theme_stylebox_override("normal", b_style)
		btn_bracket.pressed.connect(func():
			var win_rooster: RoosterData = player.rooster_data if winner_id == "MERON" else opponent.rooster_data
			var is_online_tm: bool = tm_node.get("is_online_tournament") == true
			if is_online_tm:
				var nm = get_node_or_null("/root/NetworkManager")
				if nm and nm.is_host:
					if tm_node.has_method("record_match_result"):
						tm_node.record_match_result(win_rooster)
					nm.broadcast_tournament_match_result(win_rooster.rooster_id, tm_node.serialize_bracket())
			else:
				if tm_node.has_method("record_match_result"):
					tm_node.record_match_result(win_rooster)
			var gm: Node = get_node_or_null("/root/GameManager")
			if gm and gm.has_method("change_scene"):
				gm.change_scene("res://scenes/bracketscene.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/bracketscene.tscn")
		)
		vbox.add_child(btn_bracket)
	else:
		var btn_rematch := Button.new()
		btn_rematch.text = "PLAY REMATCH"
		btn_rematch.custom_minimum_size = Vector2(0, 50)
		UIFontStyle.style_button(btn_rematch, 20)
		btn_rematch.pressed.connect(func():
			get_tree().reload_current_scene()
		)
		vbox.add_child(btn_rematch)

		var btn_char := Button.new()
		btn_char.text = "CHANGE ROOSTER"
		btn_char.custom_minimum_size = Vector2(0, 50)
		UIFontStyle.style_button(btn_char, 20)
		btn_char.pressed.connect(func():
			var gm: Node = get_node_or_null("/root/GameManager")
			if gm and gm.has_method("change_scene"):
				gm.change_scene("res://scenes/character_select.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/character_select.tscn")
		)
		vbox.add_child(btn_char)

	var btn_menu := Button.new()
	btn_menu.text = "MAIN MENU"
	btn_menu.custom_minimum_size = Vector2(0, 48)
	UIFontStyle.style_button(btn_menu, 18)
	btn_menu.pressed.connect(func():
		var tm: Node = get_node_or_null("/root/TournamentManager")
		if tm:
			tm.set("is_tournament_active", false)
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("change_scene"):
			gm.change_scene("res://scenes/main_menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn_menu)

	# Entrance Animation
	overlay.modulate.a = 0.0
	panel.scale = Vector2(0.85, 0.85)
	panel.pivot_offset = Vector2(360, 260)
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_phase_action_pressed() -> void:
	_on_end_turn_triggered()



# ---------------------------------------------------------------------------
# Card & Turn Actions
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not player or not opponent:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Check if clicking on the 3D Voxel Bell on the table
			if not is_resolving_turn and not match_over and arena_controller:
				if arena_controller.check_bell_click(event.position):
					_on_end_turn_triggered()
					get_viewport().set_input_as_handled()
					return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if primed_variable_card != null:
				_cancel_taya_priming()
				get_viewport().set_input_as_handled()
				return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if arena_controller and not is_resolving_turn:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.TABLE_VIEW)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.ARENA_VIEW)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if primed_variable_card != null:
				_cancel_taya_priming()
				get_viewport().set_input_as_handled()
				return
			elif _inspection_overlay and is_instance_valid(_inspection_overlay):
				dismiss_card_inspection()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_SPACE or event.keycode == KEY_S or event.keycode == KEY_DOWN:
			if arena_controller and not is_resolving_turn:
				arena_controller.toggle_camera_view()
		elif event.keycode == KEY_W or event.keycode == KEY_UP:
			if arena_controller:
				arena_controller.transition_camera_view(ArenaController.CameraViewState.ARENA_VIEW)



var primed_variable_card: CardData = null
var primed_card_3d: Card3D = null
var primed_taya_count: int = 1

func _on_card_clicked(card: CardData, source_card_3d: Card3D = null) -> void:
	if match_over or is_resolving_turn or not player:
		return

	if phase_manager:
		match phase_manager.current_phase:
			DuelPhase.Phase.DICE_ROLL:
				if phase_manager.can_manipulate_roll("MERON"):
					if card.card_type == CardData.CardType.ROLL_MANIPULATION or card.is_dice_reroll or card.roll_delta != 0:
						DuelLogger.action("MERON", "ROLL_MANIPULATION_CARD_CLICKED", "Card: %s" % card.display_name)
						var success: bool = phase_manager.apply_roll_manipulation("MERON", card)
						if success:
							_refresh_all_ui(false)
				return

			DuelPhase.Phase.DISCARD:
				DuelLogger.action("MERON", "DISCARD_CARD_CLICKED", "Card: %s" % card.display_name)
				phase_manager.select_discard_card("MERON", card)
				_update_discard_visuals()
				_refresh_all_ui(false)
				return

			DuelPhase.Phase.REROLL:
				var slot_idx: int = source_card_3d.slot_index if is_instance_valid(source_card_3d) else -1
				if phase_manager.can_reroll("MERON"):
					DuelLogger.action("MERON", "REROLL_CARD_CLICKED", "Card: %s (slot: %d)" % [card.display_name, slot_idx])
					phase_manager.request_card_reroll("MERON", card, slot_idx)
				else:
					_log("[color=orange]No free card rerolls remaining this round.[/color]")
				return

			DuelPhase.Phase.FIGHTING:
				DuelLogger.action("MERON", "FIGHTING_CARD_CLICKED", "Card: %s" % card.display_name)
				pass # Fall through to combat card queuing logic

			_:
				# DRAW or ROUND_END
				return

	if player.queued_cards.has(card):
		# Unqueue card
		player.unqueue_card(card)
		if card.card_id == "yagami_ryuks_watch":
			player.secret_prediction = ""
			if is_instance_valid(source_card_3d):
				source_card_3d.close_prediction_menu()
				source_card_3d.set_secret_prediction("")
		_cancel_taya_priming()
		if arena_controller and arena_controller.has_method("close_all_card_prediction_menus"):
			arena_controller.close_all_card_prediction_menus()
		_refresh_all_ui(false)
		return

	# Re-clicking the primed card CONFIRMS and CONSUMES IT!
	if primed_variable_card == card:
		_confirm_primed_variable_card()
		return

	# If another card was primed, cancel it
	if primed_variable_card != null:
		_cancel_taya_priming()

	if not player.can_play_card(card):
		if card.is_passive_trigger:
			_log("[color=orange]%s is a Passive Trigger and activates automatically.[/color]" % card.display_name)
			return
		if card.usage_gate == CardData.UsageGate.STATE_LOCKED:
			if (card.required_state == "titan_mode_active" or card.required_state == "titan_form_active") and not player.titan_form_active:
				_log("[color=orange]Cannot play %s: Only usable in Titan Mode![/color]" % card.display_name)
				return
			if card.required_state == "tension_ge_5" and player.tension_stacks < 5:
				_log("[color=orange]Cannot play %s: Requires 5 Tension stacks (current: %d)![/color]" % [card.display_name, player.tension_stacks])
				return
		if card.locks_out_card_type != -1:
			for q in player.queued_cards:
				if q.card_type == card.locks_out_card_type:
					_log("[color=orange]Cannot play %s: Conflicts with queued %s card (%s)![/color]" % [card.display_name, CardData.CardType.keys()[card.locks_out_card_type], q.display_name])
					return
		for q in player.queued_cards:
			if q.locks_out_card_type != -1 and card.card_type == q.locks_out_card_type:
				_log("[color=orange]Cannot play %s: Locked out by %s this turn![/color]" % [card.display_name, q.display_name])
				return
		if player.current_dice_roll < card.dice_requirement:
			_log("[color=orange]Cannot play %s (Requires Dice Roll >= %d, rolled %d).[/color]" % [card.display_name, card.dice_requirement, player.current_dice_roll])
		else:
			_log("[color=orange]Cannot afford %s (Requires %d Taya).[/color]" % [card.display_name, card.taya_cost])
		return

	# Variable cost card: Enter Priming Mode (awaiting Taya coin clicks / re-click)
	if card.is_variable_cost and player.taya_remaining >= card.taya_cost:
		_start_taya_priming(card, source_card_3d)
		return

	# Ryuk's Watch: Open 3 Prediction Options directly on the card face (no emojis)
	if card.card_id == "yagami_ryuks_watch":
		if is_instance_valid(source_card_3d):
			if source_card_3d.is_prediction_menu_open:
				source_card_3d.close_prediction_menu()
			else:
				if arena_controller and arena_controller.has_method("close_all_card_prediction_menus"):
					arena_controller.close_all_card_prediction_menus()
				source_card_3d.open_prediction_menu()
		return

	player.queue_card(card)
	_log("Queued: [b]%s[/b]" % card.display_name)
	_refresh_all_ui(false)

func _on_card_discard_requested(card: CardData) -> void:
	if match_over or is_resolving_turn or not player:
		return
	if primed_variable_card != null and primed_variable_card == card:
		_cancel_taya_priming()
		return
	if arena_controller and arena_controller.has_method("close_all_card_prediction_menus"):
		arena_controller.close_all_card_prediction_menus()
	if player.queued_cards.has(card):
		player.unqueue_card(card)
		if card.card_id == "yagami_ryuks_watch":
			player.secret_prediction = ""
	if player.discard_card(card):
		_log("Discarded: [b]%s[/b] (Sent to Discard Pile)" % card.display_name)
		_refresh_all_ui(false)

## Unified single entry point for ending turn / confirming phase (triggered by 3D Bell or action button)
func _on_end_turn_triggered() -> void:
	if match_over or is_resolving_turn or not player or not opponent:
		return

	if phase_manager:
		# Block duplicate triggers if player is already ready for the current phase!
		if phase_manager.is_player_ready("MERON"):
			DuelLogger.warn("MatchUI", "End turn / bell ignored: player is already ready in phase %s" % DuelPhase.Phase.keys()[phase_manager.current_phase])
			return

		# Block bell clicks during automated non-interactive phases
		if phase_manager.current_phase == DuelPhase.Phase.DRAW or phase_manager.current_phase == DuelPhase.Phase.ROUND_END or phase_manager.current_phase == DuelPhase.Phase.DICE_ROLL:
			DuelLogger.warn("MatchUI", "End turn / bell ignored during non-interactive phase %s" % DuelPhase.Phase.keys()[phase_manager.current_phase])
			return

		# Immediately clear table notice as soon as player rings the bell
		if arena_controller and arena_controller.has_method("update_table_notice"):
			arena_controller.update_table_notice("", false)

		match phase_manager.current_phase:
			DuelPhase.Phase.DISCARD:
				var needed: int = 0
				if phase_manager.meron_state:
					needed = mini(phase_manager.meron_state.discard_count, player.hand.size())
				var selected_count: int = phase_manager.get_selected_discards("MERON").size()
				if selected_count >= needed:
					var chosen_discards: Array = phase_manager.get_selected_discards("MERON").duplicate()
					var confirmed: bool = phase_manager.confirm_discard("MERON")
					if confirmed:
						_log("[color=green]Discards confirmed! Bell rung.[/color]")
						if arena_controller and arena_controller.has_method("animate_discard_cards"):
							arena_controller.animate_discard_cards(chosen_discards)
						if phase_manager.current_phase == DuelPhase.Phase.DISCARD:
							if arena_controller and arena_controller.has_method("update_table_notice"):
								arena_controller.update_table_notice("DISCARDS CONFIRMED!\nDRAWING CARDS...", true, Color.WHITE)
						_refresh_all_ui(false)
						if btn_phase_action:
							btn_phase_action.disabled = true
				else:
					_log("[color=orange]Please select %d cards to discard first! (Selected %d/%d)[/color]" % [needed, selected_count, needed])
					if arena_controller and arena_controller.has_method("update_table_discard_notice"):
						arena_controller.update_table_discard_notice(needed, selected_count, true)
				return

			DuelPhase.Phase.REROLL:
				phase_manager.finish_reroll("MERON")
				_log("[color=gray]Finished card rerolls. Bell rung.[/color]")
				# Only display Reroll Locked In if the phase hasn't advanced to Fighting phase yet!
				if phase_manager.current_phase == DuelPhase.Phase.REROLL:
					if arena_controller and arena_controller.has_method("update_table_notice"):
						arena_controller.update_table_notice("REROLL LOCKED IN", true, Color.WHITE)
				_refresh_all_ui(false)
				if btn_phase_action:
					btn_phase_action.disabled = true
				return

			DuelPhase.Phase.FIGHTING:
				_cancel_taya_priming()
				if player and player.secret_prediction == "":
					for c in player.queued_cards:
						if c.card_id == "yagami_ryuks_watch":
							player.secret_prediction = "ATTACK"
							break
				phase_manager.mark_player_ready("MERON")
				_log("[color=green]Locked in combat cards! Ringing bell...[/color]")
				if phase_manager.current_phase == DuelPhase.Phase.FIGHTING:
					if arena_controller and arena_controller.has_method("update_table_notice"):
						arena_controller.update_table_notice("CARDS LOCKED IN", true, Color.WHITE)
				_refresh_all_ui(false)
				if btn_phase_action:
					btn_phase_action.disabled = true
				return
			_:
				return

	_cancel_taya_priming()
	is_resolving_turn = true

	# CPU AI Turn Selection
	if is_vs_ai and opponent:
		AIController.make_ai_turn(opponent, player)

	if arena_controller and arena_controller.has_method("update_bell_notice"):
		arena_controller.update_bell_notice("", false)

	_log("[i]Bell rung! Resolving combat...[/i]")

	# Default prediction for Ryuk's Watch if player did not explicitly choose
	if player and player.secret_prediction == "":
		for c in player.queued_cards:
			if c.card_id == "yagami_ryuks_watch":
				player.secret_prediction = "ATTACK"
				break

	# Resolve Turn via CombatEngine
	var events: Array[Dictionary] = CombatEngine.resolve_turn(player, opponent, turn_number)

	# Play 3D visual combat sequence (ArenaController automatically looks up to ARENA_VIEW)
	if arena_controller:
		await arena_controller.play_combat_sequence(events)
	else:
		await get_tree().create_timer(1.0).timeout

	_log_events(events)
	_check_match_status()

	if not match_over:
		turn_number += 1
		player.reset_turn_for_new_round()
		opponent.reset_turn_for_new_round()
		
		# Draw cards up to MAX_HAND_SIZE (6 cards) with automatic discard reshuffle
		player.draw_cards_up_to_max(6)
		opponent.draw_cards_up_to_max(6)
		
		# Roll new dice for both duelists
		player.roll_dice()
		opponent.roll_dice()
		
		# Trigger 3D Tumbling Dice in Arena
		_trigger_dice_roll_animation()
		
		_log("[b]--- Round %d ---[/b]" % turn_number)
		_log("[color=yellow]Meron rolled %d | Wala rolled %d[/color]" % [player.current_dice_roll, opponent.current_dice_roll])

	is_resolving_turn = false
	_refresh_all_ui(true)

# Legacy alias
# Legacy alias
func _on_end_turn_pressed() -> void:
	_on_end_turn_triggered()



func _log_events(events: Array[Dictionary]) -> void:
	for ev in events:
		var type: CombatEngine.EventType = ev.get("type", CombatEngine.EventType.TURN_START)
		match type:
			CombatEngine.EventType.TRANSFORM:
				_log("[color=gold]%s[/color]" % str(ev.get("text", "Transformed!")))
			CombatEngine.EventType.ATTACK_HIT:
				var atk_name: String = "You" if int(ev.get("attacker", 1)) == 1 else "CPU"
				_log("%s struck for [b]%d dmg[/b] (Blocked: %d)" % [atk_name, int(ev.get("actual_hp_damage", 0)), int(ev.get("mitigated", 0))])
			CombatEngine.EventType.COUNTER_HIT:
				_log("[color=cyan]%s[/color]" % str(ev.get("text", "Counter!")))
			CombatEngine.EventType.HEAL:
				var h_name: String = "You" if int(ev.get("duelist", 1)) == 1 else "CPU"
				_log("%s healed [b]+%d HP[/b]" % [h_name, int(ev.get("amount", 0))])
			CombatEngine.EventType.DOT_TICK:
				var d_name: String = "You" if int(ev.get("duelist", 1)) == 1 else "CPU"
				_log("[color=purple]%s took %d Poop DoT damage[/color]" % [d_name, int(ev.get("damage", 0))])
			CombatEngine.EventType.REVIVE:
				_log("[color=gold][b]%s[/b][/color]" % str(ev.get("text", "Revived!")))

func _check_match_status() -> void:
	if player.hp <= 0 or opponent.hp <= 0:
		match_over = true
		var win_id: String = "DRAW"
		if player.hp <= 0 and opponent.hp <= 0:
			_log("[b][color=yellow]DOUBLE KO — IT'S A DRAW![/color][/b]")
			win_id = "DRAW"
		elif player.hp <= 0:
			_log("[b][color=red]DEFEAT — Opponent wins the Sabong match![/color][/b]")
			win_id = "WALA"
		else:
			_log("[b][color=green]VICTORY — You are the Champion of the Cockpit![/color][/b]")
			win_id = "MERON"
		_show_game_over_modal(win_id)

func _refresh_all_ui(animate_draw: bool = false) -> void:
	if not player or not opponent:
		return

	# Sync 3D digital LED clock screens on the tables (HP in fighting/round-end, Timer in other phases)
	if arena_controller:
		var is_fighting_or_end: bool = phase_manager and (phase_manager.current_phase == DuelPhase.Phase.FIGHTING or phase_manager.current_phase == DuelPhase.Phase.ROUND_END)
		if is_fighting_or_end or not phase_manager:
			if arena_controller.has_method("update_hp_clocks"):
				arena_controller.update_hp_clocks(player.hp, opponent.hp)
		else:
			var time_left: float = phase_manager.get_time_remaining("MERON")
			if time_left > 0.0 and arena_controller.has_method("update_table_clock_display"):
				var mins: int = int(ceil(time_left) / 60.0)
				var secs: int = int(ceil(time_left)) % 60
				var time_str: String = "%02d : %02d" % [mins, secs]
				var glow_col: Color = Color(3.5, 0.15, 0.15, 1.0) if time_left <= 10.0 else Color(2.5, 0.25, 0.25, 1.0)
				arena_controller.update_table_clock_display(time_str, glow_col)
			elif arena_controller.has_method("update_table_clock_display"):
				arena_controller.update_table_clock_display("-- : --", Color(1.2, 0.2, 0.2, 0.6))

	# Sync 3D voxel Taya coins on both tables (P1 and P2)
	if arena_controller and arena_controller.has_method("update_taya_coins"):
		arena_controller.update_taya_coins(player.taya_remaining, opponent.taya_remaining)


	# Sync physical 3D cards placed on the tabletop and deck stack
	if arena_controller and arena_controller.has_method("sync_table_cards"):
		var queued_to_show: Array[CardData] = player.queued_cards
		var can_play_fn: Callable = func(c: CardData) -> bool: return not match_over and not is_resolving_turn and player.can_play_card(c)

		if phase_manager:
			match phase_manager.current_phase:
				DuelPhase.Phase.DICE_ROLL:
					queued_to_show = []
					can_play_fn = func(c: CardData) -> bool:
						return not match_over and phase_manager.can_manipulate_roll("MERON") and (c.card_type == CardData.CardType.ROLL_MANIPULATION or c.is_dice_reroll or c.roll_delta != 0)
				DuelPhase.Phase.DISCARD:
					var discards: Array = phase_manager.get_selected_discards("MERON")
					var discards_typed: Array[CardData] = []
					for d in discards:
						if d is CardData:
							discards_typed.append(d)
					queued_to_show = discards_typed
					can_play_fn = func(_c: CardData) -> bool: return true
				DuelPhase.Phase.REROLL:
					queued_to_show = []
					can_play_fn = func(_c: CardData) -> bool: return phase_manager.can_reroll("MERON")
				DuelPhase.Phase.FIGHTING:
					queued_to_show = player.queued_cards
					can_play_fn = func(c: CardData) -> bool: return not match_over and not is_resolving_turn and player.can_play_card(c)
				_:
					queued_to_show = []
					can_play_fn = func(_c: CardData) -> bool: return false

		arena_controller.sync_table_cards(
			player.hand,
			queued_to_show,
			animate_draw,
			can_play_fn,
			player.demonic_aura_stacks if player else 0,
			player.secret_prediction if player else ""
		)

func _log(text: String) -> void:

	if log_label:
		log_label.append_text(text + "\n")

var _inspection_overlay: Control = null

## Displays a high-resolution, full-screen card inspection overlay when clicked
func show_card_inspection(card_data: CardData) -> void:
	if not card_data:
		return
	dismiss_card_inspection()

	var overlay := Control.new()
	overlay.name = "CardInspectionOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspection_overlay = overlay
	add_child(overlay)

	# Dark semi-transparent background backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.04, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(backdrop)

	# Centered card container
	var center_cont := CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center_cont)

	var card_box := VBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 14)
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_cont.add_child(card_box)

	# Demonic Aura Stack Indicator (for Nechicko cards)
	if card_data and (card_data.character_id == "nechicko" or card_data.card_id.begins_with("nechicko_")):
		var aura_panel := PanelContainer.new()
		aura_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p_style := StyleBoxFlat.new()
		p_style.bg_color = Color(0.08, 0.02, 0.03, 0.95)
		p_style.border_width_bottom = 2
		p_style.border_width_left = 2
		p_style.border_width_right = 2
		p_style.border_width_top = 2
		p_style.border_color = Color(0.85, 0.15, 0.18, 0.9)
		p_style.set_corner_radius_all(6)
		p_style.content_margin_left = 16
		p_style.content_margin_right = 16
		p_style.content_margin_top = 6
		p_style.content_margin_bottom = 6
		aura_panel.add_theme_stylebox_override("panel", p_style)

		var aura_label := Label.new()
		var stacks: int = player.demonic_aura_stacks if player else 0
		aura_label.text = "DEMONIC AURA: %d STACKS" % stacks
		aura_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIFontStyle.style_anton(aura_label, 20)
		aura_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.96))
		aura_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura_panel.add_child(aura_label)
		card_box.add_child(aura_panel)

	# Card Image Preview (High-Res 1080p native)
	var card_tex_rect := TextureRect.new()
	card_tex_rect.custom_minimum_size = Vector2(520, 749) # 750x1080 ratio (~70% screen height)
	card_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	card_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_data.art_path != "" and ResourceLoader.exists(card_data.art_path):
		card_tex_rect.texture = load(card_data.art_path)
	card_box.add_child(card_tex_rect)

	# Dismiss Prompt
	var hint_label := Label.new()
	hint_label.text = "[ Click anywhere to close ]"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(hint_label, 18, true)
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_child(hint_label)

	# Smooth pop-in animation
	overlay.modulate = Color(1, 1, 1, 0)
	card_box.scale = Vector2(0.85, 0.85)
	card_box.pivot_offset = Vector2(260, 375)
	
	var tw := create_tween()
	if tw:
		tw.set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(card_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Click anywhere to dismiss
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			dismiss_card_inspection()
			get_viewport().set_input_as_handled()
	)

func dismiss_card_inspection() -> void:
	if _inspection_overlay and is_instance_valid(_inspection_overlay):
		var target := _inspection_overlay
		_inspection_overlay = null
		var tw := create_tween()
		if tw:
			tw.set_parallel(true)
			tw.tween_property(target, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD)
			tw.chain().tween_callback(target.queue_free)

var _pause_modal: Control = null

func _on_pause_menu_pressed() -> void:
	if _pause_modal and is_instance_valid(_pause_modal):
		_pause_modal.queue_free()
		_pause_modal = null
		return

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_modal = overlay
	add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.05, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.95)
	style.border_color = Color.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSE MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(title, 32)
	title.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(title)

	var btn_resume := Button.new()
	btn_resume.text = "RESUME"
	btn_resume.custom_minimum_size = Vector2(0, 48)
	UIFontStyle.style_button(btn_resume, 20)
	btn_resume.pressed.connect(func():
		overlay.queue_free()
		_pause_modal = null
	)
	vbox.add_child(btn_resume)

	# Quick In-Game Graphics Settings
	var gm_node = get_node_or_null("/root/GraphicsManager")
	if gm_node:
		var gfx_box := PanelContainer.new()
		var g_style := StyleBoxFlat.new()
		g_style.bg_color = Color(0.04, 0.06, 0.10, 0.85)
		g_style.border_color = Color(0.3, 0.35, 0.45)
		g_style.set_border_width_all(1)
		g_style.set_corner_radius_all(8)
		g_style.content_margin_left = 14
		g_style.content_margin_right = 14
		g_style.content_margin_top = 10
		g_style.content_margin_bottom = 10
		gfx_box.add_theme_stylebox_override("panel", g_style)
		vbox.add_child(gfx_box)

		var g_vbox := VBoxContainer.new()
		g_vbox.add_theme_constant_override("separation", 8)
		gfx_box.add_child(g_vbox)

		var g_title := Label.new()
		g_title.text = "GRAPHICS PRESET"
		UIFontStyle.style_subheading(g_title, 14)
		g_title.add_theme_color_override("font_color", Color.GOLD)
		g_vbox.add_child(g_title)

		var g_presets_row := HBoxContainer.new()
		g_presets_row.add_theme_constant_override("separation", 6)
		g_vbox.add_child(g_presets_row)

		var p_btns: Array[Button] = []
		var p_defs := [
			{"name": "POTATO", "id": 0},
			{"name": "LOW", "id": 1},
			{"name": "MED", "id": 2},
			{"name": "HIGH", "id": 3},
			{"name": "ULTRA", "id": 4}
		]

		var shadow_chk: CheckBox = null

		var _update_p_btns = func():
			var cur_p = gm_node.current_preset
			for b in p_btns:
				var pid: int = b.get_meta("preset_id", -1)
				var sb := StyleBoxFlat.new()
				if pid == cur_p:
					sb.bg_color = Color(0.70, 0.50, 0.10, 0.90)
					sb.border_color = Color.GOLD
					sb.set_border_width_all(2)
				else:
					sb.bg_color = Color(0.12, 0.16, 0.24, 0.85)
					sb.border_color = Color(0.3, 0.35, 0.45)
					sb.set_border_width_all(1)
				sb.set_corner_radius_all(6)
				b.add_theme_stylebox_override("normal", sb)

		for pd in p_defs:
			var pb := Button.new()
			pb.text = pd["name"]
			pb.custom_minimum_size = Vector2(70, 34)
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			pb.set_meta("preset_id", pd["id"])
			UIFontStyle.style_button(pb, 12)
			pb.pressed.connect(func():
				gm_node.set_preset(pd["id"], true)
				_update_p_btns.call()
				if shadow_chk and is_instance_valid(shadow_chk):
					shadow_chk.button_pressed = gm_node.shadows_enabled
			)
			g_presets_row.add_child(pb)
			p_btns.append(pb)
		_update_p_btns.call()

		var toggles_row := HBoxContainer.new()
		toggles_row.add_theme_constant_override("separation", 16)
		g_vbox.add_child(toggles_row)

		shadow_chk = CheckBox.new()
		shadow_chk.text = "Dynamic 3D Shadows"
		UIFontStyle.style_button(shadow_chk, 13)
		shadow_chk.button_pressed = gm_node.shadows_enabled
		shadow_chk.toggled.connect(func(is_on: bool):
			gm_node.set_shadows_enabled(is_on)
			_update_p_btns.call()
		)
		toggles_row.add_child(shadow_chk)

		var fps_chk := CheckBox.new()
		fps_chk.text = "Show FPS Counter"
		UIFontStyle.style_button(fps_chk, 13)
		fps_chk.button_pressed = gm_node.show_fps_counter
		fps_chk.toggled.connect(func(is_on: bool):
			gm_node.toggle_fps_counter(is_on)
		)
		toggles_row.add_child(fps_chk)

	var btn_char_sel := Button.new()
	btn_char_sel.text = "CHANGE ROOSTER"
	btn_char_sel.custom_minimum_size = Vector2(0, 48)
	UIFontStyle.style_button(btn_char_sel, 18)
	btn_char_sel.pressed.connect(func():
		var gm_node_inst := get_node_or_null("/root/GameManager")
		if gm_node_inst and gm_node_inst.has_method("change_scene"):
			gm_node_inst.change_scene("res://scenes/character_select.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/character_select.tscn")
	)
	vbox.add_child(btn_char_sel)

	var btn_main_menu := Button.new()
	btn_main_menu.text = "MAIN MENU"
	btn_main_menu.custom_minimum_size = Vector2(0, 48)
	UIFontStyle.style_button(btn_main_menu, 18)
	btn_main_menu.pressed.connect(func():
		var gm_node_inst := get_node_or_null("/root/GameManager")
		if gm_node_inst and gm_node_inst.has_method("change_scene"):
			gm_node_inst.change_scene("res://scenes/main_menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn_main_menu)

var _primed_hud_overlay: Control = null
var _primed_hud_stat_label: Label = null

func _start_taya_priming(card: CardData, source_card_3d: Card3D = null) -> void:
	primed_variable_card = card
	primed_card_3d = source_card_3d
	primed_taya_count = 1

	if is_instance_valid(primed_card_3d):
		primed_card_3d.set_primed_state(true, primed_taya_count, player.taya_remaining)

	if arena_controller and arena_controller.has_method("set_taya_coins_primed_glow"):
		arena_controller.set_taya_coins_primed_glow(player.duelist_id, primed_taya_count)

	var per_taya: int = 4 if player.all_for_one_active else 2
	var stat_name: String = "DMG" if card.card_type == CardData.CardType.ATTACK else "SHIELD"
	var stat_val: int = 1 if card.card_type != CardData.CardType.ATTACK else (1 + player.bonus_flat_attack)
	_log("[color=yellow][b]%s[/b] primed ([color=#00ff88]%d %s[/color] at 1 Taya). Click + or - on the card to adjust Taya (+%d/Taya), click the card again to CONFIRM![/color]" % [card.display_name, stat_val, stat_name, per_taya])

func _on_card_variable_taya_adjusted(_source_card_3d: Card3D, new_taya: int) -> void:
	if primed_variable_card == null or not player:
		return
	primed_taya_count = clampi(new_taya, 1, player.taya_remaining)
	if is_instance_valid(primed_card_3d):
		primed_card_3d.set_primed_state(true, primed_taya_count, player.taya_remaining)
	if arena_controller and arena_controller.has_method("set_taya_coins_primed_glow"):
		arena_controller.set_taya_coins_primed_glow(player.duelist_id, primed_taya_count)

	var extra: int = primed_taya_count - 1
	var per_taya: int = 4 if player.all_for_one_active else 2
	var stat_name: String = "DMG" if primed_variable_card.card_type == CardData.CardType.ATTACK else "SHIELD"
	var stat_val: int = 1 + extra * per_taya
	if primed_variable_card.card_type == CardData.CardType.ATTACK:
		stat_val += player.bonus_flat_attack
	_log("[color=gold][b]%d / %d Taya[/b] committed -> [color=#00ff88][b]%d %s[/b][/color]! Click card again to CONFIRM.[/color]" % [primed_taya_count, player.taya_remaining, stat_val, stat_name])

func _show_primed_card_hud(card: CardData) -> void:
	_dismiss_primed_hud()

	var overlay := Control.new()
	overlay.name = "PrimedCardHUD"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_primed_hud_overlay = overlay
	add_child(overlay)

	# Dark screen backdrop (dims environment so glowing coins and card pop out)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.01, 0.02, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE # Clicks pass straight through to 3D table coins
	overlay.add_child(backdrop)

	# Right-side container (completely clear of left-side coins on the table)
	var right_box := VBoxContainer.new()
	right_box.anchor_left = 1.0
	right_box.anchor_right = 1.0
	right_box.anchor_top = 0.5
	right_box.anchor_bottom = 0.5
	right_box.offset_left = -580.0
	right_box.offset_right = -40.0
	right_box.offset_top = -400.0
	right_box.offset_bottom = 400.0
	right_box.alignment = BoxContainer.ALIGNMENT_CENTER
	right_box.add_theme_constant_override("separation", 12)
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(right_box)

	# Enlarged Card Texture Preview (Bigger, high-res)
	var card_tex := TextureRect.new()
	card_tex.custom_minimum_size = Vector2(500, 720)
	card_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	card_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	card_tex.pivot_offset = Vector2(250, 360)
	if card.art_path != "" and ResourceLoader.exists(card.art_path):
		card_tex.texture = load(card.art_path)
	right_box.add_child(card_tex)

	# Hover feedback on enlarged card
	card_tex.mouse_entered.connect(func():
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		var tw := create_tween()
		tw.tween_property(card_tex, "scale", Vector2(1.025, 1.025), 0.12).set_trans(Tween.TRANS_QUAD)
	)
	card_tex.mouse_exited.connect(func():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		var tw := create_tween()
		tw.tween_property(card_tex, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
	)

	# Clicking the enlarged card CONFIRMS AND CONSUMES IT!
	card_tex.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_primed_variable_card()
			get_viewport().set_input_as_handled()
	)

	# 1. Live Stat Badge Label (Clean pixel font, bold)
	_primed_hud_stat_label = Label.new()
	_primed_hud_stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(_primed_hud_stat_label, 24, true)
	right_box.add_child(_primed_hud_stat_label)

	# 2. Clean Instruction Text (Pixel font)
	var hint_label := Label.new()
	hint_label.text = "[ Click Card to Confirm | Click Coins to add Taya ]"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(hint_label, 16, false)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 0.95))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(hint_label)

	# 3. Clean Cancel Button (Pixel font)
	var btn_cancel := Button.new()
	btn_cancel.text = "[ Click here to Cancel ]"
	btn_cancel.flat = true
	btn_cancel.custom_minimum_size = Vector2(260, 36)
	UIFontStyle.style_button(btn_cancel, 16)
	btn_cancel.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.8))
	btn_cancel.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.4, 1.0))
	btn_cancel.pressed.connect(func():
		_cancel_taya_priming()
	)
	right_box.add_child(btn_cancel)

	# Smooth pop-in animation
	overlay.modulate = Color(1, 1, 1, 0)
	right_box.scale = Vector2(0.92, 0.92)
	right_box.pivot_offset = Vector2(250, 360)
	var tw := create_tween()
	if tw:
		tw.set_parallel(true)
		tw.tween_property(overlay, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(right_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_update_primed_card_hud_stat()

func _update_primed_card_hud_stat() -> void:
	if not _primed_hud_stat_label or not is_instance_valid(_primed_hud_stat_label) or primed_variable_card == null:
		return

	var extra: int = primed_taya_count - 1
	var per_taya: int = 4 if player.all_for_one_active else 2
	var stat_name: String = "DMG" if primed_variable_card.card_type == CardData.CardType.ATTACK else "SHIELD"
	var stat_val: int = 1 + extra * per_taya
	if primed_variable_card.card_type == CardData.CardType.ATTACK:
		stat_val += player.bonus_flat_attack

	if primed_variable_card.card_type == CardData.CardType.ATTACK:
		_primed_hud_stat_label.text = "%d DMG  (%d / %d Taya committed)" % [stat_val, primed_taya_count, player.taya_remaining]
		_primed_hud_stat_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	else:
		_primed_hud_stat_label.text = "%d SHIELD  (%d / %d Taya committed)" % [stat_val, primed_taya_count, player.taya_remaining]
		_primed_hud_stat_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))

func _dismiss_primed_hud() -> void:
	if _primed_hud_overlay and is_instance_valid(_primed_hud_overlay):
		var target := _primed_hud_overlay
		_primed_hud_overlay = null
		_primed_hud_stat_label = null
		var tw := create_tween()
		tw.tween_property(target, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD)
		tw.chain().tween_callback(target.queue_free)

func _confirm_primed_variable_card() -> void:
	if primed_variable_card == null or not player:
		return
	var card := primed_variable_card
	var extra: int = primed_taya_count - card.taya_cost
	player.queue_card(card, extra)
	_log("[color=green]Confirmed & Queued: [b]%s[/b] (Committed %d Taya)[/color]" % [card.display_name, primed_taya_count])
	_cancel_taya_priming()
	_refresh_all_ui(false)

func _on_taya_coin_clicked(player_id: int, coin_idx: int) -> void:
	if match_over or is_resolving_turn or not player:
		return
	if player_id != player.duelist_id or primed_variable_card == null:
		return

	var max_coins: int = player.taya_remaining
	var target_coins: int = clampi(coin_idx + 1, 1, max_coins)

	# If clicking the currently active highest coin, toggle down by 1 (minimum 1)
	if primed_taya_count == target_coins and target_coins > 1:
		primed_taya_count -= 1
	else:
		primed_taya_count = target_coins

	if arena_controller and arena_controller.has_method("set_taya_coins_primed_glow"):
		arena_controller.set_taya_coins_primed_glow(player.duelist_id, primed_taya_count)

	if is_instance_valid(primed_card_3d):
		primed_card_3d.set_primed_state(true, primed_taya_count, player.taya_remaining)

	_update_primed_card_hud_stat()

	var extra: int = primed_taya_count - 1
	var per_taya: int = 4 if player.all_for_one_active else 2
	var stat_name: String = "DMG" if primed_variable_card.card_type == CardData.CardType.ATTACK else "SHIELD"
	var stat_val: int = 1 + extra * per_taya
	if primed_variable_card.card_type == CardData.CardType.ATTACK:
		stat_val += player.bonus_flat_attack

	_log("[color=gold][b]%d / %d Taya[/b] committed -> [color=#00ff88][b]%d %s[/b][/color]! Click enlarged card to CONFIRM.[/color]" % [primed_taya_count, max_coins, stat_val, stat_name])

func _cancel_taya_priming() -> void:
	if is_instance_valid(primed_card_3d):
		primed_card_3d.set_primed_state(false)
	primed_variable_card = null
	primed_card_3d = null
	primed_taya_count = 1
	_dismiss_primed_hud()
	if arena_controller and arena_controller.has_method("close_all_card_prediction_menus"):
		arena_controller.close_all_card_prediction_menus()
	if arena_controller and arena_controller.has_method("set_taya_coins_primed_glow") and player:
		arena_controller.set_taya_coins_primed_glow(player.duelist_id, 0)

func _on_prediction_selected(category: String, card: CardData, source_card_3d: Card3D = null) -> void:
	if not player or not player.can_play_card(card):
		return
	player.secret_prediction = category
	player.queue_card(card)
	if is_instance_valid(source_card_3d):
		source_card_3d.close_prediction_menu()
		source_card_3d.set_secret_prediction(category)
	_log("[color=gold]Ryuk's Watch queued! Prediction set to: [b][color=#ffdd44]%s[/color][/b][/color]" % category)
	_refresh_all_ui(false)

# ---------------------------------------------------------------------------
# Spectator Mode & Taya Wagering HUD
# ---------------------------------------------------------------------------

func _build_spectator_betting_ui() -> void:
	if spectator_betting_panel and is_instance_valid(spectator_betting_panel):
		spectator_betting_panel.queue_free()

	spectator_betting_panel = PanelContainer.new()
	spectator_betting_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	spectator_betting_panel.offset_top = -210
	spectator_betting_panel.offset_bottom = -20
	spectator_betting_panel.offset_left = 60
	spectator_betting_panel.offset_right = -60

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.90)
	style.border_color = Color.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	spectator_betting_panel.add_theme_stylebox_override("panel", style)
	add_child(spectator_betting_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	spectator_betting_panel.add_child(vb)

	var top_row := HBoxContainer.new()
	vb.add_child(top_row)

	var mode_hb := HBoxContainer.new()
	mode_hb.add_theme_constant_override("separation", 8)
	mode_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(mode_hb)

	var eye_ico := UIIcons.create_icon_rect("eye", 18, Color.GOLD)
	mode_hb.add_child(eye_ico)

	var mode_lbl := Label.new()
	mode_lbl.text = "LIVE SPECTATOR ARENA • DYNAMIC PARI-MUTUEL ODDS"
	UIFontStyle.style_subheading(mode_lbl, 16)
	mode_lbl.add_theme_color_override("font_color", Color.GOLD)
	mode_hb.add_child(mode_lbl)

	var bal_hb := HBoxContainer.new()
	bal_hb.add_theme_constant_override("separation", 6)
	top_row.add_child(bal_hb)

	var coin_ico := UIIcons.create_icon_rect("coin", 18, Color(1.0, 0.85, 0.25))
	bal_hb.add_child(coin_ico)

	spectator_taya_bal_lbl = Label.new()
	var bal: int = AuthManager.taya_points if AuthManager else 500
	spectator_taya_bal_lbl.text = "WALLET: %d TAYA" % bal
	UIFontStyle.style_subheading(spectator_taya_bal_lbl, 18)
	spectator_taya_bal_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	bal_hb.add_child(spectator_taya_bal_lbl)

	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 16)
	mid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(mid_row)

	_meron_bet_btn = Button.new()
	_meron_bet_btn.custom_minimum_size = Vector2(240, 48)
	_meron_bet_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m_style := StyleBoxFlat.new()
	m_style.bg_color = Color(0.70, 0.15, 0.15, 0.90)
	m_style.border_color = Color(1.0, 0.4, 0.3)
	m_style.set_border_width_all(2)
	m_style.set_corner_radius_all(8)
	_meron_bet_btn.add_theme_stylebox_override("normal", m_style)
	var m_hover := m_style.duplicate()
	m_hover.bg_color = Color(0.85, 0.20, 0.20, 1.0)
	_meron_bet_btn.add_theme_stylebox_override("hover", m_hover)
	var p1_title: String = player.rooster_data.display_name if (player and player.rooster_data) else "MERON"
	var m_odds: float = BettingManager.meron_odds if BettingManager else 1.95
	_meron_bet_btn.text = "BET MERON [%.2fx]: %s" % [m_odds, p1_title]
	UIFontStyle.style_button(_meron_bet_btn, 17)
	_meron_bet_btn.pressed.connect(func(): _on_spectator_place_bet("MERON"))
	mid_row.add_child(_meron_bet_btn)

	var chips_box := HBoxContainer.new()
	chips_box.add_theme_constant_override("separation", 8)
	chips_box.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_row.add_child(chips_box)

	_chip_buttons.clear()
	var chip_values := [10, 50, 100, 250, 500]
	for val in chip_values:
		var c_btn := Button.new()
		c_btn.text = "%d" % val
		c_btn.custom_minimum_size = Vector2(56, 42)
		c_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var c_style := StyleBoxFlat.new()
		c_style.bg_color = Color(0.15, 0.18, 0.26, 0.9)
		c_style.border_color = Color.GOLD if val == selected_bet_chip else Color(0.3, 0.35, 0.45)
		c_style.set_border_width_all(2 if val == selected_bet_chip else 1)
		c_style.set_corner_radius_all(6)
		c_btn.add_theme_stylebox_override("normal", c_style)
		var c_hover := c_style.duplicate()
		c_hover.bg_color = Color(0.22, 0.26, 0.38, 1.0)
		c_btn.add_theme_stylebox_override("hover", c_hover)
		UIFontStyle.style_button(c_btn, 15)

		c_btn.pressed.connect(func():
			selected_bet_chip = val
			_update_chip_styles()
			_update_bet_ticket_preview()
		)
		chips_box.add_child(c_btn)
		_chip_buttons.append(c_btn)

	_wala_bet_btn = Button.new()
	_wala_bet_btn.custom_minimum_size = Vector2(240, 48)
	_wala_bet_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var w_style := StyleBoxFlat.new()
	w_style.bg_color = Color(0.12, 0.35, 0.70, 0.90)
	w_style.border_color = Color(0.3, 0.6, 1.0)
	w_style.set_border_width_all(2)
	w_style.set_corner_radius_all(8)
	_wala_bet_btn.add_theme_stylebox_override("normal", w_style)
	var w_hover := w_style.duplicate()
	w_hover.bg_color = Color(0.18, 0.45, 0.85, 1.0)
	_wala_bet_btn.add_theme_stylebox_override("hover", w_hover)
	var p2_title: String = opponent.rooster_data.display_name if (opponent and opponent.rooster_data) else "WALA"
	var w_odds: float = BettingManager.wala_odds if BettingManager else 1.95
	_wala_bet_btn.text = "BET WALA [%.2fx]: %s" % [w_odds, p2_title]
	UIFontStyle.style_button(_wala_bet_btn, 17)
	_wala_bet_btn.pressed.connect(func(): _on_spectator_place_bet("WALA"))
	mid_row.add_child(_wala_bet_btn)

	spectator_bet_ticket_lbl = Label.new()
	spectator_bet_ticket_lbl.text = "Select a chip value and click BET MERON or BET WALA before combat begins!"
	spectator_bet_ticket_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(spectator_bet_ticket_lbl, 14, true)
	spectator_bet_ticket_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	vb.add_child(spectator_bet_ticket_lbl)
	_update_bet_ticket_preview()

func _update_chip_styles() -> void:
	var chip_values := [10, 50, 100, 250, 500]
	for i in range(_chip_buttons.size()):
		var btn: Button = _chip_buttons[i]
		if not is_instance_valid(btn): continue
		var val: int = chip_values[i]
		var c_style := StyleBoxFlat.new()
		c_style.bg_color = Color(0.15, 0.18, 0.26, 0.9)
		c_style.border_color = Color.GOLD if val == selected_bet_chip else Color(0.3, 0.35, 0.45)
		c_style.set_border_width_all(2 if val == selected_bet_chip else 1)
		c_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", c_style)

func _update_bet_ticket_preview() -> void:
	if not spectator_bet_ticket_lbl or not is_instance_valid(spectator_bet_ticket_lbl): return
	if BettingManager and BettingManager.has_active_bet: return
	var m_odds: float = BettingManager.meron_odds if BettingManager else 1.95
	var w_odds: float = BettingManager.wala_odds if BettingManager else 1.95
	var est_m: int = int(round(selected_bet_chip * m_odds))
	var est_w: int = int(round(selected_bet_chip * w_odds))
	spectator_bet_ticket_lbl.text = "Chip Selected: %d Taya • Meron Win: %d Taya (%.2fx) | Wala Win: %d Taya (%.2fx)" % [selected_bet_chip, est_m, m_odds, est_w, w_odds]
	spectator_bet_ticket_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))

func _update_spectator_bet_buttons() -> void:
	var m_odds: float = BettingManager.meron_odds if BettingManager else 1.95
	var w_odds: float = BettingManager.wala_odds if BettingManager else 1.95
	var p1_title: String = player.rooster_data.display_name if (player and player.rooster_data) else "MERON"
	var p2_title: String = opponent.rooster_data.display_name if (opponent and opponent.rooster_data) else "WALA"
	if _meron_bet_btn and is_instance_valid(_meron_bet_btn) and not _meron_bet_btn.disabled:
		_meron_bet_btn.text = "BET MERON [%.2fx]: %s" % [m_odds, p1_title]
	if _wala_bet_btn and is_instance_valid(_wala_bet_btn) and not _wala_bet_btn.disabled:
		_wala_bet_btn.text = "BET WALA [%.2fx]: %s" % [w_odds, p2_title]

func _on_spectator_place_bet(side: String) -> void:
	if not BettingManager: return
	if BettingManager.has_active_bet:
		spectator_bet_ticket_lbl.text = "You already have an active bet placed for this match!"
		return
	if not BettingManager.can_place_bet(selected_bet_chip):
		spectator_bet_ticket_lbl.text = "Insufficient Taya coins in wallet to place %d Taya bet!" % selected_bet_chip
		spectator_bet_ticket_lbl.add_theme_color_override("font_color", Color.SALMON)
		return

	var ok := BettingManager.place_bet(side, selected_bet_chip)
	if ok:
		var odds: float = BettingManager.meron_odds if side.to_upper() == "MERON" else BettingManager.wala_odds
		var payout: int = int(round(selected_bet_chip * odds))
		spectator_bet_ticket_lbl.text = "TICKET LOCKED: %d TAYA ON %s • ESTIMATED PAYOUT: %d TAYA (%.2fx)" % [selected_bet_chip, side.to_upper(), payout, odds]
		spectator_bet_ticket_lbl.add_theme_color_override("font_color", Color.GOLD)
		if spectator_taya_bal_lbl and is_instance_valid(spectator_taya_bal_lbl) and AuthManager:
			spectator_taya_bal_lbl.text = "WALLET: %d TAYA" % AuthManager.taya_points
		if _meron_bet_btn and is_instance_valid(_meron_bet_btn): _meron_bet_btn.disabled = true
		if _wala_bet_btn and is_instance_valid(_wala_bet_btn): _wala_bet_btn.disabled = true

# ---------------------------------------------------------------------------
# Top Live Spectator & Dynamic Odds Bar
# ---------------------------------------------------------------------------

func _build_live_odds_bar() -> void:
	if _live_odds_bar and is_instance_valid(_live_odds_bar):
		_live_odds_bar.queue_free()

	_live_odds_bar = PanelContainer.new()
	_live_odds_bar.name = "LiveOddsBar"
	_live_odds_bar.anchor_left = 0.5
	_live_odds_bar.anchor_right = 0.5
	_live_odds_bar.anchor_top = 0.0
	_live_odds_bar.anchor_bottom = 0.0
	_live_odds_bar.offset_left = -340
	_live_odds_bar.offset_right = 340
	_live_odds_bar.offset_top = 18
	_live_odds_bar.offset_bottom = 74

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.04, 0.06, 0.12, 0.90)
	bar_style.border_color = Color.GOLD
	bar_style.set_border_width_all(2)
	bar_style.set_corner_radius_all(10)
	bar_style.content_margin_left = 16
	bar_style.content_margin_right = 16
	bar_style.content_margin_top = 8
	bar_style.content_margin_bottom = 8
	bar_style.shadow_color = Color(0, 0, 0, 0.6)
	bar_style.shadow_size = 8
	_live_odds_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_live_odds_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_live_odds_bar.add_child(hbox)

	# Spectator count ticker
	var spec_hb := HBoxContainer.new()
	spec_hb.add_theme_constant_override("separation", 6)
	spec_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(spec_hb)

	var spec_ico := UIIcons.create_icon_rect("eye", 15, Color(0.35, 0.85, 1.0))
	spec_hb.add_child(spec_ico)

	_live_spectator_lbl = Label.new()
	var spec_cnt: int = BettingManager.spectator_count if BettingManager else 0
	_live_spectator_lbl.text = "%d SPECTATING" % spec_cnt
	UIFontStyle.style_body(_live_spectator_lbl, 13, true)
	_live_spectator_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	spec_hb.add_child(_live_spectator_lbl)

	var div1 := VSeparator.new()
	hbox.add_child(div1)

	# MERON Odds Pill
	_live_meron_odds_lbl = Label.new()
	var m_odds: float = BettingManager.meron_odds if BettingManager else 1.95
	_live_meron_odds_lbl.text = "MERON [%.2fx]" % m_odds
	UIFontStyle.style_anton(_live_meron_odds_lbl, 17)
	_live_meron_odds_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	hbox.add_child(_live_meron_odds_lbl)

	# Pool Progress & Split Ratio
	var pool_vbox := VBoxContainer.new()
	pool_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pool_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(pool_vbox)

	_live_pool_text_lbl = Label.new()
	var m_pool: int = BettingManager.meron_pool if BettingManager else 0
	var w_pool: int = BettingManager.wala_pool if BettingManager else 0
	_live_pool_text_lbl.text = "POOL: %d vs %d TAYA" % [m_pool, w_pool]
	_live_pool_text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_body(_live_pool_text_lbl, 11, true)
	_live_pool_text_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	pool_vbox.add_child(_live_pool_text_lbl)

	_live_pool_progress = ProgressBar.new()
	_live_pool_progress.custom_minimum_size = Vector2(160, 8)
	_live_pool_progress.show_percentage = false
	var prog_bg := StyleBoxFlat.new()
	prog_bg.bg_color = Color(0.15, 0.40, 0.85, 0.85) # Wala blue
	prog_bg.set_corner_radius_all(4)
	var prog_fg := StyleBoxFlat.new()
	prog_fg.bg_color = Color(0.85, 0.20, 0.20, 0.95) # Meron red
	prog_fg.set_corner_radius_all(4)
	_live_pool_progress.add_theme_stylebox_override("background", prog_bg)
	_live_pool_progress.add_theme_stylebox_override("fill", prog_fg)
	_live_pool_progress.min_value = 0.0
	_live_pool_progress.max_value = 100.0
	var ratio: float = 50.0
	if (m_pool + w_pool) > 0:
		ratio = (float(m_pool) / float(m_pool + w_pool)) * 100.0
	_live_pool_progress.value = ratio
	pool_vbox.add_child(_live_pool_progress)

	# WALA Odds Pill
	_live_wala_odds_lbl = Label.new()
	var w_odds: float = BettingManager.wala_odds if BettingManager else 1.95
	_live_wala_odds_lbl.text = "WALA [%.2fx]" % w_odds
	UIFontStyle.style_anton(_live_wala_odds_lbl, 17)
	_live_wala_odds_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0))
	hbox.add_child(_live_wala_odds_lbl)

func _on_odds_updated(m_odds: float, w_odds: float) -> void:
	if _live_meron_odds_lbl and is_instance_valid(_live_meron_odds_lbl):
		_live_meron_odds_lbl.text = "MERON [%.2fx]" % m_odds
	if _live_wala_odds_lbl and is_instance_valid(_live_wala_odds_lbl):
		_live_wala_odds_lbl.text = "WALA [%.2fx]" % w_odds
	_update_spectator_bet_buttons()
	_update_bet_ticket_preview()

func _on_pool_updated(m_pool: int, w_pool: int) -> void:
	if _live_pool_text_lbl and is_instance_valid(_live_pool_text_lbl):
		_live_pool_text_lbl.text = "POOL: %d vs %d TAYA" % [m_pool, w_pool]
	if _live_pool_progress and is_instance_valid(_live_pool_progress):
		var total: int = m_pool + w_pool
		_live_pool_progress.value = 50.0 if total == 0 else (float(m_pool) / float(total) * 100.0)

func _on_spectator_count_changed(count: int) -> void:
	if _live_spectator_lbl and is_instance_valid(_live_spectator_lbl):
		_live_spectator_lbl.text = "%d SPECTATING" % count

func _on_network_bet_pool_updated(m_pool: int, w_pool: int, m_odds: float, w_odds: float) -> void:
	_on_odds_updated(m_odds, w_odds)
	_on_pool_updated(m_pool, w_pool)

func _on_network_match_finished(winner: String, _payouts: Array, _winning_odds: float, _m_pool: int, _w_pool: int) -> void:
	if not match_over:
		_on_duel_finished(winner)

func _show_bet_victory_celebration(winner_id: String, payout: int, odds: float) -> void:
	var banner := PanelContainer.new()
	banner.name = "VictoryPayoutBanner"
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_left = -340
	banner.offset_right = 340
	banner.offset_top = -140
	banner.offset_bottom = 140

	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.08, 0.05, 0.01, 0.95)
	bs.border_color = Color(1.0, 0.85, 0.2)
	bs.set_border_width_all(3)
	bs.set_corner_radius_all(16)
	bs.content_margin_left = 28
	bs.content_margin_right = 28
	bs.content_margin_top = 20
	bs.content_margin_bottom = 20
	bs.shadow_color = Color(1.0, 0.8, 0.1, 0.45)
	bs.shadow_size = 24
	banner.add_theme_stylebox_override("panel", bs)
	add_child(banner)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	banner.add_child(vb)

	var title_hb := HBoxContainer.new()
	title_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hb.add_theme_constant_override("separation", 14)
	vb.add_child(title_hb)

	var trop1 := UIIcons.create_icon_rect("trophy", 32, Color.GOLD)
	title_hb.add_child(trop1)

	var title := Label.new()
	title.text = "SPECTATOR BET VICTORY!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_anton(title, 32)
	title.add_theme_color_override("font_color", Color.GOLD)
	title_hb.add_child(title)

	var trop2 := UIIcons.create_icon_rect("trophy", 32, Color.GOLD)
	title_hb.add_child(trop2)

	var payout_hb := HBoxContainer.new()
	payout_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	payout_hb.add_theme_constant_override("separation", 10)
	vb.add_child(payout_hb)

	var coin_ico := UIIcons.create_icon_rect("coin", 24, Color(0.3, 1.0, 0.5))
	payout_hb.add_child(coin_ico)

	var payout_lbl := Label.new()
	payout_lbl.text = "+%d TAYA COINS CREDITED!" % payout
	payout_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_title(payout_lbl, 26)
	payout_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	payout_hb.add_child(payout_lbl)

	var sub := Label.new()
	var bal: int = AuthManager.taya_points if AuthManager else 500
	sub.text = "Winning Odds: %.2fx on %s • Wallet: %d Taya" % [odds, winner_id, bal]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIFontStyle.style_subheading(sub, 16)
	sub.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	vb.add_child(sub)

	# Pulse animation
	banner.scale = Vector2(0.7, 0.7)
	banner.pivot_offset = Vector2(340, 140)
	var tw := create_tween()
	if tw:
		tw.tween_property(banner, "scale", Vector2(1.05, 1.05), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(banner, "scale", Vector2.ONE, 0.15)
