extends Node
class_name UIFontStyle

## UIFontStyle — centralized font loading + styling helpers for Sabong Roosters.
##
## Role -> Font mapping (OFL-licensed):
## - Title / Logo ("SABONG ROOSTERS"): Sancreek
## - Buttons & Menu Labels ("START GAME", "1v1 QUICK DUEL"): Staatliches
## - Body / Description Text: PT Sans (Regular + Bold)
## - Battle Damage / Buff / Debuff: Bangers

static var _title_font: FontFile
static var _button_font: FontFile
static var _body_font: FontFile
static var _body_bold_font: FontFile
static var _popup_font: FontFile
static var _anton_font: FontFile

static func _resolve_font_path(filename: String) -> String:
	var paths: Array[String] = [
		"res://resources/Fonts/" + filename,
		"res://assets/fonts/" + filename,
		"res://resources/fonts/" + filename
	]
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	return paths[0]

static func _ensure_loaded() -> void:
	if not _title_font:
		var p := _resolve_font_path("Staatliches-Regular.ttf")
		if ResourceLoader.exists(p): _title_font = load(p)
		else:
			var p2 := _resolve_font_path("Sancreek-Regular.ttf")
			if ResourceLoader.exists(p2): _title_font = load(p2)
	if not _anton_font:
		var p_anton := _resolve_font_path("Anton-Regular.ttf")
		if ResourceLoader.exists(p_anton): _anton_font = load(p_anton)
		elif _title_font: _anton_font = _title_font
	if not _button_font:
		var p := _resolve_font_path("Staatliches-Regular.ttf")
		if ResourceLoader.exists(p): _button_font = load(p)
		else:
			var p2 := _resolve_font_path("PT_Sans-Web-Bold.ttf")
			if ResourceLoader.exists(p2): _button_font = load(p2)
	if not _body_font:
		var p := _resolve_font_path("PT_Sans-Web-Regular.ttf")
		if ResourceLoader.exists(p): _body_font = load(p)
	if not _body_bold_font:
		var p := _resolve_font_path("PT_Sans-Web-Bold.ttf")
		if ResourceLoader.exists(p): _body_bold_font = load(p)
	if not _popup_font:
		var p := _resolve_font_path("PressStart2P-Regular.ttf")
		if ResourceLoader.exists(p): _popup_font = load(p)
		else:
			var p2 := _resolve_font_path("Silkscreen-Bold.ttf")
			if ResourceLoader.exists(p2): _popup_font = load(p2)

static func get_anton_font() -> FontFile:
	_ensure_loaded()
	return _anton_font if _anton_font else _title_font

## Apply Anton bold uppercase styling for phase titles, camera pop announcements, or buttons
static func style_anton(control: Control, size: int = 72) -> void:
	_ensure_loaded()
	var f := get_anton_font()
	if not control:
		return
	if f:
		control.add_theme_font_override("font", f)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_constant_override("outline_size", maxi(6, int(size * 0.12)))
	control.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.98))
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	control.add_theme_constant_override("shadow_offset_x", maxi(4, int(size * 0.05)))
	control.add_theme_constant_override("shadow_offset_y", maxi(4, int(size * 0.05)))

## Apply to your main title/logo Label (e.g. "SABONG LEGENDS: CLUCK COCK", "CHOOSE GAME MODE", Rooster name).
static func style_title(label: Label, size: int = 48) -> void:
	_ensure_loaded()
	if _title_font:
		label.add_theme_font_override("font", _title_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", maxi(4, int(size * 0.07)))
	label.add_theme_color_override("font_outline_color", Color(0.10, 0.04, 0.02, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", maxi(3, int(size * 0.045)))
	label.add_theme_constant_override("shadow_offset_y", maxi(3, int(size * 0.045)))

## Apply to any menu Button's label (START GAME, 1v1 QUICK DUEL, FIGHT!, etc.)
static func style_button(button: Control, size: int = 34) -> void:
	_ensure_loaded()
	if not button:
		return
	if _button_font:
		button.add_theme_font_override("font", _button_font)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_constant_override("outline_size", 5)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	button.add_theme_color_override("font_color", Color.WHITE)
	if button is Button:
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.2))
		button.add_theme_color_override("font_pressed_color", Color(0.9, 0.7, 0.1))
		button.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.2))

## Apply Silkscreen Bold font to condensed subheadings or button labels embedded in custom layouts
static func style_subheading(label: Label, size: int = 28) -> void:
	_ensure_loaded()
	if _button_font:
		label.add_theme_font_override("font", _button_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_color", Color.WHITE)

## Apply to descriptive subtext ("Select your battlefield challenge", mode descriptions, lore)
static func style_body(label: Label, size: int = 18, bold: bool = false) -> void:
	_ensure_loaded()
	var font_to_use: FontFile = _body_bold_font if (bold and _body_bold_font) else _body_font
	if font_to_use:
		label.add_theme_font_override("font", font_to_use)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0, 0.95))

## Apply to RichTextLabel
static func style_rich_text(rtl: RichTextLabel, size: int = 18, is_bold: bool = false) -> void:
	_ensure_loaded()
	if _body_font:
		rtl.add_theme_font_override("normal_font", _body_bold_font if (is_bold and _body_bold_font) else _body_font)
	if _body_bold_font:
		rtl.add_theme_font_override("bold_font", _body_bold_font)
	rtl.add_theme_font_size_override("normal_font_size", size)
	rtl.add_theme_font_size_override("bold_font_size", size)

## Apply styling to LineEdit input fields
static func style_line_edit(line_edit: LineEdit, size: int = 20, use_title_font: bool = false) -> void:
	_ensure_loaded()
	var font_to_use: FontFile = _title_font if use_title_font else _body_font
	if font_to_use:
		line_edit.add_theme_font_override("font", font_to_use)
	line_edit.add_theme_font_size_override("font_size", size)
	line_edit.add_theme_color_override("font_color", Color.WHITE)
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.65, 0.70, 0.80, 0.50))

	var le_sb := StyleBoxFlat.new()
	le_sb.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	le_sb.border_color = Color(1.0, 1.0, 1.0, 0.14)
	le_sb.set_border_width_all(1)
	le_sb.set_corner_radius_all(8)
	le_sb.content_margin_left = 14
	le_sb.content_margin_right = 14
	le_sb.content_margin_top = 8
	le_sb.content_margin_bottom = 8
	line_edit.add_theme_stylebox_override("normal", le_sb)

	var le_focus := le_sb.duplicate()
	le_focus.bg_color = Color(1.0, 1.0, 1.0, 0.09)
	le_focus.border_color = Color(1.0, 1.0, 1.0, 0.35)
	line_edit.add_theme_stylebox_override("focus", le_focus)

## Styles a ScrollContainer's vertical and horizontal scrollbars:
## - If hide_completely is true: hides the scrollbars (zero width/height, transparent), but mouse wheel / touch dragging still scrolls smoothly.
## - If hide_completely is false: gives it an ultra-thin (4px), modern minimalist rounded pill grabber with no background track strip.
static func style_scroll_container(scroll: ScrollContainer, hide_completely: bool = true) -> void:
	if not scroll:
		return
	var v_bar: VScrollBar = scroll.get_v_scroll_bar()
	if v_bar:
		var empty_v := StyleBoxEmpty.new()
		v_bar.add_theme_stylebox_override("scroll", empty_v)
		v_bar.add_theme_stylebox_override("scroll_focus", empty_v)
		if hide_completely:
			v_bar.custom_minimum_size = Vector2(0, 0)
			v_bar.modulate.a = 0.0
		else:
			v_bar.custom_minimum_size = Vector2(4, 0)
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(1.0, 1.0, 1.0, 0.20)
			grab.set_corner_radius_all(2)
			var grab_h := grab.duplicate()
			grab_h.bg_color = Color(1.0, 1.0, 1.0, 0.45)
			v_bar.add_theme_stylebox_override("grabber", grab)
			v_bar.add_theme_stylebox_override("grabber_highlight", grab_h)
			v_bar.add_theme_stylebox_override("grabber_pressed", grab_h)

	var h_bar: HScrollBar = scroll.get_h_scroll_bar()
	if h_bar:
		var empty_h := StyleBoxEmpty.new()
		h_bar.add_theme_stylebox_override("scroll", empty_h)
		h_bar.add_theme_stylebox_override("scroll_focus", empty_h)
		if hide_completely:
			h_bar.custom_minimum_size = Vector2(0, 0)
			h_bar.modulate.a = 0.0
		else:
			h_bar.custom_minimum_size = Vector2(0, 4)
			var grab2 := StyleBoxFlat.new()
			grab2.bg_color = Color(1.0, 1.0, 1.0, 0.20)
			grab2.set_corner_radius_all(2)
			var grab2_h := grab2.duplicate()
			grab2_h.bg_color = Color(1.0, 1.0, 1.0, 0.45)
			h_bar.add_theme_stylebox_override("grabber", grab2)
			h_bar.add_theme_stylebox_override("grabber_highlight", grab2_h)
			h_bar.add_theme_stylebox_override("grabber_pressed", grab2_h)

## Get the popup font directly, for use in 3D billboards (FloatingText3D).
static func get_popup_font() -> FontFile:
	_ensure_loaded()
	return _popup_font

static func get_title_font() -> FontFile:
	_ensure_loaded()
	return _title_font

static func get_button_font() -> FontFile:
	_ensure_loaded()
	return _button_font

static func get_body_font(bold: bool = false) -> FontFile:
	_ensure_loaded()
	return _body_bold_font if bold else _body_font

## ===========================================================================
## Battle Damage / Buff / Debuff Popup (2D Screen-space)
## ===========================================================================
static func spawn_battle_popup(parent: Node, screen_position: Vector2, text: String, kind: String = "damage") -> void:
	_ensure_loaded()

	var color: Color
	match kind:
		"damage":
			color = Color(1.0, 0.25, 0.15)
		"heal":
			color = Color(0.35, 0.95, 0.4)
		"buff":
			color = Color(1.0, 0.82, 0.2)
		"debuff":
			color = Color(0.65, 0.25, 0.95)
		_:
			color = Color.WHITE

	var label := Label.new()
	label.text = text
	if _popup_font:
		label.add_theme_font_override("font", _popup_font)
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	label.position = screen_position
	label.pivot_offset = Vector2(0, 0)
	label.z_index = 100
	parent.add_child(label)

	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0

	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 1.0, 0.05)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.35)
	tw.tween_property(label, "position:y", label.position.y - 40, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(label.queue_free)
