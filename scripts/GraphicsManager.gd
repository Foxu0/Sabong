extends Node

## GraphicsManager — Centralized Graphics & Performance Controller for Sabong Roosters.
## Manages AMD FSR 1.0 resolution scaling, 4 curated quality presets (Low, Medium, High, Ultra),
## target FPS capping, V-Sync, dynamic WorldEnvironment post-processing, and in-game FPS telemetry.

enum QualityPreset { POTATO, LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

signal preset_changed(preset: QualityPreset)
signal settings_applied(settings: Dictionary)
signal fps_counter_toggled(enabled: bool)

const SETTINGS_FILE := "user://graphics_settings.json"

# Core Settings
var current_preset: QualityPreset = QualityPreset.HIGH
var scaling_3d_mode: int = Viewport.SCALING_3D_MODE_BILINEAR
var scaling_3d_scale: float = 1.0
var fsr_sharpness: float = 0.0
var msaa_3d: int = Viewport.MSAA_DISABLED
var max_fps: int = 60
var vsync_enabled: bool = true
var fullscreen: bool = false
var shadow_quality: int = 2
var shadows_enabled: bool = true
var glow_enabled: bool = true
var ssao_enabled: bool = true
var ssr_enabled: bool = true
var ssil_enabled: bool = false
var volumetric_fog_enabled: bool = false
var show_fps_counter: bool = false

# Telemetry Overlay Nodes
var _fps_canvas_layer: CanvasLayer = null
var _fps_panel: PanelContainer = null
var _fps_label: Label = null
var _fps_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Smart Auto-Tune: Default to LOW on Web builds, HIGH on Desktop
	if OS.has_feature("web"):
		set_preset(QualityPreset.LOW, false)
	else:
		set_preset(QualityPreset.HIGH, false)

	# Load user overrides if saved previously
	load_settings()

	# Build Telemetry Overlay
	_build_fps_overlay()

	# Apply initial graphics state to viewport & engine
	apply_all_settings()

	# Listen for scene changes to dynamically configure new WorldEnvironments
	get_tree().node_added.connect(_on_node_added)

func _process(delta: float) -> void:
	if show_fps_counter and _fps_label and is_instance_valid(_fps_label):
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25 # update 4 times per second
			var fps := Engine.get_frames_per_second()
			var msec := delta * 1000.0
			_fps_label.text = "%d FPS • %.1f ms" % [fps, msec]
			if fps >= 55:
				_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			elif fps >= 30:
				_fps_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			else:
				_fps_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

# ---------------------------------------------------------------------------
# Quality Presets
# ---------------------------------------------------------------------------

func set_preset(preset: QualityPreset, apply_immediately: bool = true) -> void:
	current_preset = preset

	match preset:
		QualityPreset.POTATO:
			# Potato / Ultra Performance (No Shadows, No Post-processing)
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			scaling_3d_scale = 1.0 if OS.has_feature("web") else 0.50
			fsr_sharpness = 0.0
			msaa_3d = Viewport.MSAA_DISABLED
			shadow_quality = 0
			shadows_enabled = false
			glow_enabled = false
			ssao_enabled = false
			ssr_enabled = false
			ssil_enabled = false
			volumetric_fog_enabled = false
			max_fps = 0 if OS.has_feature("web") else 60

		QualityPreset.LOW:
			# Low / High Efficiency (No Shadows, No Glow, No Post-processing)
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			scaling_3d_scale = 1.0 if OS.has_feature("web") else 0.65
			fsr_sharpness = 0.0
			msaa_3d = Viewport.MSAA_DISABLED
			shadow_quality = 0
			shadows_enabled = false
			glow_enabled = false
			ssao_enabled = false
			ssr_enabled = false
			ssil_enabled = false
			volumetric_fog_enabled = false
			max_fps = 0 if OS.has_feature("web") else 60

		QualityPreset.MEDIUM:
			# Balanced (Soft Low Shadows, Glow ON)
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			scaling_3d_scale = 1.0 if OS.has_feature("web") else 0.85
			fsr_sharpness = 0.0
			msaa_3d = Viewport.MSAA_DISABLED
			shadow_quality = 1 # Soft Low
			shadows_enabled = true
			glow_enabled = true
			ssao_enabled = false
			ssr_enabled = false
			ssil_enabled = false
			volumetric_fog_enabled = false
			max_fps = 0 if OS.has_feature("web") else 60

		QualityPreset.HIGH:
			# High Desktop (100% Native, Soft Shadows, SSAO, SSR)
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			scaling_3d_scale = 1.0
			fsr_sharpness = 0.0
			msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_2X
			shadow_quality = 2 # Soft Medium
			shadows_enabled = true
			glow_enabled = true
			ssao_enabled = not OS.has_feature("web")
			ssr_enabled = not OS.has_feature("web")
			ssil_enabled = false
			volumetric_fog_enabled = false
			max_fps = 0 if OS.has_feature("web") else 60

		QualityPreset.ULTRA:
			# Ultra Enthusiast (100% Native, Max Shadows, Full Post-processing)
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			scaling_3d_scale = 1.0
			fsr_sharpness = 0.0
			msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
			shadow_quality = 4 # Soft Ultra
			shadows_enabled = true
			glow_enabled = true
			ssao_enabled = not OS.has_feature("web")
			ssr_enabled = not OS.has_feature("web")
			ssil_enabled = not OS.has_feature("web")
			volumetric_fog_enabled = not OS.has_feature("web")
			max_fps = 0 if OS.has_feature("web") else 120

		QualityPreset.CUSTOM:
			pass

	preset_changed.emit(current_preset)

	if apply_immediately:
		apply_all_settings()
		save_settings()

func get_preset_name(preset: QualityPreset) -> String:
	match preset:
		QualityPreset.POTATO: return "POTATO (MAX SPEED)"
		QualityPreset.LOW:    return "LOW (MAX FPS / WEB)"
		QualityPreset.MEDIUM: return "MEDIUM (BALANCED)"
		QualityPreset.HIGH:   return "HIGH (DESKTOP DEFAULT)"
		QualityPreset.ULTRA:  return "ULTRA (CINEMATIC)"
		QualityPreset.CUSTOM: return "CUSTOM"
	return "UNKNOWN"

# ---------------------------------------------------------------------------
# Application of Settings
# ---------------------------------------------------------------------------

func apply_all_settings() -> void:
	var vp := get_viewport()
	if vp:
		if OS.has_feature("web"):
			# Direct 1.0 rendering avoids WebGL offscreen FBO blit pass
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
		else:
			vp.scaling_3d_mode = scaling_3d_mode
			vp.scaling_3d_scale = scaling_3d_scale
			vp.fsr_sharpness = fsr_sharpness
			vp.msaa_3d = msaa_3d

	# Framerate Capping: In Web builds, browser requestAnimationFrame MUST drive timing.
	# Setting Engine.max_fps > 0 forces Godot to sleep inside the rAF loop, causing severe stuttering!
	if OS.has_feature("web"):
		Engine.max_fps = 0
	else:
		Engine.max_fps = max_fps

	# V-Sync
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

	# Shadow Quality
	_apply_shadow_quality()

	# Apply to all active environments in current scene
	apply_to_active_scene()

	# Telemetry Overlay
	if _fps_canvas_layer and is_instance_valid(_fps_canvas_layer):
		_fps_canvas_layer.visible = show_fps_counter

	settings_applied.emit(to_dict())

func _apply_shadow_quality() -> void:
	match shadow_quality:
		0:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		1:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		2:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		3:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		4, 5:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)

	_apply_lights_shadow_state()

func _apply_lights_shadow_state() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene: return
	for node in tree.current_scene.find_children("*", "Light3D", true, false):
		if node is Light3D:
			node.shadow_enabled = shadows_enabled

func set_shadows_enabled(enabled: bool) -> void:
	shadows_enabled = enabled
	_apply_lights_shadow_state()
	apply_to_active_scene()
	save_settings()

func apply_to_environment(env: Environment) -> void:
	if not env: return
	if OS.has_feature("web"):
		env.glow_enabled = glow_enabled
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.ssil_enabled = false
		env.volumetric_fog_enabled = false
		env.fog_enabled = false
	else:
		env.glow_enabled = glow_enabled
		env.ssao_enabled = ssao_enabled
		env.ssr_enabled = ssr_enabled
		env.ssil_enabled = ssil_enabled
		env.volumetric_fog_enabled = volumetric_fog_enabled
		if not volumetric_fog_enabled:
			# Standard lightweight aerial fog
			env.fog_enabled = (current_preset >= QualityPreset.MEDIUM)
			env.fog_density = 0.002

	# Cel-shaded ambient compensation when shadows are cut
	if not shadows_enabled:
		env.ambient_light_energy = 0.85
		env.ambient_light_sky_contribution = 0.75
	else:
		env.ambient_light_energy = 0.60
		env.ambient_light_sky_contribution = 0.60

func apply_to_active_scene() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene: return
	for node in tree.current_scene.find_children("*", "WorldEnvironment", true, false):
		if node is WorldEnvironment and node.environment:
			apply_to_environment(node.environment)
	_apply_lights_shadow_state()

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment and node.environment:
		apply_to_environment(node.environment)
	elif node is Light3D:
		node.shadow_enabled = shadows_enabled

# ---------------------------------------------------------------------------
# In-Game FPS Telemetry Overlay
# ---------------------------------------------------------------------------

func _build_fps_overlay() -> void:
	if _fps_canvas_layer and is_instance_valid(_fps_canvas_layer):
		_fps_canvas_layer.queue_free()

	_fps_canvas_layer = CanvasLayer.new()
	_fps_canvas_layer.name = "FPSTelemetryLayer"
	_fps_canvas_layer.layer = 125
	_fps_canvas_layer.visible = show_fps_counter
	add_child(_fps_canvas_layer)

	_fps_panel = PanelContainer.new()
	_fps_panel.name = "FPSBadge"
	_fps_panel.anchor_left = 1.0
	_fps_panel.anchor_right = 1.0
	_fps_panel.anchor_top = 0.0
	_fps_panel.anchor_bottom = 0.0
	_fps_panel.offset_left = -170.0
	_fps_panel.offset_right = -16.0
	_fps_panel.offset_top = 16.0
	_fps_panel.offset_bottom = 50.0
	_fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.10, 0.85)
	style.border_color = Color(1.0, 0.85, 0.2, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_fps_panel.add_theme_stylebox_override("panel", style)
	_fps_canvas_layer.add_child(_fps_panel)

	_fps_label = Label.new()
	_fps_label.text = "60 FPS • 16.6 ms"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_fps_panel.add_child(_fps_label)

func toggle_fps_counter(enabled: bool) -> void:
	show_fps_counter = enabled
	if _fps_canvas_layer and is_instance_valid(_fps_canvas_layer):
		_fps_canvas_layer.visible = show_fps_counter
	fps_counter_toggled.emit(show_fps_counter)
	save_settings()

# ---------------------------------------------------------------------------
# Persistence (user://graphics_settings.json)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"preset": int(current_preset),
		"scaling_3d_mode": scaling_3d_mode,
		"scaling_3d_scale": scaling_3d_scale,
		"fsr_sharpness": fsr_sharpness,
		"msaa_3d": msaa_3d,
		"max_fps": max_fps,
		"vsync_enabled": vsync_enabled,
		"fullscreen": fullscreen,
		"shadow_quality": shadow_quality,
		"shadows_enabled": shadows_enabled,
		"glow_enabled": glow_enabled,
		"ssao_enabled": ssao_enabled,
		"ssr_enabled": ssr_enabled,
		"ssil_enabled": ssil_enabled,
		"volumetric_fog_enabled": volumetric_fog_enabled,
		"show_fps_counter": show_fps_counter
	}

func from_dict(d: Dictionary) -> void:
	if d.has("preset"): current_preset = d["preset"] as QualityPreset
	if d.has("scaling_3d_mode"): scaling_3d_mode = int(d["scaling_3d_mode"])
	if d.has("scaling_3d_scale"): scaling_3d_scale = float(d["scaling_3d_scale"])
	if d.has("fsr_sharpness"): fsr_sharpness = float(d["fsr_sharpness"])
	if d.has("msaa_3d"): msaa_3d = int(d["msaa_3d"])
	if d.has("max_fps"): max_fps = int(d["max_fps"])
	if d.has("vsync_enabled"): vsync_enabled = bool(d["vsync_enabled"])
	if d.has("fullscreen"): fullscreen = bool(d["fullscreen"])
	if d.has("shadow_quality"): shadow_quality = int(d["shadow_quality"])
	if d.has("shadows_enabled"): shadows_enabled = bool(d["shadows_enabled"])
	if d.has("glow_enabled"): glow_enabled = bool(d["glow_enabled"])
	if d.has("ssao_enabled"): ssao_enabled = bool(d["ssao_enabled"])
	if d.has("ssr_enabled"): ssr_enabled = bool(d["ssr_enabled"])
	if d.has("ssil_enabled"): ssil_enabled = bool(d["ssil_enabled"])
	if d.has("volumetric_fog_enabled"): volumetric_fog_enabled = bool(d["volumetric_fog_enabled"])
	if d.has("show_fps_counter"): show_fps_counter = bool(d["show_fps_counter"])

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))
		f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if f:
		var txt := f.get_as_text()
		f.close()
		var json := JSON.new()
		if json.parse(txt) == OK and json.get_data() is Dictionary:
			from_dict(json.get_data())
