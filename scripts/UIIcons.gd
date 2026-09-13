extends Node
class_name UIIcons

## UIIcons — Crisp vector icon system for Sabong Roosters menus & HUD.
## Pure SVG-based resolution-independent icons. Never uses emojis.

static var _cache: Dictionary = {}

const SVG_DATA: Dictionary = {
	"swords": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5"/><line x1="13" y1="19" x2="19" y2="13"/><line x1="16" y1="16" x2="20" y2="20"/><line x1="19" y1="21" x2="21" y2="19"/><polyline points="14.5 6.5 18 3 21 3 21 6 17.5 9.5"/><line x1="5" y1="19" x2="11" y2="13"/><line x1="8" y1="16" x2="4" y2="20"/><line x1="3" y1="19" x2="5" y2="21"/></svg>""",

	"trophy": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h2"/><path d="M18 9h2a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-2"/><path d="M4 3h16v6a8 8 0 0 1-16 0V3z"/><path d="M12 17v4"/><path d="M8 21h8"/></svg>""",

	"globe": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>""",

	"lan": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="6" height="6" rx="1"/><rect x="16" y="2" width="6" height="6" rx="1"/><rect x="9" y="16" width="6" height="6" rx="1"/><path d="M5 8v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/><line x1="12" y1="13" x2="12" y2="16"/></svg>""",

	"shield": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>""",

	"plus": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>""",

	"arrow_right": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>""",

	"arrow_left": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>""",

	"refresh": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>""",

	"users": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>""",

	"key": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="15.5" r="5.5"/><path d="M11.4 11.6l8.6-8.6h4v4l-2 2v2l-2 2v2l-2.6-2.6"/></svg>""",

	"check": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>""",

	"alert": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>""",

	"circle": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#FFFFFF"><circle cx="12" cy="12" r="6"/></svg>""",

	"spinner": """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round"><path d="M12 2a10 10 0 0 1 10 10"/></svg>"""
}

## Returns a resolution-independent Texture2D for the given icon name.
## Size determines rasterization resolution (e.g. 24, 32, 48).
static func get_icon(icon_name: String, size: int = 24) -> Texture2D:
	var key := "%s_%d" % [icon_name, size]
	if _cache.has(key):
		return _cache[key]

	if not SVG_DATA.has(icon_name):
		push_warning("UIIcons: Unknown icon '%s'" % icon_name)
		return null

	var svg_str: String = SVG_DATA[icon_name]
	var scale: float = float(size) / 24.0

	var img := Image.new()
	var err := img.load_svg_from_string(svg_str, scale)
	if err != OK:
		push_warning("UIIcons: Failed to parse SVG for icon '%s' (err %d)" % [icon_name, err])
		return null

	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Creates a TextureRect with the specified icon, size, and modulate color.
static func create_icon_rect(icon_name: String, size: int = 24, col: Color = Color.WHITE) -> TextureRect:
	var icon_rect := TextureRect.new()
	icon_rect.texture = get_icon(icon_name, size)
	icon_rect.custom_minimum_size = Vector2(size, size)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = col
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect

## Creates an animated vector spinner that continuously rotates smoothly
static func create_spinner_node(size: int = 24, col: Color = Color.GOLD) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spinner_rect := TextureRect.new()
	spinner_rect.texture = get_icon("spinner", size)
	spinner_rect.custom_minimum_size = Vector2(size, size)
	spinner_rect.size = Vector2(size, size)
	spinner_rect.pivot_offset = Vector2(size * 0.5, size * 0.5)
	spinner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spinner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spinner_rect.modulate = col
	spinner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(spinner_rect)

	var tw := holder.create_tween().set_loops()
	tw.tween_property(spinner_rect, "rotation", TAU, 0.85).as_relative()
	return holder

## Sets up a Button so that its icon and text label are centered together as a single
## balanced unit in the middle of the button, preventing the icon from sticking or clipping
## against the outer border lines.
static func setup_centered_button(btn: Button, text: String, icon_name: String = "", icon_size: int = 24, font_size: int = 24, normal_color: Color = Color.WHITE, hover_color: Color = Color(1.0, 0.85, 0.2), separation: int = 12) -> Dictionary:
	btn.text = ""
	btn.icon = null

	var existing := btn.get_node_or_null("CenteredButtonContent")
	if existing:
		existing.name = "CenteredButtonContent_Old"
		existing.queue_free()

	var hbox := HBoxContainer.new()
	hbox.name = "CenteredButtonContent"
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", separation)
	btn.add_child(hbox)

	var icon_rect: TextureRect = null
	if not icon_name.is_empty():
		icon_rect = create_icon_rect(icon_name, icon_size, normal_color)
		icon_rect.name = "ButtonIcon"
		hbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.name = "ButtonLabel"
	lbl.text = text
	UIFontStyle.style_button(lbl, font_size)
	lbl.add_theme_color_override("font_color", normal_color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	btn.mouse_entered.connect(func():
		if not btn.disabled:
			if icon_rect:
				icon_rect.modulate = hover_color
			lbl.add_theme_color_override("font_color", hover_color)
	)
	btn.mouse_exited.connect(func():
		if not btn.disabled:
			if icon_rect:
				icon_rect.modulate = normal_color
			lbl.add_theme_color_override("font_color", normal_color)
	)
	btn.button_down.connect(func():
		if not btn.disabled:
			var pressed_col := hover_color.lerp(Color.BLACK, 0.2)
			if icon_rect:
				icon_rect.modulate = pressed_col
			lbl.add_theme_color_override("font_color", pressed_col)
	)
	btn.button_up.connect(func():
		if not btn.disabled:
			var col := hover_color if btn.is_hovered() else normal_color
			if icon_rect:
				icon_rect.modulate = col
			lbl.add_theme_color_override("font_color", col)
	)

	return {"hbox": hbox, "icon": icon_rect, "label": lbl}

## Dynamically updates the text and/or icon of a centered button created with setup_centered_button.
static func update_centered_button(btn: Button, text: String, icon_name: String = "", icon_size: int = 24) -> void:
	var lbl := btn.get_node_or_null("CenteredButtonContent/ButtonLabel") as Label
	if lbl:
		lbl.text = text
	var icon_rect := btn.get_node_or_null("CenteredButtonContent/ButtonIcon") as TextureRect
	if icon_rect and not icon_name.is_empty():
		icon_rect.texture = get_icon(icon_name, icon_size)
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)

## Sets the normal and hover colors for a centered button's icon and label.
static func set_centered_button_color(btn: Button, normal_color: Color, _hover_color: Color = Color(1.0, 0.85, 0.2)) -> void:
	var hbox := btn.get_node_or_null("CenteredButtonContent") as HBoxContainer
	if hbox:
		for child in hbox.get_children():
			if child is TextureRect:
				child.modulate = normal_color
			elif child is Label:
				child.add_theme_color_override("font_color", normal_color)

