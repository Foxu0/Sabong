extends RefCounted
class_name UITheme

## UITheme — "barnyard" look shared by every 2D screen.
## Flat painted-wood blocks, square corners, a hard dark bottom edge instead of blurred shadows,
## cream text with an ink outline. No glass, glow, gradients or decorative icons.

const INK := Color("1c120b")          # outlines, hard shadows
const WOOD_DARK := Color("3a2416")    # panels, modal bodies
const WOOD := Color("6b4428")         # secondary buttons, inset rows
const WOOD_LIGHT := Color("8a5a35")   # hover on wood
const BARN_RED := Color("a83c2a")     # primary action
const BARN_RED_LIGHT := Color("c4502f")
const STRAW := Color("e9b949")        # highlights, selected state, titles
const STRAW_LIGHT := Color("f3cd6a")
const CREAM := Color("f4e7cc")        # body text, input fields
const GRASS := Color("6f9a3c")        # positive / online
const MUTED := Color(0.957, 0.906, 0.8, 0.62) # secondary text (cream at 62%)

const EDGE := 5       # hard bottom edge on raised blocks
const CORNER := 2

## Solid panel (modal bodies, cards).
static func panel(color: Color = WOOD_DARK, pad_x: int = 28, pad_y: int = 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.border_width_bottom = 3 + EDGE
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y + EDGE
	sb.set_meta("barn", true)
	return sb

## Recessed area inside a panel (lists, rows, field groups).
static func inset(color: Color = Color("2c1b10"), pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.set_meta("barn", true)
	return sb

static func _block(color: Color, edge: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.border_width_bottom = 3 + edge
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	# Pressing removes the bottom edge and pushes the label down by the same amount
	sb.content_margin_top = pad_y + (EDGE - edge)
	sb.content_margin_bottom = pad_y
	sb.set_meta("barn", true)
	return sb

## Chunky raised button. kind: "primary" (barn red), "secondary" (wood), "accent" (straw).
static func style_button(btn: Button, kind: String = "secondary", font_size: int = 26, pad_x: int = 22, pad_y: int = 8) -> void:
	var base := WOOD
	var hover := WOOD_LIGHT
	var text := CREAM
	match kind:
		"primary":
			base = BARN_RED
			hover = BARN_RED_LIGHT
		"accent":
			base = STRAW
			hover = STRAW_LIGHT
			text = INK
	btn.flat = false
	btn.icon = null
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _block(base, EDGE, pad_x, pad_y))
	btn.add_theme_stylebox_override("hover", _block(hover, EDGE, pad_x, pad_y))
	btn.add_theme_stylebox_override("pressed", _block(base.darkened(0.12), 0, pad_x, pad_y))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var dis := _block(base.lerp(WOOD_DARK, 0.6), EDGE, pad_x, pad_y)
	btn.add_theme_stylebox_override("disabled", dis)
	UIFontStyle.style_button(btn, font_size)
	btn.add_theme_constant_override("outline_size", 0 if kind == "accent" else 4)
	btn.add_theme_color_override("font_outline_color", INK)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, text)
	btn.add_theme_color_override("font_disabled_color", Color(text, 0.45))
	btn.set_meta("barn_skinned", true)

## Plain text link (close, back, small actions): cream, straw on hover, no box.
static func style_link(btn: Button, font_size: int = 22) -> void:
	btn.flat = true
	btn.icon = null
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	UIFontStyle.style_button(btn, font_size)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_color_override("font_outline_color", INK)
	btn.add_theme_color_override("font_color", CREAM)
	btn.add_theme_color_override("font_hover_color", STRAW)
	btn.add_theme_color_override("font_focus_color", STRAW)
	btn.add_theme_color_override("font_pressed_color", STRAW.darkened(0.15))
	btn.set_meta("barn_skinned", true)

## Big screen titles: straw (or given color) with a thick ink outline and a hard offset shadow.
static func style_title(label: Label, size: int, color: Color = STRAW) -> void:
	UIFontStyle.style_title(label, size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", maxi(6, int(size * 0.11)))
	label.add_theme_color_override("font_shadow_color", INK)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(3, int(size * 0.06)))
	label.add_theme_constant_override("shadow_outline_size", maxi(6, int(size * 0.11)))

## Body text over the 3D world or a panel.
static func style_text(label: Label, size: int = 20, color: Color = CREAM, bold: bool = false) -> void:
	UIFontStyle.style_body(label, size, bold)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4)

## Small all-caps section label ("ONLINE", "OFFLINE").
static func style_caption(label: Label, size: int = 18, color: Color = STRAW) -> void:
	UIFontStyle.style_subheading(label, size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4)

static func style_input(le: LineEdit, size: int = 20) -> void:
	UIFontStyle.style_line_edit(le, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	le.add_theme_stylebox_override("normal", sb)
	var focus := sb.duplicate() as StyleBoxFlat
	focus.border_color = BARN_RED
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", INK)
	le.add_theme_color_override("font_placeholder_color", Color(INK, 0.45))
	le.add_theme_color_override("caret_color", BARN_RED)
	le.add_theme_color_override("selection_color", Color(STRAW, 0.6))
	le.set_meta("barn_skinned", true)

static func backdrop_color() -> Color:
	return Color(INK, 0.6)

# ---------------------------------------------------------------------------
# skin(): converts screens built with the old glass look, including styles their code
# swaps in later (tab highlights, hover states), without rewriting every builder.
# ---------------------------------------------------------------------------

## Re-skins `root` and everything added under it later.
static func skin(root: Node) -> void:
	_skin_tree(root)
	if root.is_inside_tree():
		_watch(root)
	elif not root.tree_entered.is_connected(_watch.bind(root)):
		root.tree_entered.connect(_watch.bind(root), CONNECT_ONE_SHOT)

static func _watch(root: Node) -> void:
	var tree := root.get_tree()
	var cb := func(n: Node):
		if is_instance_valid(root) and root.is_ancestor_of(n):
			_skin_node(n)
	tree.node_added.connect(cb)
	var unwatch := func():
		if tree.node_added.is_connected(cb):
			tree.node_added.disconnect(cb)
	root.tree_exiting.connect(unwatch, CONNECT_ONE_SHOT)

static func _skin_tree(n: Node) -> void:
	_skin_node(n)
	for c in n.get_children():
		_skin_tree(c)

static func _skin_node(n: Node) -> void:
	if not (n is Control) or n.has_meta("barn_watch"):
		return
	var c := n as Control
	c.set_meta("barn_watch", true)
	_restyle(c)
	# Code often swaps style overrides later (selected tab, hover); convert those as they arrive.
	c.theme_changed.connect(_restyle.bind(c))

static func _restyle(c: Control) -> void:
	if not is_instance_valid(c) or c.get_meta("barn_restyling", false):
		return
	c.set_meta("barn_restyling", true)
	if c is Button:
		# Always re-check: code may swap in new glass styles after a button was skinned
		_restyle_button(c as Button)
	elif c is LineEdit and not c.get_meta("barn_skinned", false):
		style_input(c as LineEdit, (c as LineEdit).get_theme_font_size("font_size"))
	elif c is PanelContainer or c is Panel:
		_remap_box(c, "panel", false)
	elif c is ColorRect:
		var cr := c as ColorRect
		if cr.get_meta("barn_src", Color.TRANSPARENT) != cr.color:
			# Full-screen scrims and dividers keep their transparency so the game shows through
			cr.color = _map_fill(cr.color, true)
			cr.set_meta("barn_src", cr.color)
	elif c is ProgressBar:
		_remap_box(c, "background", false)
		_remap_box(c, "fill", false)
	if c is Label or c is Button or c is LineEdit:
		_remap_font_colors(c)
	c.set_meta("barn_restyling", false)

static func _restyle_button(b: Button) -> void:
	if b.text.strip_edges() != "":
		b.icon = null
		# Plain buttons still on Godot's default grey theme get the wood block outright
		if not b.flat and not b.has_theme_stylebox_override("normal") and not (b is CheckBox or b is CheckButton):
			style_button(b, "secondary", b.get_theme_font_size("font_size"))
			return
	for s in ["normal", "hover", "pressed", "disabled"]:
		_remap_box(b, s, true)
	if b.has_theme_stylebox_override("focus") and not (b.get_theme_stylebox("focus") is StyleBoxEmpty):
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func _remap_box(c: Control, slot: String, raised: bool) -> void:
	if not c.has_theme_stylebox_override(slot):
		return
	var sb := c.get_theme_stylebox(slot)
	if not (sb is StyleBoxFlat) or sb.has_meta("barn"):
		return
	var src := sb as StyleBoxFlat
	if src.bg_color.a < 0.03 and (src.border_color.a < 0.06 or src.get_border_width(SIDE_LEFT) == 0):
		return # invisible boxes stay invisible
	var out := src.duplicate() as StyleBoxFlat
	out.set_meta("barn", true)
	out.bg_color = _map_button_fill(src.bg_color, slot) if raised else _map_fill(src.bg_color)
	out.set_corner_radius_all(CORNER)
	out.shadow_size = 0
	out.anti_aliasing = false
	var has_border := src.border_color.a > 0.06 and (src.get_border_width(SIDE_LEFT) + src.get_border_width(SIDE_BOTTOM)) > 0
	if has_border or raised:
		out.border_color = INK
		out.set_border_width_all(maxi(2, src.get_border_width(SIDE_LEFT)))
	if raised and slot != "pressed":
		out.border_width_bottom = out.border_width_top + 3
	c.add_theme_stylebox_override(slot, out)

## Buttons always read as wood blocks. Old glass buttons told states apart by how much
## white they let through, so that ordering is kept: faint -> dark wood, stronger -> lighter wood.
static func _map_button_fill(col: Color, slot: String) -> Color:
	if col.s > 0.45 and col.v > 0.35:
		return _map_fill(col)
	var strength := col.get_luminance() if col.a >= 0.35 else col.a * 2.0
	var mapped := WOOD_LIGHT
	if strength < 0.12:
		mapped = Color("4a2e1b")
	elif strength < 0.28:
		mapped = WOOD
	if slot == "pressed":
		mapped = mapped.darkened(0.12)
	return mapped

## Maps an old glass/neon fill onto the barnyard palette, keeping its rough brightness.
## Panels become solid; keep_alpha leaves translucent layers (scrims) translucent.
static func _map_fill(col: Color, keep_alpha: bool = false) -> Color:
	if col.a < 0.03:
		return col
	var lum := col.get_luminance()
	var alpha := col.a if keep_alpha else (clampf(col.a * 1.6, 0.0, 1.0) if col.a < 0.5 else 1.0)
	if col.s > 0.45 and col.v > 0.35:
		var h := col.h * 360.0
		var mapped := STRAW
		if h < 25.0 or h >= 330.0:
			mapped = BARN_RED
		elif h < 70.0:
			mapped = STRAW
		elif h < 170.0:
			mapped = GRASS
		# blues/cyans/purples (old "selected" accents) become straw
		if col.v < 0.6:
			mapped = mapped.darkened(0.35)
		return Color(mapped, alpha)
	if lum > 0.7:
		return Color(CREAM, alpha)
	if lum > 0.16:
		return Color(WOOD, alpha)
	if lum > 0.06:
		return Color(WOOD_DARK, alpha)
	return Color(Color("2c1b10"), alpha)

static func _remap_font_colors(c: Control) -> void:
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		if not c.has_theme_color_override(slot):
			continue
		var col := c.get_theme_color(slot)
		var mapped := _map_text(col)
		if mapped != col:
			c.add_theme_color_override(slot, mapped)
	# Only write real changes: every override write re-fires theme_changed
	if c.has_theme_color_override("font_outline_color") and c.get_theme_color("font_outline_color") != INK:
		c.add_theme_color_override("font_outline_color", INK)

static func _map_text(col: Color) -> Color:
	if col.a < 0.05:
		return col
	if c_is_ink(col):
		return col
	if col.s < 0.25:
		# whites / greys / blue-greys -> cream, dimmer ones -> muted cream
		return Color(CREAM, col.a) if col.v > 0.8 else Color(MUTED, minf(col.a, MUTED.a + 0.15))
	var h := col.h * 360.0
	if h < 25.0 or h >= 330.0:
		return Color(Color("e8735a"), col.a)   # warnings stay readable red
	if h < 70.0:
		return Color(STRAW, col.a)
	if h < 170.0:
		return Color(Color("9cc861"), col.a)   # success green
	return Color(STRAW, col.a)                # old cyan/blue highlights

static func c_is_ink(col: Color) -> bool:
	return col.v < 0.2
