extends Control
class_name CardUIElement

## CardUIElement — UNO/Hearthstone style fanned card widget with large readable art, draw animations, and hover zoom.

signal card_clicked(card_data: CardData)
signal card_discard_requested(card_data: CardData)

var card_data: CardData
var is_selected: bool = false
var is_enabled: bool = true

var texture_rect: TextureRect
var anim_tween: Tween
var hover_tween: Tween

# Bigger, readable card dimensions
const CARD_WIDTH: float = 180.0
const CARD_HEIGHT: float = 265.0

var base_fan_rotation: float = 0.0
var base_fan_offset_y: float = 0.0
var target_local_x: float = 0.0

func _init(p_card: CardData = null) -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.85)
	if p_card:
		set_card_data(p_card)

func _ready() -> void:
	_build_widget()
	if card_data:
		_update_display()

func set_card_data(p_card: CardData) -> void:
	card_data = p_card
	if is_inside_tree():
		_update_display()

func _build_widget() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.85)

	# High-res Card Artwork
	texture_rect = TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


static var _tex_cache: Dictionary = {}

func _update_display() -> void:
	if not card_data:
		return

	if card_data.art_path != "":
		if not _tex_cache.has(card_data.art_path):
			if ResourceLoader.exists(card_data.art_path):
				_tex_cache[card_data.art_path] = load(card_data.art_path)
		if _tex_cache.has(card_data.art_path):
			texture_rect.texture = _tex_cache[card_data.art_path]

	tooltip_text = "%s\nCost: %d Taya | Dice: %d+\n%s\n[Right-Click to Discard]" % [card_data.display_name, card_data.taya_cost, card_data.dice_requirement, card_data.effect_text]

## Sets up the UNO/Hearthstone style fanning curvature
func set_fan_transform(card_index: int, total_cards: int) -> void:
	if total_cards <= 1:
		base_fan_rotation = 0.0
		base_fan_offset_y = 0.0
	else:
		var normalized_idx: float = float(card_index) / float(total_cards - 1) - 0.5 # -0.5 to +0.5
		base_fan_rotation = normalized_idx * 16.0 # -8 deg to +8 deg arc
		base_fan_offset_y = abs(normalized_idx) * 16.0 # slight arch

	rotation_degrees = base_fan_rotation
	position.y = base_fan_offset_y

## Smooth, optimized cinematic card deal
func play_draw_animation(delay: float = 0.0) -> void:
	var final_pos_x: float = position.x
	var final_pos_y: float = position.y + base_fan_offset_y
	var final_rot: float   = base_fan_rotation

	position.x = 0.0
	position.y = 260.0
	rotation_degrees = 0.0
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	z_index = 20

	if anim_tween:
		anim_tween.kill()
	anim_tween = create_tween().set_parallel(true)

	anim_tween.tween_property(self, "modulate:a", 1.0, 0.12).set_delay(delay)
	anim_tween.tween_property(self, "position:x", final_pos_x, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	anim_tween.tween_property(self, "position:y", final_pos_y, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	anim_tween.tween_property(self, "rotation_degrees", final_rot, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	anim_tween.tween_property(self, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)

	anim_tween.chain().tween_callback(func(): z_index = 0)

func set_enabled_state(p_enabled: bool) -> void:
	is_enabled = p_enabled
	if not is_selected:
		modulate = Color(1.0, 1.0, 1.0, 1.0) if is_enabled else Color(0.45, 0.45, 0.45, 0.75)

func set_selected_state(p_selected: bool) -> void:
	is_selected = p_selected
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween()
	if hover_tween:
		hover_tween.set_parallel(true)

	if is_selected:
		z_index = 8
		if hover_tween:
			hover_tween.tween_property(self, "position:y", base_fan_offset_y - 55.0, 0.15).set_trans(Tween.TRANS_QUAD)
			hover_tween.tween_property(self, "rotation_degrees", 0.0, 0.15)
			hover_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.15)
		modulate = Color(1.25, 1.25, 0.85, 1.0) # Golden Glow
	else:
		z_index = 0
		if hover_tween:
			hover_tween.tween_property(self, "position:y", base_fan_offset_y, 0.15).set_trans(Tween.TRANS_QUAD)
			hover_tween.tween_property(self, "rotation_degrees", base_fan_rotation, 0.15)
			hover_tween.tween_property(self, "scale", Vector2.ONE, 0.15)
		modulate = Color(1.0, 1.0, 1.0, 1.0) if is_enabled else Color(0.45, 0.45, 0.45, 0.75)

func _on_mouse_entered() -> void:
	if not is_enabled:
		return
	z_index = 15 # Pop above all other cards
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween()
	if hover_tween:
		hover_tween.set_parallel(true)
		hover_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_QUAD)
		hover_tween.tween_property(self, "position:y", base_fan_offset_y - 60.0, 0.12).set_trans(Tween.TRANS_QUAD)
		hover_tween.tween_property(self, "rotation_degrees", 0.0, 0.12).set_trans(Tween.TRANS_QUAD)

func _on_mouse_exited() -> void:
	if is_selected:
		return
	z_index = 0
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween()
	if hover_tween:
		hover_tween.set_parallel(true)
		hover_tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
		hover_tween.tween_property(self, "position:y", base_fan_offset_y, 0.12).set_trans(Tween.TRANS_QUAD)
		hover_tween.tween_property(self, "rotation_degrees", base_fan_rotation, 0.12).set_trans(Tween.TRANS_QUAD)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Right click always triggers discard
			card_discard_requested.emit(card_data)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if is_enabled or is_selected:
				card_clicked.emit(card_data)
				get_viewport().set_input_as_handled()

