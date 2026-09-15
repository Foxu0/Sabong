extends Node3D
class_name ArenaController

signal card_prediction_selected(card_data: CardData, category: String, card_3d: Card3D)

## ArenaController — Coordinates the 3D Arena scene, cameras, roosters, and combat animation sequence.

@export var camera_p1: Camera3D
@export var camera_p2: Camera3D
@export var p1_rooster_anchor: RoosterVisual3D
@export var p2_rooster_anchor: RoosterVisual3D

@onready var phase_manager: DuelPhaseManager = $DuelPhaseManager if has_node("DuelPhaseManager") else null

enum CameraViewState { ARENA_VIEW, TABLE_VIEW }
var current_camera_view: CameraViewState = CameraViewState.ARENA_VIEW
var camera_tween: Tween

var local_player_id: int = 1

func get_arena_view_transform(player_id: int = -1) -> Transform3D:
	var pid: int = local_player_id if player_id == -1 else player_id
	if pid == 2:
		# P2 Arena View (facing +X from -X side)
		var pos := Vector3(-5.0, 2.0, 0.0)
		var target := Vector3(0.0, 1.6, 0.0)
		var b := Basis.looking_at(target - pos, Vector3.UP)
		return Transform3D(b, pos)
	else:
		# P1 Arena View (facing -X from +X side)
		var pos := Vector3(5.0, 2.0, 0.0)
		var target := Vector3(0.0, 1.6, 0.0)
		var b := Basis.looking_at(target - pos, Vector3.UP)
		return Transform3D(b, pos)

func get_spectator_view_transform() -> Transform3D:
	# Ringside elevated broadcast stadium camera
	var pos := Vector3(0.0, 4.2, 5.5)
	var target := Vector3(0.0, 1.2, 0.0)
	var b := Basis.looking_at(target - pos, Vector3.UP)
	return Transform3D(b, pos)

func get_table_view_transform(player_id: int = -1) -> Transform3D:
	var pid: int = local_player_id if player_id == -1 else player_id
	if pid == 2:
		# P2 Table View (looking down at Table 2: prop_table_light_brown2)
		var pos := Vector3(-4.6, 1.65, 0.0)
		var target := Vector3(-3.72, 0.95, 0.0)
		var b := Basis.looking_at(target - pos, Vector3.UP)
		return Transform3D(b, pos)
	else:
		# P1 Table View (looking down at Table 1: prop_table_light_brown)
		var pos := Vector3(4.6, 1.65, 0.0)
		var target := Vector3(3.72, 0.95, 0.0)
		var b := Basis.looking_at(target - pos, Vector3.UP)
		return Transform3D(b, pos)

signal combat_sequence_completed

var table_deck_3d: TableDeck3D
var table_cards_root: Node3D
var table_discard_p1: Node3D = null
var table_discard_p2: Node3D = null
var active_3d_cards: Array[Card3D] = []
var p1_passive_card_3d: Card3D = null
var p2_passive_card_3d: Card3D = null

var _bell_base_pos: Dictionary = {}
var _bell_base_scale: Dictionary = {}
var _bell_tween: Tween
var _bell_last_click_time: int = 0
var table_notice_p1: Label3D = null
var table_notice_p2: Label3D = null

const LAYER_P1_PHASE_BANNER: int = 1 << 4 # Layer 5 (16)
const LAYER_P2_PHASE_BANNER: int = 1 << 5 # Layer 6 (32)

var phase_banner_p1: Node3D = null
var phase_banner_p2: Node3D = null

func _ready() -> void:
	if not camera_p1:
		camera_p1 = get_node_or_null("CameraP1")
	if not camera_p2:
		camera_p2 = get_node_or_null("CameraP2")

	if camera_p1:
		camera_p1.transform = get_arena_view_transform(1)
		current_camera_view = CameraViewState.ARENA_VIEW
	if camera_p2:
		camera_p2.transform = get_arena_view_transform(2)

	_setup_phase_banners()
	_setup_table_deck()
	_setup_bell_interaction()

	var mm = get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("play_battle_theme"):
		mm.play_battle_theme()

func _exit_tree() -> void:
	DiceRoller3D.clear_active_dice(false)
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	if _bell_tween and _bell_tween.is_valid():
		_bell_tween.kill()

func _setup_phase_banners() -> void:
	if camera_p1:
		camera_p1.cull_mask = (1048575 | LAYER_P1_PHASE_BANNER) & ~LAYER_P2_PHASE_BANNER
	if camera_p2:
		camera_p2.cull_mask = (1048575 | LAYER_P2_PHASE_BANNER) & ~LAYER_P1_PHASE_BANNER

	if not is_instance_valid(phase_banner_p1):
		phase_banner_p1 = _create_phase_banner_instance(Vector3(-2.3, 2.65, 0.0), LAYER_P1_PHASE_BANNER, "PhaseBannerP1")
		add_child(phase_banner_p1)

	if not is_instance_valid(phase_banner_p2):
		phase_banner_p2 = _create_phase_banner_instance(Vector3(2.3, 2.65, 0.0), LAYER_P2_PHASE_BANNER, "PhaseBannerP2")
		add_child(phase_banner_p2)

func _create_phase_banner_instance(pos: Vector3, layer_mask: int, p_name: String) -> Node3D:
	var banner := Node3D.new()
	banner.name = p_name
	banner.position = pos

	# 1. Round Badge (Top) — Anton font uppercase
	var r_lbl := Label3D.new()
	r_lbl.name = "RoundLabel"
	r_lbl.text = "--- ROUND 1 ---"
	r_lbl.font = UIFontStyle.get_anton_font()
	r_lbl.font_size = 96
	r_lbl.outline_size = 18
	r_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.95)
	r_lbl.modulate = Color(0.85, 0.92, 1.0, 0.95)
	r_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	r_lbl.no_depth_test = false
	r_lbl.layers = layer_mask
	r_lbl.position = Vector3(0, 1.45, 0.0)
	banner.add_child(r_lbl)

	# 2. Main Phase Title (e.g. CARD MULLIGAN, DICE ROLL) — Enlarged Anton font uppercase
	var t_lbl := Label3D.new()
	t_lbl.name = "TitleLabel"
	t_lbl.text = "DICE ROLL"
	t_lbl.font = UIFontStyle.get_anton_font()
	t_lbl.font_size = 250
	t_lbl.outline_size = 26
	t_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
	t_lbl.modulate = Color(0.96, 0.96, 0.98)
	t_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	t_lbl.no_depth_test = false
	t_lbl.layers = layer_mask
	t_lbl.position = Vector3(0, 0.40, 0.0)
	banner.add_child(t_lbl)

	# 3. Subtitle / Instructions — Anton font uppercase
	var s_lbl := Label3D.new()
	s_lbl.name = "SubLabel"
	s_lbl.text = "ROLLING 3D COCKPIT DICE..."
	s_lbl.font = UIFontStyle.get_anton_font()
	s_lbl.font_size = 86
	s_lbl.outline_size = 14
	s_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
	s_lbl.modulate = Color(0.95, 0.98, 1.0)
	s_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s_lbl.no_depth_test = false
	s_lbl.layers = layer_mask
	s_lbl.position = Vector3(0, -0.65, 0.0)
	banner.add_child(s_lbl)

	banner.visible = false
	return banner

func update_3d_phase_banner(title: String, subtitle: String, _title_color: Color, round_num: int) -> void:
	_setup_phase_banners()
	var banners: Array[Node3D] = [phase_banner_p1, phase_banner_p2]
	for banner: Node3D in banners:
		if not is_instance_valid(banner):
			continue
		banner.visible = true
		var r_lbl := banner.get_node_or_null("RoundLabel") as Label3D
		var t_lbl := banner.get_node_or_null("TitleLabel") as Label3D
		var s_lbl := banner.get_node_or_null("SubLabel") as Label3D

		if r_lbl:
			r_lbl.text = ("--- ROUND %d ---" % round_num).to_upper()
			r_lbl.modulate = Color(0.96, 0.96, 0.98)
			r_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.95)
		if t_lbl:
			t_lbl.text = title.to_upper()
			t_lbl.modulate = Color(0.96, 0.96, 0.98)
			t_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
		if s_lbl:
			s_lbl.text = subtitle.to_upper()
			s_lbl.modulate = Color(0.96, 0.96, 0.98)
			s_lbl.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)

		banner.scale = Vector3(0.5, 0.5, 0.5)
		var tw: Tween = banner.create_tween()
		if tw:
			# Pop in presentation
			tw.tween_property(banner, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			# Hold for viewing
			tw.tween_interval(1.1)
			# Fade away smoothly: BOTH text fill (modulate) AND text border (outline_modulate)
			var is_first: bool = true
			for lbl in [r_lbl, t_lbl, s_lbl]:
				if lbl:
					if is_first:
						tw.chain().tween_property(lbl, "modulate:a", 0.0, 0.6)
						tw.parallel().tween_property(lbl, "outline_modulate:a", 0.0, 0.6)
						is_first = false
					else:
						tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
						tw.parallel().tween_property(lbl, "outline_modulate:a", 0.0, 0.6)
			# Hide banner node completely once fade is finished
			tw.chain().tween_callback(func():
				if is_instance_valid(banner):
					banner.visible = false
			)

func _setup_table_deck() -> void:
	if not is_instance_valid(table_deck_3d):
		table_deck_3d = get_node_or_null("TableDeck3D")

	if not is_instance_valid(table_cards_root):
		table_cards_root = get_node_or_null("TableCardsRoot")
		if not table_cards_root:
			table_cards_root = Node3D.new()
			table_cards_root.name = "TableCardsRoot"
			add_child(table_cards_root)

	# Clean up any leftover TableDiscardPile instances to keep the table clean and unblocked
	var old_dp1 := get_node_or_null("TableDiscardPile1")
	if is_instance_valid(old_dp1):
		old_dp1.queue_free()
	var old_dp2 := get_node_or_null("TableDiscardPile2")
	if is_instance_valid(old_dp2):
		old_dp2.queue_free()
	table_discard_p1 = null
	table_discard_p2 = null

func setup_match(p1_rooster: RoosterData, p2_rooster: RoosterData, p_local_player_id: int = 1) -> void:
	local_player_id = p_local_player_id
	_setup_phase_banners()
	_setup_table_deck()
	
	# Set active camera based on player or spectator perspective
	if GameManager.is_spectator:
		if camera_p1:
			camera_p1.make_current()
			camera_p1.transform = get_spectator_view_transform()
	elif local_player_id == 1 and camera_p1:
		camera_p1.make_current()
		camera_p1.transform = get_arena_view_transform(1)
	elif local_player_id == 2 and camera_p2:
		camera_p2.make_current()
		camera_p2.transform = get_arena_view_transform(2)

	current_camera_view = CameraViewState.ARENA_VIEW

	if p1_rooster_anchor:
		p1_rooster_anchor.set_rooster(p1_rooster)
	if p2_rooster_anchor:
		p2_rooster_anchor.set_rooster(p2_rooster)

	update_taya_coins(3, 3)
	update_hp_clocks(p1_rooster.base_hp if p1_rooster else 20, p2_rooster.base_hp if p2_rooster else 20)
	_setup_passive_cards(p1_rooster, p2_rooster)
	_setup_taya_coin_hitboxes()

## Sets up interactive Area3D hitboxes on 3D Taya coins for direct tactile clicking
func _setup_taya_coin_hitboxes() -> void:
	var p1_coins: Array[Node3D] = [
		get_node_or_null("TayaCoins"),
		get_node_or_null("TayaCoins2"),
		get_node_or_null("TayaCoins3")
	]
	var p2_coins: Array[Node3D] = [
		get_node_or_null("TayaCoins4"),
		get_node_or_null("TayaCoins5"),
		get_node_or_null("TayaCoins6")
	]
	_attach_coin_hitboxes(p1_coins, 1)
	_attach_coin_hitboxes(p2_coins, 2)

func _attach_coin_hitboxes(coins: Array[Node3D], player_id: int) -> void:
	for i in range(coins.size()):
		var coin: Node3D = coins[i]
		if not coin:
			continue
		var existing_area: Area3D = coin.get_node_or_null("CoinArea")
		if not existing_area:
			var area := Area3D.new()
			area.name = "CoinArea"
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.5, 0.4, 0.5)
			col.shape = box
			area.add_child(col)
			coin.add_child(area)

			var coin_idx: int = i
			area.input_event.connect(func(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _s: int):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_on_taya_coin_clicked(player_id, coin_idx)
					get_viewport().set_input_as_handled()
			)
			area.mouse_entered.connect(func():
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			)
			area.mouse_exited.connect(func():
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			)

func _on_taya_coin_clicked(player_id: int, coin_idx: int) -> void:
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("_on_taya_coin_clicked"):
		match_ui._on_taya_coin_clicked(player_id, coin_idx)

## Sets the visual glowing / aura state on 3D Taya coins when committing Taya
func set_taya_coins_primed_glow(player_id: int, primed_count: int) -> void:
	var coins: Array = []
	if player_id == 1:
		coins = [
			get_node_or_null("TayaCoins"),
			get_node_or_null("TayaCoins2"),
			get_node_or_null("TayaCoins3")
		]
	else:
		coins = [
			get_node_or_null("TayaCoins4"),
			get_node_or_null("TayaCoins5"),
			get_node_or_null("TayaCoins6")
		]

	for i in range(coins.size()):
		var coin: Node3D = coins[i]
		if not coin or not is_instance_valid(coin):
			continue
		var aura: MeshInstance3D = coin.get_node_or_null("TayaAuraRing")
		var is_primed: bool = (i < primed_count)
		
		if is_primed:
			if not aura:
				aura = MeshInstance3D.new()
				aura.name = "TayaAuraRing"
				var t_mesh := TorusMesh.new()
				t_mesh.inner_radius = 0.22
				t_mesh.outer_radius = 0.36
				aura.mesh = t_mesh
				var mat := StandardMaterial3D.new()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(0.2, 1.0, 0.5, 0.85)
				mat.emission_enabled = true
				mat.emission = Color(0.3, 1.0, 0.6)
				mat.emission_energy_multiplier = 4.5
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				aura.material_override = mat
				aura.position = Vector3(0, 0.05, 0)
				coin.add_child(aura)
			
			aura.visible = true
		else:
			if aura:
				aura.queue_free()

func _get_table_deck_node() -> Node3D:
	if is_instance_valid(table_deck_3d):
		return table_deck_3d
	if local_player_id == 2:
		return get_node_or_null("cardstack2")
	return get_node_or_null("cardstack")

func _get_table_deck_pos() -> Vector3:
	var node := _get_table_deck_node()
	if is_instance_valid(node):
		return node.global_position
	return Vector3(4.0303, 0.8327, -1.0366) if local_player_id == 1 else Vector3(-4.0303, 0.8327, 1.0366)

func _play_deck_pulse() -> void:
	var stack: Node3D = _get_table_deck_node()
	if stack and is_instance_valid(stack):
		if stack.has_method("play_draw_pulse"):
			stack.play_draw_pulse()
		else:
			var tw := stack.create_tween()
			if tw:
				var base_s: Vector3 = stack.scale
				tw.tween_property(stack, "scale", base_s * Vector3(1.08, 0.85, 1.08), 0.07).set_trans(Tween.TRANS_QUAD)
				tw.tween_property(stack, "scale", base_s, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Explicitly animates a single card being rerolled and drawn fresh from the deck
func animate_reroll_draw(slot_idx: int, new_card: CardData) -> void:
	if slot_idx < 0 or slot_idx >= active_3d_cards.size():
		return
	var card_3d: Card3D = active_3d_cards[slot_idx]
	if not is_instance_valid(card_3d) or not new_card:
		return

	var deck_pos: Vector3 = _get_table_deck_pos()
	_play_deck_pulse()
	card_3d.play_reroll_animation(deck_pos, new_card)

## Synchronizes physical 3D cards placed on the tabletop
func sync_table_cards(hand: Array[CardData], queued: Array[CardData], animate_draw: bool = false, can_play_checker: Callable = Callable(), demonic_aura_stacks: int = 0, secret_prediction: String = "") -> void:
	_setup_table_deck()
	if not is_instance_valid(table_cards_root):
		return

	var total_cards: int = hand.size()
	var deck_pos: Vector3 = _get_table_deck_pos()
	var remaining_queued: Array[CardData] = queued.duplicate()

	# Calculate positions along the tabletop in front of the player
	var spacing: float = 0.275
	var start_z: float = float(total_cards - 1) * spacing * 0.5 + 0.12

	if animate_draw or active_3d_cards.size() != total_cards:
		# Full rebuild / animated deal: clean up ALL non-passive Card3D nodes in table_cards_root
		for child in table_cards_root.get_children():
			if child is Card3D:
				if child == p1_passive_card_3d or child == p2_passive_card_3d or child.slot_index >= 10:
					continue
				if child.get_parent():
					child.get_parent().remove_child(child)
				child.queue_free()
		active_3d_cards.clear()

		if animate_draw:
			_play_deck_pulse()

		for i in range(total_cards):
			var card_data: CardData = hand[i]
			var card_3d := Card3D.new()
			card_3d.card_data = card_data
			card_3d.slot_index = i
			
			var slot_z: float = start_z - float(i) * spacing
			var slot_y: float = 0.837 + float(i) * 0.0015
			var slot_pos: Vector3
			var slot_rot: Vector3
			
			if local_player_id == 2:
				# Table 2 (-X side)
				slot_pos = Vector3(-4.04, slot_y, -slot_z)
				var fan_y: float = -90.0 - (float(i) - float(total_cards - 1) * 0.5) * 2.0
				slot_rot = Vector3(-90.0, fan_y, 0.0)
			else:
				# Table 1 (+X side)
				slot_pos = Vector3(4.04, slot_y, slot_z)
				var fan_y: float = 90.0 + (float(i) - float(total_cards - 1) * 0.5) * 2.0
				slot_rot = Vector3(-90.0, fan_y, 0.0)
			
			card_3d.set_slot_position(slot_pos, slot_rot)

			table_cards_root.add_child(card_3d)
			active_3d_cards.append(card_3d)

			# Duplicate-safe queued state: consume matched queued item so identical cards don't both raise
			var q_idx: int = remaining_queued.find(card_data)
			var is_q: bool = (q_idx != -1)
			if is_q:
				remaining_queued.remove_at(q_idx)
			card_3d.set_queued_state(is_q)
			var is_en: bool = is_q or (can_play_checker.is_valid() and can_play_checker.call(card_data))
			card_3d.set_enabled_state(is_en)
			card_3d.set_demonic_aura(demonic_aura_stacks)
			card_3d.set_secret_prediction(secret_prediction if is_q else "")

			card_3d.card_clicked.connect(func(c_data): _on_3d_card_clicked(c_data, card_3d))
			card_3d.card_right_clicked.connect(func(c_data): _on_3d_card_right_clicked(c_data, card_3d))
			card_3d.variable_taya_adjusted.connect(func(new_taya): _on_3d_card_variable_taya_adjusted(card_3d, new_taya))
			card_3d.prediction_category_selected.connect(func(category): _on_3d_card_prediction_selected(card_3d, category))

			if animate_draw:
				card_3d.play_draw_animation(deck_pos, float(i) * 0.08)
	else:
		# Sanitize any stray/orphan Card3D nodes in table_cards_root not in active_3d_cards
		for child in table_cards_root.get_children():
			if child is Card3D:
				if child == p1_passive_card_3d or child == p2_passive_card_3d or child.slot_index >= 10:
					continue
				if child.is_busy_animating:
					continue
				if not active_3d_cards.has(child):
					if child.get_parent():
						child.get_parent().remove_child(child)
					child.queue_free()

		# Fast state update
		for i in range(total_cards):
			var card_3d: Card3D = active_3d_cards[i]
			var card_data: CardData = hand[i]
			if is_instance_valid(card_3d):
				var prev_card_id: String = card_3d.card_data.card_id if card_3d.card_data else ""
				var changed: bool = (card_3d.card_data != card_data)
				card_3d.update_card_data(card_data)
				var q_idx: int = remaining_queued.find(card_data)
				var is_q: bool = (q_idx != -1)
				if is_q:
					remaining_queued.remove_at(q_idx)
				card_3d.set_queued_state(is_q)
				var is_en: bool = is_q or (can_play_checker.is_valid() and can_play_checker.call(card_data))
				card_3d.set_enabled_state(is_en)
				card_3d.set_demonic_aura(demonic_aura_stacks)
				card_3d.set_secret_prediction(secret_prediction if is_q else "")
				if changed:
					card_3d.force_reset_hover()
					var is_transform: bool = (
						(card_data and card_data.card_id == "eren_titan_stomp" and prev_card_id == "eren_claw_stomp") or
						(card_data and card_data.card_id == "eren_claw_stomp" and prev_card_id == "eren_titan_stomp")
					)
					if is_transform and card_3d.has_method("play_transform_animation"):
						card_3d.play_transform_animation(float(i) * 0.06)
					else:
						_play_deck_pulse()
						card_3d.play_draw_animation(deck_pos, 0.0)

func _on_3d_card_clicked(card_data: CardData, clicked_c3d: Card3D = null) -> void:
	if not is_instance_valid(clicked_c3d):
		for c in active_3d_cards:
			if is_instance_valid(c) and c.card_data == card_data:
				clicked_c3d = c
				break
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("_on_card_clicked"):
		match_ui._on_card_clicked(card_data, clicked_c3d)

func _on_3d_card_right_clicked(card_data: CardData, _clicked_c3d: Card3D = null) -> void:
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("_on_card_discard_requested"):
		match_ui._on_card_discard_requested(card_data)

func _on_3d_card_variable_taya_adjusted(card_3d: Card3D, new_taya: int) -> void:
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("_on_card_variable_taya_adjusted"):
		match_ui._on_card_variable_taya_adjusted(card_3d, new_taya)

func _on_3d_card_prediction_selected(card_3d: Card3D, category: String) -> void:
	if not is_instance_valid(card_3d) or not card_3d.card_data:
		return
	card_prediction_selected.emit(card_3d.card_data, category, card_3d)
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("_on_prediction_selected"):
		match_ui._on_prediction_selected(category, card_3d.card_data, card_3d)

func close_all_card_prediction_menus() -> void:
	for c in active_3d_cards:
		if is_instance_valid(c) and c.has_method("close_prediction_menu"):
			c.close_prediction_menu()

## Instantiates and places visible 3D passive trigger cards on the left side of the table (below Taya coins)
func _setup_passive_cards(p1_rooster: RoosterData, p2_rooster: RoosterData) -> void:
	if is_instance_valid(p1_passive_card_3d):
		p1_passive_card_3d.queue_free()
		p1_passive_card_3d = null
	if is_instance_valid(p2_passive_card_3d):
		p2_passive_card_3d.queue_free()
		p2_passive_card_3d = null

	if not table_cards_root:
		return

	# Setup P1 Passive Card (Table 1: +X side, flat on table in front of Taya coins)
	var p1_passive := _find_passive_card(p1_rooster)
	if p1_passive:
		p1_passive_card_3d = Card3D.new()
		p1_passive_card_3d.card_data = p1_passive
		p1_passive_card_3d.slot_index = 10
		table_cards_root.add_child(p1_passive_card_3d)
		var slot_pos := Vector3(3.48, 0.838, 1.22)
		var slot_rot := Vector3(-90.0, 90.0, 0.0)
		p1_passive_card_3d.set_slot_position(slot_pos, slot_rot)
		p1_passive_card_3d.set_enabled_state(true)
		p1_passive_card_3d.card_clicked.connect(_on_passive_card_clicked)

	# Setup P2 Passive Card (Table 2: -X side, flat on table in front of Taya coins)
	var p2_passive := _find_passive_card(p2_rooster)
	if p2_passive:
		p2_passive_card_3d = Card3D.new()
		p2_passive_card_3d.card_data = p2_passive
		p2_passive_card_3d.slot_index = 10
		table_cards_root.add_child(p2_passive_card_3d)
		var slot_pos := Vector3(-3.48, 0.838, -1.22)
		var slot_rot := Vector3(-90.0, -90.0, 0.0)
		p2_passive_card_3d.set_slot_position(slot_pos, slot_rot)
		p2_passive_card_3d.set_enabled_state(true)
		p2_passive_card_3d.card_clicked.connect(_on_passive_card_clicked)

func _find_passive_card(rooster: RoosterData) -> CardData:
	if not rooster:
		return null
	for card in rooster.moveset:
		if card and (card.is_passive_trigger or card.card_id in Duelist.PASSIVE_CARD_IDS):
			return card
	return null

func _on_passive_card_clicked(card_data: CardData) -> void:
	var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
	if not match_ui:
		match_ui = get_tree().root.find_child("MatchUI", true, false)
	if match_ui and match_ui.has_method("show_card_inspection"):
		match_ui.show_card_inspection(card_data)
	elif match_ui and match_ui.has_method("_log"):
		match_ui._log("[color=gold][PASSIVE CARD] %s — %s[/color]" % [card_data.display_name, card_data.effect_text])

## Smoothly transitions camera between ARENA_VIEW and TABLE_VIEW
func transition_camera_view(target_state: CameraViewState, duration: float = 0.32) -> void:
	current_camera_view = target_state
	# Force reset hover on all active 3D cards to prevent ghost-hovering across camera switches
	for card_node in active_3d_cards:
		if is_instance_valid(card_node) and card_node.has_method("force_reset_hover"):
			card_node.force_reset_hover()

	var active_cam: Camera3D = get_active_camera()
	if not active_cam:
		return
	if camera_tween:
		camera_tween.kill()
	camera_tween = create_tween()
	
	var target_transform: Transform3D
	if GameManager.is_spectator:
		target_transform = get_spectator_view_transform()
	else:
		target_transform = get_arena_view_transform(local_player_id) if target_state == CameraViewState.ARENA_VIEW else get_table_view_transform(local_player_id)
	
	camera_tween.tween_property(active_cam, "transform", target_transform, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func toggle_camera_view() -> void:
	if current_camera_view == CameraViewState.ARENA_VIEW:
		transition_camera_view(CameraViewState.TABLE_VIEW)
	else:
		transition_camera_view(CameraViewState.ARENA_VIEW)


## Updates the physical 3D voxel Taya coins on both tables (P1: TayaCoins 1-3, P2: TayaCoins 4-6)
func update_taya_coins(p1_taya: int, p2_taya: int = 3) -> void:
	var p1_coins: Array[Node3D] = [
		get_node_or_null("TayaCoins"),
		get_node_or_null("TayaCoins2"),
		get_node_or_null("TayaCoins3")
	]
	var p2_coins: Array[Node3D] = [
		get_node_or_null("TayaCoins4"),
		get_node_or_null("TayaCoins5"),
		get_node_or_null("TayaCoins6")
	]
	_animate_coin_group(p1_coins, p1_taya)
	_animate_coin_group(p2_coins, p2_taya)

func _animate_coin_group(coins: Array[Node3D], remaining_taya: int) -> void:
	for i in range(coins.size()):
		var coin: Node3D = coins[i]
		if not coin:
			continue
		var should_be_active: bool = (i < remaining_taya)
		if should_be_active and not coin.visible:
			coin.visible = true
			coin.scale = Vector3(0.001, 0.001, 0.001)
			var tw := create_tween()
			tw.tween_property(coin, "scale", Vector3(0.3, 0.3, 0.3), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not should_be_active and coin.visible:
			var tw := create_tween()
			tw.tween_property(coin, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_QUAD)
			tw.chain().tween_callback(func():
				if is_instance_valid(coin) and not (i < remaining_taya):
					coin.visible = false
			)
## Updates the 3D digital LED screen on the tables (supports HP or Timer countdown)
func update_table_clock_display(display_text: String, glow_color: Color = Color(2.5, 0.25, 0.25, 1.0)) -> void:
	var digital_font = load("res://resources/world/digital_7segment.tres")
	for clock_name in ["hpclock", "hpclock2"]:
		var clock: Node3D = get_node_or_null(clock_name)
		if clock:
			var screen: MeshInstance3D = clock.get_node_or_null("screen")
			if screen:
				var label: Label3D = screen.get_node_or_null("HPLabel")
				if not label:
					label = Label3D.new()
					label.name = "HPLabel"
					label.position = Vector3(0.0, 0.02, 0.0)
					label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
					label.pixel_size = 0.012
					label.shaded = false
					label.double_sided = false
					label.font_size = 110
					label.outline_size = 10
					label.modulate = glow_color
					label.outline_modulate = Color(0.25, 0.02, 0.02, 0.9)
					if digital_font:
						label.font = digital_font
					screen.add_child(label)
				else:
					if digital_font and label.font != digital_font:
						label.font = digital_font
					label.modulate = glow_color
				label.text = display_text

## Updates the 3D digital LED HP clock screens on the tables (Meron HP : Wala HP)
func update_hp_clocks(p1_hp: int, p2_hp: int) -> void:
	var hp_text: String = "%d : %d" % [max(0, p1_hp), max(0, p2_hp)]
	update_table_clock_display(hp_text, Color(2.5, 0.25, 0.25, 1.0))

func get_active_camera() -> Camera3D:
	if camera_p1 and camera_p1.current:
		return camera_p1
	if camera_p2 and camera_p2.current:
		return camera_p2
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if cam:
			return cam
	return camera_p1

## Shakes the active camera for impact hits and energy explosions
func shake_camera(duration: float = 0.35, intensity: float = 0.12) -> void:
	var cam: Camera3D = get_active_camera()
	if not cam:
		return
	var orig_pos: Vector3 = cam.position
	var tw := create_tween()
	var steps: int = max(4, int(duration / 0.04))
	for i in range(steps):
		var decay: float = 1.0 - float(i) / float(steps)
		var offset := Vector3(
			randf_range(-intensity, intensity) * decay,
			randf_range(-intensity * 0.7, intensity * 0.7) * decay,
			randf_range(-intensity, intensity) * decay
		)
		tw.tween_property(cam, "position", orig_pos + offset, 0.04)
	tw.tween_property(cam, "position", orig_pos, 0.04)

## Configures the 3D Voxel Bell Click Collision, hover cursor, and callback for both tables
func _setup_bell_interaction() -> void:
	for bell_name in ["bellendturn", "bellendturn2"]:
		var bell: Node3D = get_node_or_null(bell_name)
		if bell:
			_bell_base_pos[bell_name] = bell.position
			_bell_base_scale[bell_name] = bell.scale
			
			if not bell.has_node("BellClickArea"):
				var area := Area3D.new()
				area.name = "BellClickArea"
				var shape := CollisionShape3D.new()
				# Exact cylinder matching the voxel bell geometry (radius 0.5, height 0.8, base at Y=0)
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.5
				cyl.height = 0.8
				shape.shape = cyl
				shape.position = Vector3(0.0, 0.4, 0.0) # Centered on the bell height
				area.add_child(shape)
				bell.add_child(area)
				area.input_ray_pickable = true
				area.input_event.connect(_on_bell_input_event)
				area.mouse_entered.connect(_on_bell_mouse_entered)
				area.mouse_exited.connect(_on_bell_mouse_exited)

	# Single unified 3D Description / Notification lying flat and centered on each tabletop
	if not is_instance_valid(table_notice_p1):
		table_notice_p1 = Label3D.new()
		table_notice_p1.name = "TableNoticeP1"
		table_notice_p1.font = UIFontStyle.get_anton_font()
		table_notice_p1.font_size = 44
		table_notice_p1.pixel_size = 0.0028
		table_notice_p1.outline_size = 9
		table_notice_p1.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
		table_notice_p1.modulate = Color(0.98, 0.98, 1.0, 0.98)
		table_notice_p1.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		table_notice_p1.rotation_degrees = Vector3(-90.0, 90.0, 0.0)
		table_notice_p1.no_depth_test = false
		table_notice_p1.layers = LAYER_P1_PHASE_BANNER
		table_notice_p1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		table_notice_p1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		table_notice_p1.text = ""
		table_notice_p1.position = Vector3(3.24, 0.842, 0.0)
		add_child(table_notice_p1)
		table_notice_p1.visible = false

	if not is_instance_valid(table_notice_p2):
		table_notice_p2 = Label3D.new()
		table_notice_p2.name = "TableNoticeP2"
		table_notice_p2.font = UIFontStyle.get_anton_font()
		table_notice_p2.font_size = 44
		table_notice_p2.pixel_size = 0.0028
		table_notice_p2.outline_size = 9
		table_notice_p2.outline_modulate = Color(0.04, 0.04, 0.06, 0.98)
		table_notice_p2.modulate = Color(0.98, 0.98, 1.0, 0.98)
		table_notice_p2.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		table_notice_p2.rotation_degrees = Vector3(-90.0, -90.0, 0.0)
		table_notice_p2.no_depth_test = false
		table_notice_p2.layers = LAYER_P2_PHASE_BANNER
		table_notice_p2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		table_notice_p2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		table_notice_p2.text = ""
		table_notice_p2.position = Vector3(-3.24, 0.842, 0.0)
		add_child(table_notice_p2)
		table_notice_p2.visible = false

## Sets the single 3D description lying flat on the table, cleanly replacing any previous text
func update_table_notice(notice_text: String, is_visible: bool = true, _text_color: Color = Color.WHITE) -> void:
	if not is_instance_valid(table_notice_p1) or not is_instance_valid(table_notice_p2):
		_setup_bell_interaction()

	for lbl_item in [table_notice_p1, table_notice_p2]:
		var lbl: Label3D = lbl_item as Label3D
		if is_instance_valid(lbl):
			if not is_visible or notice_text.strip_edges() == "":
				lbl.visible = false
				lbl.text = ""
			else:
				lbl.text = notice_text.to_upper()
				lbl.modulate = Color(0.96, 0.96, 0.98) # Clean white only — strictly never colored!
				lbl.visible = true
				var tw := (lbl as Node).create_tween()
				if tw:
					lbl.scale = Vector3(0.92, 0.92, 0.92)
					tw.tween_property(lbl, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Aliases to ensure full backwards compatibility across callers
func update_bell_notice(notice_text: String, is_visible: bool = true, text_color: Color = Color(0.96, 0.96, 0.98)) -> void:
	update_table_notice(notice_text, is_visible, text_color)

func update_table_discard_notice(needed_count: int, selected_count: int, is_visible: bool = true) -> void:
	if not is_visible or needed_count <= 0:
		update_table_notice("", false)
		return
	if selected_count >= needed_count:
		update_table_notice("RING BELL\nTO CONFIRM DISCARD", true, Color(0.96, 0.96, 0.98))
	else:
		var remaining: int = needed_count - selected_count
		var card_word: String = "CARD" if remaining == 1 else "CARDS"
		var text: String = "SELECT %d %s\n(%d / %d SELECTED)" % [remaining, card_word, selected_count, needed_count]
		update_table_notice(text, true, Color(0.96, 0.96, 0.98))

func _on_bell_mouse_entered() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_bell_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_bell_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	var is_click_or_tap: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if is_click_or_tap:
		var now: int = Time.get_ticks_msec()
		if now - _bell_last_click_time < 450:
			return # Debounce cooldown
		_bell_last_click_time = now
		var bell_name: String = "bellendturn" if local_player_id == 1 else "bellendturn2"
		_play_bell_animation(bell_name)
		DuelLogger.action("MERON" if local_player_id == 1 else "WALA", "BELL_RUNG", "Triggered via Area3D input")
		var match_ui: MatchUI = get_node_or_null("UILayer/MatchUI")
		if not match_ui:
			match_ui = get_tree().root.find_child("MatchUI", true, false)
		if match_ui and match_ui.has_method("_on_end_turn_triggered"):
			match_ui._on_end_turn_triggered()

## Raycast click detector matching the exact cylindrical geometry of the active player's 3D Bell
func check_bell_click(screen_pos: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _bell_last_click_time < 450:
		return false # Debounce cooldown

	var cam: Camera3D = get_active_camera()
	if not cam:
		return false
	var bell_name: String = "bellendturn" if local_player_id == 1 else "bellendturn2"
	var bell: Node3D = get_node_or_null(bell_name)
	if not bell:
		bell = get_node_or_null("bellendturn")
	if not bell:
		return false
	
	var ray_origin: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(screen_pos)
	
	# 1. Physics Space Raycast (tests BellClickArea Cylinder)
	if get_world_3d() and get_world_3d().direct_space_state:
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 50.0)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var result := space_state.intersect_ray(query)
		if result and result.has("collider") and result.collider:
			var col: Node = result.collider
			if col.name == "BellClickArea" or col.get_parent() == bell:
				_bell_last_click_time = now
				_play_bell_animation(bell.name)
				DuelLogger.action("MERON" if local_player_id == 1 else "WALA", "BELL_RUNG", "Triggered via Raycast collision")
				return true

	# 2. Exact Geometric Cylinder Intersection (radius 0.5, height 0.0..0.8 in bell local space)
	if _ray_intersects_bell(bell, ray_origin, ray_normal):
		_bell_last_click_time = now
		_play_bell_animation(bell.name)
		DuelLogger.action("MERON" if local_player_id == 1 else "WALA", "BELL_RUNG", "Triggered via Geometric cylinder test")
		return true

	return false

func _ray_intersects_bell(bell: Node3D, ray_origin: Vector3, ray_normal: Vector3) -> bool:
	var inv_xform: Transform3D = bell.global_transform.affine_inverse()
	var local_origin: Vector3 = inv_xform * ray_origin
	var local_dir: Vector3 = (inv_xform.basis * ray_normal).normalized()
	
	const R: float = 0.5
	const Y_MIN: float = 0.0
	const Y_MAX: float = 0.8
	
	var ox: float = local_origin.x
	var oz: float = local_origin.z
	var dx: float = local_dir.x
	var dz: float = local_dir.z
	
	# Test cylinder curved surface
	var a: float = dx * dx + dz * dz
	var b: float = 2.0 * (ox * dx + oz * dz)
	var c: float = ox * ox + oz * oz - R * R
	
	if a > 0.00001:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sqrt_disc: float = sqrt(disc)
			var t1: float = (-b - sqrt_disc) / (2.0 * a)
			var t2: float = (-b + sqrt_disc) / (2.0 * a)
			for t in [t1, t2]:
				if t > 0.0:
					var hit_y: float = local_origin.y + t * local_dir.y
					if hit_y >= Y_MIN and hit_y <= Y_MAX:
						return true

	# Test top cap disc
	if absf(local_dir.y) > 0.00001:
		var t_top: float = (Y_MAX - local_origin.y) / local_dir.y
		if t_top > 0.0:
			var hx: float = local_origin.x + t_top * local_dir.x
			var hz: float = local_origin.z + t_top * local_dir.z
			if (hx * hx + hz * hz) <= (R * R):
				return true
				
	return false

func _play_bell_animation(bell_name: String = "bellendturn") -> void:
	var bell: Node3D = get_node_or_null(bell_name)
	if not bell:
		bell = get_node_or_null("bellendturn")
	if not bell:
		return
	var base_pos: Vector3 = _bell_base_pos.get(bell.name, bell.position)
	var base_scale: Vector3 = _bell_base_scale.get(bell.name, bell.scale)
	
	if _bell_tween and _bell_tween.is_valid():
		_bell_tween.kill()
	bell.position = base_pos
	bell.scale = base_scale
	
	_bell_tween = create_tween()
	_bell_tween.tween_property(bell, "position:y", base_pos.y - 0.08, 0.05).set_trans(Tween.TRANS_QUAD)
	_bell_tween.tween_property(bell, "scale", base_scale * Vector3(1.2, 0.75, 1.2), 0.05)
	_bell_tween.tween_property(bell, "position:y", base_pos.y, 0.15).set_trans(Tween.TRANS_BOUNCE)
	_bell_tween.tween_property(bell, "scale", base_scale, 0.15)

## Automatically rings the 3D Voxel Bell on the table
func ring_bell(player_id: int = 0) -> void:
	var target_p: int = player_id if player_id > 0 else local_player_id
	var bell_name: String = "bellendturn" if target_p == 1 else "bellendturn2"
	_play_bell_animation(bell_name)

func _get_table_discard_pos() -> Vector3:
	return _get_table_deck_pos()

## Safely updates table discard state (retained for API compatibility)
func update_table_discard_pile(_player_id: int, _discard_cards: Array, _top_card: CardData = null) -> void:
	pass

## Animates specific physical cards flying off the tabletop into the discard/deck pile
func animate_discard_cards(discarded_cards: Array) -> void:
	_setup_table_deck()
	var discard_pos: Vector3 = _get_table_discard_pos()

	var cards_to_discard: Array = discarded_cards.duplicate()
	var remaining_active: Array[Card3D] = []

	for card_3d in active_3d_cards:
		if not is_instance_valid(card_3d):
			continue
		var found_idx: int = -1
		for j in range(cards_to_discard.size()):
			var c = cards_to_discard[j]
			if c is CardData and (card_3d.card_data == c or (card_3d.card_data and card_3d.card_data.card_id == c.card_id)):
				found_idx = j
				break
		if found_idx != -1:
			cards_to_discard.remove_at(found_idx)
			card_3d.play_discard_animation(discard_pos)
		else:
			remaining_active.append(card_3d)

	active_3d_cards = remaining_active

## Animates discarding all physical cards currently active on the tabletop into the deck stack
func animate_discard_all_cards(_discarded_cards: Array = []) -> void:
	_setup_table_deck()
	var discard_pos: Vector3 = _get_table_discard_pos()

	for i in range(active_3d_cards.size()):
		var card_3d: Card3D = active_3d_cards[i]
		if is_instance_valid(card_3d):
			card_3d.play_discard_animation(discard_pos)
	active_3d_cards.clear()



## Sequentially executes turn combat events for cinematic presentation
func play_combat_sequence(events: Array[Dictionary]) -> void:
	# 1. Look up to ARENA_VIEW
	transition_camera_view(CameraViewState.ARENA_VIEW, 0.35)
	await get_tree().create_timer(0.2).timeout

	# 2. Both roosters hop down from their roost stages into the arena ring to fight
	if p1_rooster_anchor and not p1_rooster_anchor.is_dead:
		p1_rooster_anchor.play_step_into_arena()
	if p2_rooster_anchor and not p2_rooster_anchor.is_dead:
		p2_rooster_anchor.play_step_into_arena()
	await get_tree().create_timer(0.55).timeout

	for event in events:

		var type: CombatEngine.EventType = event.get("type", CombatEngine.EventType.TURN_START)
		
		match type:
			CombatEngine.EventType.SELF_DAMAGE:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				var card_id: String = str(event.get("card_id", ""))
				var amount: int = int(event.get("amount", 1))
				if visual:
					if card_id == "yagami_ryuks_watch" or (visual.rooster_data and visual.rooster_data.rooster_id == "chick_yagami"):
						visual.play_yagami_self_strain(amount)
						await get_tree().create_timer(0.40).timeout
					else:
						visual.play_hit(amount)
						FloatingText3D.spawn(self, visual.global_position, "-%d HP" % amount, Color.CRIMSON)
						await get_tree().create_timer(0.40).timeout

			CombatEngine.EventType.TRANSFORM:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				if visual:
					var form: String = str(event.get("form", ""))
					var model_path: String = str(event.get("model_path", ""))
					var text: String = str(event.get("text", "AWAKEN!"))
					if form == "golden_form" or (visual.rooster_data and visual.rooster_data.rooster_id == "hen_goku"):
						visual.play_golden_transformation(model_path, text)
						await get_tree().create_timer(1.0).timeout
					elif form == "gear_5" or (visual.rooster_data and visual.rooster_data.rooster_id == "cluckey_d_puffy"):
						visual.play_cluckey_gear5_transformation(model_path, text)
						await get_tree().create_timer(1.1).timeout
					elif form == "all_for_one_cock" or form == "all_for_one" or (visual.rooster_data and visual.rooster_data.rooster_id == "decluck"):
						visual.play_decluck_power_transformation(model_path, text)
						await get_tree().create_timer(1.25).timeout
					elif form == "pecker_titan" or form == "titan_form" or (visual.rooster_data and visual.rooster_data.rooster_id == "eren_pecker"):
						visual.play_eren_titan_transformation(model_path, text)
						await get_tree().create_timer(1.35).timeout
					elif form == "demon_form" or (visual.rooster_data and visual.rooster_data.rooster_id == "nechicko"):
						visual.play_nechicko_demon_transformation(model_path, text)
						await get_tree().create_timer(1.0).timeout
					else:
						visual.play_transformation(model_path, text)
						await get_tree().create_timer(0.6).timeout

			CombatEngine.EventType.PREDICTION_RESULT:
				var predictor_id: int = int(event.get("predictor", 1))
				var target_id: int = int(event.get("target", 2))
				var p_visual: RoosterVisual3D = p1_rooster_anchor if predictor_id == 1 else p2_rooster_anchor
				var t_visual: RoosterVisual3D = p1_rooster_anchor if target_id == 1 else p2_rooster_anchor
				var success: bool = bool(event.get("success", false))
				if p_visual:
					if p_visual.rooster_data and p_visual.rooster_data.rooster_id == "chick_yagami":
						p_visual.play_yagami_ryuks_watch(success, t_visual)
						await get_tree().create_timer(1.30 if success else 0.85).timeout
					else:
						var msg: String = "PREDICTION: SUCCESS!" if success else "PREDICTION: MISSED!"
						FloatingText3D.spawn(self, p_visual.global_position, msg, Color.GOLD if success else Color.GRAY, true)
						await get_tree().create_timer(0.60).timeout

			CombatEngine.EventType.TURN_DECAY:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				var form: String = str(event.get("form", ""))
				if visual:
					if form == "gear_5_ended":
						visual.play_cluckey_gear5_exhaust_revert()
						await get_tree().create_timer(0.75).timeout
					elif form == "titan_ended":
						visual.play_eren_titan_revert()
						await get_tree().create_timer(0.95).timeout
					elif visual.is_transformed and visual.rooster_data and visual.rooster_data.rooster_id == "eren_pecker":
						# Titan upkeep: 1 HP drain with steam hiss & small red strain flinch
						visual.play_titan_upkeep_drain()
						await get_tree().create_timer(0.45).timeout
					elif form == "demon_form_ended" or (visual.rooster_data and visual.rooster_data.rooster_id == "nechicko" and visual.is_transformed and form != ""):
						visual.play_nechicko_demon_revert()
						await get_tree().create_timer(0.85).timeout
					elif form != "" and visual.is_transformed:
						visual.play_revert_to_base()
						await get_tree().create_timer(0.55).timeout

			CombatEngine.EventType.SHIELD_GAIN:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				if visual:
					var spent_t: int = int(event.get("spent_taya", 1))
					if visual.rooster_data and visual.rooster_data.rooster_id == "decluck":
						visual.play_decluck_all_for_one_heart(int(event.get("amount", 0)), spent_t)
						await get_tree().create_timer(0.85).timeout
					elif visual.rooster_data and visual.rooster_data.rooster_id == "cluckey_d_puffy":
						visual.play_cluckey_gum_barrier(int(event.get("amount", 0)))
						await get_tree().create_timer(0.75).timeout
					elif visual.rooster_data and visual.rooster_data.rooster_id == "hen_goku":
						visual.play_kikiriki_barrier(int(event.get("amount", 0)))
						await get_tree().create_timer(0.85).timeout
					else:
						var theme: String = "cyan"
						if visual.rooster_data:
							if visual.rooster_data.rooster_id == "cocktaro":
								theme = "purple"
						visual.play_shield_gain(int(event.get("amount", 0)), theme)
						await get_tree().create_timer(0.7).timeout
				else:
					await get_tree().create_timer(0.4).timeout

			CombatEngine.EventType.ATTACK_HIT:
				DuelLogger.combat_event(event)
				var attacker_id: int = int(event.get("attacker", 1))
				var atk_visual: RoosterVisual3D = p1_rooster_anchor if attacker_id == 1 else p2_rooster_anchor
				var def_visual: RoosterVisual3D = p2_rooster_anchor if attacker_id == 1 else p1_rooster_anchor
				var vfx_key: String = str(event.get("vfx", "slash"))
				var card_id: String = str(event.get("card_id", ""))
				var target_pos: Vector3 = def_visual.global_position if def_visual else Vector3.ZERO

				if atk_visual:
					# Daniel: Unseen Claw shadow phantom hand strike
					if card_id == "daniel_unseen_claw":
						atk_visual.play_daniel_unseen_claw(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(0.95).timeout
					# Nechicko: Peck Breaker demonic claw burst
					elif card_id == "nechicko_peck_breaker":
						atk_visual.play_nechicko_peck_breaker(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(0.95).timeout
					# Eren Pecker: Claw Stomp / Titan Stomp earth-shattering crash
					elif card_id == "eren_claw_stomp" or card_id == "eren_titan_stomp" or (atk_visual.rooster_data and atk_visual.rooster_data.rooster_id == "eren_pecker" and vfx_key == "stomp"):
						var is_titan: bool = (card_id == "eren_titan_stomp" or atk_visual.is_transformed)
						atk_visual.play_eren_stomp(target_pos, is_titan, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						var wait_time: float = 1.20 if is_titan else 0.85
						await get_tree().create_timer(wait_time).timeout
					# Decluck: All For One Punch green lightning smash
					elif card_id == "decluck_all_for_one_punch":
						var spent_t: int = int(event.get("spent_taya", 1))
						atk_visual.play_decluck_all_for_one_punch(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						, spent_t)
						await get_tree().create_timer(0.95).timeout
					# Cluckey D Puffy: Red Hawk (or Gear 5 Gigant Bajrang Gun in 5th Gear)
					elif card_id == "cluckey_gum_slash":
						if atk_visual.is_transformed:
							atk_visual.play_cluckey_gear5_bajrang_attack(target_pos, func():
								if def_visual:
									var dmg: int = int(event.get("actual_hp_damage", 0))
									var raw_dmg: int = int(event.get("raw_damage", 0))
									var blocked: bool = (dmg == 0 and raw_dmg > 0)
									def_visual.play_hit(dmg, blocked)
							)
							await get_tree().create_timer(1.15).timeout
						else:
							atk_visual.play_cluckey_gum_slash(target_pos, func():
								if def_visual:
									var dmg: int = int(event.get("actual_hp_damage", 0))
									var raw_dmg: int = int(event.get("raw_damage", 0))
									var blocked: bool = (dmg == 0 and raw_dmg > 0)
									def_visual.play_hit(dmg, blocked)
							)
							await get_tree().create_timer(0.95).timeout
					# Cocktaro: Star Platinum is summoned for his signature Ora Ora card
					elif card_id == "cocktaro_ora_ora":
						atk_visual.play_cocktaro_stand_attack(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(1.1).timeout
					# Chick Yagami: Ryuk Swoop Execution
					elif card_id == "yagami_chixecution":
						atk_visual.play_yagami_chixecution(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(1.35).timeout
					# Hen-Goku: Kamecock Laser Beam
					elif card_id == "hen_goku_kamecock":
						atk_visual.play_kamecock_beam(target_pos, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(1.05).timeout
					else:
						# Physical close-range dash or Instant Transmission strike
						atk_visual.play_attack(target_pos, vfx_key, func():
							if def_visual:
								var dmg: int = int(event.get("actual_hp_damage", 0))
								var raw_dmg: int = int(event.get("raw_damage", 0))
								var blocked: bool = (dmg == 0 and raw_dmg > 0)
								def_visual.play_hit(dmg, blocked)
						)
						await get_tree().create_timer(0.65).timeout

			CombatEngine.EventType.COUNTER_HIT:
				var attacker_id: int = int(event.get("attacker", 1))
				var atk_visual: RoosterVisual3D = p1_rooster_anchor if attacker_id == 1 else p2_rooster_anchor
				var def_visual: RoosterVisual3D = p2_rooster_anchor if attacker_id == 1 else p1_rooster_anchor
				if atk_visual and def_visual:
					if atk_visual.rooster_data and atk_visual.rooster_data.rooster_id == "cocktaro":
						atk_visual.play_cocktaro_stand_attack(def_visual.global_position, func():
							def_visual.play_hit(int(event.get("damage", 2)))
						)
						await get_tree().create_timer(1.1).timeout
					else:
						atk_visual.play_attack(def_visual.global_position, "oraora", func():
							def_visual.play_hit(int(event.get("damage", 2)))
						)
						await get_tree().create_timer(0.65).timeout

			CombatEngine.EventType.HEAL:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				if visual:
					if visual.rooster_data and visual.rooster_data.rooster_id == "daniel":
						visual.play_daniel_heartbeat_heal(int(event.get("amount", 0)))
						await get_tree().create_timer(0.80).timeout
					elif visual.rooster_data and visual.rooster_data.rooster_id == "nechicko":
						visual.play_nechicko_ketchup_aura(int(event.get("amount", 0)))
						await get_tree().create_timer(1.40).timeout
					else:
						var theme: String = ""
						visual.play_heal(int(event.get("amount", 0)), theme)
						await get_tree().create_timer(0.80).timeout

			CombatEngine.EventType.DOT_APPLY:
				var attacker_id: int = int(event.get("attacker", 1))
				var defender_id: int = int(event.get("defender", 2))
				var atk_visual: RoosterVisual3D = p1_rooster_anchor if attacker_id == 1 else p2_rooster_anchor
				var def_visual: RoosterVisual3D = p1_rooster_anchor if defender_id == 1 else p2_rooster_anchor
				var added_stacks: int = int(event.get("added_stacks", 1))
				if atk_visual and def_visual:
					if atk_visual.rooster_data and atk_visual.rooster_data.rooster_id == "chick_yagami":
						atk_visual.play_yagami_chick_note(def_visual.global_position, def_visual, added_stacks)
						await get_tree().create_timer(1.25).timeout
					else:
						FloatingText3D.spawn(self, def_visual.global_position, "+%d POOP DOT" % added_stacks, Color(0.8, 0.2, 0.8))
						await get_tree().create_timer(0.50).timeout

			CombatEngine.EventType.DOT_TICK:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				if visual:
					var tick_dmg: int = int(event.get("damage", 0))
					visual.play_hit(tick_dmg)
					FloatingText3D.spawn(self, visual.global_position, "POOP TICK -%d" % tick_dmg, Color(0.8, 0.2, 0.8))
				await get_tree().create_timer(0.55).timeout

			CombatEngine.EventType.REVIVE:
				var duelist_id: int = int(event.get("duelist", 1))
				var visual: RoosterVisual3D = p1_rooster_anchor if duelist_id == 1 else p2_rooster_anchor
				
				# Fade away the 3D passive trigger card on the table
				var passive_card: Card3D = p1_passive_card_3d if duelist_id == 1 else p2_passive_card_3d
				if is_instance_valid(passive_card):
					passive_card.play_consume_fade_animation()
					if duelist_id == 1:
						p1_passive_card_3d = null
					else:
						p2_passive_card_3d = null

				if visual:
					if visual.rooster_data and visual.rooster_data.rooster_id == "daniel":
						visual.play_daniel_revive()
						await get_tree().create_timer(1.30).timeout
					else:
						FloatingText3D.spawn(self, visual.global_position, "RETURN BY DEATH!", Color.GOLD, true)
						await get_tree().create_timer(0.75).timeout

			CombatEngine.EventType.MATCH_END:
				var winner_id: int = int(event.get("winner_id", event.get("winner", 0)))
				if winner_id == 1 and p2_rooster_anchor:
					p2_rooster_anchor.play_death()
				elif winner_id == 2 and p1_rooster_anchor:
					p1_rooster_anchor.play_death()
				elif winner_id == -1:
					if p1_rooster_anchor: p1_rooster_anchor.play_death()
					if p2_rooster_anchor: p2_rooster_anchor.play_death()
				await get_tree().create_timer(1.8).timeout

				# Winner celebration crow / hop
				var winner_visual: RoosterVisual3D = p1_rooster_anchor if winner_id == 1 else (p2_rooster_anchor if winner_id == 2 else null)
				if winner_visual and not winner_visual.is_dead and winner_visual.has_method("play_victory_celebration"):
					winner_visual.play_victory_celebration()
					await get_tree().create_timer(1.2).timeout

	# Check if the match concluded or if continuing to next round
	var has_match_ended: bool = false
	for ev in events:
		if int(ev.get("type", -1)) == CombatEngine.EventType.MATCH_END:
			has_match_ended = true
			break

	# If match continues, wait for all impact VFX and animations to settle, then roosters hop back up to their roost stages
	if not has_match_ended:
		# Cooldown settle pause so all floating numbers, hit flinches, and beams are 100% finished
		await get_tree().create_timer(0.45).timeout

		if p1_rooster_anchor and not p1_rooster_anchor.is_dead:
			p1_rooster_anchor.play_return_to_stage()
		if p2_rooster_anchor and not p2_rooster_anchor.is_dead:
			p2_rooster_anchor.play_return_to_stage()
		await get_tree().create_timer(0.6).timeout

	combat_sequence_completed.emit()
