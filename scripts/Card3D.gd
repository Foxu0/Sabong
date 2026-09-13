class_name Card3D
extends Node3D

signal card_clicked(card_data: CardData)
signal card_right_clicked(card_data: CardData)
signal variable_taya_adjusted(new_taya: int)
signal prediction_category_selected(category: String)

const CARD_WIDTH: float = 0.32
const CARD_HEIGHT: float = 0.461 # 750x1080 ratio (1 : 1.44)


var card_data: CardData
var slot_index: int = 0
var is_queued: bool = false
var is_hovered: bool = false
var is_enabled: bool = true
var is_primed: bool = false
var primed_coins: int = 1
var is_busy_animating: bool = false

var front_mesh: MeshInstance3D
var back_mesh: MeshInstance3D
var front_mat: StandardMaterial3D
var back_mat: StandardMaterial3D
var area: Area3D
var collision_shape: CollisionShape3D

var base_pos: Vector3 = Vector3.ZERO
# -90 degrees X: card lies perfectly flat on the table
# +90 degrees Y: card face points toward P1 camera (at +X)
var base_rot: Vector3 = Vector3(-90.0, 90.0, 0.0)
var active_tween: Tween


const BACK_CARD_PATH: String = "res://resources/cards/BackCard.png"
const REPEAT_SYMBOL_PATH: String = "res://resources/ui/repeat_symbol.png"
const PLUS_SYMBOL_PATH: String = "res://resources/ui/plus_symbol.png"
const MINUS_SYMBOL_PATH: String = "res://resources/ui/minus_symbol.png"

var repeat_symbol_mesh: MeshInstance3D
var repeat_symbol_mat: StandardMaterial3D
var repeat_tween: Tween

var variable_taya_root: Node3D = null
var minus_mesh: MeshInstance3D = null
var plus_mesh: MeshInstance3D = null
var taya_label_3d: Label3D = null
var taya_stat_label_3d: Label3D = null
var variable_taya_tween: Tween = null
var max_available_taya: int = 3

var aura_badge_root: Node3D = null
var aura_badge_label: Label3D = null
var aura_border_mat: StandardMaterial3D = null
var aura_plate_mat: StandardMaterial3D = null
var current_aura_stacks: int = 0

var prediction_badge_root: Node3D = null
var prediction_badge_label: Label3D = null
var prediction_border_mat: StandardMaterial3D = null
var prediction_plate_mat: StandardMaterial3D = null
var current_prediction: String = ""

var prediction_menu_root: Node3D = null
var is_prediction_menu_open: bool = false
var opt_attack_root: Node3D = null
var opt_defend_root: Node3D = null
var opt_special_root: Node3D = null
var opt_cancel_root: Node3D = null
var opt_attack_border_mat: StandardMaterial3D = null
var opt_defend_border_mat: StandardMaterial3D = null
var opt_special_border_mat: StandardMaterial3D = null
var opt_cancel_border_mat: StandardMaterial3D = null

func _ready() -> void:
	_build_3d_card()
	if card_data:
		update_card_data(card_data)

func _build_3d_card() -> void:
	# Front Face Quad (faces player at +X when rotated Vector3(-60, 90, 0))
	front_mesh = MeshInstance3D.new()
	var f_quad := QuadMesh.new()
	f_quad.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	front_mesh.mesh = f_quad
	front_mat = StandardMaterial3D.new()
	front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	front_mat.alpha_scissor_threshold = 0.5
	front_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	front_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	front_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	front_mesh.material_override = front_mat
	add_child(front_mesh)

	# Back Face Quad
	back_mesh = MeshInstance3D.new()
	var b_quad := QuadMesh.new()
	b_quad.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	back_mesh.mesh = b_quad
	back_mat = StandardMaterial3D.new()
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	back_mat.alpha_scissor_threshold = 0.5
	back_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	back_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(BACK_CARD_PATH):
		back_mat.albedo_texture = load(BACK_CARD_PATH)
	back_mesh.material_override = back_mat
	back_mesh.position.z = -0.002
	back_mesh.rotation_degrees.y = 180.0
	add_child(back_mesh)

	# Reverse / Repeat Symbol (attached directly onto the card face over artwork)
	repeat_symbol_mesh = MeshInstance3D.new()
	var r_quad := QuadMesh.new()
	r_quad.size = Vector2(CARD_WIDTH * 0.58, CARD_WIDTH * 0.58)
	repeat_symbol_mesh.mesh = r_quad
	repeat_symbol_mat = StandardMaterial3D.new()
	repeat_symbol_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	repeat_symbol_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	repeat_symbol_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	repeat_symbol_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(REPEAT_SYMBOL_PATH):
		repeat_symbol_mat.albedo_texture = load(REPEAT_SYMBOL_PATH)
	repeat_symbol_mat.render_priority = 35
	repeat_symbol_mesh.material_override = repeat_symbol_mat
	repeat_symbol_mesh.position = Vector3(0.0, 0.04, 0.004) # Centered over card artwork
	repeat_symbol_mesh.scale = Vector3.ZERO
	repeat_symbol_mesh.visible = false
	add_child(repeat_symbol_mesh)

	# Variable Taya committed controls (+ and - interactive buttons for DeCluck)
	variable_taya_root = Node3D.new()
	variable_taya_root.name = "VariableTayaRoot"
	variable_taya_root.position = Vector3(0.0, 0.04, 0.005) # Centered over card artwork
	variable_taya_root.scale = Vector3.ZERO
	variable_taya_root.visible = false
	add_child(variable_taya_root)

	# Minus Button Mesh (on left)
	minus_mesh = MeshInstance3D.new()
	minus_mesh.name = "MinusButton"
	var m_quad := QuadMesh.new()
	m_quad.size = Vector2(0.065, 0.065)
	minus_mesh.mesh = m_quad
	var m_mat := StandardMaterial3D.new()
	m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	m_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(MINUS_SYMBOL_PATH):
		m_mat.albedo_texture = load(MINUS_SYMBOL_PATH)
	m_mat.render_priority = 42
	minus_mesh.material_override = m_mat
	minus_mesh.position = Vector3(-0.095, 0.0, 0.002)
	variable_taya_root.add_child(minus_mesh)

	# Plus Button Mesh (on right)
	plus_mesh = MeshInstance3D.new()
	plus_mesh.name = "PlusButton"
	var p_quad := QuadMesh.new()
	p_quad.size = Vector2(0.065, 0.065)
	plus_mesh.mesh = p_quad
	var p_mat := StandardMaterial3D.new()
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(PLUS_SYMBOL_PATH):
		p_mat.albedo_texture = load(PLUS_SYMBOL_PATH)
	p_mat.render_priority = 42
	plus_mesh.material_override = p_mat
	plus_mesh.position = Vector3(0.095, 0.0, 0.002)
	variable_taya_root.add_child(plus_mesh)

	# Center Committed Taya Label (e.g. "1 TAYA", "2 TAYA", "3 TAYA") - Bigger plain white text
	taya_label_3d = Label3D.new()
	taya_label_3d.name = "TayaCountLabel"
	taya_label_3d.font = UIFontStyle.get_anton_font()
	taya_label_3d.font_size = 46
	taya_label_3d.pixel_size = 0.0012
	taya_label_3d.outline_size = 10
	taya_label_3d.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	taya_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)
	taya_label_3d.render_priority = 43
	taya_label_3d.position = Vector3(0.0, 0.028, 0.003)
	taya_label_3d.text = "1 TAYA"
	variable_taya_root.add_child(taya_label_3d)

	# Center Bonus Stat Label (e.g. "1 DMG", "2 DMG", "3 SHIELD") - Bigger plain white text
	taya_stat_label_3d = Label3D.new()
	taya_stat_label_3d.name = "TayaStatLabel"
	taya_stat_label_3d.font = UIFontStyle.get_anton_font()
	taya_stat_label_3d.font_size = 36
	taya_stat_label_3d.pixel_size = 0.0011
	taya_stat_label_3d.outline_size = 8
	taya_stat_label_3d.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	taya_stat_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)
	taya_stat_label_3d.render_priority = 43
	taya_stat_label_3d.position = Vector3(0.0, -0.024, 0.003)
	taya_stat_label_3d.text = "1 DMG"
	variable_taya_root.add_child(taya_stat_label_3d)

	# Demonic Aura Stacks Badge (for Nechicko cards) - Lowest center part of the card
	aura_badge_root = Node3D.new()
	aura_badge_root.name = "DemonicAuraBadge"
	aura_badge_root.position = Vector3(0.0, -0.198, 0.002) # Lowest center part of the card
	aura_badge_root.visible = false
	add_child(aura_badge_root)

	# Border Plate (Sleek crimson accent rim)
	var a_border := MeshInstance3D.new()
	var border_quad := QuadMesh.new()
	border_quad.size = Vector2(0.088, 0.028)
	a_border.mesh = border_quad
	aura_border_mat = StandardMaterial3D.new()
	aura_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_border_mat.albedo_color = Color(0.85, 0.15, 0.18, 0.95)
	aura_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	aura_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aura_border_mat.render_priority = 2
	a_border.material_override = aura_border_mat
	aura_badge_root.add_child(a_border)

	# Inner Obsidian Plate
	var a_plate := MeshInstance3D.new()
	var a_quad := QuadMesh.new()
	a_quad.size = Vector2(0.084, 0.024)
	a_plate.mesh = a_quad
	aura_plate_mat = StandardMaterial3D.new()
	aura_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_plate_mat.albedo_color = Color(0.06, 0.02, 0.03, 0.98) # Dark obsidian inner
	aura_plate_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	aura_plate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aura_plate_mat.render_priority = 3
	a_plate.position = Vector3(0.0, 0.0, 0.0003)
	a_plate.material_override = aura_plate_mat
	aura_badge_root.add_child(a_plate)

	aura_badge_label = Label3D.new()
	aura_badge_label.name = "AuraLabel"
	aura_badge_label.font = UIFontStyle.get_anton_font()
	aura_badge_label.font_size = 24
	aura_badge_label.pixel_size = 0.00075
	aura_badge_label.outline_size = 5
	aura_badge_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	aura_badge_label.modulate = Color(0.98, 0.98, 1.0) # Clean white only
	aura_badge_label.render_priority = 4
	aura_badge_label.position = Vector3(0.0, 0.0, 0.0006)
	aura_badge_label.text = "AURA: 0"
	aura_badge_root.add_child(aura_badge_label)

	# Ryuk's Watch Prediction Badge (for Chick Yagami Ryuk's Watch) - Lowest center part of the card
	prediction_badge_root = Node3D.new()
	prediction_badge_root.name = "PredictionBadge"
	prediction_badge_root.position = Vector3(0.0, -0.198, 0.002)
	prediction_badge_root.visible = false
	add_child(prediction_badge_root)

	var p_border := MeshInstance3D.new()
	var p_border_quad := QuadMesh.new()
	p_border_quad.size = Vector2(0.124, 0.028)
	p_border.mesh = p_border_quad
	prediction_border_mat = StandardMaterial3D.new()
	prediction_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	prediction_border_mat.albedo_color = Color(0.85, 0.15, 0.18, 0.95)
	prediction_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	prediction_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	prediction_border_mat.render_priority = 2
	p_border.material_override = prediction_border_mat
	prediction_badge_root.add_child(p_border)

	var p_plate := MeshInstance3D.new()
	var p_plate_quad := QuadMesh.new()
	p_plate_quad.size = Vector2(0.120, 0.024)
	p_plate.mesh = p_plate_quad
	prediction_plate_mat = StandardMaterial3D.new()
	prediction_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	prediction_plate_mat.albedo_color = Color(0.06, 0.02, 0.03, 0.98) # Dark obsidian inner
	prediction_plate_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	prediction_plate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	prediction_plate_mat.render_priority = 3
	p_plate.position = Vector3(0.0, 0.0, 0.0003)
	p_plate.material_override = prediction_plate_mat
	prediction_badge_root.add_child(p_plate)

	prediction_badge_label = Label3D.new()
	prediction_badge_label.name = "PredictionLabel"
	prediction_badge_label.font = UIFontStyle.get_anton_font()
	prediction_badge_label.font_size = 20
	prediction_badge_label.pixel_size = 0.00075
	prediction_badge_label.outline_size = 5
	prediction_badge_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	prediction_badge_label.modulate = Color(0.98, 0.98, 1.0)
	prediction_badge_label.render_priority = 4
	prediction_badge_label.position = Vector3(0.0, 0.0, 0.0006)
	prediction_badge_label.text = "CLICK TO PREDICT"
	prediction_badge_root.add_child(prediction_badge_label)

	_build_prediction_menu()

	# Interactive Area3D (generous hitbox)
	area = Area3D.new()
	collision_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CARD_WIDTH * 1.1, CARD_HEIGHT * 1.1, 0.08)
	collision_shape.shape = box
	area.add_child(collision_shape)
	add_child(area)

	area.input_event.connect(_on_area_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)

func set_demonic_aura(count: int) -> void:
	current_aura_stacks = count
	_refresh_demonic_aura_display()

func _refresh_demonic_aura_display() -> void:
	if not aura_badge_root or not is_instance_valid(aura_badge_root):
		return
	if card_data and (card_data.character_id == "nechicko" or card_data.card_id.begins_with("nechicko_")):
		aura_badge_label.text = "AURA: %d" % current_aura_stacks
		aura_badge_root.visible = true
	else:
		aura_badge_root.visible = false

func set_secret_prediction(pred: String) -> void:
	current_prediction = pred.to_upper()
	_refresh_prediction_display()

func _refresh_prediction_display() -> void:
	if not prediction_badge_root or not is_instance_valid(prediction_badge_root):
		return
	if card_data and card_data.card_id == "yagami_ryuks_watch":
		if current_prediction == "":
			prediction_badge_label.text = "CLICK TO PREDICT"
			if prediction_border_mat:
				prediction_border_mat.albedo_color = Color(0.85, 0.65, 0.15, 0.95)
		else:
			prediction_badge_label.text = "PREDICT: %s" % current_prediction
			if prediction_border_mat:
				match current_prediction:
					"ATTACK":
						prediction_border_mat.albedo_color = Color(0.85, 0.15, 0.18, 0.95)
					"DEFEND", "GUARD":
						prediction_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
					"SPECIAL":
						prediction_border_mat.albedo_color = Color(0.65, 0.20, 0.95, 0.95)
					_:
						prediction_border_mat.albedo_color = Color(0.85, 0.65, 0.15, 0.95)
		prediction_badge_root.visible = true
	else:
		prediction_badge_root.visible = false

func _update_aura_badge_render_priority(base_pri: int) -> void:
	if aura_border_mat:
		aura_border_mat.render_priority = base_pri + 1
	if aura_plate_mat:
		aura_plate_mat.render_priority = base_pri + 2
	if aura_badge_label:
		aura_badge_label.render_priority = base_pri + 3
	if prediction_border_mat:
		prediction_border_mat.render_priority = base_pri + 1
	if prediction_plate_mat:
		prediction_plate_mat.render_priority = base_pri + 2
	if prediction_badge_label:
		prediction_badge_label.render_priority = base_pri + 3

func update_card_data(data: CardData) -> void:
	var prev_data: CardData = card_data
	card_data = data
	if prev_data != data:
		force_reset_hover()
	_refresh_demonic_aura_display()
	_refresh_prediction_display()
	if not front_mat:
		return
	if card_data and card_data.art_path != "" and ResourceLoader.exists(card_data.art_path):
		front_mat.albedo_texture = load(card_data.art_path)

func force_reset_hover() -> void:
	if is_hovered:
		is_hovered = false
		if minus_mesh:
			minus_mesh.scale = Vector3.ONE
		if plus_mesh:
			plus_mesh.scale = Vector3.ONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_animate_state()

func set_slot_position(pos: Vector3, rot: Vector3 = Vector3(-90.0, 90.0, 0.0)) -> void:
	base_pos = pos
	base_rot = rot
	position = pos
	rotation_degrees = rot
	is_hovered = false
	var base_pri: int = slot_index * 4 + 1
	if front_mat:
		front_mat.render_priority = base_pri
	if back_mat:
		back_mat.render_priority = base_pri
	_update_aura_badge_render_priority(base_pri)

func set_queued_state(queued: bool) -> void:
	is_queued = queued
	if is_queued:
		is_primed = false
		is_hovered = false
	_animate_state()

func set_primed_state(primed: bool, committed_coins: int = 1, max_taya: int = 3) -> void:
	is_primed = primed
	primed_coins = committed_coins
	max_available_taya = max_taya
	_update_variable_taya_display()
	_animate_state()

func set_enabled_state(enabled: bool) -> void:
	is_enabled = enabled
	if front_mat and not is_primed and not is_queued:
		front_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0) if is_enabled else Color(0.45, 0.45, 0.45, 1.0)

func _animate_state() -> void:
	if is_busy_animating:
		return
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	active_tween = create_tween()
	if active_tween:
		active_tween.set_parallel(true)
	
	var target_pos: Vector3 = base_pos
	var target_rot: Vector3 = base_rot
	var target_scale: Vector3 = Vector3.ONE

	if is_prediction_menu_open:
		# Lift high and tilt forward into player focus for prediction menu
		target_pos.y = base_pos.y + 0.22
		target_pos.x = base_pos.x + 0.04
		target_rot.x = -55.0
		target_scale = Vector3(1.18, 1.18, 1.18)
		var base_pri: int = 28
		if front_mat:
			front_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			front_mat.render_priority = base_pri
		if back_mat:
			back_mat.render_priority = base_pri
		_update_aura_badge_render_priority(base_pri)
	elif is_primed:
		# Lift up and tilt forward into player focus
		target_pos.y = base_pos.y + 0.18
		target_pos.x = base_pos.x + 0.03
		target_rot.x = -60.0
		target_scale = Vector3(1.15, 1.15, 1.15)
		var base_pri: int = 25
		if front_mat:
			front_mat.albedo_color = Color(0.75, 1.25, 0.85, 1.0) # Emerald highlight
			front_mat.render_priority = base_pri
		if back_mat:
			back_mat.render_priority = base_pri
		_update_aura_badge_render_priority(base_pri)
	elif is_queued:
		# Lift high in the air and tilt toward player with plenty of table clearance
		target_pos.y = base_pos.y + 0.20
		target_pos.x = base_pos.x + 0.03
		target_rot.x = -55.0
		target_scale = Vector3(1.12, 1.12, 1.12)
		var base_pri: int = 25
		if front_mat:
			front_mat.albedo_color = Color(1.3, 1.2, 0.7, 1.0) # Golden glow
			front_mat.render_priority = base_pri
		if back_mat:
			back_mat.render_priority = base_pri
		_update_aura_badge_render_priority(base_pri)
	elif is_hovered and is_enabled:
		if slot_index >= 10:
			# Passive card on table: subtle highlight and slight lift
			target_pos.y = base_pos.y + 0.04
			target_rot = base_rot
			target_scale = Vector3(1.08, 1.08, 1.08)
		else:
			# Hand card inspection
			target_pos.y = base_pos.y + 0.22
			target_pos.x = base_pos.x + 0.04
			target_rot.x = -55.0
			target_scale = Vector3(1.15, 1.15, 1.15)
		var base_pri: int = 30
		if front_mat:
			front_mat.albedo_color = Color(1.15, 1.15, 1.25, 1.0)
			front_mat.render_priority = base_pri
		if back_mat:
			back_mat.render_priority = base_pri
		_update_aura_badge_render_priority(base_pri)
	else:
		var base_pri: int = slot_index * 4 + 1
		if front_mat:
			front_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0) if is_enabled else Color(0.45, 0.45, 0.45, 1.0)
			front_mat.render_priority = base_pri
		if back_mat:
			back_mat.render_priority = base_pri
		_update_aura_badge_render_priority(base_pri)



	if is_hovered and is_enabled and _is_mulligan_or_rolling_phase() and not is_queued and not is_primed:
		_show_repeat_symbol(true)
	else:
		_show_repeat_symbol(false)

	var is_var_cost: bool = card_data != null and card_data.is_variable_cost and slot_index < 10
	if is_var_cost and _is_fighting_phase() and not is_queued and (is_hovered or is_primed):
		_show_variable_taya_controls(true)
	else:
		_show_variable_taya_controls(false)

	active_tween.tween_property(self, "position", target_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "rotation_degrees", target_rot, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "scale", target_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _is_fighting_phase() -> bool:
	if slot_index >= 10:
		return false
	if not is_inside_tree():
		return true
	var tree := get_tree()
	if not tree or not tree.root:
		return true
	var match_ui = tree.root.find_child("MatchUI", true, false)
	if match_ui:
		if match_ui.get("phase_manager") and match_ui.phase_manager:
			return match_ui.phase_manager.current_phase == DuelPhase.Phase.FIGHTING
		return false
	return true

func _get_player_taya_remaining() -> int:
	if not is_inside_tree():
		return 3
	var tree := get_tree()
	if tree and tree.root:
		var match_ui = tree.root.find_child("MatchUI", true, false)
		if match_ui and match_ui.get("player") and match_ui.player:
			return match_ui.player.taya_remaining
	return 3

func _update_variable_taya_display() -> void:
	if not card_data or not card_data.is_variable_cost:
		return
	if not taya_label_3d or not taya_stat_label_3d:
		return

	if not is_primed and max_available_taya <= 1:
		max_available_taya = _get_player_taya_remaining()

	taya_label_3d.text = "%d TAYA" % primed_coins

	var extra: int = primed_coins - card_data.taya_cost
	var is_all_for_one_active: bool = false
	var bonus_flat_atk: int = 0
	if is_inside_tree():
		var tree := get_tree()
		if tree and tree.root:
			var match_ui = tree.root.find_child("MatchUI", true, false)
			if match_ui and match_ui.get("player") and match_ui.player:
				is_all_for_one_active = match_ui.player.all_for_one_active
				bonus_flat_atk = match_ui.player.bonus_flat_attack

	var per_taya: int = 4 if is_all_for_one_active else card_data.value_per_taya
	var total_val: int = card_data.base_value + extra * per_taya

	taya_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if card_data.card_type == CardData.CardType.ATTACK:
		total_val += bonus_flat_atk
		taya_stat_label_3d.text = "%d DMG" % total_val
	else:
		taya_stat_label_3d.text = "%d SHIELD" % total_val
	taya_stat_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if minus_mesh and minus_mesh.material_override is StandardMaterial3D:
		var can_minus: bool = primed_coins > card_data.taya_cost
		(minus_mesh.material_override as StandardMaterial3D).albedo_color = Color(1.0, 1.0, 1.0, 1.0) if can_minus else Color(0.75, 0.75, 0.75, 0.45)
	if plus_mesh and plus_mesh.material_override is StandardMaterial3D:
		var can_plus: bool = primed_coins < max_available_taya
		(plus_mesh.material_override as StandardMaterial3D).albedo_color = Color(1.0, 1.0, 1.0, 1.0) if can_plus else Color(0.75, 0.75, 0.75, 0.45)

func _show_variable_taya_controls(show: bool) -> void:
	if not variable_taya_root:
		return
	if variable_taya_tween and variable_taya_tween.is_valid():
		variable_taya_tween.kill()
		variable_taya_tween = null

	if show:
		_update_variable_taya_display()
		variable_taya_root.visible = true
		variable_taya_tween = create_tween()
		if variable_taya_tween:
			variable_taya_tween.tween_property(variable_taya_root, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if variable_taya_root.visible:
			variable_taya_tween = create_tween()
			if variable_taya_tween:
				variable_taya_tween.tween_property(variable_taya_root, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_QUAD)
				variable_taya_tween.chain().tween_callback(func():
					if is_instance_valid(variable_taya_root) and not is_hovered and not is_primed:
						variable_taya_root.visible = false
				)

func _on_plus_button_clicked() -> void:
	if not is_primed and max_available_taya <= 1:
		max_available_taya = _get_player_taya_remaining()
	if primed_coins < max_available_taya:
		primed_coins += 1
		_pulse_button(plus_mesh)
		_update_variable_taya_display()
		variable_taya_adjusted.emit(primed_coins)

func _on_minus_button_clicked() -> void:
	var min_cost: int = card_data.taya_cost if card_data else 1
	if primed_coins > min_cost:
		primed_coins -= 1
		_pulse_button(minus_mesh)
		_update_variable_taya_display()
		variable_taya_adjusted.emit(primed_coins)

func _pulse_button(btn: MeshInstance3D) -> void:
	if not btn:
		return
	var tw := create_tween()
	if tw:
		tw.tween_property(btn, "scale", Vector3(1.35, 1.35, 1.35), 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(btn, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _is_mulligan_or_rolling_phase() -> bool:
	if not is_inside_tree() or slot_index >= 10:
		return false
	var tree := get_tree()
	if not tree or not tree.root:
		return false
	var match_ui = tree.root.find_child("MatchUI", true, false)
	if match_ui and match_ui.get("phase_manager"):
		var pm = match_ui.phase_manager
		if pm:
			return pm.current_phase == DuelPhase.Phase.REROLL or pm.current_phase == DuelPhase.Phase.DICE_ROLL
	return false

func _show_repeat_symbol(show: bool) -> void:
	if not repeat_symbol_mesh:
		return
	if repeat_tween and repeat_tween.is_valid():
		repeat_tween.kill()
		repeat_tween = null

	if show:
		repeat_symbol_mesh.visible = true
		repeat_symbol_mesh.scale = Vector3.ZERO
		repeat_symbol_mesh.rotation_degrees.z = -35.0
		repeat_tween = create_tween()
		if repeat_tween:
			repeat_tween.set_parallel(true)
			repeat_tween.tween_property(repeat_symbol_mesh, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			repeat_tween.tween_property(repeat_symbol_mesh, "rotation_degrees:z", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if repeat_symbol_mesh.visible:
			repeat_tween = create_tween()
			if repeat_tween:
				repeat_tween.tween_property(repeat_symbol_mesh, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_QUAD)
				repeat_tween.chain().tween_callback(func():
					if is_instance_valid(repeat_symbol_mesh) and not is_hovered:
						repeat_symbol_mesh.visible = false
				)


func _on_mouse_entered() -> void:
	if is_busy_animating:
		return
	is_hovered = true
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	_animate_state()

func _on_mouse_exited() -> void:
	if is_busy_animating:
		return
	is_hovered = false
	if minus_mesh:
		minus_mesh.scale = Vector3.ONE
	if plus_mesh:
		plus_mesh.scale = Vector3.ONE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_animate_state()

func _on_area_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _shape_idx: int) -> void:
	if is_prediction_menu_open:
		var local_pos: Vector3 = to_local(_pos) if is_inside_tree() else _pos
		var click_2d := Vector2(local_pos.x, local_pos.y)
		var rel_x: float = click_2d.x
		var rel_y: float = click_2d.y - 0.03

		if event is InputEventMouseMotion:
			_update_prediction_hover(rel_x, rel_y)
			return

		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if absf(rel_x) <= 0.13:
					if rel_y >= 0.030 and rel_y <= 0.080:
						_on_prediction_button_clicked("ATTACK")
						_safe_set_input_handled()
						return
					elif rel_y >= -0.030 and rel_y <= 0.020:
						_on_prediction_button_clicked("DEFEND")
						_safe_set_input_handled()
						return
					elif rel_y >= -0.090 and rel_y <= -0.040:
						_on_prediction_button_clicked("SPECIAL")
						_safe_set_input_handled()
						return
				if absf(rel_x) <= 0.08 and rel_y >= -0.135 and rel_y <= -0.100:
					close_prediction_menu()
					_safe_set_input_handled()
					return
				# Clicking elsewhere on card closes prediction menu
				close_prediction_menu()
				_safe_set_input_handled()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				close_prediction_menu()
				_safe_set_input_handled()
				return

	if event is InputEventMouseMotion and (is_hovered or is_primed) and card_data and card_data.is_variable_cost and _is_fighting_phase():
		var local_pos: Vector3 = to_local(_pos) if is_inside_tree() else _pos
		var minus_center := Vector2(-0.095, 0.04)
		var plus_center := Vector2(0.095, 0.04)
		var click_2d := Vector2(local_pos.x, local_pos.y)
		if minus_mesh:
			var hovering_minus: bool = click_2d.distance_to(minus_center) <= 0.048
			minus_mesh.scale = Vector3(1.15, 1.15, 1.15) if hovering_minus else Vector3.ONE
		if plus_mesh:
			var hovering_plus: bool = click_2d.distance_to(plus_center) <= 0.048
			plus_mesh.scale = Vector3(1.15, 1.15, 1.15) if hovering_plus else Vector3.ONE

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if card_data and card_data.is_variable_cost and (is_primed or is_hovered) and _is_fighting_phase():
				var local_pos: Vector3 = to_local(_pos) if is_inside_tree() else _pos
				var minus_center := Vector2(-0.095, 0.04)
				var plus_center := Vector2(0.095, 0.04)
				var click_2d := Vector2(local_pos.x, local_pos.y)
				if click_2d.distance_to(minus_center) <= 0.048:
					if not is_primed:
						card_clicked.emit(card_data)
					_on_minus_button_clicked()
					_safe_set_input_handled()
					return
				elif click_2d.distance_to(plus_center) <= 0.048:
					if not is_primed:
						card_clicked.emit(card_data)
					_on_plus_button_clicked()
					_safe_set_input_handled()
					return

			# Clicking on the card except on the - / + symbol confirms / consumes it!
			card_clicked.emit(card_data)
			_safe_set_input_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			card_right_clicked.emit(card_data)
			_safe_set_input_handled()

func _safe_set_input_handled() -> void:
	if is_inside_tree():
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


## Animates drawing from the facedown deck stack onto this slot
func play_draw_animation(from_pos: Vector3, delay: float = 0.0) -> void:
	is_busy_animating = true
	is_hovered = false
	if area:
		area.input_ray_pickable = false

	position = from_pos + Vector3(0.0, 0.01, 0.0)
	# Start flat and facedown (back facing up = 90 Y rotated 180 from face-up)
	rotation_degrees = Vector3(-90.0, 90.0, 180.0)
	scale = Vector3(0.85, 0.85, 0.85)
	
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	active_tween = create_tween()
	if delay > 0:
		active_tween.tween_interval(delay)
		
	# Arc up slightly and flip face-up onto table slot
	var mid_pos := (from_pos + base_pos) * 0.5 + Vector3(0.08, 0.14, 0.0)
	active_tween.tween_property(self, "position", mid_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "rotation_degrees", Vector3(-90.0, 90.0, 90.0), 0.14)
	active_tween.parallel().tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.14)
	
	active_tween.tween_property(self, "position", base_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
	active_tween.parallel().tween_property(self, "scale", Vector3.ONE, 0.14)

	active_tween.chain().tween_callback(func():
		is_busy_animating = false
		if area:
			area.input_ray_pickable = true
		_animate_state()
	)

## Animates card transformation in-place on the tabletop (e.g. Claw Stomp <-> Titan Stomp)
func play_transform_animation(delay: float = 0.0) -> void:
	is_busy_animating = true
	is_hovered = false
	if area:
		area.input_ray_pickable = false

	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	active_tween = create_tween()
	if delay > 0.0:
		active_tween.tween_interval(delay)

	# Phase 1: Lift up, flip 180 degrees with golden/crimson energy flash
	var peak_pos: Vector3 = base_pos + Vector3(0.0, 0.16, 0.0)
	var peak_rot: Vector3 = base_rot + Vector3(0.0, 180.0, 0.0)
	active_tween.tween_property(self, "position", peak_pos, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "rotation_degrees", peak_rot, 0.16)
	active_tween.parallel().tween_property(self, "scale", Vector3(1.22, 1.22, 1.22), 0.16)
	if front_mat:
		active_tween.parallel().tween_property(front_mat, "albedo_color", Color(1.8, 1.3, 0.6, 1.0), 0.16)

	# Phase 2: Snap back down into table slot with normal color
	active_tween.tween_property(self, "position", base_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
	active_tween.parallel().tween_property(self, "scale", Vector3.ONE, 0.14)
	if front_mat:
		active_tween.parallel().tween_property(front_mat, "albedo_color", Color.WHITE, 0.14)

	active_tween.chain().tween_callback(func():
		is_busy_animating = false
		if area:
			area.input_ray_pickable = true
		_animate_state()
	)

## Animates rerolling this card: tosses to discard, then draws fresh replacement from deck
func play_reroll_animation(from_pos: Vector3, new_data: CardData) -> void:
	is_busy_animating = true
	is_hovered = false
	if area:
		area.input_ray_pickable = false
	if repeat_symbol_mesh:
		repeat_symbol_mesh.visible = false

	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	active_tween = create_tween()

	# Phase 1: Card lifts and tosses toward the discard pile
	var discard_toss := position + Vector3(0.0, 0.12, -0.38)
	active_tween.tween_property(self, "position", discard_toss, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "scale", Vector3(0.65, 0.65, 0.65), 0.12)
	active_tween.parallel().tween_property(self, "rotation_degrees:y", rotation_degrees.y + 35.0, 0.12)

	# Phase 2: Teleport to deck position, facedown, load new card texture
	active_tween.chain().tween_callback(func():
		update_card_data(new_data)
		position = from_pos + Vector3(0.0, 0.015, 0.0)
		rotation_degrees = Vector3(-90.0, 90.0, 180.0)
		scale = Vector3(0.85, 0.85, 0.85)
	)

	# Phase 3: Arc up from deck, flip face-up, and settle onto table slot
	var mid_pos := (from_pos + base_pos) * 0.5 + Vector3(0.08, 0.16, 0.0)
	active_tween.tween_property(self, "position", mid_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "rotation_degrees", Vector3(-90.0, 90.0, 90.0), 0.15)
	active_tween.parallel().tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.15)

	active_tween.tween_property(self, "position", base_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
	active_tween.parallel().tween_property(self, "scale", Vector3.ONE, 0.14)

	active_tween.chain().tween_callback(func():
		is_busy_animating = false
		if area:
			area.input_ray_pickable = true
		_animate_state()
	)


## Animates discarding this card off the table
func play_discard_animation(discard_pos: Vector3) -> void:
	is_busy_animating = true
	is_hovered = false
	is_enabled = false
	is_queued = false
	is_primed = false
	if area:
		area.input_ray_pickable = false
	if collision_shape:
		collision_shape.disabled = true
	if repeat_symbol_mesh:
		repeat_symbol_mesh.visible = false
	if variable_taya_root:
		variable_taya_root.visible = false
	if prediction_menu_root:
		prediction_menu_root.visible = false

	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	active_tween = create_tween()
	var mid_pos := (position + discard_pos) * 0.5 + Vector3(0.0, 0.14, 0.0)
	active_tween.tween_property(self, "position", mid_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "rotation_degrees:y", rotation_degrees.y + 90.0, 0.15)
	active_tween.parallel().tween_property(self, "scale", Vector3(0.7, 0.7, 0.7), 0.15)
	active_tween.tween_property(self, "position", discard_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "scale", Vector3(0.001, 0.001, 0.001), 0.15)
	active_tween.chain().tween_callback(func():
		if is_inside_tree() and get_parent():
			get_parent().remove_child(self)
		queue_free()
	)

## Animates dissolving / fading away when a passive card is consumed
func play_consume_fade_animation() -> void:
	if active_tween:
		active_tween.kill()
	is_enabled = false
	if area:
		area.input_ray_pickable = false
	
	active_tween = create_tween()
	# Lift slightly, glow violet/white, dissolve into transparency, and scale down
	active_tween.tween_property(self, "position:y", position.y + 0.12, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "scale", Vector3(1.15, 1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK)
	if front_mat:
		front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		active_tween.parallel().tween_property(front_mat, "albedo_color", Color(1.5, 0.4, 1.5, 0.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if back_mat:
		back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		active_tween.parallel().tween_property(back_mat, "albedo_color", Color(1.5, 0.4, 1.5, 0.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.chain().tween_callback(queue_free)

func _build_prediction_menu() -> void:
	prediction_menu_root = Node3D.new()
	prediction_menu_root.name = "PredictionMenuRoot"
	prediction_menu_root.position = Vector3(0.0, 0.03, 0.006)
	prediction_menu_root.scale = Vector3.ZERO
	prediction_menu_root.visible = false
	add_child(prediction_menu_root)

	# Dark Obsidian Dimmer / Backdrop Quad
	var dimmer := MeshInstance3D.new()
	var d_quad := QuadMesh.new()
	d_quad.size = Vector2(0.284, 0.320)
	dimmer.mesh = d_quad
	var d_mat := StandardMaterial3D.new()
	d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	d_mat.albedo_color = Color(0.05, 0.03, 0.08, 0.94)
	d_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	d_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	d_mat.render_priority = 44
	dimmer.material_override = d_mat
	dimmer.position = Vector3(0.0, 0.0, 0.0002)
	prediction_menu_root.add_child(dimmer)

	# Header: PREDICT MOVE
	var header_lbl := Label3D.new()
	header_lbl.name = "PredictHeader"
	header_lbl.font = UIFontStyle.get_anton_font()
	header_lbl.font_size = 22
	header_lbl.pixel_size = 0.00085
	header_lbl.outline_size = 5
	header_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	header_lbl.modulate = Color(1.0, 0.85, 0.25)
	header_lbl.render_priority = 47
	header_lbl.position = Vector3(0.0, 0.128, 0.001)
	header_lbl.text = "PREDICT MOVE"
	prediction_menu_root.add_child(header_lbl)

	# Subtitle: CHOOSE OPPONENT CATEGORY
	var sub_lbl := Label3D.new()
	sub_lbl.name = "PredictSubtitle"
	sub_lbl.font = UIFontStyle.get_anton_font()
	sub_lbl.font_size = 13
	sub_lbl.pixel_size = 0.00065
	sub_lbl.outline_size = 4
	sub_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	sub_lbl.modulate = Color(0.85, 0.85, 0.92)
	sub_lbl.render_priority = 47
	sub_lbl.position = Vector3(0.0, 0.106, 0.001)
	sub_lbl.text = "CHOOSE OPPONENT CATEGORY"
	prediction_menu_root.add_child(sub_lbl)

	# 1. ATTACK Option
	opt_attack_root = Node3D.new()
	opt_attack_root.name = "OptAttack"
	opt_attack_root.position = Vector3(0.0, 0.055, 0.001)
	prediction_menu_root.add_child(opt_attack_root)

	var att_border := MeshInstance3D.new()
	var att_b_quad := QuadMesh.new()
	att_b_quad.size = Vector2(0.250, 0.046)
	att_border.mesh = att_b_quad
	opt_attack_border_mat = StandardMaterial3D.new()
	opt_attack_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	opt_attack_border_mat.albedo_color = Color(0.88, 0.15, 0.20, 0.95)
	opt_attack_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	opt_attack_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	opt_attack_border_mat.render_priority = 45
	att_border.material_override = opt_attack_border_mat
	opt_attack_root.add_child(att_border)

	var att_plate := MeshInstance3D.new()
	var att_p_quad := QuadMesh.new()
	att_p_quad.size = Vector2(0.244, 0.040)
	att_plate.mesh = att_p_quad
	var att_p_mat := StandardMaterial3D.new()
	att_p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	att_p_mat.albedo_color = Color(0.12, 0.04, 0.06, 0.96)
	att_p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	att_p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	att_p_mat.render_priority = 46
	att_plate.material_override = att_p_mat
	att_plate.position = Vector3(0.0, 0.0, 0.0003)
	opt_attack_root.add_child(att_plate)

	var att_title := Label3D.new()
	att_title.font = UIFontStyle.get_anton_font()
	att_title.font_size = 24
	att_title.pixel_size = 0.00095
	att_title.outline_size = 5
	att_title.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	att_title.modulate = Color(1.0, 1.0, 1.0)
	att_title.render_priority = 47
	att_title.position = Vector3(0.0, 0.006, 0.0006)
	att_title.text = "ATTACK"
	opt_attack_root.add_child(att_title)

	var att_sub := Label3D.new()
	att_sub.font = UIFontStyle.get_anton_font()
	att_sub.font_size = 12
	att_sub.pixel_size = 0.0006
	att_sub.outline_size = 4
	att_sub.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	att_sub.modulate = Color(0.92, 0.65, 0.68)
	att_sub.render_priority = 47
	att_sub.position = Vector3(0.0, -0.010, 0.0006)
	att_sub.text = "(ATTACK & DOT)"
	opt_attack_root.add_child(att_sub)

	# 2. DEFEND Option
	opt_defend_root = Node3D.new()
	opt_defend_root.name = "OptDefend"
	opt_defend_root.position = Vector3(0.0, -0.005, 0.001)
	prediction_menu_root.add_child(opt_defend_root)

	var def_border := MeshInstance3D.new()
	var def_b_quad := QuadMesh.new()
	def_b_quad.size = Vector2(0.250, 0.046)
	def_border.mesh = def_b_quad
	opt_defend_border_mat = StandardMaterial3D.new()
	opt_defend_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	opt_defend_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
	opt_defend_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	opt_defend_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	opt_defend_border_mat.render_priority = 45
	def_border.material_override = opt_defend_border_mat
	opt_defend_root.add_child(def_border)

	var def_plate := MeshInstance3D.new()
	var def_p_quad := QuadMesh.new()
	def_p_quad.size = Vector2(0.244, 0.040)
	def_plate.mesh = def_p_quad
	var def_p_mat := StandardMaterial3D.new()
	def_p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	def_p_mat.albedo_color = Color(0.04, 0.08, 0.14, 0.96)
	def_p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	def_p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	def_p_mat.render_priority = 46
	def_plate.material_override = def_p_mat
	def_plate.position = Vector3(0.0, 0.0, 0.0003)
	opt_defend_root.add_child(def_plate)

	var def_title := Label3D.new()
	def_title.font = UIFontStyle.get_anton_font()
	def_title.font_size = 24
	def_title.pixel_size = 0.00095
	def_title.outline_size = 5
	def_title.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	def_title.modulate = Color(1.0, 1.0, 1.0)
	def_title.render_priority = 47
	def_title.position = Vector3(0.0, 0.006, 0.0006)
	def_title.text = "DEFEND"
	opt_defend_root.add_child(def_title)

	var def_sub := Label3D.new()
	def_sub.font = UIFontStyle.get_anton_font()
	def_sub.font_size = 12
	def_sub.pixel_size = 0.0006
	def_sub.outline_size = 4
	def_sub.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	def_sub.modulate = Color(0.65, 0.82, 0.95)
	def_sub.render_priority = 47
	def_sub.position = Vector3(0.0, -0.010, 0.0006)
	def_sub.text = "(SHIELD & HEAL)"
	opt_defend_root.add_child(def_sub)

	# 3. SPECIAL Option
	opt_special_root = Node3D.new()
	opt_special_root.name = "OptSpecial"
	opt_special_root.position = Vector3(0.0, -0.065, 0.001)
	prediction_menu_root.add_child(opt_special_root)

	var spe_border := MeshInstance3D.new()
	var spe_b_quad := QuadMesh.new()
	spe_b_quad.size = Vector2(0.250, 0.046)
	spe_border.mesh = spe_b_quad
	opt_special_border_mat = StandardMaterial3D.new()
	opt_special_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	opt_special_border_mat.albedo_color = Color(0.68, 0.20, 0.95, 0.95)
	opt_special_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	opt_special_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	opt_special_border_mat.render_priority = 45
	spe_border.material_override = opt_special_border_mat
	opt_special_root.add_child(spe_border)

	var spe_plate := MeshInstance3D.new()
	var spe_p_quad := QuadMesh.new()
	spe_p_quad.size = Vector2(0.244, 0.040)
	spe_plate.mesh = spe_p_quad
	var spe_p_mat := StandardMaterial3D.new()
	spe_p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spe_p_mat.albedo_color = Color(0.08, 0.04, 0.14, 0.96)
	spe_p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	spe_p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spe_p_mat.render_priority = 46
	spe_plate.material_override = spe_p_mat
	spe_plate.position = Vector3(0.0, 0.0, 0.0003)
	opt_special_root.add_child(spe_plate)

	var spe_title := Label3D.new()
	spe_title.font = UIFontStyle.get_anton_font()
	spe_title.font_size = 24
	spe_title.pixel_size = 0.00095
	spe_title.outline_size = 5
	spe_title.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	spe_title.modulate = Color(1.0, 1.0, 1.0)
	spe_title.render_priority = 47
	spe_title.position = Vector3(0.0, 0.006, 0.0006)
	spe_title.text = "SPECIAL"
	opt_special_root.add_child(spe_title)

	var spe_sub := Label3D.new()
	spe_sub.font = UIFontStyle.get_anton_font()
	spe_sub.font_size = 12
	spe_sub.pixel_size = 0.0006
	spe_sub.outline_size = 4
	spe_sub.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	spe_sub.modulate = Color(0.85, 0.68, 0.95)
	spe_sub.render_priority = 47
	spe_sub.position = Vector3(0.0, -0.010, 0.0006)
	spe_sub.text = "(SPECIAL & BUFF)"
	opt_special_root.add_child(spe_sub)

	# 4. CANCEL Button
	opt_cancel_root = Node3D.new()
	opt_cancel_root.name = "OptCancel"
	opt_cancel_root.position = Vector3(0.0, -0.118, 0.001)
	prediction_menu_root.add_child(opt_cancel_root)

	var can_border := MeshInstance3D.new()
	var can_b_quad := QuadMesh.new()
	can_b_quad.size = Vector2(0.140, 0.026)
	can_border.mesh = can_b_quad
	opt_cancel_border_mat = StandardMaterial3D.new()
	opt_cancel_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	opt_cancel_border_mat.albedo_color = Color(0.40, 0.40, 0.45, 0.80)
	opt_cancel_border_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	opt_cancel_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	opt_cancel_border_mat.render_priority = 45
	can_border.material_override = opt_cancel_border_mat
	opt_cancel_root.add_child(can_border)

	var can_title := Label3D.new()
	can_title.font = UIFontStyle.get_anton_font()
	can_title.font_size = 15
	can_title.pixel_size = 0.0007
	can_title.outline_size = 4
	can_title.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	can_title.modulate = Color(0.75, 0.75, 0.80)
	can_title.render_priority = 47
	can_title.position = Vector3(0.0, 0.0, 0.0006)
	can_title.text = "CANCEL"
	opt_cancel_root.add_child(can_title)

func open_prediction_menu() -> void:
	if not card_data or card_data.card_id != "yagami_ryuks_watch":
		return
	is_prediction_menu_open = true
	_animate_state()

	if prediction_menu_root:
		prediction_menu_root.visible = true
		prediction_menu_root.scale = Vector3(0.65, 0.65, 0.65)
		var tw := create_tween()
		tw.tween_property(prediction_menu_root, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_prediction_menu() -> void:
	if not is_prediction_menu_open:
		return
	is_prediction_menu_open = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_animate_state()

	if prediction_menu_root:
		var tw := create_tween()
		tw.tween_property(prediction_menu_root, "scale", Vector3(0.01, 0.01, 0.01), 0.10)
		tw.chain().tween_callback(func():
			if prediction_menu_root and not is_prediction_menu_open:
				prediction_menu_root.visible = false
		)

func _update_prediction_hover(rel_x: float, rel_y: float) -> void:
	if not is_prediction_menu_open:
		return
	var hovered_any: bool = false
	if absf(rel_x) <= 0.13:
		if rel_y >= 0.030 and rel_y <= 0.080: # ATTACK
			hovered_any = true
			if opt_attack_root: opt_attack_root.scale = Vector3(1.05, 1.05, 1.05)
			if opt_defend_root: opt_defend_root.scale = Vector3.ONE
			if opt_special_root: opt_special_root.scale = Vector3.ONE
			if opt_cancel_root: opt_cancel_root.scale = Vector3.ONE
			if opt_attack_border_mat: opt_attack_border_mat.albedo_color = Color(1.0, 0.30, 0.35, 1.0)
			if opt_defend_border_mat: opt_defend_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
			if opt_special_border_mat: opt_special_border_mat.albedo_color = Color(0.68, 0.20, 0.95, 0.95)
			if opt_cancel_border_mat: opt_cancel_border_mat.albedo_color = Color(0.40, 0.40, 0.45, 0.80)
		elif rel_y >= -0.030 and rel_y <= 0.020: # DEFEND
			hovered_any = true
			if opt_attack_root: opt_attack_root.scale = Vector3.ONE
			if opt_defend_root: opt_defend_root.scale = Vector3(1.05, 1.05, 1.05)
			if opt_special_root: opt_special_root.scale = Vector3.ONE
			if opt_cancel_root: opt_cancel_root.scale = Vector3.ONE
			if opt_attack_border_mat: opt_attack_border_mat.albedo_color = Color(0.88, 0.15, 0.20, 0.95)
			if opt_defend_border_mat: opt_defend_border_mat.albedo_color = Color(0.35, 0.75, 1.0, 1.0)
			if opt_special_border_mat: opt_special_border_mat.albedo_color = Color(0.68, 0.20, 0.95, 0.95)
			if opt_cancel_border_mat: opt_cancel_border_mat.albedo_color = Color(0.40, 0.40, 0.45, 0.80)
		elif rel_y >= -0.090 and rel_y <= -0.040: # SPECIAL
			hovered_any = true
			if opt_attack_root: opt_attack_root.scale = Vector3.ONE
			if opt_defend_root: opt_defend_root.scale = Vector3.ONE
			if opt_special_root: opt_special_root.scale = Vector3(1.05, 1.05, 1.05)
			if opt_cancel_root: opt_cancel_root.scale = Vector3.ONE
			if opt_attack_border_mat: opt_attack_border_mat.albedo_color = Color(0.88, 0.15, 0.20, 0.95)
			if opt_defend_border_mat: opt_defend_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
			if opt_special_border_mat: opt_special_border_mat.albedo_color = Color(0.85, 0.40, 1.0, 1.0)
			if opt_cancel_border_mat: opt_cancel_border_mat.albedo_color = Color(0.40, 0.40, 0.45, 0.80)
	if not hovered_any and absf(rel_x) <= 0.08 and rel_y >= -0.135 and rel_y <= -0.100: # CANCEL
		hovered_any = true
		if opt_attack_root: opt_attack_root.scale = Vector3.ONE
		if opt_defend_root: opt_defend_root.scale = Vector3.ONE
		if opt_special_root: opt_special_root.scale = Vector3.ONE
		if opt_cancel_root: opt_cancel_root.scale = Vector3(1.06, 1.06, 1.06)
		if opt_attack_border_mat: opt_attack_border_mat.albedo_color = Color(0.88, 0.15, 0.20, 0.95)
		if opt_defend_border_mat: opt_defend_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
		if opt_special_border_mat: opt_special_border_mat.albedo_color = Color(0.68, 0.20, 0.95, 0.95)
		if opt_cancel_border_mat: opt_cancel_border_mat.albedo_color = Color(0.85, 0.35, 0.35, 1.0)
	if not hovered_any:
		if opt_attack_root: opt_attack_root.scale = Vector3.ONE
		if opt_defend_root: opt_defend_root.scale = Vector3.ONE
		if opt_special_root: opt_special_root.scale = Vector3.ONE
		if opt_cancel_root: opt_cancel_root.scale = Vector3.ONE
		if opt_attack_border_mat: opt_attack_border_mat.albedo_color = Color(0.88, 0.15, 0.20, 0.95)
		if opt_defend_border_mat: opt_defend_border_mat.albedo_color = Color(0.15, 0.55, 0.95, 0.95)
		if opt_special_border_mat: opt_special_border_mat.albedo_color = Color(0.68, 0.20, 0.95, 0.95)
		if opt_cancel_border_mat: opt_cancel_border_mat.albedo_color = Color(0.40, 0.40, 0.45, 0.80)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovered_any else Input.CURSOR_ARROW)

func _on_prediction_button_clicked(category: String) -> void:
	close_prediction_menu()
	prediction_category_selected.emit(category)

func _exit_tree() -> void:
	if is_hovered:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	if repeat_tween and repeat_tween.is_valid():
		repeat_tween.kill()
	if variable_taya_tween and variable_taya_tween.is_valid():
		variable_taya_tween.kill()
