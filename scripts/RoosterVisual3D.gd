extends Node3D
class_name RoosterVisual3D

## RoosterVisual3D — Controls 3D Voxel Rooster model, animations, stands and visual effects on stage.

@export var duelist_id: int = 1
@export var opponent_visual: RoosterVisual3D

var rooster_data: RoosterData
var current_model_instance: Node3D = null
var is_dead: bool = false
var base_stage_pos: Vector3 = Vector3.ZERO
var base_scale: Vector3 = Vector3.ONE
var base_rot: Vector3 = Vector3.ZERO
var stage_pos: Vector3 = Vector3.ZERO
var arena_pos: Vector3 = Vector3.ZERO
var is_in_arena: bool = false
var is_transformed: bool = false
var current_stand_instance: Node3D = null
var _stand_hover_tween: Tween = null
var _stand_ghost_material: StandardMaterial3D = null
var _gear5_drums_tween: Tween = null
var untransformed_scale: Vector3 = Vector3.ONE

# --- High-Performance Caching (Eliminates Shader Compilation Spikes & Model Load Freezes) ---
var _model_cache: Dictionary = {}
var _cached_stand_meshes: Array[MeshInstance3D] = []

static var _global_flash_layer: CanvasLayer = null
static var _global_flash_rect: ColorRect = null
static var _global_flash_tween: Tween = null
static var _vfx_mat_cache: Dictionary = {}

static func _get_cached_material(key: String, albedo: Color, emission: Color = Color.BLACK, emission_energy: float = 0.0, unshaded: bool = true, cull_disabled: bool = false) -> StandardMaterial3D:
	if _vfx_mat_cache.has(key) and is_instance_valid(_vfx_mat_cache[key]):
		var m: StandardMaterial3D = _vfx_mat_cache[key]
		m.albedo_color = albedo
		return m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = albedo
	if emission != Color.BLACK and emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if cull_disabled:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vfx_mat_cache[key] = mat
	return mat

func _trigger_camera_shake(duration: float = 0.35, intensity: float = 0.12) -> void:
	var arena = get_parent()
	while arena and not arena is ArenaController:
		arena = arena.get_parent()
	if arena and arena.has_method("shake_camera"):
		arena.shake_camera(duration, intensity)
	elif get_tree() and get_tree().current_scene and get_tree().current_scene.has_method("shake_camera"):
		get_tree().current_scene.shake_camera(duration, intensity)

## Fullscreen 1-frame shonen impact flash (reusing single persistent overlay to prevent canvas layer creation spikes)
func _trigger_screen_flash(flash_color: Color = Color(1.0, 0.96, 0.75, 0.65), duration: float = 0.12) -> void:
	if not get_tree() or not get_tree().root:
		return
	if not _global_flash_layer or not is_instance_valid(_global_flash_layer):
		_global_flash_layer = CanvasLayer.new()
		_global_flash_layer.layer = 120
		_global_flash_rect = ColorRect.new()
		_global_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_global_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_global_flash_rect.color = Color(1, 1, 1, 0)
		_global_flash_layer.add_child(_global_flash_rect)
		get_tree().root.add_child(_global_flash_layer)

	if _global_flash_tween and _global_flash_tween.is_valid():
		_global_flash_tween.kill()

	_global_flash_rect.color = flash_color
	_global_flash_tween = _global_flash_rect.create_tween()
	_global_flash_tween.tween_property(_global_flash_rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 3D Radiating Anime Speed-Lines on Supersonic Launch
func _spawn_launch_speed_burst(origin: Vector3, dir: Vector3) -> void:
	var burst_root := Node3D.new()
	get_parent().add_child(burst_root)
	burst_root.global_position = origin
	
	var streak_mat := _get_cached_material("launch_streak", Color(1.0, 0.92, 0.45, 0.9), Color(1.0, 0.95, 0.6), 3.5)
	var count: int = 4 if OS.has_feature("web") else 8
	
	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU
		var line_mesh := CylinderMesh.new()
		line_mesh.top_radius = 0.015
		line_mesh.bottom_radius = 0.05
		line_mesh.height = 0.85
		
		var line_inst := MeshInstance3D.new()
		line_inst.mesh = line_mesh
		line_inst.material_override = streak_mat
		burst_root.add_child(line_inst)
		
		var radial_offset := Vector3(cos(angle) * 0.35, sin(angle) * 0.35, 0)
		line_inst.position = radial_offset
		line_inst.look_at(origin + dir * 2.0 + radial_offset, Vector3.UP)
	
	var tw := burst_root.create_tween()
	burst_root.scale = Vector3(0.2, 0.2, 0.2)
	tw.tween_property(burst_root, "scale", Vector3(1.6, 1.6, 2.4), 0.10).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(burst_root, "position", origin + dir * 0.8, 0.10)
	tw.chain().tween_property(burst_root, "scale", Vector3(0.001, 0.001, 0.001), 0.04)
	tw.chain().tween_callback(burst_root.queue_free)

## Red Hawk Explosive Impact Blast
func _spawn_red_hawk_impact_explosion(impact_pos: Vector3, dir: Vector3) -> void:
	var blast_root := Node3D.new()
	get_parent().add_child(blast_root)
	blast_root.global_position = impact_pos
	
	var shock_mat := _get_cached_material("red_hawk_shock", Color(1.0, 0.35, 0.05, 0.95), Color(1.0, 0.85, 0.2), 5.0)
	
	# Expanding fire shockwave ring
	var shock_mesh := TorusMesh.new()
	shock_mesh.inner_radius = 0.3
	shock_mesh.outer_radius = 0.65
	var shock_inst := MeshInstance3D.new()
	shock_inst.mesh = shock_mesh
	shock_inst.material_override = shock_mat
	blast_root.add_child(shock_inst)
	shock_inst.look_at(impact_pos + dir, Vector3.UP)
	
	# Expanding fireball
	var fireball := MeshInstance3D.new()
	var f_sphere := SphereMesh.new()
	f_sphere.radius = 0.38
	f_sphere.height = 0.76
	fireball.mesh = f_sphere
	fireball.material_override = shock_mat
	blast_root.add_child(fireball)
	
	var tw := blast_root.create_tween()
	blast_root.scale = Vector3(0.2, 0.2, 0.2)
	tw.tween_property(blast_root, "scale", Vector3(2.6, 2.6, 2.6), 0.12).set_trans(Tween.TRANS_EXPO)
	tw.chain().tween_property(blast_root, "scale", Vector3(0.001, 0.001, 0.001), 0.06)
	tw.chain().tween_callback(blast_root.queue_free)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_cleanup_stand()

func _cleanup_stand() -> void:
	if _stand_hover_tween and _stand_hover_tween.is_valid():
		_stand_hover_tween.kill()
		_stand_hover_tween = null
	if current_stand_instance and is_instance_valid(current_stand_instance):
		current_stand_instance.queue_free()
		current_stand_instance = null
	_stand_ghost_material = null

func _get_stand_offset() -> Vector3:
	if duelist_id == 1:
		return Vector3(0.0, 1.25, 1.25)
	else:
		return Vector3(0.0, 1.25, -1.25)

func _get_stand_target_pos(origin: Vector3) -> Vector3:
	return origin + _get_stand_offset()

func _setup_stand_companion() -> void:
	_cleanup_stand()
	if not rooster_data or rooster_data.rooster_id != "cocktaro":
		return

	var stand_path: String = rooster_data.stand_model_path
	if stand_path == "" or not ResourceLoader.exists(stand_path):
		stand_path = "res://resources/models/cocktaro/kotarostand.vox"

	if ResourceLoader.exists(stand_path):
		var res = load(stand_path)
		if res is PackedScene:
			current_stand_instance = res.instantiate()
			get_parent().add_child(current_stand_instance)

			var init_pos := _get_stand_target_pos(position)
			current_stand_instance.position = init_pos
			current_stand_instance.rotation_degrees = base_rot
			current_stand_instance.scale = Vector3(0.70, 0.70, 0.70)

			_cached_stand_meshes.clear()
			for child in current_stand_instance.find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D:
					_cached_stand_meshes.append(child)

			# Ghostly translucent material for out-of-battle standby
			_stand_ghost_material = _get_cached_material("stand_ghost_mat", Color(0.85, 0.45, 1.0, 0.22), Color(0.75, 0.25, 1.0), 1.4, false, true)
			_stand_ghost_material.rim_enabled = true
			_stand_ghost_material.rim = 0.95

			_set_stand_ghostly_mode(not is_in_arena, 0.01)
			_start_stand_hover_loop()

func _set_stand_ghostly_mode(is_ghost: bool, duration: float = 0.25) -> void:
	if not current_stand_instance or not is_instance_valid(current_stand_instance) or not _stand_ghost_material:
		return

	var target_scale: Vector3 = Vector3(0.70, 0.70, 0.70) if is_ghost else Vector3(1.05, 1.05, 1.05)

	if is_ghost:
		# Out of battle: apply ghostly translucent purple shader (more transparent)
		for child in _cached_stand_meshes:
			if is_instance_valid(child):
				child.material_override = _stand_ghost_material
		
		if duration <= 0.02:
			_stand_ghost_material.albedo_color.a = 0.22
			_stand_ghost_material.emission_energy_multiplier = 1.4
			current_stand_instance.scale = target_scale
		else:
			var tw := current_stand_instance.create_tween()
			if tw:
				tw.set_parallel(true)
				tw.tween_property(_stand_ghost_material, "albedo_color:a", 0.22, duration).set_trans(Tween.TRANS_SINE)
				tw.tween_property(_stand_ghost_material, "emission_energy_multiplier", 1.4, duration)
				tw.tween_property(current_stand_instance, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# In battle: become fully visible and completely solid!
		if duration <= 0.02:
			for child in _cached_stand_meshes:
				if is_instance_valid(child):
					child.material_override = null
			current_stand_instance.scale = target_scale
		else:
			var tw := current_stand_instance.create_tween()
			tw.tween_property(_stand_ghost_material, "albedo_color:a", 0.95, duration * 0.7).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(_stand_ghost_material, "emission_energy_multiplier", 2.6, duration * 0.7)
			tw.parallel().tween_property(current_stand_instance, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				if not is_in_arena and not is_dead:
					return
				for child in _cached_stand_meshes:
					if is_instance_valid(child):
						child.material_override = null
			)

func _start_stand_hover_loop() -> void:
	if _stand_hover_tween and _stand_hover_tween.is_valid():
		_stand_hover_tween.kill()
	if not current_stand_instance or not is_instance_valid(current_stand_instance):
		return

	var hover_base_pos := _get_stand_target_pos(base_stage_pos)
	current_stand_instance.position = hover_base_pos
	
	_stand_hover_tween = current_stand_instance.create_tween().set_loops()
	_stand_hover_tween.tween_property(current_stand_instance, "position:y", hover_base_pos.y + 0.08, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_stand_hover_tween.tween_property(current_stand_instance, "position:y", hover_base_pos.y - 0.04, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _ready() -> void:
	stage_pos = position
	base_stage_pos = stage_pos
	base_scale = scale
	untransformed_scale = scale
	base_rot = rotation_degrees
	arena_pos = Vector3(stage_pos.x, 1.20, 1.35 if duelist_id == 1 else -1.35)

func _get_or_create_model(path: String) -> Node3D:
	if path == "":
		return null
	if _model_cache.has(path) and is_instance_valid(_model_cache[path]):
		return _model_cache[path]
	if ResourceLoader.exists(path):
		var scene_res = load(path)
		if scene_res is PackedScene:
			var inst: Node3D = scene_res.instantiate() as Node3D
			add_child(inst)
			inst.position = Vector3.ZERO
			inst.scale = Vector3.ONE
			inst.visible = false
			_model_cache[path] = inst
			return inst
	return null

func _switch_to_model(path: String) -> void:
	if path == "":
		return
	var next_model: Node3D = _get_or_create_model(path)
	if next_model:
		for k in _model_cache:
			var m: Node3D = _model_cache[k]
			if is_instance_valid(m):
				m.visible = (m == next_model)
		current_model_instance = next_model

func _load_model(path: String) -> void:
	_switch_to_model(path)

func set_rooster(p_rooster: RoosterData) -> void:
	rooster_data = p_rooster
	is_dead = false
	is_in_arena = false
	stage_pos = position
	base_stage_pos = stage_pos
	base_scale = scale
	untransformed_scale = base_scale
	base_rot = rotation_degrees
	arena_pos = Vector3(stage_pos.x, 1.20, 1.35 if duelist_id == 1 else -1.35)
	if rooster_data:
		if rooster_data.model_path != "":
			_switch_to_model(rooster_data.model_path)
		# Pre-warm alt / transformed model and KO model so zero load lag during combat
		if rooster_data.alt_model_path != "":
			_get_or_create_model(rooster_data.alt_model_path)
		_get_or_create_model("res://resources/world/friedchicken(dead).vox")
	_setup_stand_companion()

## Steps down from the elevated roost stage into the combat arena ring
func play_step_into_arena() -> void:
	if is_dead or is_in_arena:
		return
	is_in_arena = true
	base_stage_pos = arena_pos
	
	# Cocktaro leap into arena
	var tw := create_tween()
	# 1. Anticipation: Crouch down on stage
	tw.tween_property(self, "scale", Vector3(base_scale.x * 1.2, base_scale.y * 0.7, base_scale.z * 1.2), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. High leap arc down into arena ring
	var mid_jump := (stage_pos + arena_pos) * 0.5 + Vector3(0, 0.65, 0)
	tw.tween_property(self, "position", mid_jump, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.15, base_scale.z * 0.85), 0.12)
	
	# 3. Land on arena floor with impact squash
	tw.tween_property(self, "position", arena_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.3, base_scale.y * 0.7, base_scale.z * 1.3), 0.10)
	
	# 4. Spring back to idle
	tw.tween_property(self, "scale", base_scale, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		scale = base_scale
		position = arena_pos
		rotation_degrees = base_rot
		if is_transformed and rooster_data and rooster_data.rooster_id == "cluckey_d_puffy":
			_start_gear5_drums_loop()
	)

	# If Star Platinum is present, he manifests solid and glides into the arena
	if current_stand_instance and is_instance_valid(current_stand_instance):
		_set_stand_ghostly_mode(false, 0.18)
		var stand_stage_pos := _get_stand_target_pos(stage_pos)
		var stand_arena_pos := _get_stand_target_pos(arena_pos)
		var stand_mid := (stand_stage_pos + stand_arena_pos) * 0.5 + Vector3(0, 0.85, 0)

		if _stand_hover_tween and _stand_hover_tween.is_valid():
			_stand_hover_tween.kill()

		var stw := current_stand_instance.create_tween()
		stw.tween_property(current_stand_instance, "position", stand_mid, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stw.tween_property(current_stand_instance, "position", stand_arena_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		stw.chain().tween_callback(_start_stand_hover_loop)

## Returns/hops back onto the elevated roost stage after round combat concludes
func play_return_to_stage() -> void:
	if is_dead or not is_in_arena:
		return
	is_in_arena = false
	base_stage_pos = stage_pos

	var tw := create_tween()
	# 1. Crouch on arena floor
	tw.tween_property(self, "scale", Vector3(base_scale.x * 1.2, base_scale.y * 0.7, base_scale.z * 1.2), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. High leap arc back up to stage
	var mid_jump := (arena_pos + stage_pos) * 0.5 + Vector3(0, 0.65, 0)
	tw.tween_property(self, "position", mid_jump, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.2, base_scale.z * 0.85), 0.14)
	
	# 3. Land on stage
	tw.tween_property(self, "position", stage_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.2, base_scale.y * 0.8, base_scale.z * 1.2), 0.10)
	
	# 4. Reset scale
	tw.tween_property(self, "scale", base_scale, 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		scale = base_scale
		position = stage_pos
		rotation_degrees = base_rot
		if is_transformed and rooster_data and rooster_data.rooster_id == "cluckey_d_puffy":
			_start_gear5_drums_loop()
	)

	# Star Platinum glides back up and fades back to ghostly phantom mode
	if current_stand_instance and is_instance_valid(current_stand_instance):
		var stand_arena_pos := _get_stand_target_pos(arena_pos)
		var stand_stage_pos := _get_stand_target_pos(stage_pos)
		var stand_mid := (stand_arena_pos + stand_stage_pos) * 0.5 + Vector3(0, 0.85, 0)

		if _stand_hover_tween and _stand_hover_tween.is_valid():
			_stand_hover_tween.kill()

		var stw := current_stand_instance.create_tween()
		stw.tween_property(current_stand_instance, "position", stand_mid, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stw.tween_property(current_stand_instance, "position", stand_stage_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		stw.chain().tween_callback(func():
			_set_stand_ghostly_mode(true, 0.20)
			_start_stand_hover_loop()
		)

## Melee Attack: charges up close directly in front of the enemy and delivers a physical slap/peck!
## For Hen-Goku, routes to Instant Transmission Teleport Strike!
## For Nechicko, routes to 360° Horizontal Spinning Top Dive!
func play_attack(target_pos: Vector3, _vfx_key: String = "", on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	if rooster_data and rooster_data.rooster_id == "hen_goku":
		play_hengoku_instant_transmission_strike(target_pos, on_hit_callback)
		return
	if rooster_data and rooster_data.rooster_id == "nechicko":
		play_nechicko_basic_attack(target_pos, on_hit_callback)
		return

	# Calculate strike position directly in front of the opponent
	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir_to_target * 1.2
	strike_pos.y = base_stage_pos.y

	var tween := create_tween()
	
	# 1. Anticipation: Quick crouch & step back
	var back_step: Vector3 = base_stage_pos - dir_to_target * 0.25
	tween.tween_property(self, "position", back_step, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 0.8, base_scale.z * 1.15), 0.1)

	# 2. Fast Speed Dash directly to Enemy's Face
	tween.tween_property(self, "position", strike_pos, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.9, base_scale.y * 1.1, base_scale.z * 1.25), 0.16)

	# 3. Physical Slap Jump & Body Swing Strike
	var slap_jump_pos: Vector3 = strike_pos + Vector3(0, 0.35, 0) + dir_to_target * 0.2
	var slap_rot: Vector3 = base_rot + Vector3(25.0, 35.0, -20.0)
	tween.tween_property(self, "position", slap_jump_pos, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", slap_rot, 0.08)

	# 4. Impact frame: trigger hit callback and impact squash
	tween.tween_callback(func():
		if on_hit_callback.is_valid():
			on_hit_callback.call()
	)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.3, base_scale.y * 0.7, base_scale.z * 1.3), 0.06).set_trans(Tween.TRANS_BOUNCE)

	# 5. Flip & Hop Back to Base Stage Position
	tween.tween_property(self, "position", base_stage_pos, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.24).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "scale", base_scale, 0.24).set_trans(Tween.TRANS_QUAD)

## Nechicko Basic Attack: Horizontal 360° spinning dive like a top, sweeping across the enemy with curved black-and-red crescent arcs
func play_nechicko_basic_attack(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir_to_target * 0.95
	strike_pos.y = base_stage_pos.y

	var tween := create_tween()

	# 1. Anticipation: Quick low coil
	var back_step: Vector3 = base_stage_pos - dir_to_target * 0.20
	tween.tween_property(self, "position", back_step, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.70, base_scale.z * 1.25), 0.08)

	# 2. Horizontal 360° Spinning Top Dive straight into the enemy face
	tween.tween_property(self, "position", strike_pos, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "rotation_degrees:y", base_rot.y + 720.0, 0.16)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.15, base_scale.z * 1.35), 0.16)

	# 3. Sweeping Slash Impact Frame
	tween.tween_callback(func():
		_spawn_nechicko_hit_slash(target_pos, dir_to_target)
		if on_hit_callback.is_valid():
			on_hit_callback.call()
	)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.35, base_scale.y * 0.75, base_scale.z * 1.35), 0.06).set_trans(Tween.TRANS_BOUNCE)

	# 4. Spin Rebound & Hop Back to Base Stage Position
	tween.tween_property(self, "position", base_stage_pos, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees:y", base_rot.y, 0.20).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x, 0.20)
	tween.parallel().tween_property(self, "rotation_degrees:z", base_rot.z, 0.20)
	tween.parallel().tween_property(self, "scale", base_scale, 0.20).set_trans(Tween.TRANS_QUAD)

## Nechicko basic attack impact: dynamic black and blood-red twin crescent claw slash with crimson sparks
func _spawn_nechicko_hit_slash(target_pos: Vector3, dir: Vector3) -> void:
	var hit_root := Node3D.new()
	var p: Node = get_parent() if get_parent() else self
	p.add_child(hit_root)
	if hit_root.is_inside_tree():
		hit_root.global_position = target_pos + Vector3(0, 0.5, 0)
		if dir.length() > 0.01:
			hit_root.look_at(hit_root.global_position + dir, Vector3.UP)
	else:
		hit_root.position = target_pos + Vector3(0, 0.5, 0)

	var s_mat := _get_cached_material("nechicko_slash_black", Color(0.04, 0.02, 0.02, 0.98), Color(0.95, 0.05, 0.05), 4.8, true, true)
	var red_mat := _get_cached_material("nechicko_slash_red", Color(1.0, 0.08, 0.08, 0.95), Color(1.0, 0.03, 0.03), 5.0, true, true)

	# Crescent Arc 1 (Obsidian Black)
	var arc1 := MeshInstance3D.new()
	var t_mesh1 := TorusMesh.new()
	t_mesh1.inner_radius = 0.45
	t_mesh1.outer_radius = 0.80
	t_mesh1.rings = 20
	t_mesh1.ring_segments = 6
	arc1.mesh = t_mesh1
	arc1.material_override = s_mat
	arc1.rotation_degrees = Vector3(0, 0, -30.0)
	arc1.scale = Vector3(0.001, 0.001, 0.001)
	hit_root.add_child(arc1)

	# Crescent Arc 2 (Blood Red counter arc)
	var arc2 := MeshInstance3D.new()
	var t_mesh2 := TorusMesh.new()
	t_mesh2.inner_radius = 0.45
	t_mesh2.outer_radius = 0.80
	t_mesh2.rings = 20
	t_mesh2.ring_segments = 6
	arc2.mesh = t_mesh2
	arc2.material_override = red_mat
	arc2.rotation_degrees = Vector3(0, 0, 30.0)
	arc2.scale = Vector3(0.001, 0.001, 0.001)
	hit_root.add_child(arc2)

	_trigger_screen_flash(Color(0.85, 0.04, 0.04, 0.35), 0.12)
	_trigger_camera_shake(0.35, 0.18)

	var tw := hit_root.create_tween()
	tw.tween_property(arc1, "scale", Vector3(1.3, 1.3, 0.35), 0.08).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(arc2, "scale", Vector3(1.3, 1.3, 0.35), 0.08).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(s_mat, "albedo_color:a", 0.0, 0.16).set_delay(0.05)
	tw.parallel().tween_property(red_mat, "albedo_color:a", 0.0, 0.16).set_delay(0.05)
	tw.chain().tween_callback(hit_root.queue_free)

## Hen-Goku Instant Transmission (Zanzoken) Teleport Strike:
## Clean anime Instant Transmission: deliberate stance vanish, clear disappear pause, reappears in enemy face, 3-strike flurry, and clean teleport return!
func play_hengoku_instant_transmission_strike(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir_to_target * 1.15
	strike_pos.y = base_stage_pos.y

	var tween := create_tween()

	# --- Phase 1: Instant Transmission Stance & Vanish (0.14s + 0.12s pause) ---
	# Focused transmission crouch & vertical compression
	tween.tween_property(self, "scale", Vector3(base_scale.x * 0.75, base_scale.y * 1.25, base_scale.z * 0.75), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(-10.0, 0.0, 0.0), 0.12)
	tween.tween_callback(func():
		visible = false
	)
	# Deliberate vanish pause so the empty stage is clearly perceived
	tween.tween_interval(0.12)

	# --- Phase 2: Materialize in Front of Enemy (0.10s) ---
	tween.tween_callback(func():
		position = strike_pos
		rotation_degrees = base_rot
		scale = Vector3(base_scale.x * 1.25, base_scale.y * 0.85, base_scale.z * 1.25)
		visible = true
	)
	tween.tween_property(self, "scale", base_scale, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.06)

	# --- Phase 3: Rapid 3-Strike Martial Arts Flurry (0.28s) ---
	# Hit 1 (Left Wing Slap)
	tween.tween_property(self, "rotation_degrees", base_rot + Vector3(15.0, 30.0, -25.0), 0.07).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "position", strike_pos + dir_to_target * 0.18, 0.07)
	
	# Hit 2 (Right Wing Slash)
	tween.tween_property(self, "rotation_degrees", base_rot + Vector3(20.0, -35.0, 25.0), 0.07).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "position", strike_pos + Vector3(0, 0.2, 0) + dir_to_target * 0.22, 0.07)
	
	# Hit 3 (Heavy Impact Kick / Peck)
	tween.tween_property(self, "rotation_degrees", base_rot + Vector3(35.0, 10.0, -10.0), 0.09).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.45, base_scale.y * 0.7, base_scale.z * 1.45), 0.09)
	tween.tween_callback(func():
		if on_hit_callback.is_valid():
			on_hit_callback.call()
		_trigger_camera_shake(0.28, 0.10)
	)
	# Follow-through impact pause
	tween.tween_interval(0.10)

	# --- Phase 4: Instant Transmission Return to Stage (0.08s + 0.10s pause + 0.14s land) ---
	tween.tween_property(self, "scale", Vector3(base_scale.x * 0.8, base_scale.y * 1.2, base_scale.z * 0.8), 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		visible = false
	)
	# Vanish travel interval
	tween.tween_interval(0.10)
	tween.tween_callback(func():
		position = base_stage_pos
		rotation_degrees = base_rot
		scale = Vector3(base_scale.x * 1.2, base_scale.y * 0.8, base_scale.z * 1.2)
		visible = true
	)
	tween.tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

## Hen-Goku Kame-cock: Deep Kamehameha charging crouch, inward-converging Ki rings, massive continuous laser beam, and camera shake!
func play_kamecock_beam(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var is_gold: bool = current_model_instance != null and "Golden" in str(current_model_instance.name)
	var beam_color: Color = Color(1.0, 0.85, 0.2) if is_gold else Color(0.2, 0.75, 1.0)
	var core_color: Color = Color(1.0, 1.0, 0.8) if is_gold else Color(0.85, 0.95, 1.0)

	var dir: Vector3 = (target_pos - global_position).normalized()
	var start_pos: Vector3 = global_position + Vector3(0, 0.6, 0) + dir * 0.7
	var end_pos: Vector3 = target_pos + Vector3(0, 0.6, 0)
	var beam_dist: float = start_pos.distance_to(end_pos)

	# --- 1. Charge-up phase: Deep low Kamehameha crouch & converging Ki sphere ---
	var charge_root := Node3D.new()
	get_parent().add_child(charge_root)
	charge_root.global_position = start_pos

	var charge_orb := MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.38
	orb_mesh.height = 0.76
	charge_orb.mesh = orb_mesh

	var orb_key: String = "kamecock_orb_gold" if is_gold else "kamecock_orb_cyan"
	var orb_mat := _get_cached_material(orb_key, Color(core_color.r, core_color.g, core_color.b, 0.88), beam_color, 3.5)
	charge_orb.material_override = orb_mat
	charge_root.add_child(charge_orb)
	charge_orb.scale = Vector3(0.05, 0.05, 0.05)

	# Converging Ki energy ring
	var converge_ring := MeshInstance3D.new()
	var c_mesh := TorusMesh.new()
	c_mesh.inner_radius = 0.5
	c_mesh.outer_radius = 0.9
	converge_ring.mesh = c_mesh
	converge_ring.material_override = orb_mat
	charge_root.add_child(converge_ring)
	converge_ring.scale = Vector3(1.8, 1.8, 1.8)

	var tween := create_tween()
	# Deep low Kamehameha crouch pose: pulled back with wings tucked to side
	var charge_rot: Vector3 = base_rot + Vector3(18.0, -32.0, 12.0)
	tween.tween_property(self, "position", base_stage_pos - dir * 0.4, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", charge_rot, 0.3)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.75, base_scale.z * 1.25), 0.3)
	# Charge orb growth + Ki energy suction
	tween.parallel().tween_property(charge_orb, "scale", Vector3(1.35, 1.35, 1.35), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(converge_ring, "scale", Vector3(0.1, 0.1, 0.1), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	# --- 2. Explosive Fire Beam ---
	tween.tween_callback(func():
		charge_root.queue_free()

		# Forward thrust surge & recoil recovery
		var recoil_tw := create_tween()
		recoil_tw.tween_property(self, "position", base_stage_pos + dir * 0.45, 0.07).set_trans(Tween.TRANS_EXPO)
		recoil_tw.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(25.0, 0.0, 0.0), 0.07)
		recoil_tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.15, base_scale.z * 1.35), 0.07)
		recoil_tw.tween_property(self, "position", base_stage_pos, 0.35).set_trans(Tween.TRANS_BACK).set_delay(0.32)
		recoil_tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.35).set_delay(0.32)
		recoil_tw.parallel().tween_property(self, "scale", base_scale, 0.35).set_delay(0.32)

		# Build 3D Laser Beam Hierarchy
		var beam_root := Node3D.new()
		get_parent().add_child(beam_root)
		beam_root.global_position = start_pos
		beam_root.look_at(end_pos, Vector3.UP)

		# Outer glowing beam cylinder
		var outer_beam := MeshInstance3D.new()
		var outer_mesh := CylinderMesh.new()
		outer_mesh.top_radius = 0.42
		outer_mesh.bottom_radius = 0.42
		outer_mesh.height = beam_dist
		outer_beam.mesh = outer_mesh
		outer_beam.rotation_degrees.x = 90.0
		outer_beam.position = Vector3(0, 0, -beam_dist * 0.5)

		var outer_key: String = "kamecock_outer_gold" if is_gold else "kamecock_outer_cyan"
		var outer_mat := _get_cached_material(outer_key, Color(beam_color.r, beam_color.g, beam_color.b, 0.65), beam_color, 2.8)
		outer_beam.material_override = outer_mat
		beam_root.add_child(outer_beam)

		# Inner intense white-hot core
		var core_beam := MeshInstance3D.new()
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 0.2
		core_mesh.bottom_radius = 0.2
		core_mesh.height = beam_dist
		core_beam.mesh = core_mesh
		core_beam.rotation_degrees.x = 90.0
		core_beam.position = Vector3(0, 0, -beam_dist * 0.5)

		var core_key: String = "kamecock_core_gold" if is_gold else "kamecock_core_cyan"
		var core_mat := _get_cached_material(core_key, Color(core_color.r, core_color.g, core_color.b, 0.95), core_color, 4.5)
		core_beam.material_override = core_mat
		beam_root.add_child(core_beam)

		# Impact Burst Sphere at Defender
		var impact_burst := MeshInstance3D.new()
		var impact_mesh := SphereMesh.new()
		impact_mesh.radius = 1.05
		impact_mesh.height = 2.1
		impact_burst.mesh = impact_mesh
		impact_burst.material_override = outer_mat
		get_parent().add_child(impact_burst)
		impact_burst.global_position = end_pos
		impact_burst.scale = Vector3(0.2, 0.2, 0.2)

		# Beam pulsation, impact hit callback, and camera rumble
		var beam_tw := create_tween()
		beam_root.scale = Vector3(0.1, 0.1, 1.0)
		beam_tw.tween_property(beam_root, "scale", Vector3(1.4, 1.4, 1.0), 0.08).set_trans(Tween.TRANS_EXPO)
		beam_tw.parallel().tween_property(impact_burst, "scale", Vector3(1.8, 1.8, 1.8), 0.08).set_trans(Tween.TRANS_BACK)
		
		beam_tw.tween_callback(func():
			if on_hit_callback.is_valid():
				on_hit_callback.call()
			_trigger_camera_shake(0.42, 0.14)
		)

		# Beam fade out & cleanup
		beam_tw.tween_interval(0.28)
		beam_tw.tween_property(beam_root, "scale", Vector3(0.001, 0.001, 1.0), 0.16).set_trans(Tween.TRANS_QUAD)
		beam_tw.parallel().tween_property(impact_burst, "scale", Vector3(0.001, 0.001, 0.001), 0.16)
		beam_tw.chain().tween_callback(func():
			beam_root.queue_free()
			impact_burst.queue_free()
		)
	)

## -----------------------------------------------------------------------------
## CHICK YAGAMI MOVESET (Death Note / Light Yagami & Shinigami Ryuk)
## -----------------------------------------------------------------------------

## Chick Yagami Self-Strain (for Ryuk's Watch 1 HP Cost / Shinigami pact)
func play_yagami_self_strain(amount: int = 1) -> void:
	if is_dead:
		return
	_trigger_screen_flash(Color(0.6, 0.05, 0.2, 0.45), 0.10)
	var tw := create_tween()
	tw.tween_property(self, "position:y", base_stage_pos.y + 0.15, 0.06).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "rotation_degrees:z", base_rot.z - 12.0, 0.06)
	tw.tween_property(self, "position:y", base_stage_pos.y, 0.12).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.12)
	FloatingText3D.spawn(self, global_position + Vector3(0, 1.2, 0), "-%d HP (SHINIGAMI DEAL)" % amount, Color(0.85, 0.15, 0.35), true)

## Chick Note: Opens 3D Death Note voxel book, frantic scribbling motion with purple ink sparks,
## book snap-shut shockwave, and manifests a dark purple curse seal on the victim with +Poop DoT!
func play_yagami_chick_note(target_pos: Vector3, target_visual: RoosterVisual3D = null, added_stacks: int = 5) -> void:
	if is_dead:
		return

	var book_path: String = "res://resources/models/chick_yagami/yagami book.vox"
	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()

	# 1. Spawn Voxel Death Note floating in front of Yagami
	var book_node: Node3D = null
	if ResourceLoader.exists(book_path):
		var book_res = load(book_path)
		if book_res is PackedScene:
			book_node = book_res.instantiate()
			get_parent().add_child(book_node)
			book_node.global_position = global_position + Vector3(0, 0.42, 0) + dir_to_target * 0.72
			book_node.scale = Vector3(0.01, 0.01, 0.01)
			book_node.rotation_degrees = Vector3(32.0, base_rot.y, 0.0)

	# 2. Dark Miasma Particles / Rings around the Book
	var miasma_root := Node3D.new()
	get_parent().add_child(miasma_root)
	miasma_root.global_position = global_position + Vector3(0, 0.35, 0) + dir_to_target * 0.72

	var miasma_mat := _get_cached_material("yagami_miasma", Color(0.65, 0.1, 0.95, 0.9), Color(0.7, 0.15, 1.0), 4.0)

	# 3. Create Scribble Writing Tween
	var write_tw := create_tween()
	if book_node:
		write_tw.tween_property(book_node, "scale", Vector3(1.0, 1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)

	# Yagami leans furiously into the book
	write_tw.parallel().tween_property(self, "position", base_stage_pos + dir_to_target * 0.28, 0.1)
	write_tw.parallel().tween_property(self, "rotation_degrees:x", base_rot.x + 30.0, 0.1)

	# Rapid quill scribbling vibration (jerking head and beak into pages)
	for i in range(4):
		var sign_z: float = 1.0 if (i % 2 == 0) else -1.0
		write_tw.tween_property(self, "rotation_degrees:z", base_rot.z + sign_z * 16.0, 0.04)
		write_tw.parallel().tween_property(self, "rotation_degrees:x", base_rot.x + 35.0 - float(i % 2) * 8.0, 0.04)
		# Spawn small flying ink drop / spark from book
		write_tw.tween_callback(func():
			if book_node and is_instance_valid(book_node):
				var drop := MeshInstance3D.new()
				var d_sphere := SphereMesh.new()
				d_sphere.radius = 0.04
				d_sphere.height = 0.08
				drop.mesh = d_sphere
				drop.material_override = miasma_mat
				miasma_root.add_child(drop)
				drop.position = Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.25), randf_range(-0.15, 0.15))
				var d_tw := drop.create_tween()
				d_tw.tween_property(drop, "position:y", drop.position.y + 0.35, 0.18).set_trans(Tween.TRANS_QUAD)
				d_tw.parallel().tween_property(drop, "scale", Vector3(0.001, 0.001, 0.001), 0.18)
				d_tw.chain().tween_callback(drop.queue_free)
		)

	# 4. Final Dot Stroke & Shockwave Snap Shut
	write_tw.tween_property(self, "rotation_degrees:x", base_rot.x - 10.0, 0.08).set_trans(Tween.TRANS_QUAD)
	write_tw.tween_property(self, "rotation_degrees:x", base_rot.x + 38.0, 0.05).set_trans(Tween.TRANS_EXPO)

	write_tw.tween_callback(func():
		_trigger_screen_flash(Color(0.55, 0.08, 0.85, 0.45), 0.12)
		_trigger_camera_shake(0.35, 0.14)

		# Book shockwave ring
		var snap_ring := MeshInstance3D.new()
		var r_mesh := TorusMesh.new()
		r_mesh.inner_radius = 0.25
		r_mesh.outer_radius = 0.55
		snap_ring.mesh = r_mesh
		snap_ring.material_override = miasma_mat
		miasma_root.add_child(snap_ring)
		snap_ring.scale = Vector3(0.1, 0.1, 0.1)

		var r_tw := snap_ring.create_tween()
		r_tw.tween_property(snap_ring, "scale", Vector3(2.2, 0.2, 2.2), 0.18).set_trans(Tween.TRANS_EXPO)
		r_tw.parallel().tween_property(miasma_mat, "albedo_color:a", 0.0, 0.18)
		r_tw.chain().tween_callback(snap_ring.queue_free)

		# Book shrinks and vanishes
		if book_node and is_instance_valid(book_node):
			var b_tw := book_node.create_tween()
			b_tw.tween_property(book_node, "scale", Vector3(0.001, 0.001, 0.001), 0.10).set_trans(Tween.TRANS_QUAD)
			b_tw.chain().tween_callback(book_node.queue_free)

		# Yagami returns to roost stance
		var back_tw := create_tween()
		back_tw.tween_property(self, "position", base_stage_pos, 0.18).set_trans(Tween.TRANS_BACK)
		back_tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.18)

		# Cleanup miasma root
		var c_tw := miasma_root.create_tween()
		c_tw.tween_interval(0.3)
		c_tw.chain().tween_callback(miasma_root.queue_free)

		# 5. Direct Curse Impact on Opponent (No death sigil)
		if target_visual and is_instance_valid(target_visual):
			target_visual.play_hit(0, false)
		FloatingText3D.spawn(self, target_pos + Vector3(0, 1.2, 0), "+%d POOP DOT (CHICK NOTE)" % added_stacks, Color(0.75, 0.15, 0.95), true)
	)

## Chixecution: Manic Kira Laugh, Giant Shinigami Ryuk summons from shadows,
## Supersonic Death Swoop with twin scythe slashes, dark purple DoT detonation, and heart attack collapse!
func play_yagami_chixecution(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var ryuk_path: String = "res://resources/models/chick_yagami/ryuk.vox"
	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()

	# --- Phase 1: Manic Kira Laugh Tremor ---
	var laugh_tw := create_tween()
	laugh_tw.tween_property(self, "rotation_degrees:x", base_rot.x - 30.0, 0.12).set_trans(Tween.TRANS_QUAD)
	laugh_tw.parallel().tween_property(self, "position:y", base_stage_pos.y + 0.15, 0.12)

	# Laughter shaking vibration
	for i in range(5):
		var sign_z: float = 1.0 if (i % 2 == 0) else -1.0
		laugh_tw.tween_property(self, "rotation_degrees:z", base_rot.z + sign_z * 10.0, 0.04)
		laugh_tw.parallel().tween_property(self, "rotation_degrees:x", base_rot.x - 28.0 + float(i % 2) * 5.0, 0.04)

	laugh_tw.tween_callback(func():
		_trigger_screen_flash(Color(0.40, 0.05, 0.60, 0.55), 0.15)

		# --- Phase 2: Giant Shinigami Ryuk Manifests High Behind Yagami ---
		var ryuk_node: Node3D = null
		if ResourceLoader.exists(ryuk_path):
			var ryuk_res = load(ryuk_path)
			if ryuk_res is PackedScene:
				ryuk_node = ryuk_res.instantiate()
				get_parent().add_child(ryuk_node)
				var spawn_pos: Vector3 = base_stage_pos - dir_to_target * 0.6 + Vector3(0, 1.8, 0)
				ryuk_node.global_position = spawn_pos
				ryuk_node.scale = Vector3(0.01, 0.01, 0.01)
				ryuk_node.rotation_degrees = base_rot

		if not ryuk_node:
			if on_hit_callback.is_valid():
				on_hit_callback.call()
			return

		var ryuk_tw := ryuk_node.create_tween()
		ryuk_tw.tween_property(ryuk_node, "scale", Vector3(0.95, 0.95, 0.95), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ryuk_tw.tween_interval(0.08)

		var yagami_tw := create_tween()
		yagami_tw.tween_property(self, "position", base_stage_pos, 0.18).set_trans(Tween.TRANS_BACK)
		yagami_tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.18)

		# --- Phase 3A: Ryuk Flies Like a Crow Around the Enemy ---
		var side_vec: Vector3 = Vector3(-dir_to_target.z, 0.0, dir_to_target.x).normalized()
		var crow_radius: float = 1.6
		var wp_flank_left: Vector3 = target_pos + side_vec * crow_radius + Vector3(0, 1.8, 0)
		var wp_behind: Vector3 = target_pos + dir_to_target * crow_radius + Vector3(0, 2.1, 0)
		var wp_flank_right: Vector3 = target_pos - side_vec * crow_radius + Vector3(0, 1.8, 0)
		var wp_apex_dive: Vector3 = target_pos - dir_to_target * 1.5 + Vector3(0, 2.3, 0)

		# Swoop from spawn into high left flank
		ryuk_tw.tween_property(ryuk_node, "global_position", wp_flank_left, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ryuk_tw.parallel().tween_property(ryuk_node, "rotation_degrees:y", base_rot.y + 90.0, 0.16)

		# Circle behind enemy like a stalking crow
		ryuk_tw.tween_property(ryuk_node, "global_position", wp_behind, 0.14).set_trans(Tween.TRANS_SINE)
		ryuk_tw.parallel().tween_property(ryuk_node, "rotation_degrees:y", base_rot.y + 180.0, 0.14)

		# Circle right flank
		ryuk_tw.tween_property(ryuk_node, "global_position", wp_flank_right, 0.14).set_trans(Tween.TRANS_SINE)
		ryuk_tw.parallel().tween_property(ryuk_node, "rotation_degrees:y", base_rot.y + 270.0, 0.14)

		# Reach apex dive point above/in front
		ryuk_tw.tween_property(ryuk_node, "global_position", wp_apex_dive, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ryuk_tw.parallel().tween_property(ryuk_node, "rotation_degrees:y", base_rot.y + 360.0, 0.12)

		# --- Phase 3B: Ryuk Supersonic Execution Swoop & Scythe Slits ---
		var strike_pos: Vector3 = target_pos - dir_to_target * 1.1 + Vector3(0, 0.45, 0)
		ryuk_tw.tween_property(ryuk_node, "global_position", strike_pos, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		ryuk_tw.parallel().tween_property(ryuk_node, "scale", Vector3(1.05, 1.05, 1.05), 0.15)

		var scythe_root := Node3D.new()
		get_parent().add_child(scythe_root)
		scythe_root.global_position = target_pos + Vector3(0, 0.6, 0)
		scythe_root.look_at(scythe_root.global_position + dir_to_target, Vector3.UP)

		var scythe_mat := _get_cached_material("yagami_scythe", Color(0.75, 0.08, 0.95, 0.95), Color(0.85, 0.15, 0.35), 5.0, true, true)

		var scythe1 := MeshInstance3D.new()
		var arc1 := TorusMesh.new()
		arc1.inner_radius = 0.60
		arc1.outer_radius = 1.10
		arc1.rings = 24
		arc1.ring_segments = 6
		scythe1.mesh = arc1
		scythe1.material_override = scythe_mat
		scythe1.rotation_degrees = Vector3(0, 0, -42.0)
		scythe1.scale = Vector3(0.001, 0.001, 0.001)
		scythe_root.add_child(scythe1)

		var scythe2 := MeshInstance3D.new()
		var arc2 := TorusMesh.new()
		arc2.inner_radius = 0.60
		arc2.outer_radius = 1.10
		arc2.rings = 24
		arc2.ring_segments = 6
		scythe2.mesh = arc2
		scythe2.material_override = scythe_mat
		scythe2.rotation_degrees = Vector3(0, 0, 42.0)
		scythe2.scale = Vector3(0.001, 0.001, 0.001)
		scythe_root.add_child(scythe2)

		ryuk_tw.tween_property(ryuk_node, "rotation_degrees:y", base_rot.y + 360.0, 0.12).set_trans(Tween.TRANS_QUAD)
		ryuk_tw.parallel().tween_property(scythe1, "scale", Vector3(1.6, 1.6, 0.4), 0.08).set_trans(Tween.TRANS_EXPO)
		ryuk_tw.parallel().tween_property(scythe2, "scale", Vector3(1.6, 1.6, 0.4), 0.08).set_trans(Tween.TRANS_EXPO)

		ryuk_tw.tween_callback(func():
			_trigger_screen_flash(Color(0.85, 0.1, 0.25, 0.70), 0.15)
			_trigger_camera_shake(0.55, 0.22)

			if on_hit_callback.is_valid():
				on_hit_callback.call()

			# --- Phase 4: DoT Detonation Nova Blast ---
			var blast_root := Node3D.new()
			get_parent().add_child(blast_root)
			blast_root.global_position = target_pos + Vector3(0, 0.5, 0)

			var sphere := MeshInstance3D.new()
			var s_mesh := SphereMesh.new()
			s_mesh.radius = 1.2
			s_mesh.height = 2.4
			sphere.mesh = s_mesh
			sphere.material_override = scythe_mat
			sphere.scale = Vector3(0.1, 0.1, 0.1)
			blast_root.add_child(sphere)

			var shock_ring := MeshInstance3D.new()
			var r_mesh := TorusMesh.new()
			r_mesh.inner_radius = 0.8
			r_mesh.outer_radius = 1.4
			shock_ring.mesh = r_mesh
			shock_ring.material_override = scythe_mat
			shock_ring.scale = Vector3(0.1, 0.1, 0.1)
			blast_root.add_child(shock_ring)

			var b_tw := blast_root.create_tween()
			b_tw.tween_property(sphere, "scale", Vector3(1.8, 1.8, 1.8), 0.15).set_trans(Tween.TRANS_EXPO)
			b_tw.parallel().tween_property(shock_ring, "scale", Vector3(2.5, 0.3, 2.5), 0.15).set_trans(Tween.TRANS_EXPO)
			b_tw.parallel().tween_property(scythe_mat, "albedo_color:a", 0.0, 0.18).set_delay(0.05)
			b_tw.chain().tween_callback(func():
				blast_root.queue_free()
				scythe_root.queue_free()
			)

			FloatingText3D.spawn(self, target_pos + Vector3(0, 1.3, 0), "CHIXECUTION! (HEART ATTACK)", Color.RED, true)
		)

		var sky_pos: Vector3 = target_pos + Vector3(0, 4.5, -2.0)
		ryuk_tw.tween_property(ryuk_node, "global_position", sky_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ryuk_tw.parallel().tween_property(ryuk_node, "scale", Vector3(0.001, 0.001, 0.001), 0.22)
		ryuk_tw.chain().tween_callback(ryuk_node.queue_free)
	)

## Forwarder for backwards compatibility
func play_yagami_ryuk_attack(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	play_yagami_chixecution(target_pos, on_hit_callback)

## Ryuk's Watch (Mindgame Prediction):
## Ryuk appears flying behind the enemy.
## If wrong (prediction missed): A question mark '?' appears over Ryuk, he tilts in confusion, and fades away.
## If right (prediction succeeded): Ryuk swoops directly above the enemy and drops poop.vox straight onto the enemy,
## splatting with Poop DoT floating text, screen flash, and impact VFX, while Ryuk ascends and vanishes!
func play_yagami_ryuks_watch(success: bool, target_visual: RoosterVisual3D = null) -> void:
	if is_dead:
		return

	var ryuk_path: String = "res://resources/models/chick_yagami/ryuk.vox"
	var poop_path: String = "res://resources/models/chick_yagami/poop.vox"

	var parent_node: Node = get_parent() if get_parent() else self
	var enemy_pos: Vector3 = base_stage_pos + Vector3.FORWARD * 4.0
	var dir_from_yagami: Vector3 = Vector3.FORWARD

	if target_visual and is_instance_valid(target_visual):
		enemy_pos = target_visual.global_position if target_visual.is_inside_tree() else target_visual.position
		var my_pos: Vector3 = global_position if is_inside_tree() else base_stage_pos
		dir_from_yagami = (enemy_pos - my_pos).normalized()

	# 1. Ryuk manifests flying behind the enemy
	var ryuk_node: Node3D = null
	if ResourceLoader.exists(ryuk_path):
		var ryuk_res = load(ryuk_path)
		if ryuk_res is PackedScene:
			ryuk_node = ryuk_res.instantiate()
			parent_node.add_child(ryuk_node)

	var behind_enemy_pos: Vector3 = enemy_pos + dir_from_yagami * 0.95 + Vector3(0, 1.45, 0)
	if ryuk_node:
		if ryuk_node.is_inside_tree():
			ryuk_node.global_position = behind_enemy_pos
			ryuk_node.look_at(enemy_pos + Vector3(0, 0.6, 0), Vector3.UP)
		else:
			ryuk_node.position = behind_enemy_pos
		ryuk_node.scale = Vector3(0.01, 0.01, 0.01)

	# Yagami sinister smirk / lean
	var yagami_tw := create_tween()
	yagami_tw.tween_property(self, "position:y", base_stage_pos.y + 0.12, 0.12)
	yagami_tw.parallel().tween_property(self, "rotation_degrees:x", base_rot.x - 18.0, 0.12)

	# Ryuk scales up with back-ease into flight behind the enemy
	if ryuk_node:
		var ryuk_tw := ryuk_node.create_tween()
		ryuk_tw.tween_property(ryuk_node, "scale", Vector3(0.95, 0.95, 0.95), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Flying bobbing motion
		ryuk_tw.tween_property(ryuk_node, "position:y", behind_enemy_pos.y + 0.12, 0.12).set_trans(Tween.TRANS_SINE)

		ryuk_tw.tween_callback(func():
			if not is_instance_valid(ryuk_node):
				return

			if success:
				# ─── SUCCESS: RYUK POOPS RIGHT ON THE ENEMY! ───
				# Ryuk swoops up directly above the enemy
				var above_enemy_pos: Vector3 = enemy_pos + dir_from_yagami * 0.2 + Vector3(0, 1.85, 0)
				var swoop_tw := ryuk_node.create_tween()
				swoop_tw.tween_property(ryuk_node, "global_position", above_enemy_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				swoop_tw.parallel().tween_property(ryuk_node, "rotation_degrees:x", 30.0, 0.16)

				swoop_tw.tween_callback(func():
					if not is_instance_valid(ryuk_node):
						return

					# Spawn poop.vox from Ryuk
					var poop_node: Node3D = null
					if ResourceLoader.exists(poop_path):
						var poop_res = load(poop_path)
						if poop_res is PackedScene:
							poop_node = poop_res.instantiate()
							parent_node.add_child(poop_node)

					var poop_drop_pos: Vector3 = ryuk_node.global_position + Vector3(0, -0.35, 0)
					var hit_pos: Vector3 = enemy_pos + Vector3(0, 0.55, 0)

					if poop_node:
						poop_node.global_position = poop_drop_pos
						poop_node.scale = Vector3(0.08, 0.08, 0.08)

						var poop_tw := poop_node.create_tween()
						poop_tw.tween_property(poop_node, "scale", Vector3(0.65, 0.65, 0.65), 0.06).set_trans(Tween.TRANS_BACK)
						# Drop rapidly straight down onto enemy
						poop_tw.tween_property(poop_node, "global_position", hit_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
						poop_tw.parallel().tween_property(poop_node, "rotation_degrees:y", 360.0, 0.22)

						poop_tw.tween_callback(func():
							_trigger_screen_flash(Color(0.45, 0.30, 0.10, 0.55), 0.14)
							_trigger_camera_shake(0.35, 0.14)
							CombatVFX3D.play_effect(parent_node, hit_pos, "normalpoop")

							if target_visual and is_instance_valid(target_visual):
								target_visual.play_hit(0, false)

							FloatingText3D.spawn(self, global_position + Vector3(0, 1.4, 0), "KEIKAKU DORI! (JUST AS PLANNED!)", Color.WHITE, true)
							FloatingText3D.spawn(self, hit_pos + Vector3(0, 0.9, 0), "+2 POOP DOT (PREDICTED)", Color(0.75, 0.15, 0.95), true)
						)

						# Squash on enemy head
						poop_tw.tween_property(poop_node, "scale", Vector3(0.95, 0.28, 0.95), 0.08).set_trans(Tween.TRANS_EXPO)
						poop_tw.tween_interval(0.35)
						poop_tw.tween_property(poop_node, "scale", Vector3(0.001, 0.001, 0.001), 0.18).set_trans(Tween.TRANS_QUAD)
						poop_tw.chain().tween_callback(poop_node.queue_free)
					else:
						# Fallback if poop.vox model is unavailable
						CombatVFX3D.play_effect(parent_node, hit_pos, "normalpoop")
						if target_visual and is_instance_valid(target_visual):
							target_visual.play_hit(0, false)
						FloatingText3D.spawn(self, hit_pos + Vector3(0, 0.9, 0), "+2 POOP DOT (PREDICTED)", Color(0.75, 0.15, 0.95), true)

					# Ryuk ascends triumphantly into the sky
					var ryuk_exit_tw := ryuk_node.create_tween()
					ryuk_exit_tw.tween_interval(0.20)
					ryuk_exit_tw.tween_property(ryuk_node, "global_position:y", above_enemy_pos.y + 2.8, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					ryuk_exit_tw.parallel().tween_property(ryuk_node, "scale", Vector3(0.001, 0.001, 0.001), 0.45)
					ryuk_exit_tw.chain().tween_callback(ryuk_node.queue_free)
				)

			else:
				# ─── WRONG: QUESTION MARK APPEARS & RYUK FADES AWAY ───
				# Ryuk tilts head in confusion
				var confuse_tw := ryuk_node.create_tween()
				confuse_tw.tween_property(ryuk_node, "rotation_degrees:z", 26.0, 0.12).set_trans(Tween.TRANS_QUAD)

				# Pop a bold 3D Question Mark right above Ryuk's head
				var q_label := Label3D.new()
				q_label.text = "?"
				q_label.font_size = 80
				q_label.modulate = Color(1.0, 0.90, 0.15, 1.0)
				q_label.outline_modulate = Color(0.12, 0.08, 0.0, 1.0)
				q_label.outline_size = 14
				q_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				q_label.no_depth_test = true
				q_label.position = Vector3(0, 0.70, 0)
				q_label.scale = Vector3.ZERO
				ryuk_node.add_child(q_label)

				var q_tw := q_label.create_tween()
				q_tw.tween_property(q_label, "scale", Vector3(1.3, 1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

				FloatingText3D.spawn(self, global_position + Vector3(0, 1.3, 0), "PREDICTION MISSED!", Color.GRAY, true)

				# Chick Yagami recoils in shock/disbelief
				var shock_tw := create_tween()
				shock_tw.tween_property(self, "rotation_degrees:z", base_rot.z + 18.0, 0.08)
				shock_tw.parallel().tween_property(self, "position:y", base_stage_pos.y + 0.15, 0.08)
				shock_tw.tween_property(self, "rotation_degrees", base_rot, 0.15)
				shock_tw.parallel().tween_property(self, "position", base_stage_pos, 0.15)

				# Hold confused beat, then Ryuk and ? fade away
				confuse_tw.tween_interval(0.25)
				confuse_tw.tween_property(ryuk_node, "scale", Vector3(0.001, 0.001, 0.001), 0.22).set_trans(Tween.TRANS_QUAD)
				confuse_tw.parallel().tween_property(ryuk_node, "position:y", ryuk_node.position.y + 0.25, 0.22)
				confuse_tw.chain().tween_callback(ryuk_node.queue_free)
		)

	# Yagami recovers to base stance
	var recover_tw := create_tween()
	recover_tw.tween_interval(0.35)
	recover_tw.tween_property(self, "position", base_stage_pos, 0.18)
	recover_tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.18)


## Cocktaro Signature Attack: Strikes JoJo pose, Star Platinum instantly teleports to enemy face, unleashes a furious multiple punch flurry, and teleports back!
func play_cocktaro_stand_attack(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var dir_to_target: Vector3 = (target_pos - base_stage_pos).normalized()
	var stand_origin: Vector3 = _get_stand_target_pos(base_stage_pos)

	if not current_stand_instance or not is_instance_valid(current_stand_instance):
		_setup_stand_companion()

	if not current_stand_instance or not is_instance_valid(current_stand_instance):
		if on_hit_callback.is_valid():
			on_hit_callback.call()
		return

	if _stand_hover_tween and _stand_hover_tween.is_valid():
		_stand_hover_tween.kill()

	# 1. Cocktaro JoJo Pose
	var pose_tw := create_tween()
	pose_tw.tween_property(self, "position", base_stage_pos - dir_to_target * 0.2, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pose_tw.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(0, 15.0, -10.0), 0.12)

	_set_stand_ghostly_mode(false, 0.01)

	# Perpendicular side vector for alternating left/right punches
	var side_vec: Vector3 = Vector3(-dir_to_target.z, 0, dir_to_target.x).normalized()
	var strike_pos: Vector3 = target_pos - dir_to_target * 0.95 + Vector3(0, 0.22, 0)

	# 2. INSTANT TELEPORT TO ENEMY FACE
	var stand_tw := current_stand_instance.create_tween()
	
	# Vanish flash from Cocktaro's back
	stand_tw.tween_property(current_stand_instance, "scale", Vector3(0.001, 0.001, 0.001), 0.04).set_trans(Tween.TRANS_QUAD)
	# Instant position warp
	stand_tw.tween_callback(func():
		current_stand_instance.position = strike_pos
		current_stand_instance.rotation_degrees = base_rot
	)
	# Materialize in enemy's face
	stand_tw.tween_property(current_stand_instance, "scale", Vector3(1.35, 1.35, 1.35), 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3. --- POWERFUL PUNCH BARRAGE ("ORA ORA ORA ORA!") ---
	# Punch 1: Heavy Right Jab
	stand_tw.tween_property(current_stand_instance, "position", strike_pos + dir_to_target * 0.34 + side_vec * 0.22, 0.055)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(12.0, 25.0, 15.0), 0.055)
	
	# Punch 2: Heavy Left Hook
	stand_tw.tween_property(current_stand_instance, "position", strike_pos + dir_to_target * 0.34 - side_vec * 0.22, 0.055)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(12.0, -25.0, -15.0), 0.055)

	# Punch 3: Right Straight
	stand_tw.tween_property(current_stand_instance, "position", strike_pos + dir_to_target * 0.38 + side_vec * 0.20 + Vector3(0, 0.1, 0), 0.055)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(-10.0, 22.0, 12.0), 0.055)

	# Punch 4: Left Upper
	stand_tw.tween_property(current_stand_instance, "position", strike_pos + dir_to_target * 0.38 - side_vec * 0.20 - Vector3(0, 0.08, 0), 0.055)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(-10.0, -22.0, -12.0), 0.055)

	# Punch 5: Double Fist Windup
	stand_tw.tween_property(current_stand_instance, "position", strike_pos - dir_to_target * 0.2 + Vector3(0, 0.22, 0), 0.07).set_trans(Tween.TRANS_QUAD)
	stand_tw.parallel().tween_property(current_stand_instance, "scale", Vector3(1.5, 1.5, 1.5), 0.07)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(-20.0, 0.0, 0.0), 0.07)

	# Punch 6: GRAND SLAM OVERHAND FINISHER!
	stand_tw.tween_property(current_stand_instance, "position", strike_pos + dir_to_target * 0.45 + Vector3(0, -0.1, 0), 0.08).set_trans(Tween.TRANS_BACK)
	stand_tw.parallel().tween_property(current_stand_instance, "rotation_degrees", base_rot + Vector3(35.0, 0.0, 0.0), 0.08)
	stand_tw.parallel().tween_property(current_stand_instance, "scale", Vector3(1.6, 1.35, 1.6), 0.08)

	# Impact Frame Trigger
	stand_tw.tween_callback(func():
		if on_hit_callback.is_valid():
			on_hit_callback.call()
		_trigger_camera_shake(0.42, 0.14)
	)

	# 4. INSTANT TELEPORT RETURN BEHIND COCKTARO
	stand_tw.tween_interval(0.1)
	# Instant pop vanish
	stand_tw.tween_property(current_stand_instance, "scale", Vector3(0.001, 0.001, 0.001), 0.05)
	# Reappear behind Cocktaro
	stand_tw.tween_callback(func():
		current_stand_instance.position = stand_origin
		current_stand_instance.rotation_degrees = base_rot
	)
	stand_tw.tween_property(current_stand_instance, "scale", Vector3(1.05, 1.05, 1.05), 0.07).set_trans(Tween.TRANS_BACK)
	stand_tw.chain().tween_callback(_start_stand_hover_loop)

	# Cocktaro relaxes back to neutral
	pose_tw.chain().tween_property(self, "position", base_stage_pos, 0.2).set_trans(Tween.TRANS_BACK).set_delay(0.4)
	pose_tw.parallel().tween_property(self, "rotation_degrees", base_rot, 0.2).set_delay(0.4)

func _stop_gear5_drums_loop() -> void:
	if _gear5_drums_tween and _gear5_drums_tween.is_valid():
		_gear5_drums_tween.kill()
		_gear5_drums_tween = null
	scale = base_scale
	position = base_stage_pos
	rotation_degrees = base_rot

func _start_gear5_drums_loop() -> void:
	_stop_gear5_drums_loop()
	if not is_transformed or not rooster_data or rooster_data.rooster_id != "cluckey_d_puffy" or is_dead:
		return

	_gear5_drums_tween = create_tween().set_loops()
	# Drums of Liberation rhythm: Doom -> Dut -> Da Da!
	# 1. Doom (Hop 1 left tilt)
	_gear5_drums_tween.tween_property(self, "position:y", base_stage_pos.y + 0.10, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gear5_drums_tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.95, base_scale.y * 1.10, base_scale.z * 0.95), 0.12)
	_gear5_drums_tween.parallel().tween_property(self, "rotation_degrees:z", base_rot.z - 5.0, 0.12)
	_gear5_drums_tween.tween_property(self, "position:y", base_stage_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE)
	_gear5_drums_tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.05, base_scale.y * 0.95, base_scale.z * 1.05), 0.08)

	# 2. Dut (Hop 2 right tilt)
	_gear5_drums_tween.tween_property(self, "position:y", base_stage_pos.y + 0.14, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gear5_drums_tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.94, base_scale.y * 1.12, base_scale.z * 0.94), 0.13)
	_gear5_drums_tween.parallel().tween_property(self, "rotation_degrees:z", base_rot.z + 5.0, 0.13)
	_gear5_drums_tween.tween_property(self, "position:y", base_stage_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE)
	_gear5_drums_tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.06, base_scale.y * 0.94, base_scale.z * 1.06), 0.08)

	# 3. Da Da! (Joyful laugh bounce)
	_gear5_drums_tween.tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_ELASTIC)
	_gear5_drums_tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
	_gear5_drums_tween.tween_interval(0.20)

## Cluckey D Puffy "Gomu Gomu no Red Hawk" (Flaming Rubber Beak / Comet Strike):
## Deep rubber slingshot pull-back -> friction heat tremble -> supersonic fire bullet snap -> explosive Red Hawk flaming impact shockwave & screen flash -> elastic recoil!
func play_cluckey_gum_slash(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return
	_stop_gear5_drums_loop()

	var dir: Vector3 = (target_pos - base_stage_pos).normalized()
	var side_vec: Vector3 = Vector3(-dir.z, 0, dir.x).normalized()
	var strike_pos: Vector3 = target_pos - dir * 1.10
	strike_pos.y = base_stage_pos.y

	var pull_pos: Vector3 = base_stage_pos - dir * 0.95

	var tween := create_tween()

	# --- Phase 1: Deep Slingshot Draw-Back & Rubber Strain (0.18s) ---
	tween.tween_property(self, "position", pull_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.65, base_scale.y * 0.65, base_scale.z * 2.2), 0.18)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(-20.0, 0.0, 0.0), 0.18)

	# --- Phase 2: Friction Heat Tremble at Maximum Strain (0.08s) ---
	# High-frequency heat tremble as tension reaches maximum
	tween.tween_property(self, "position", pull_pos + side_vec * 0.04, 0.02)
	tween.tween_property(self, "position", pull_pos - side_vec * 0.04, 0.02)
	tween.tween_property(self, "position", pull_pos, 0.02)
	tween.tween_interval(0.02)

	# --- Phase 3: Supersonic Fire Bullet SNAP Launch (0.06s) ---
	tween.tween_callback(func():
		_spawn_launch_speed_burst(pull_pos + Vector3(0, 0.4, 0), dir)
	)
	tween.tween_property(self, "position", strike_pos, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.55, base_scale.y * 0.55, base_scale.z * 2.8), 0.06)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(10.0, 0.0, 0.0), 0.06)

	# --- Phase 4: RED HAWK Flaming Shockwave Impact (0.28s) ---
	# Massive flaming beak strike into opponent's face
	tween.tween_property(self, "position", strike_pos + dir * 0.45, 0.04).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.6, base_scale.y * 1.6, base_scale.z * 0.65), 0.04)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(25.0, 0.0, 0.0), 0.04)

	# Explosive Fiery Blast Impact
	tween.tween_callback(func():
		_spawn_red_hawk_impact_explosion(strike_pos + dir * 0.35 + Vector3(0, 0.4, 0), dir)
		_trigger_screen_flash(Color(1.0, 0.45, 0.12, 0.75), 0.14)
		_trigger_camera_shake(0.50, 0.22)
		if on_hit_callback.is_valid():
			on_hit_callback.call()
	)
	tween.tween_interval(0.12)

	# --- Phase 5: Elastic Rubber Rebound Recoil (0.28s) ---
	tween.tween_property(self, "position", base_stage_pos - dir * 0.35, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.25, base_scale.z * 0.85), 0.12)
	
	tween.tween_property(self, "position", base_stage_pos + dir * 0.12, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 0.9, base_scale.z * 1.15), 0.08)
	
	tween.tween_property(self, "position", base_stage_pos, 0.08).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "scale", base_scale, 0.08)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.08)

	tween.chain().tween_callback(_start_gear5_drums_loop)

## Cluckey D Puffy 5th Gear: Gigant Bajrang Gun / Gigant Stomp!
## Cartoon moonwalk leap, MASSIVE cartoon inflation to colossal size, meteor ground slam, and rubber recoil bounce!
func play_cluckey_gear5_bajrang_attack(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return
	_stop_gear5_drums_loop()

	var dir: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir * 0.4
	strike_pos.y = base_stage_pos.y

	var tween := create_tween()

	# 1. Joyful Moonwalk Hop & 360 Spin (0.22s)
	tween.tween_property(self, "position:y", base_stage_pos.y + 2.4, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position:x", (base_stage_pos.x + strike_pos.x) * 0.5, 0.22)
	tween.parallel().tween_property(self, "position:z", (base_stage_pos.z + strike_pos.z) * 0.5, 0.22)
	tween.parallel().tween_property(self, "rotation_degrees:y", base_rot.y + 360.0, 0.22)
	tween.parallel().tween_property(self, "scale", base_scale * 1.35, 0.22)

	# 2. MASSIVE CARTOON INFLATION (Bajrang Gun / Gigant Stomp) (0.20s)
	tween.tween_property(self, "scale", base_scale * 3.6, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position", strike_pos + Vector3(0, 3.4, 0) - dir * 0.25, 0.20)
	tween.tween_interval(0.06)

	# 3. METEOR SLAM IMPACT DOWN ON OPPONENT! (0.10s)
	tween.tween_property(self, "position", strike_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 4.2, base_scale.y * 1.2, base_scale.z * 4.2), 0.10)

	# Impact Frame Trigger
	tween.tween_callback(func():
		if on_hit_callback.is_valid():
			on_hit_callback.call()
		_trigger_camera_shake(0.55, 0.22)
	)

	# 4. Joyful Cartoon Rubber Rebound Bounce (0.26s)
	tween.tween_property(self, "position:y", base_stage_pos.y + 1.4, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position:x", base_stage_pos.x, 0.16)
	tween.parallel().tween_property(self, "position:z", base_stage_pos.z, 0.16)
	tween.parallel().tween_property(self, "scale", base_scale * 1.4, 0.16)
	
	tween.tween_property(self, "position:y", base_stage_pos.y, 0.14).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_ELASTIC)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
	tween.chain().tween_callback(_start_gear5_drums_loop)

## Cluckey D Puffy Gum Barrier: Bouncy rubber puff with shield bubble!
func play_cluckey_gum_barrier(amount: int) -> void:
	if is_dead:
		return
	_stop_gear5_drums_loop()

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), "+%d GUM SHIELD" % amount, Color(1.0, 0.45, 0.75), true)

	var tween := create_tween()
	# 1. Subtle Bouncy Puff Up (0.14s)
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.18, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 1.20, base_scale.z * 1.25), 0.14)

	_spawn_shield_bubble("pink")

	# 2. Gentle rubber wobble (0.12s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.28, base_scale.y * 1.15, base_scale.z * 1.28), 0.06)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.18, base_scale.y * 1.24, base_scale.z * 1.18), 0.06)

	# 3. Spring Reset (0.16s)
	tween.tween_property(self, "position:y", base_stage_pos.y, 0.16).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "scale", base_scale, 0.16).set_trans(Tween.TRANS_ELASTIC)
	tween.chain().tween_callback(_start_gear5_drums_loop)

## Cluckey Gum-Gum Balloon Deflection: Subtle comical rubber bounce deflection!
func play_cluckey_balloon_deflection() -> void:
	_stop_gear5_drums_loop()
	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.7, 0), "BOING! DEFLECTED!", Color(1.0, 0.45, 0.85), true)

	var tween := create_tween()
	# 1. Subtle belly puff (0.05s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.28, base_scale.y * 1.22, base_scale.z * 1.28), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. Impact dent squash (0.04s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.32, base_scale.y * 0.96, base_scale.z * 1.16), 0.04).set_trans(Tween.TRANS_QUAD)
	
	# 3. Bouncy BOING snap-back outwards (0.06s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.16, base_scale.y * 1.28, base_scale.z * 1.22), 0.06).set_trans(Tween.TRANS_BACK)
	
	# 4. Elastic return back to normal (0.14s)
	tween.tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		scale = base_scale
		position = base_stage_pos
		_start_gear5_drums_loop()
	)

## Cluckey D Puffy 5th Gear Transformation: Drums of Liberation cartoon dance, white cloud aura eruption, Sun God Nika awakening!
func play_cluckey_gear5_transformation(alt_path: String, banner_text: String = "5TH GEAR: SUN GOD NIKA!") -> void:
	if is_dead or alt_path == "":
		return
	_stop_gear5_drums_loop()

	# Cartoon Cloud Aura Root
	var cloud_root := Node3D.new()
	get_parent().add_child(cloud_root)
	cloud_root.global_position = base_stage_pos

	# Swirling White Steam Aura
	var steam_mesh_inst := MeshInstance3D.new()
	var steam_mesh := TorusMesh.new()
	steam_mesh.inner_radius = 0.8
	steam_mesh.outer_radius = 1.3
	steam_mesh.rings = 24
	steam_mesh.ring_segments = 12
	steam_mesh_inst.mesh = steam_mesh
	steam_mesh_inst.position = Vector3(0, 0.6, 0)

	var steam_mat := _get_cached_material("gear5_transform_steam", Color(1.0, 1.0, 1.0, 0.85), Color(0.9, 0.95, 1.0), 3.5)
	steam_mesh_inst.material_override = steam_mat
	cloud_root.add_child(steam_mesh_inst)

	cloud_root.scale = Vector3(0.1, 0.1, 0.1)

	var tween := create_tween()

	# --- Phase 1: Drums of Liberation (Cartoon Bounces) ---
	# Hop 1 (Doom)
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.35, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.8, base_scale.y * 1.3, base_scale.z * 0.8), 0.1)
	tween.tween_property(self, "position:y", base_stage_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.75, base_scale.z * 1.25), 0.08)

	# Hop 2 (Dut)
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.45, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.75, base_scale.y * 1.35, base_scale.z * 0.75), 0.1)
	tween.tween_property(self, "position:y", base_stage_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE)

	# Hop 3 (Da Da! Apex Float & Steam Eruption)
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.75, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(cloud_root, "scale", Vector3(1.5, 1.5, 1.5), 0.18).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "rotation_degrees:y", base_rot.y + 360.0, 0.25)

	# --- Phase 2: Joyful Awakening Pop & Model Swap ---
	tween.tween_property(self, "scale", base_scale * 1.6, 0.1).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func():
		_load_model(alt_path)
		is_transformed = true
		FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.9, 0), banner_text, Color.WHITE, true)
	)

	# --- Phase 3: Cartoon Bounce Landing ---
	tween.tween_property(self, "position:y", base_stage_pos.y, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", base_scale, 0.15).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(steam_mat, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(func():
		cloud_root.queue_free()
		_start_gear5_drums_loop()
	)

## Cluckey D Puffy: Reverts from 5th Gear back to normal form when Tension expires.
## Anime gag deflation: white steam puffs out, tired squashing, swaps model back to cluckey.vox, and resets to normal stance!
func play_cluckey_gear5_exhaust_revert(banner_text: String = "5TH GEAR EXHAUSTED!") -> void:
	if is_dead:
		return
	_stop_gear5_drums_loop()
	is_transformed = false

	# Exhaust Steam Puff Root
	var puff_root := Node3D.new()
	get_parent().add_child(puff_root)
	puff_root.global_position = base_stage_pos + Vector3(0, 0.4, 0)

	var puff_mesh := MeshInstance3D.new()
	var p_sphere := SphereMesh.new()
	p_sphere.radius = 0.5
	p_sphere.height = 1.0
	puff_mesh.mesh = p_sphere

	var puff_mat := _get_cached_material("gear5_exhaust_puff", Color(0.9, 0.9, 0.95, 0.75), Color(0.8, 0.85, 0.95), 2.0)
	puff_mesh.material_override = puff_mat
	puff_root.add_child(puff_mesh)

	var p_tw := puff_root.create_tween()
	puff_root.scale = Vector3(0.2, 0.2, 0.2)
	p_tw.tween_property(puff_root, "scale", Vector3(1.8, 1.8, 1.8), 0.25).set_trans(Tween.TRANS_EXPO)
	p_tw.parallel().tween_property(puff_mat, "albedo_color:a", 0.0, 0.25)
	p_tw.chain().tween_callback(puff_root.queue_free)

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), banner_text, Color.WHITE, true)

	var tween := create_tween()
	# Deflation Squash (Puff... out of breath)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.35, base_scale.y * 0.65, base_scale.z * 1.35), 0.18).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var base_model_path: String = rooster_data.model_path if rooster_data else "res://resources/models/puffy/cluckey.vox"
		_load_model(base_model_path)
	)
	# Restores back to normal upright rooster idle
	tween.tween_property(self, "scale", base_scale, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position", base_stage_pos, 0.22)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.22)

## General revert to base form when a transformation timer expires
func play_revert_to_base(banner_text: String = "FORM EXPIRED") -> void:
	if is_dead:
		return
	is_transformed = false
	_stop_gear5_drums_loop()

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), banner_text, Color.WHITE)
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale * 1.25, 0.12).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var base_model_path: String = rooster_data.model_path if rooster_data else ""
		if base_model_path != "":
			_load_model(base_model_path)
	)
	tween.tween_property(self, "scale", base_scale, 0.16).set_trans(Tween.TRANS_BOUNCE)

## Helper to construct dynamic zigzag One For All emerald lightning arcs
func _spawn_decluck_zigzag_bolt(parent_node: Node3D, start_pos: Vector3, end_pos: Vector3, num_segments: int = 5, jitter: float = 0.25, mat: StandardMaterial3D = null) -> Node3D:
	var bolt_root := Node3D.new()
	parent_node.add_child(bolt_root)
	
	if OS.has_feature("web"):
		num_segments = mini(num_segments, 3)
	
	if not mat:
		mat = _get_cached_material("decluck_zigzag_emerald", Color(0.2, 1.0, 0.5, 0.95), Color(0.3, 1.0, 0.6), 4.5)

	var dir: Vector3 = end_pos - start_pos
	var dist: float = dir.length()
	if dist < 0.001:
		return bolt_root
	var dir_norm: Vector3 = dir.normalized()
	var right_vec: Vector3 = Vector3(-dir_norm.z, 0, dir_norm.x).normalized()
	if right_vec.length() < 0.1:
		right_vec = Vector3.RIGHT
	var up_vec: Vector3 = dir_norm.cross(right_vec).normalized()

	var points: Array[Vector3] = [start_pos]
	for i in range(1, num_segments):
		var t: float = float(i) / float(num_segments)
		var base_p: Vector3 = start_pos.lerp(end_pos, t)
		var offset_r: float = randf_range(-jitter, jitter)
		var offset_u: float = randf_range(-jitter, jitter)
		points.append(base_p + right_vec * offset_r + up_vec * offset_u)
	points.append(end_pos)

	for i in range(points.size() - 1):
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var seg_dir: Vector3 = p2 - p1
		var seg_len: float = seg_dir.length()
		if seg_len > 0.001:
			var link_node := Node3D.new()
			bolt_root.add_child(link_node)
			var cyl := MeshInstance3D.new()
			var c_mesh := CylinderMesh.new()
			c_mesh.top_radius = 0.025
			c_mesh.bottom_radius = 0.025
			c_mesh.height = seg_len
			cyl.mesh = c_mesh
			cyl.material_override = mat
			cyl.rotation_degrees.x = 90.0
			link_node.add_child(cyl)
			if link_node.is_inside_tree():
				link_node.global_position = (p1 + p2) * 0.5
				var align_up: Vector3 = up_vec if abs(seg_dir.normalized().dot(up_vec)) < 0.9 else right_vec
				link_node.look_at(p2, align_up)
			else:
				link_node.position = (p1 + p2) * 0.5

	return bolt_root

## Decluck All For One Punch: 3D Zigzag One For All Emerald Lightning Punch!
## Electricity scales directly with committed Taya (1 Taya = light arcs, 2 Taya = intense lightning aura, 3+ Taya = roaring lightning storm explosion!)
func play_decluck_all_for_one_punch(target_pos: Vector3, on_hit_callback: Callable = Callable(), taya_spent: int = 1) -> void:
	if is_dead:
		return

	var intensity: int = clampi(taya_spent, 1, 4)
	var dir: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir * 1.15
	strike_pos.y = base_stage_pos.y

	# Emerald Lightning Material
	var spark_mat := _get_cached_material("decluck_spark_" + str(intensity), Color(0.2, 1.0, 0.5, 0.95), Color(0.25, 1.0, 0.55), 3.5 + float(intensity) * 1.5)

	var lightning_root := Node3D.new()
	get_parent().add_child(lightning_root)
	lightning_root.global_position = base_stage_pos

	# Generate swirling zigzag lightning bolts around Decluck during windup
	var num_bolts: int = intensity * 3 # 3, 6, 9 bolts
	if OS.has_feature("web"):
		num_bolts = mini(num_bolts, 4)
	for b in range(num_bolts):
		var angle: float = (float(b) / float(num_bolts)) * TAU
		var start_p: Vector3 = base_stage_pos + Vector3(cos(angle) * 0.45, randf_range(0.1, 0.6), sin(angle) * 0.45)
		var end_p: Vector3 = base_stage_pos + Vector3(cos(angle + 1.2) * 0.75, randf_range(0.3, 0.9), sin(angle + 1.2) * 0.75)
		_spawn_decluck_zigzag_bolt(lightning_root, start_p, end_p, 4 + intensity, 0.15 + float(intensity) * 0.08, spark_mat)

	var tween := create_tween()

	# 1. Delaware Smash Deep Crouch & High-Voltage Electric Windup (0.16s)
	tween.tween_property(self, "position", base_stage_pos - dir * 0.35, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.75, base_scale.z * 1.25), 0.16)
	if intensity >= 2:
		tween.parallel().tween_callback(func():
			_trigger_screen_flash(Color(0.2, 1.0, 0.5, 0.30 * float(intensity - 1)), 0.08)
		)

	# 2. 100% Super Smash Leap Dash with Trailing Electric Current (0.14s)
	tween.tween_callback(func():
		# Trailing lightning streak from launch point
		var streak_count: int = intensity * 2
		if OS.has_feature("web"):
			streak_count = mini(streak_count, 3)
		for b in range(streak_count):
			var arc_start: Vector3 = base_stage_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3))
			var arc_end: Vector3 = strike_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 0.7), randf_range(-0.3, 0.3))
			_spawn_decluck_zigzag_bolt(lightning_root, arc_start, arc_end, 6, 0.25, spark_mat)
	)
	tween.tween_property(self, "position", strike_pos, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.15, base_scale.z * (1.2 + float(intensity) * 0.3)), 0.14)

	# 3. Detroit Smash Impact Slam & Scaled Lightning Detonation (0.08s)
	var smash_rot: Vector3 = base_rot + Vector3(35.0, 20.0, -25.0)
	tween.tween_property(self, "rotation_degrees", smash_rot, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.5, base_scale.y * 0.75, base_scale.z * 1.5), 0.08)

	tween.tween_callback(func():
		# Clean up windup lightning
		lightning_root.queue_free()

		# Spawn scaled radial electrical shockwave explosion
		var impact_root := Node3D.new()
		get_parent().add_child(impact_root)
		impact_root.global_position = target_pos + Vector3(0, 0.5, 0)

		var shockwave := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = 0.8 + float(intensity) * 0.4
		s_mesh.height = s_mesh.radius * 2.0
		shockwave.mesh = s_mesh
		shockwave.material_override = spark_mat
		impact_root.add_child(shockwave)

		# Multi-directional radial lightning branches into ground & opponent
		var num_impact_arcs: int = intensity * 4 # 4, 8, 12 radial lightning bolts
		if OS.has_feature("web"):
			num_impact_arcs = mini(num_impact_arcs, 5)
		for a in range(num_impact_arcs):
			var a_angle: float = (float(a) / float(num_impact_arcs)) * TAU
			var arc_len: float = randf_range(1.0, 1.8 + float(intensity) * 0.4)
			var a_end: Vector3 = impact_root.global_position + Vector3(cos(a_angle) * arc_len, randf_range(-0.4, 0.8), sin(a_angle) * arc_len)
			_spawn_decluck_zigzag_bolt(impact_root, impact_root.global_position, a_end, 5 + intensity, 0.3, spark_mat)

		# Sky lightning strike at max intensity (3+ Taya)
		if intensity >= 3:
			_spawn_decluck_zigzag_bolt(impact_root, impact_root.global_position + Vector3(0, 5.0, 0), impact_root.global_position, 8, 0.4, spark_mat)

		var s_tw := impact_root.create_tween()
		impact_root.scale = Vector3(0.2, 0.2, 0.2)
		s_tw.tween_property(impact_root, "scale", Vector3(1.6 + float(intensity) * 0.4, 1.6 + float(intensity) * 0.4, 1.6 + float(intensity) * 0.4), 0.12).set_trans(Tween.TRANS_EXPO)
		s_tw.parallel().tween_property(spark_mat, "albedo_color:a", 0.0, 0.16 + float(intensity) * 0.04)
		s_tw.chain().tween_callback(impact_root.queue_free)

		# Screen Flash and Camera Rumble scaled by Taya!
		_trigger_screen_flash(Color(0.25, 1.0, 0.55, 0.35 + float(intensity) * 0.20), 0.10 + float(intensity) * 0.04)
		_trigger_camera_shake(0.38 + float(intensity) * 0.14, 0.16 + float(intensity) * 0.05)

		if on_hit_callback.is_valid():
			on_hit_callback.call()
	)

	# 4. Acrobatic Backflip Reset to Base (0.24s)
	tween.tween_property(self, "position", base_stage_pos, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.24).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "scale", base_scale, 0.24).set_trans(Tween.TRANS_QUAD)

## Decluck All For One Heart: High-Voltage Full Cowling Electrical Forcefield
## Lightning density and shield barrier layers scale directly with committed Taya!
func play_decluck_all_for_one_heart(amount: int, taya_spent: int = 1) -> void:
	if is_dead:
		return

	var intensity: int = clampi(taya_spent, 1, 4)
	FloatingText3D.spawn(get_parent(), global_position, "+%d SHIELD" % amount, Color(0.2, 1.0, 0.5))

	var shield_root := Node3D.new()
	get_parent().add_child(shield_root)
	shield_root.global_position = global_position + Vector3(0, 0.6, 0)

	var glow_color := Color(0.2, 1.0, 0.5)

	# Sphere bubble
	var sphere_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.1 + float(intensity) * 0.15
	sphere_mesh.height = sphere_mesh.radius * 2.0
	sphere_inst.mesh = sphere_mesh

	var mat := _get_cached_material("decluck_shield_mat_" + str(intensity), Color(0.1, 0.95, 0.45, 0.35 + float(intensity) * 0.10), glow_color, 2.5 + float(intensity) * 1.0, false, true)
	sphere_inst.material_override = mat
	shield_root.add_child(sphere_inst)

	# Swirling Zigzag Lightning Cage wrapping around shield
	var spark_mat := _get_cached_material("decluck_spark_cage_" + str(intensity), Color(0.25, 1.0, 0.6, 0.95), Color(0.3, 1.0, 0.65), 4.0 + float(intensity) * 1.5)

	var num_arcs: int = intensity * 4 # 4, 8, 12 zigzag lightning bolts
	if OS.has_feature("web"):
		num_arcs = mini(num_arcs, 4)
	for a in range(num_arcs):
		var phi: float = randf_range(0.2, PI - 0.2)
		var theta: float = randf_range(0, TAU)
		var r: float = sphere_mesh.radius * 1.05
		var p_start := shield_root.global_position + Vector3(r * sin(phi) * cos(theta), r * cos(phi), r * sin(phi) * sin(theta))
		var p_end := shield_root.global_position + Vector3(r * sin(phi + 0.8) * cos(theta + 1.2), r * cos(phi + 0.8), r * sin(phi + 0.8) * sin(theta + 1.2))
		_spawn_decluck_zigzag_bolt(shield_root, p_start, p_end, 5, 0.20 + float(intensity) * 0.08, spark_mat)

	# Ground energy ring
	var ring_inst := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.35 + float(intensity) * 0.2
	ring_inst.mesh = ring_mesh
	ring_inst.position = Vector3(0, -0.55, 0)

	var ring_mat := _get_cached_material("decluck_shield_ring_" + str(intensity), Color(0.2, 1.0, 0.5, 0.65), glow_color, 3.0 + float(intensity) * 1.0)
	ring_inst.material_override = ring_mat
	shield_root.add_child(ring_inst)

	# Expand, pulse and fade out
	shield_root.scale = Vector3(0.2, 0.2, 0.2)
	var tween := shield_root.create_tween()
	tween.tween_property(shield_root, "scale", Vector3(1.25, 1.25, 1.25), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(shield_root, "scale", Vector3(1.05, 1.05, 1.05), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_delay(0.18)
	tween.parallel().tween_property(spark_mat, "albedo_color:a", 0.0, 0.22).set_delay(0.18)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.22).set_delay(0.18)
	tween.chain().tween_callback(shield_root.queue_free)

	if intensity >= 2:
		_trigger_screen_flash(Color(0.2, 1.0, 0.5, 0.25 * float(intensity - 1)), 0.10)

## Eren Pecker Claw Stomp / Titan Stomp:
## If normal form (Claw Stomp): Agile forward leap, sharp talon strike down, and expanding dust ring.
## If Titan form (Titan Stomp): Colossal skyward launch into the clouds, cataclysmic downward meteor crash,
## earth-shattering screen rumble, multi-tier volcanic shockwave, and visceral impact!
func play_eren_stomp(target_pos: Vector3, is_titan: bool = false, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var dir: Vector3 = (target_pos - base_stage_pos).normalized()
	var strike_pos: Vector3 = target_pos - dir * (0.85 if is_titan else 0.95)
	strike_pos.y = base_stage_pos.y

	var tween := create_tween()

	if not is_titan:
		# --- BASE CLAW STOMP ---
		# 1. Agile Leap into the Air (0.18s)
		tween.tween_property(self, "position", (base_stage_pos + strike_pos) * 0.5 + Vector3(0, 1.35, 0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x + 35.0, 0.18)
		tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.9, base_scale.y * 1.25, base_scale.z * 0.9), 0.18)

		# 2. Downward Claw Strike (0.12s)
		tween.tween_property(self, "position", strike_pos, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.12)
		tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.35, base_scale.y * 0.75, base_scale.z * 1.35), 0.12)

		# 3. Dust Shockwave & Hit
		tween.tween_callback(func():
			_trigger_camera_shake(0.3, 0.15)
			var shock_ring := MeshInstance3D.new()
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = 0.6
			ring_mesh.outer_radius = 1.1
			shock_ring.mesh = ring_mesh
			shock_ring.position = Vector3(0, 0.05, 0)

			var shock_mat := _get_cached_material("eren_stomp_shock", Color(0.85, 0.65, 0.35, 0.8), Color(0.9, 0.7, 0.3), 2.5)
			shock_ring.material_override = shock_mat

			get_parent().add_child(shock_ring)
			shock_ring.global_position = strike_pos

			var s_tw := shock_ring.create_tween()
			s_tw.tween_property(shock_ring, "scale", Vector3(2.5, 1.0, 2.5), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			s_tw.parallel().tween_property(shock_mat, "albedo_color:a", 0.0, 0.2)
			s_tw.chain().tween_callback(shock_ring.queue_free)

			if on_hit_callback.is_valid():
				on_hit_callback.call()
		)

		# 4. Hop Back Landing to Base
		tween.tween_property(self, "position", base_stage_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "scale", base_scale, 0.22).set_trans(Tween.TRANS_BOUNCE)

	else:
		# --- TITAN STOMP: COLOSSAL METEOR CRASH ---
		var active_titan_scale: Vector3 = base_scale

		# 1. Heavy Crouch & Charge (0.12s)
		tween.tween_property(self, "scale", Vector3(active_titan_scale.x * 1.4, active_titan_scale.y * 0.6, active_titan_scale.z * 1.4), 0.12)
		tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x - 15.0, 0.12)

		# 2. Stratospheric Launch into the Sky (0.28s) - Soars 5.8m high!
		var apex_pos: Vector3 = (base_stage_pos + strike_pos) * 0.5 + Vector3(0, 5.8, 0)
		tween.tween_property(self, "position", apex_pos, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x + 85.0, 0.28)
		tween.parallel().tween_property(self, "scale", Vector3(active_titan_scale.x * 0.8, active_titan_scale.y * 1.6, active_titan_scale.z * 0.8), 0.28)

		# 3. Meteor Crash Downward (0.14s)
		tween.tween_property(self, "position", strike_pos, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)
		tween.parallel().tween_property(self, "scale", Vector3(active_titan_scale.x * 1.65, active_titan_scale.y * 0.55, active_titan_scale.z * 1.65), 0.14)

		# 4. Cataclysmic Earth-Shattering Impact
		tween.tween_callback(func():
			_trigger_screen_flash(Color(1.0, 0.88, 0.35, 0.8), 0.20)
			_trigger_camera_shake(0.75, 0.40)

			# Dual Shockwave Rings (Golden inner blast + Volcanic dust outer ring)
			var shock_root := Node3D.new()
			get_parent().add_child(shock_root)
			shock_root.global_position = strike_pos

			# Inner Golden Blast
			var inner_ring := MeshInstance3D.new()
			var in_mesh := TorusMesh.new()
			in_mesh.inner_radius = 0.8
			in_mesh.outer_radius = 1.4
			inner_ring.mesh = in_mesh
			inner_ring.position = Vector3(0, 0.08, 0)

			var in_mat := _get_cached_material("eren_inner_shock", Color(1.0, 0.85, 0.2, 0.95), Color(1.0, 0.75, 0.15), 4.5)
			inner_ring.material_override = in_mat
			shock_root.add_child(inner_ring)

			# Outer Earth & Dust Ring
			var outer_ring := MeshInstance3D.new()
			var out_mesh := TorusMesh.new()
			out_mesh.inner_radius = 1.2
			out_mesh.outer_radius = 2.0
			outer_ring.mesh = out_mesh
			outer_ring.position = Vector3(0, 0.05, 0)

			var out_mat := _get_cached_material("eren_outer_shock", Color(0.75, 0.6, 0.4, 0.75), Color(0.8, 0.65, 0.35), 2.0)
			outer_ring.material_override = out_mat
			shock_root.add_child(outer_ring)

			# Flying Voxel Dust Puffs
			var dust_nodes: Array[Node3D] = []
			var dust_count: int = 4 if OS.has_feature("web") else 8
			for d in range(dust_count):
				var d_angle: float = float(d) * (TAU / float(dust_count))
				var puff := MeshInstance3D.new()
				var p_mesh := SphereMesh.new()
				p_mesh.radius = 0.35
				p_mesh.height = 0.7
				puff.mesh = p_mesh
				puff.material_override = out_mat
				puff.position = Vector3(0, 0.25, 0)
				shock_root.add_child(puff)
				dust_nodes.append(puff)

			var s_tw := shock_root.create_tween()
			s_tw.tween_property(inner_ring, "scale", Vector3(3.2, 1.0, 3.2), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			s_tw.parallel().tween_property(outer_ring, "scale", Vector3(4.5, 1.0, 4.5), 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			s_tw.parallel().tween_property(in_mat, "albedo_color:a", 0.0, 0.22)
			s_tw.parallel().tween_property(out_mat, "albedo_color:a", 0.0, 0.28)

			# Expand dust puffs outward
			for d in range(dust_nodes.size()):
				var d_node: Node3D = dust_nodes[d]
				var d_angle: float = float(d) * (TAU / float(dust_nodes.size()))
				var d_dest := Vector3(cos(d_angle) * 2.8, randf_range(0.1, 0.6), sin(d_angle) * 2.8)
				s_tw.parallel().tween_property(d_node, "position", d_dest, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				s_tw.parallel().tween_property(d_node, "scale", Vector3(1.8, 1.8, 1.8), 0.26)

			s_tw.chain().tween_callback(shock_root.queue_free)

			if on_hit_callback.is_valid():
				on_hit_callback.call()
		)

		# 5. Titan Roar Shudder & Heavy Hop Back (0.35s)
		tween.tween_property(self, "scale", Vector3(active_titan_scale.x * 1.25, active_titan_scale.y * 1.15, active_titan_scale.z * 1.25), 0.12).set_trans(Tween.TRANS_BACK)
		tween.tween_property(self, "position", base_stage_pos, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "scale", active_titan_scale, 0.26).set_trans(Tween.TRANS_BOUNCE)

## Eren Pecker Titan Transformation (Attack on Titan Overhaul):
## Hand-bite spark flare, 8 chaotic 3D zigzag heavenly golden lightning bolts striking from the sky,
## blinding flash, seismic camera shake, billowing white-hot Titan steam clouds, and awakening of giant Pecker Titan with a roar!
func play_eren_titan_transformation(alt_path: String, banner_text: String = "PECKER TITAN AWAKENED!") -> void:
	if is_dead:
		return

	if alt_path == "" and rooster_data and rooster_data.alt_model_path != "":
		alt_path = rooster_data.alt_model_path
	if alt_path == "":
		alt_path = "res://resources/models/eren_pecker/erentitan.vox"

	var parent_scene: Node = get_parent() if get_parent() else self
	var stage_target: Vector3 = global_position

	# 1. Screen flash & Camera shake
	_trigger_screen_flash(Color(1.0, 0.95, 0.45, 0.85), 0.22)
	_trigger_camera_shake(0.70, 0.35)

	# 2. Lightning Root Container
	var lightning_root := Node3D.new()
	parent_scene.add_child(lightning_root)
	lightning_root.global_position = stage_target

	# 3. Heavenly Golden AoT Lightning Material
	var bolt_mat := _get_cached_material("eren_titan_bolt", Color(1.0, 0.95, 0.35, 0.98), Color(1.0, 0.88, 0.18), 5.5)

	# 4. Central Luminous Heavenly Column
	var core_column := MeshInstance3D.new()
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 0.7
	col_mesh.bottom_radius = 1.4
	col_mesh.height = 9.5
	core_column.mesh = col_mesh
	core_column.material_override = bolt_mat
	core_column.position = Vector3(0, 4.75, 0)
	core_column.scale = Vector3(0.01, 1.0, 0.01)
	lightning_root.add_child(core_column)

	# 5. Generate Chaotic 3D Zigzag Lightning Bolts from the Sky
	var num_bolts := 3 if OS.has_feature("web") else 8
	var num_segs := 4 if OS.has_feature("web") else 8
	var bolts_data: Array[Dictionary] = []

	for b in range(num_bolts):
		var sky_x: float = randf_range(-3.2, 3.2)
		var sky_z: float = randf_range(-2.5, 2.5)
		var target_x: float = randf_range(-0.4, 0.4)
		var target_z: float = randf_range(-0.4, 0.4)

		# Generate 3D zigzag points from Y = 9.5 to Y = 0.3
		var pts: Array[Vector3] = []
		for i in range(num_segs):
			var t: float = float(i) / float(num_segs - 1)
			var px: float = lerp(sky_x, target_x, t) + (randf_range(-0.45, 0.45) if (i > 0 and i < num_segs - 1) else 0.0)
			var py: float = lerp(9.5, 0.3, t)
			var pz: float = lerp(sky_z, target_z, t) + (randf_range(-0.45, 0.45) if (i > 0 and i < num_segs - 1) else 0.0)
			pts.append(Vector3(px, py, pz))

		var b_dict := {
			"pts": pts,
			"link_nodes": [] as Array[Node3D]
		}

		for i in range(num_segs - 1):
			var p_start: Vector3 = pts[i]
			var p_end: Vector3 = pts[i + 1]
			var dir := p_end - p_start
			var dist := dir.length()

			var link_node := Node3D.new()
			link_node.position = (p_start + p_end) * 0.5
			lightning_root.add_child(link_node)

			var cyl_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.07
			cyl.bottom_radius = 0.07
			cyl.height = dist + 0.04
			cyl_inst.mesh = cyl
			cyl_inst.material_override = bolt_mat
			cyl_inst.rotation_degrees.x = 90.0
			link_node.add_child(cyl_inst)

			if dist > 0.001:
				var up_v := Vector3.UP if abs(dir.normalized().y) < 0.9 else Vector3.RIGHT
				link_node.look_at(lightning_root.global_position + p_end, up_v)

			b_dict["link_nodes"].append(link_node)

		bolts_data.append(b_dict)

	# 6. Hand-Bite Spark Sphere at Beak
	var spark_sphere := MeshInstance3D.new()
	var sp_mesh := SphereMesh.new()
	sp_mesh.radius = 0.35
	sp_mesh.height = 0.7
	spark_sphere.mesh = sp_mesh

	var spark_mat := _get_cached_material("eren_titan_spark", Color(1.0, 0.4, 0.1, 0.95), Color(1.0, 0.5, 0.15), 4.0)
	spark_sphere.material_override = spark_mat
	spark_sphere.position = Vector3(0, 0.7, 0.3)
	spark_sphere.scale = Vector3(0.001, 0.001, 0.001)
	add_child(spark_sphere)

	# 7. Lightning Impact Explosion Dome
	var dome_inst := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 1.7
	dome_mesh.height = 3.4
	dome_inst.mesh = dome_mesh
	dome_inst.position = Vector3(0, 0.7, 0)
	dome_inst.material_override = bolt_mat
	dome_inst.scale = Vector3(0.001, 0.001, 0.001)
	lightning_root.add_child(dome_inst)

	# 8. Ground Crater Shockwave Ring
	var ground_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.6
	ring_mesh.outer_radius = 1.1
	ground_ring.mesh = ring_mesh
	ground_ring.position = Vector3(0, 0.06, 0)
	ground_ring.material_override = bolt_mat
	ground_ring.scale = Vector3(0.1, 0.1, 0.1)
	lightning_root.add_child(ground_ring)

	# 9. Billowing Titan Steam Clouds Root
	var steam_root := Node3D.new()
	parent_scene.add_child(steam_root)
	steam_root.global_position = stage_target

	var steam_mat := _get_cached_material("eren_titan_steam", Color(0.93, 0.93, 0.96, 0.65), Color(1.0, 0.92, 0.6), 1.2)

	# Generate billowing steam puff spheres
	var steam_nodes: Array[MeshInstance3D] = []
	var steam_count: int = 4 if OS.has_feature("web") else 8
	for s in range(steam_count):
		var s_inst := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = randf_range(0.4, 0.7)
		s_mesh.height = s_mesh.radius * 2.0
		s_inst.mesh = s_mesh
		s_inst.material_override = steam_mat
		var s_offset := Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.6), randf_range(-0.7, 0.7))
		s_inst.position = s_offset
		s_inst.scale = Vector3(0.1, 0.1, 0.1)
		steam_root.add_child(s_inst)
		steam_nodes.append(s_inst)

	var titan_scale: Vector3 = untransformed_scale * 1.45
	var tween := create_tween()

	# Phase 1: Hand-Bite Trigger & Spark Flare (0.10s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.65, base_scale.z * 1.25), 0.10)
	tween.parallel().tween_property(spark_sphere, "scale", Vector3(2.2, 2.2, 2.2), 0.10)
	tween.chain().tween_property(spark_sphere, "scale", Vector3(0.001, 0.001, 0.001), 0.06)
	tween.tween_callback(spark_sphere.queue_free)

	# Phase 2: Heavenly Lightning Strikes Down with High Voltage Jitter (0.24s)
	tween.tween_method(func(_prog: float):
		for b in range(num_bolts):
			var bd: Dictionary = bolts_data[b]
			var link_nodes: Array[Node3D] = bd["link_nodes"]
			for l in link_nodes:
				l.scale = Vector3.ONE * (1.0 + randf_range(-0.35, 0.35))
		rotation_degrees.z = base_rot.z + randf_range(-16.0, 16.0)
		rotation_degrees.x = base_rot.x + randf_range(-10.0, 10.0)
	, 0.0, 1.0, 0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(core_column, "scale", Vector3(1.8, 1.0, 1.8), 0.24).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(self, "position:y", base_stage_pos.y + 0.65, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Phase 3: Blinding Blast, Titan Awaken, Roar Shudder & Steam Eruption
	tween.tween_callback(func():
		dome_inst.scale = Vector3(1.7, 1.7, 1.7)
		ground_ring.scale = Vector3(3.5, 1.0, 3.5)
		_trigger_screen_flash(Color(1.0, 0.98, 0.65, 0.9), 0.18)
		_trigger_camera_shake(0.75, 0.38)
		rotation_degrees = base_rot

		# Load giant Pecker Titan model
		is_transformed = true
		_load_model(alt_path)
		base_scale = titan_scale

		FloatingText3D.spawn(parent_scene, global_position + Vector3(0, 1.35, 0), banner_text, Color.WHITE, true)
	)

	# Dissolve lightning column, bolts, and dome
	tween.tween_property(dome_inst, "scale", Vector3(0.001, 0.001, 0.001), 0.12).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(core_column, "scale", Vector3(0.001, 1.0, 0.001), 0.12)
	tween.parallel().tween_property(lightning_root, "scale", Vector3(0.001, 0.001, 0.001), 0.12)
	tween.tween_callback(lightning_root.queue_free)

	# Phase 4: Billowing Steam Clouds Erupt Upward (0.55s)
	for s_node in steam_nodes:
		var target_scale := Vector3.ONE * randf_range(1.8, 2.6)
		var rise_y := randf_range(1.4, 2.5)
		tween.parallel().tween_property(s_node, "position:y", s_node.position.y + rise_y, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(s_node, "position:x", s_node.position.x * 2.2, 0.55)
		tween.parallel().tween_property(s_node, "position:z", s_node.position.z * 2.2, 0.55)
		tween.parallel().tween_property(s_node, "scale", target_scale, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(steam_mat, "albedo_color:a", 0.0, 0.55).set_delay(0.1)
	tween.tween_callback(steam_root.queue_free)

	# Phase 5: Heavy Titan Ground Slam & Primal Roar Stance
	tween.tween_property(self, "position", base_stage_pos, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", titan_scale * 1.25, 0.16)
	# Roar shudder: head tilts back, chest expands
	tween.chain().tween_property(self, "rotation_degrees:x", base_rot.x - 16.0, 0.14).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "scale", titan_scale * 1.12, 0.14)
	tween.chain().tween_property(self, "rotation_degrees:x", base_rot.x, 0.16).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", titan_scale, 0.16).set_trans(Tween.TRANS_BOUNCE)

## Eren Pecker Titan Power Exhausted:
## Titan staggers and slumps, intense white steam hisses out from the nape/body,
## and normal rooster Eren emerges coughing and shaking off the steam!
func play_eren_titan_revert(banner_text: String = "TITAN POWER EXHAUSTED") -> void:
	if is_dead:
		return

	is_transformed = false
	var parent_scene: Node = get_parent() if get_parent() else self
	var standard_scale: Vector3 = untransformed_scale

	_trigger_camera_shake(0.35, 0.25)
	FloatingText3D.spawn(parent_scene, global_position + Vector3(0, 1.1, 0), banner_text, Color.WHITE)

	# Steam Eruption Root
	var steam_root := Node3D.new()
	parent_scene.add_child(steam_root)
	steam_root.global_position = global_position

	var steam_mat := _get_cached_material("hengoku_revert_steam", Color(0.92, 0.92, 0.96, 0.75), Color(0.85, 0.85, 0.9), 1.0)

	var steam_puffs: Array[MeshInstance3D] = []
	var steam_puffs_count: int = 3 if OS.has_feature("web") else 7
	for s in range(steam_puffs_count):
		var s_inst := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = randf_range(0.35, 0.6)
		s_mesh.height = s_mesh.radius * 2.0
		s_inst.mesh = s_mesh
		s_inst.material_override = steam_mat
		s_inst.position = Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 1.0), randf_range(-0.4, 0.4))
		s_inst.scale = Vector3(0.1, 0.1, 0.1)
		steam_root.add_child(s_inst)
		steam_puffs.append(s_inst)

	var tween := create_tween()

	# 1. Titan Slump & Stamina Exhaustion (0.22s)
	tween.tween_property(self, "rotation_degrees:x", base_rot.x + 22.0, 0.22).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", base_scale * Vector3(1.15, 0.75, 1.15), 0.22)

	# 2. Steam Billows from Nape & Body
	for s_puff in steam_puffs:
		var target_scale := Vector3.ONE * randf_range(1.6, 2.4)
		var rise_y := randf_range(1.2, 2.2)
		tween.parallel().tween_property(s_puff, "position:y", s_puff.position.y + rise_y, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(s_puff, "scale", target_scale, 0.45)

	tween.parallel().tween_property(steam_mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)

	# 3. Model Swap back to Base Eren in the middle of steam (at 0.22s)
	tween.tween_callback(func():
		var base_model_path: String = rooster_data.model_path if rooster_data else "res://resources/models/eren_pecker/eren.vox"
		_load_model(base_model_path)
		base_scale = standard_scale
		rotation_degrees = base_rot
	)

	# 4. Normal Eren Pops Out & Shakes off Steam (0.20s)
	tween.tween_property(self, "scale", standard_scale * 1.2, 0.12).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", standard_scale, 0.14).set_trans(Tween.TRANS_BOUNCE)
	tween.chain().tween_callback(steam_root.queue_free)

## Eren Pecker Titan Upkeep: Hot steam billows from body and regenerates +2 HP
func play_titan_upkeep_drain() -> void:
	if is_dead:
		return

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.2, 0), "+2 HP (TITAN REGEN)", Color(0.25, 1.0, 0.45))

	# Hissing steam puff from nape
	var steam_inst := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.4
	s_mesh.height = 0.8
	steam_inst.mesh = s_mesh

	var steam_mat := _get_cached_material("titan_upkeep_steam", Color(0.92, 0.92, 0.95, 0.7), Color(0.9, 0.85, 0.8), 1.5)
	steam_inst.material_override = steam_mat
	steam_inst.position = Vector3(0, 0.6, -0.2)
	steam_inst.scale = Vector3(0.2, 0.2, 0.2)
	add_child(steam_inst)

	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees:x", base_rot.x + 8.0, 0.12).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.08, base_scale.y * 0.92, base_scale.z * 1.08), 0.12)
	tw.parallel().tween_property(steam_inst, "position:y", steam_inst.position.y + 1.2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(steam_inst, "scale", Vector3(1.8, 1.8, 1.8), 0.35)
	tw.parallel().tween_property(steam_mat, "albedo_color:a", 0.0, 0.35)

	tw.chain().tween_property(self, "rotation_degrees:x", base_rot.x, 0.15).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(self, "scale", base_scale, 0.15)
	tw.chain().tween_callback(steam_inst.queue_free)

## Attack on Titan: Hot white steam hisses from wounds as the Titan regenerates
func _spawn_titan_wound_steam(wound_pos: Vector3) -> void:
	var steam_root := Node3D.new()
	get_parent().add_child(steam_root)
	steam_root.global_position = wound_pos

	var mat := _get_cached_material("titan_wound_steam", Color(0.95, 0.95, 0.98, 0.75), Color(0.9, 0.9, 0.9), 1.2)

	for i in range(3):
		var puff := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = randf_range(0.25, 0.45)
		s_mesh.height = s_mesh.radius * 2.0
		puff.mesh = s_mesh
		puff.material_override = mat
		puff.position = Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.2), randf_range(-0.3, 0.3))
		steam_root.add_child(puff)

		var tw := steam_root.create_tween()
		tw.tween_property(puff, "position:y", puff.position.y + randf_range(0.7, 1.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(puff, "scale", Vector3(1.6, 1.6, 1.6), 0.35)

	var fade_tw := steam_root.create_tween()
	fade_tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_delay(0.08)
	fade_tw.chain().tween_callback(steam_root.queue_free)

## Attack on Titan: Huge clouds of steam billow high into the sky upon Titan defeat
func _spawn_titan_corpse_steam_dissolution() -> void:
	var steam_root := Node3D.new()
	get_parent().add_child(steam_root)
	steam_root.global_position = global_position

	var mat := _get_cached_material("titan_corpse_steam", Color(0.93, 0.93, 0.96, 0.8), Color(0.9, 0.9, 0.9), 1.5)

	var corpse_puffs: int = 3 if OS.has_feature("web") else 6
	for i in range(corpse_puffs):
		var puff := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = randf_range(0.5, 0.9)
		s_mesh.height = s_mesh.radius * 2.0
		puff.mesh = s_mesh
		puff.material_override = mat
		puff.position = Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.8), randf_range(-0.6, 0.6))
		puff.scale = Vector3(0.2, 0.2, 0.2)
		steam_root.add_child(puff)

		var tw := puff.create_tween()
		tw.tween_property(puff, "position:y", puff.position.y + randf_range(1.5, 2.8), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(puff, "scale", Vector3(2.2, 2.2, 2.2), 0.7)

	var fade_tw := steam_root.create_tween()
	fade_tw.tween_property(mat, "albedo_color:a", 0.0, 0.65).set_delay(0.15)
	fade_tw.chain().tween_callback(steam_root.queue_free)

## Nechicko Peck Breaker (Blood Demon Art: Exploding Claw Slash):
## Nechicko Peck Breaker (Blood Demon Art: Talon Drop Aerial Stomp Dive):
## Deep coiled spring crouch, hypersonic rocket launch into the sky above the enemy,
## 180° upside-down apex flip with crackling red electricity, vertical talon meteor divebomb onto enemy's head,
## devastating obsidian & blood-red shockwave detonation, and high 360° backflip rebound!
func play_nechicko_peck_breaker(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var sky_apex := Vector3(target_pos.x, base_stage_pos.y + 3.4, target_pos.z)
	var stomp_pos := target_pos + Vector3(0, 0.40, 0)

	# Claw Slashes & Impact Container on Target
	var claw_root := Node3D.new()
	get_parent().add_child(claw_root)
	if claw_root.is_inside_tree():
		claw_root.global_position = target_pos + Vector3(0, 0.55, 0)
	else:
		claw_root.position = target_pos + Vector3(0, 0.55, 0)

	# Obsidian Black with Glowing Blood-Red Edge
	var slash_mat := _get_cached_material("nechicko_peck_black", Color(0.04, 0.02, 0.02, 0.98), Color(0.95, 0.05, 0.05), 4.8, true, true)

	# Blazing Blood-Red Edge Material
	var red_mat := _get_cached_material("nechicko_peck_red", Color(1.0, 0.06, 0.06, 0.95), Color(1.0, 0.02, 0.02), 5.0, true, true)

	# Crescent Slash Arc 1 (Obsidian Black with Red Core)
	var slash1 := MeshInstance3D.new()
	var arc_mesh1 := TorusMesh.new()
	arc_mesh1.inner_radius = 0.55
	arc_mesh1.outer_radius = 0.90
	arc_mesh1.rings = 24
	arc_mesh1.ring_segments = 6
	slash1.mesh = arc_mesh1
	slash1.material_override = slash_mat
	slash1.rotation_degrees = Vector3(0, 0, -35.0)
	slash1.scale = Vector3(0.001, 0.001, 0.001)
	claw_root.add_child(slash1)

	# Crescent Slash Arc 2 (Blazing Blood-Red Counter Slash)
	var slash2 := MeshInstance3D.new()
	var arc_mesh2 := TorusMesh.new()
	arc_mesh2.inner_radius = 0.55
	arc_mesh2.outer_radius = 0.90
	arc_mesh2.rings = 24
	arc_mesh2.ring_segments = 6
	slash2.mesh = arc_mesh2
	slash2.material_override = red_mat
	slash2.rotation_degrees = Vector3(0, 0, 35.0)
	slash2.scale = Vector3(0.001, 0.001, 0.001)
	claw_root.add_child(slash2)

	var tween := create_tween()

	# Phase 1: Deep Coiled Spring Crouch (0.12s)
	tween.tween_property(self, "position:y", base_stage_pos.y - 0.10, 0.12).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.35, base_scale.y * 0.55, base_scale.z * 1.35), 0.12)

	# Phase 2: Hypersonic Rocket Leap into the Sky above Enemy (0.24s)
	tween.tween_property(self, "position", sky_apex, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.85, base_scale.y * 1.35, base_scale.z * 0.85), 0.24)

	# Phase 3: Apex 180° Upside-Down Flip (Talons Pointed Straight Down) (0.08s)
	tween.tween_property(self, "rotation_degrees:x", base_rot.x + 180.0, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 0.95, base_scale.z * 1.15), 0.08)

	# Phase 4: Hypersonic Talon Meteor Divebomb straight down onto enemy head (0.10s)
	tween.tween_property(self, "position", stomp_pos, 0.10).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.90, base_scale.y * 1.30, base_scale.z * 0.90), 0.10)

	# Phase 5: Heavy Detonation Stomp Impact
	tween.tween_callback(func():
		# Blood Red Screen Flash & Violent Screen Shake
		_trigger_screen_flash(Color(0.85, 0.04, 0.04, 0.75), 0.16)
		_trigger_camera_shake(0.70, 0.35)

		# Exploding Blood Detonation Root
		var blast_root := Node3D.new()
		get_parent().add_child(blast_root)
		if blast_root.is_inside_tree():
			blast_root.global_position = target_pos + Vector3(0, 0.45, 0)
		else:
			blast_root.position = target_pos + Vector3(0, 0.45, 0)

		# Inner Obsidian Blood Dome
		var dome := MeshInstance3D.new()
		var d_mesh := SphereMesh.new()
		d_mesh.radius = 1.25
		d_mesh.height = 2.5
		dome.mesh = d_mesh
		dome.material_override = slash_mat
		dome.scale = Vector3(0.2, 0.2, 0.2)
		blast_root.add_child(dome)

		# Outer Blood-Red Shockwave Ring
		var ring := MeshInstance3D.new()
		var r_mesh := TorusMesh.new()
		r_mesh.inner_radius = 0.7
		r_mesh.outer_radius = 1.2
		ring.mesh = r_mesh
		ring.material_override = red_mat
		ring.position = Vector3(0, -0.38, 0)
		ring.scale = Vector3(0.2, 0.2, 0.2)
		blast_root.add_child(ring)

		# Flying 3D Black and Blood Red Embers
		var ember_nodes: Array[Node3D] = []
		var ember_count: int = 4 if OS.has_feature("web") else 8
		for e in range(ember_count):
			var ember := MeshInstance3D.new()
			var e_mesh := SphereMesh.new()
			e_mesh.radius = 0.20
			e_mesh.height = 0.40
			ember.mesh = e_mesh
			ember.material_override = slash_mat if (e % 2 == 0) else red_mat
			blast_root.add_child(ember)
			ember_nodes.append(ember)

		# Radial Little Red Lightning Sparks
		var spark_count: int = 3 if OS.has_feature("web") else 6
		for b in range(spark_count):
			var s_ang: float = float(b) * (TAU / float(spark_count)) + randf_range(-0.2, 0.2)
			var b_end := Vector3(cos(s_ang) * randf_range(1.1, 1.8), randf_range(0.1, 0.7), sin(s_ang) * randf_range(1.1, 1.8))
			_spawn_decluck_zigzag_bolt(blast_root, Vector3.ZERO, b_end, 3, 0.10, red_mat)

		var b_tw := blast_root.create_tween()
		b_tw.tween_property(dome, "scale", Vector3(1.7, 1.7, 1.7), 0.15).set_trans(Tween.TRANS_EXPO)
		b_tw.parallel().tween_property(ring, "scale", Vector3(3.4, 1.0, 3.4), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		b_tw.parallel().tween_property(slash1, "scale", Vector3(1.45, 1.45, 0.4), 0.08).set_trans(Tween.TRANS_EXPO)
		b_tw.parallel().tween_property(slash2, "scale", Vector3(1.45, 1.45, 0.4), 0.08).set_trans(Tween.TRANS_EXPO)
		for e_idx in range(ember_nodes.size()):
			var e_node: Node3D = ember_nodes[e_idx]
			var e_ang: float = float(e_idx) * (TAU / float(ember_nodes.size()))
			var e_dest := Vector3(cos(e_ang) * randf_range(1.6, 2.4), randf_range(0.3, 1.2), sin(e_ang) * randf_range(1.6, 2.4))
			b_tw.parallel().tween_property(e_node, "position", e_dest, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			b_tw.parallel().tween_property(e_node, "scale", Vector3(1.4, 1.4, 1.4), 0.22)

		b_tw.parallel().tween_property(slash_mat, "albedo_color:a", 0.0, 0.22).set_delay(0.04)
		b_tw.parallel().tween_property(red_mat, "albedo_color:a", 0.0, 0.22).set_delay(0.04)
		b_tw.chain().tween_callback(func():
			blast_root.queue_free()
			claw_root.queue_free()
		)

		if on_hit_callback.is_valid():
			on_hit_callback.call()
	)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.45, base_scale.y * 0.65, base_scale.z * 1.45), 0.06).set_trans(Tween.TRANS_BOUNCE)

	# Phase 6: High Rebound & 360° Backflip Landing (0.24s)
	var mid_rebound: Vector3 = (base_stage_pos + target_pos) * 0.5 + Vector3(0, 1.8, 0)
	tween.tween_property(self, "position", mid_rebound, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x - 180.0, 0.12)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 0.9, base_scale.y * 1.15, base_scale.z * 0.9), 0.12)

	tween.tween_property(self, "position", base_stage_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "rotation_degrees:x", base_rot.x - 360.0, 0.12)
	tween.chain().tween_callback(func(): rotation_degrees = base_rot)
	tween.tween_property(self, "scale", base_scale, 0.12).set_trans(Tween.TRANS_BOUNCE)

## Daniel: "Unseen Hand / Unseen Claw" Strike
## Swarm of chaotic thin squiggly spaghetti Unseen Hands erupt from the shadows behind Daniel,
## surge across the arena with undulating sine waves and twitching claw fingers,
## violently crush/impale the opponent with a deep purple screen flash & shockwave, and retract into the void!
func play_daniel_unseen_claw(target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	if is_dead:
		return

	var dir: Vector3 = (target_pos - base_stage_pos).normalized()
	var dist_to_target: float = (target_pos - base_stage_pos).length()
	var right_vec: Vector3 = Vector3(-dir.z, 0, dir.x).normalized()
	var up_vec: Vector3 = Vector3.UP
	var origin_pos: Vector3 = base_stage_pos + Vector3(0, 0.45, 0)
	var strike_pos: Vector3 = target_pos + Vector3(0, 0.45, 0)

	# --- 1. Construct Swarm of 5 Chaotic Squiggly Spaghetti Hands ---
	var hand_root := Node3D.new()
	get_parent().add_child(hand_root)
	hand_root.global_position = Vector3.ZERO

	# Shadow material (dark violet core with bright ethereal purple emission)
	var shadow_mat := _get_cached_material("daniel_shadow_hand", Color(0.10, 0.01, 0.18, 0.95), Color(0.72, 0.12, 1.0), 4.5)

	var num_hands := 3 if OS.has_feature("web") else 5
	var num_joints := 5 if OS.has_feature("web") else 8
	var hands_data: Array[Dictionary] = []

	var hand_offsets: Array[Vector3] = [
		Vector3(0, 0.65, -0.45),
		Vector3(0, 0.35, 0.50),
		Vector3(0, -0.15, -0.20),
		Vector3(0, -0.45, 0.35),
		Vector3(0, 0.85, 0.15)
	]

	for h in range(num_hands):
		var h_dict := {
			"offset": hand_offsets[h],
			"freq": 22.0 + float(h) * 3.5,
			"phase_y": float(h) * 1.3,
			"phase_r": float(h) * 1.7 + 0.5,
			"amp_y": 0.40 + float(h % 3) * 0.15,
			"amp_r": 0.35 + float((h + 1) % 3) * 0.15,
			"joint_spheres": [] as Array[MeshInstance3D],
			"link_nodes": [] as Array[Node3D],
			"link_cyls": [] as Array[CylinderMesh],
			"palm_node": Node3D.new(),
			"fingers": [] as Array[MeshInstance3D]
		}

		# 1. Thin joint spheres
		for i in range(num_joints):
			var sph_inst := MeshInstance3D.new()
			var sph := SphereMesh.new()
			var t_ratio := float(i) / float(num_joints - 1)
			var rad: float = lerp(0.06, 0.13, t_ratio)
			sph.radius = rad
			sph.height = rad * 2.0
			sph_inst.mesh = sph
			sph_inst.material_override = shadow_mat
			hand_root.add_child(sph_inst)
			h_dict["joint_spheres"].append(sph_inst)

		# 2. Thin continuous connecting cylinders
		for i in range(num_joints - 1):
			var link_node := Node3D.new()
			hand_root.add_child(link_node)

			var cyl_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			var t_ratio := float(i) / float(num_joints - 1)
			var rad_start: float = lerp(0.06, 0.13, t_ratio)
			var rad_end: float = lerp(0.06, 0.13, float(i + 1) / float(num_joints - 1))
			cyl.top_radius = rad_end
			cyl.bottom_radius = rad_start
			cyl.height = 1.0
			cyl_inst.mesh = cyl
			cyl_inst.material_override = shadow_mat
			cyl_inst.rotation_degrees.x = 90.0
			link_node.add_child(cyl_inst)

			h_dict["link_nodes"].append(link_node)
			h_dict["link_cyls"].append(cyl)

		# 3. Palm & 4 Claw Fingers at the tip
		var palm_node: Node3D = h_dict["palm_node"]
		hand_root.add_child(palm_node)

		var palm := MeshInstance3D.new()
		var palm_box := BoxMesh.new()
		palm_box.size = Vector3(0.28, 0.32, 0.20)
		palm.mesh = palm_box
		palm.material_override = shadow_mat
		palm.position = Vector3(0.12, 0, 0)
		palm_node.add_child(palm)

		for f in range(4):
			var finger := MeshInstance3D.new()
			var f_box := BoxMesh.new()
			f_box.size = Vector3(0.26, 0.06, 0.06)
			finger.mesh = f_box
			finger.material_override = shadow_mat
			finger.position = Vector3(0.26, (f - 1.5) * 0.09, (f % 2 - 0.5) * 0.07)
			finger.rotation_degrees.z = (f - 1.5) * 18.0
			palm_node.add_child(finger)
			h_dict["fingers"].append(finger)

		hands_data.append(h_dict)

	var tween := create_tween()

	# Daniel Anticipation: Creepy crouch and shadow tilt (0.12s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 0.85, base_scale.z * 1.15), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot + Vector3(15.0, 0, -10.0), 0.12)

	# --- Phase 2: Swarm of Unseen Hands surges across the arena (0.28s) ---
	var has_hit := [false]
	tween.tween_method(func(progress: float):
		var cur_tip_pos: Vector3 = origin_pos + dir * (dist_to_target * progress)

		for h in range(num_hands):
			var hd: Dictionary = hands_data[h]
			var offset: Vector3 = hd["offset"]
			var freq: float = hd["freq"]
			var phase_y: float = hd["phase_y"]
			var phase_r: float = hd["phase_r"]
			var amp_y: float = hd["amp_y"]
			var amp_r: float = hd["amp_r"]
			var joint_spheres: Array[MeshInstance3D] = hd["joint_spheres"]
			var link_nodes: Array[Node3D] = hd["link_nodes"]
			var link_cyls: Array[CylinderMesh] = hd["link_cyls"]
			var palm_node: Node3D = hd["palm_node"]
			var fingers: Array[MeshInstance3D] = hd["fingers"]

			# Calculate joint positions along this hand's wild wavy path
			var joint_pts: Array[Vector3] = []
			for i in range(num_joints):
				var t_joint: float = float(i) / float(num_joints - 1)
				var base_pt: Vector3 = origin_pos.lerp(cur_tip_pos, t_joint)
				var wave_time: float = progress * freq + float(i) * 0.9
				var r_disp: float = offset.z * t_joint + sin(wave_time + phase_r) * amp_r * t_joint
				var y_disp: float = offset.y * t_joint + cos(wave_time * 0.85 + phase_y) * amp_y * t_joint
				var pt: Vector3 = base_pt + right_vec * r_disp + up_vec * y_disp
				joint_pts.append(pt)
				joint_spheres[i].global_position = pt

			# Update connecting cylinder links
			for i in range(num_joints - 1):
				var p_start: Vector3 = joint_pts[i]
				var p_end: Vector3 = joint_pts[i + 1]
				var link_dir: Vector3 = p_end - p_start
				var link_dist: float = link_dir.length()
				if link_dist > 0.001:
					var l_node: Node3D = link_nodes[i]
					var l_cyl: CylinderMesh = link_cyls[i]
					l_cyl.height = link_dist + 0.04
					l_node.global_position = (p_start + p_end) * 0.5
					var align_up: Vector3 = up_vec if abs(link_dir.normalized().dot(up_vec)) < 0.9 else right_vec
					l_node.look_at(p_end, align_up)

			# Position & orient palm tip
			var tip_pt: Vector3 = joint_pts[num_joints - 1]
			var prev_pt: Vector3 = joint_pts[num_joints - 2]
			palm_node.global_position = tip_pt
			var palm_dir: Vector3 = (tip_pt - prev_pt).normalized()
			if palm_dir.length() > 0.001:
				var align_up: Vector3 = up_vec if abs(palm_dir.dot(up_vec)) < 0.9 else right_vec
				palm_node.look_at(tip_pt + palm_dir, align_up)

			# Twitch fingers chaotically
			for f in range(fingers.size()):
				fingers[f].rotation_degrees.z = (f - 1.5) * 18.0 + sin(progress * 40.0 + f * 2.0 + h) * 25.0

		# On impact reach (progress >= 0.92)
		if not has_hit[0] and progress >= 0.92:
			has_hit[0] = true
			_trigger_screen_flash(Color(0.65, 0.1, 0.95, 0.65), 0.14)
			_trigger_camera_shake(0.48, 0.20)
			_spawn_shadow_impact_burst(strike_pos, dir)
			if on_hit_callback.is_valid():
				on_hit_callback.call()
	, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Impact Freeze & violent clench
	tween.tween_interval(0.10)

	# --- Phase 3: Dissolve tendrils & retract into the void (0.24s) ---
	tween.tween_callback(func():
		var fade_tw := hand_root.create_tween()
		fade_tw.tween_property(shadow_mat, "albedo_color:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_tw.parallel().tween_property(hand_root, "scale", Vector3(0.2, 0.2, 0.2), 0.20)
		fade_tw.chain().tween_callback(hand_root.queue_free)
	)

	# Daniel snaps back to normal stance
	tween.tween_property(self, "scale", base_scale, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.16)

## Shadow explosion shockwave for Daniel's Unseen Hand strike
func _spawn_shadow_impact_burst(impact_pos: Vector3, dir: Vector3) -> void:
	var blast_root := Node3D.new()
	get_parent().add_child(blast_root)
	blast_root.global_position = impact_pos

	var shock_mesh := TorusMesh.new()
	shock_mesh.inner_radius = 0.35
	shock_mesh.outer_radius = 0.70
	var shock_inst := MeshInstance3D.new()
	shock_inst.mesh = shock_mesh

	var shock_mat := _get_cached_material("daniel_shadow_burst", Color(0.2, 0.02, 0.35, 0.95), Color(0.85, 0.15, 1.0), 4.5)
	shock_inst.material_override = shock_mat
	blast_root.add_child(shock_inst)
	shock_inst.look_at(impact_pos + dir, Vector3.UP)

	var fireball := MeshInstance3D.new()
	var f_sphere := SphereMesh.new()
	f_sphere.radius = 0.40
	f_sphere.height = 0.80
	fireball.mesh = f_sphere
	fireball.material_override = shock_mat
	blast_root.add_child(fireball)

	var tw := blast_root.create_tween()
	blast_root.scale = Vector3(0.2, 0.2, 0.2)
	tw.tween_property(blast_root, "scale", Vector3(2.4, 2.4, 2.4), 0.12).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(shock_mat, "albedo_color:a", 0.0, 0.18).set_delay(0.06)
	tw.chain().tween_callback(blast_root.queue_free)

## Daniel Chicken's Heart: Rhythmic heartbeat thumping squashes and 3D floating '+' crosses!
func play_daniel_heartbeat_heal(amount: int) -> void:
	if is_dead:
		return

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), "+%d HP" % amount, Color(0.95, 0.35, 0.85), true)
	_spawn_3d_heal_crosses(amount, "purple")

	var tween := create_tween()

	# Heartbeat Thump 1
	tween.tween_property(self, "scale", base_scale * 1.35, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale * 0.95, 0.08).set_trans(Tween.TRANS_QUAD)

	# Heartbeat Thump 2
	tween.tween_property(self, "scale", base_scale * 1.45, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale, 0.18).set_trans(Tween.TRANS_BOUNCE)

## Daniel Chick to Zero: Shattered Glass Time-Fracture (Chronos Rewind)
## 1. High-contrast black & white / violet negative screen filter
## 2. Stage shatters into 28 floating glowing voxel glass shards suspended in mid-air
## 3. Rewind: Shards violently fly backwards in reverse motion into Daniel's core, reconstructing his body
## 4. Color violently snaps back with a full-screen flash, radial shockwave blast, and revival banner!
func play_daniel_revive(banner_text: String = "RETURN BY DEATH: CHICK TO ZERO!") -> void:
	is_dead = false

	# 1. High-contrast Black & White / Violet Negative Screen Filter via persistent overlay
	_trigger_screen_flash(Color(0.22, 0.02, 0.45, 0.78), 0.52)

	var shatter_root := Node3D.new()
	get_parent().add_child(shatter_root)
	shatter_root.global_position = base_stage_pos + Vector3(0, 0.45, 0)

	# Luminous Crystalline Violet Glass Shard Material
	var glass_mat := _get_cached_material("daniel_revive_glass", Color(0.95, 0.78, 1.0, 0.90), Color(0.85, 0.25, 1.0), 5.0)

	# 2. Spawn Floating Voxel Glass Shards
	var num_shards := 10 if OS.has_feature("web") else 28
	var shards_data: Array[Dictionary] = []

	for i in range(num_shards):
		var shard_inst := MeshInstance3D.new()
		var mesh_type := i % 2
		if mesh_type == 0:
			var b_mesh := BoxMesh.new()
			b_mesh.size = Vector3(randf_range(0.14, 0.28), randf_range(0.14, 0.35), randf_range(0.08, 0.20))
			shard_inst.mesh = b_mesh
		else:
			var p_mesh := PrismMesh.new()
			p_mesh.size = Vector3(randf_range(0.18, 0.32), randf_range(0.18, 0.36), randf_range(0.10, 0.22))
			shard_inst.mesh = p_mesh

		shard_inst.material_override = glass_mat
		shatter_root.add_child(shard_inst)

		# Spherical spread in mid-air
		var burst_pos := Vector3(
			randf_range(-1.8, 1.8),
			randf_range(0.2, 2.2),
			randf_range(-1.8, 1.8)
		)
		var burst_rot := Vector3(
			randf_range(-180.0, 180.0),
			randf_range(-180.0, 180.0),
			randf_range(-180.0, 180.0)
		)
		shard_inst.position = Vector3.ZERO
		shard_inst.rotation_degrees = Vector3.ZERO

		shards_data.append({
			"inst": shard_inst,
			"target_pos": burst_pos,
			"target_rot": burst_rot
		})

	var tween := create_tween()

	# --- Phase 1: Shatter Outward into Mid-Air (0.14s) ---
	for s in shards_data:
		var inst: MeshInstance3D = s["inst"]
		var t_pos: Vector3 = s["target_pos"]
		var t_rot: Vector3 = s["target_rot"]
		tween.parallel().tween_property(inst, "position", t_pos, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(inst, "rotation_degrees", t_rot, 0.14)

	# Daniel flinches and floats slightly in suspended reality
	tween.parallel().tween_property(self, "position:y", base_stage_pos.y + 0.65, 0.14).set_trans(Tween.TRANS_QUAD)

	# --- Phase 2: Mid-Air Time Freeze (0.12s) ---
	# Suspended in frozen time
	tween.tween_interval(0.12)

	# --- Phase 3: Violent Reverse Rewind into Daniel's Core (0.26s) ---
	for s in shards_data:
		var inst: MeshInstance3D = s["inst"]
		tween.parallel().tween_property(inst, "position", Vector3.ZERO, 0.26).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(inst, "rotation_degrees", Vector3.ZERO, 0.26)

	# As shards converge in reverse, load Daniel model and reassemble
	tween.tween_callback(func():
		_load_model("res://resources/models/daniel/daniel.vox")
		FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.0, 0), banner_text, Color.WHITE, true)
	)

	# --- Phase 4: Color Snaps Back + Blinding Flash + Shockwave Detonation (0.28s) ---
	tween.tween_callback(func():
		# Shards vanish into core
		shatter_root.queue_free()

		# Full-screen violent white/violet flash
		_trigger_screen_flash(Color(0.95, 0.85, 1.0, 0.90), 0.16)

		# Radial temporal shockwave explosion
		_spawn_shadow_impact_burst(base_stage_pos, Vector3.UP)
		_trigger_camera_shake(0.55, 0.22)
	)

	# Daniel drops down and lands firmly on stage with a solid bounce
	tween.tween_property(self, "position", base_stage_pos, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", base_scale * 1.55, 0.06).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.14)

## Animates taking a hit / knockback
func play_hit(damage: int, is_blocked: bool = false) -> void:
	if is_dead:
		return

	if is_blocked and rooster_data and rooster_data.rooster_id == "cluckey_d_puffy":
		play_cluckey_balloon_deflection()
		return

	_stop_gear5_drums_loop()

	var color: Color = Color(1, 0.3, 0.3) if not is_blocked else Color(0.3, 0.8, 1.0)
	var text: String = "-%d" % damage if not is_blocked else "BLOCKED!"
	FloatingText3D.spawn(get_parent(), global_position, text, color)

	if is_transformed and rooster_data and rooster_data.rooster_id == "eren_pecker" and not is_blocked:
		_spawn_titan_wound_steam(global_position + Vector3(0, 0.6, 0))

	var tween := create_tween()
	var shake_dir: Vector3 = Vector3(randf_range(-0.35, 0.35), 0.25, randf_range(-0.35, 0.35))
	
	# Flinch squash & knockback
	tween.tween_property(self, "position", base_stage_pos + shake_dir, 0.08).set_trans(Tween.TRANS_ELASTIC)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 0.75, base_scale.z * 1.25), 0.08)
	
	# Elastic recovery
	tween.tween_property(self, "position", base_stage_pos, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", base_scale, 0.18).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "rotation_degrees", base_rot, 0.18)
	tween.chain().tween_callback(_start_gear5_drums_loop)

## Hen-Goku Kikiriki Barrier: Dragon Ball Android 17 / Goku Ki Barrier Sphere
## Semi-transparent glowing gold sphere with 2 intersecting orbiting electrical spark rings and pulsing energy
func play_kikiriki_barrier(amount: int) -> void:
	if is_dead:
		return

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), "+%d KIKIRIKI BARRIER" % amount, Color(1.0, 0.9, 0.2), true)

	var barrier_root := Node3D.new()
	get_parent().add_child(barrier_root)
	barrier_root.global_position = global_position + Vector3(0, 0.55, 0)

	# Main Semi-Transparent Ki Sphere
	var sphere_mesh_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.35
	sphere_mesh.height = 2.7
	sphere_mesh_inst.mesh = sphere_mesh

	var sphere_mat := _get_cached_material("golden_barrier_sphere", Color(1.0, 0.85, 0.2, 0.32), Color(1.0, 0.88, 0.25), 3.2, false, true)
	sphere_mesh_inst.material_override = sphere_mat
	barrier_root.add_child(sphere_mesh_inst)

	# Orbiting Ki Spark Ring 1 (Diagonal 45 deg)
	var ring1 := MeshInstance3D.new()
	var r_mesh1 := TorusMesh.new()
	r_mesh1.inner_radius = 1.38
	r_mesh1.outer_radius = 1.48
	r_mesh1.rings = 24
	r_mesh1.ring_segments = 8
	ring1.mesh = r_mesh1
	ring1.rotation_degrees = Vector3(45.0, 30.0, 0.0)

	var ring_mat := _get_cached_material("golden_barrier_ring", Color(1.0, 0.95, 0.45, 0.65), Color(1.0, 0.95, 0.45), 3.5)
	ring1.material_override = ring_mat
	barrier_root.add_child(ring1)

	# Orbiting Ki Spark Ring 2 (Diagonal -45 deg)
	var ring2 := MeshInstance3D.new()
	var r_mesh2 := TorusMesh.new()
	r_mesh2.inner_radius = 1.38
	r_mesh2.outer_radius = 1.48
	r_mesh2.rings = 24
	r_mesh2.ring_segments = 8
	ring2.mesh = r_mesh2
	ring2.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	ring2.material_override = ring_mat
	barrier_root.add_child(ring2)

	barrier_root.scale = Vector3(0.1, 0.1, 0.1)

	var tween := create_tween()
	# 1. Erupt & Expand outward with power jump
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.35, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(barrier_root, "scale", Vector3(1.15, 1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ring1, "rotation_degrees:y", 220.0, 0.6)
	tween.parallel().tween_property(ring2, "rotation_degrees:y", -220.0, 0.6)

	# 2. Pulse & Settle
	tween.tween_property(barrier_root, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
	tween.parallel().tween_property(self, "position:y", base_stage_pos.y, 0.15).set_trans(Tween.TRANS_BOUNCE)

	# 3. Ki Spark Dissipation
	tween.tween_interval(0.2)
	tween.tween_property(sphere_mat, "albedo_color:a", 0.0, 0.2)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.2)
	tween.parallel().tween_property(barrier_root, "scale", Vector3(1.3, 1.3, 1.3), 0.2)
	tween.chain().tween_callback(barrier_root.queue_free)

## Animates healing with glowing 3D floating '+' crosses & joyful rooster hop (No halo)
func play_heal(amount: int, theme: String = "") -> void:
	if is_dead:
		return
	var text_color: Color = Color(0.25, 1.0, 0.45)
	if theme == "pink" or (rooster_data and rooster_data.rooster_id == "nechicko"):
		text_color = Color(1.0, 0.35, 0.7)
	elif theme == "purple" or (rooster_data and rooster_data.rooster_id == "daniel"):
		text_color = Color(0.95, 0.35, 0.85)

	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), "+%d HP" % amount, text_color, true)
	
	# Spawn 3D '+' crosses scaling with heal amount!
	_spawn_3d_heal_crosses(amount, theme)

	# Rooster cheerful hop
	var hop_tween := create_tween()
	hop_tween.tween_property(self, "position:y", base_stage_pos.y + 0.3, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(self, "position:y", base_stage_pos.y, 0.15).set_trans(Tween.TRANS_BOUNCE)

## Creates a luminous 3D '+' cross node made of two intersecting BoxMeshes
func _create_3d_cross_node(color: Color, glow: Color, cross_size: float = 0.35) -> Node3D:
	var cross_root := Node3D.new()

	var mat := _get_cached_material("heal_cross_" + color.to_html(false), Color(color.r, color.g, color.b, 0.92), glow, 3.2, false, true)

	var thickness: float = cross_size * 0.28

	# Horizontal bar of the '+'
	var bar_h := MeshInstance3D.new()
	var mesh_h := BoxMesh.new()
	mesh_h.size = Vector3(cross_size, thickness, thickness)
	bar_h.mesh = mesh_h
	bar_h.material_override = mat
	cross_root.add_child(bar_h)

	# Vertical bar of the '+'
	var bar_v := MeshInstance3D.new()
	var mesh_v := BoxMesh.new()
	mesh_v.size = Vector3(thickness, cross_size, thickness)
	bar_v.mesh = mesh_v
	bar_v.material_override = mat
	cross_root.add_child(bar_v)

	return cross_root

## Spawns an eruption of floating 3D '+' crosses. Higher heal amount = more crosses!
func _spawn_3d_heal_crosses(amount: int, theme: String = "") -> void:
	var parent_node := get_parent()
	if not parent_node:
		return

	var cross_color: Color = Color(0.25, 1.0, 0.45)
	var glow_color: Color = Color(0.3, 1.0, 0.5)

	if theme == "pink" or (rooster_data and rooster_data.rooster_id == "nechicko"):
		cross_color = Color(1.0, 0.35, 0.75)
		glow_color = Color(1.0, 0.45, 0.85)
	elif theme == "purple" or (rooster_data and rooster_data.rooster_id == "daniel"):
		cross_color = Color(0.85, 0.25, 0.95)
		glow_color = Color(0.95, 0.4, 1.0)
	elif theme == "gold" or (rooster_data and rooster_data.rooster_id == "hen_goku"):
		cross_color = Color(1.0, 0.85, 0.25)
		glow_color = Color(1.0, 0.9, 0.35)

	# Scale count directly with amount: 1 HP -> 3 crosses, 2 HP -> 5 crosses, 4 HP -> 8 crosses, 6+ HP -> 12-16 crosses!
	var num_crosses: int = clampi(amount * 2 + 1, 3, 16)
	if OS.has_feature("web"):
		num_crosses = mini(num_crosses, 4)

	for i in range(num_crosses):
		var angle: float = (float(i) / float(num_crosses)) * TAU + randf_range(-0.35, 0.35)
		var radius: float = randf_range(0.25, 0.75)
		var cross_size: float = randf_range(0.24, 0.42)
		var cross_node := _create_3d_cross_node(cross_color, glow_color, cross_size)

		parent_node.add_child(cross_node)

		var spawn_pos: Vector3 = global_position + Vector3(cos(angle) * radius, randf_range(0.1, 0.4), sin(angle) * radius)
		cross_node.global_position = spawn_pos
		cross_node.scale = Vector3(0.001, 0.001, 0.001)
		cross_node.rotation_degrees = Vector3(randf_range(-20, 20), randf_range(0, 360), randf_range(-20, 20))

		var float_height: float = randf_range(1.1, 1.85)
		var drift_target: Vector3 = spawn_pos + Vector3(cos(angle) * randf_range(0.2, 0.5), float_height, sin(angle) * randf_range(0.2, 0.5))
		var delay: float = float(i) * 0.035
		var float_duration: float = randf_range(0.45, 0.65)
		var spin_y: float = randf_range(120.0, 280.0) * (1.0 if i % 2 == 0 else -1.0)
		var spin_z: float = randf_range(-45.0, 45.0)

		# Get material reference for fade-out
		var bar_mesh = cross_node.get_child(0) as MeshInstance3D
		var cross_mat: StandardMaterial3D = bar_mesh.material_override if bar_mesh else null

		var tw := cross_node.create_tween()
		# 1. Pop into view
		tw.tween_interval(delay)
		tw.tween_property(cross_node, "scale", Vector3(1.15, 1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cross_node, "position", spawn_pos + Vector3(0, 0.25, 0), 0.12).set_trans(Tween.TRANS_QUAD)

		# 2. Float upward, swirl & rotate
		tw.tween_property(cross_node, "position", drift_target, float_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cross_node, "scale", Vector3(0.85, 0.85, 0.85), float_duration)
		tw.parallel().tween_property(cross_node, "rotation_degrees:y", cross_node.rotation_degrees.y + spin_y, float_duration)
		tw.parallel().tween_property(cross_node, "rotation_degrees:z", cross_node.rotation_degrees.z + spin_z, float_duration)
		if cross_mat:
			tw.parallel().tween_property(cross_mat, "albedo_color:a", 0.0, float_duration * 0.5).set_delay(float_duration * 0.5)

		# 3. Shrink to safe non-zero epsilon and cleanup
		tw.tween_property(cross_node, "scale", Vector3(0.001, 0.001, 0.001), 0.08)
		tw.chain().tween_callback(cross_node.queue_free)

## Nechicko Demon Form Transformation:
## Simple, punchy Super Mario power-up animation!
## Rapid growth pulses, hop, retro power-up stars & flash, model swap to Demon Nechicko, and big landing!
func play_nechicko_demon_transformation(alt_path: String, banner_text: String = "DEMON FORM AWAKENED!") -> void:
	if is_dead:
		return

	if alt_path == "" and rooster_data and rooster_data.alt_model_path != "":
		alt_path = rooster_data.alt_model_path
	if alt_path == "":
		alt_path = "res://resources/models/nechicko/Nezukodemon.vox"

	var parent_scene: Node = get_parent() if get_parent() else self

	var tween := create_tween()

	# 1. Mario Power-Up Pre-squash / Crouch (0.08s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 0.75, base_scale.z * 1.15), 0.08).set_trans(Tween.TRANS_QUAD)

	# 2. Mario Growth Pulse 1: Stretch up & pop down (0.16s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.25, base_scale.y * 1.35, base_scale.z * 1.25), 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.05, base_scale.y * 0.95, base_scale.z * 1.05), 0.08).set_trans(Tween.TRANS_QUAD)

	# 3. Mario Growth Pulse 2: Bigger stretch up & pop down (0.16s)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.40, base_scale.y * 1.55, base_scale.z * 1.40), 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", Vector3(base_scale.x * 1.15, base_scale.y * 1.05, base_scale.z * 1.15), 0.08).set_trans(Tween.TRANS_QUAD)

	# 4. Mario Growth Pulse 3: The Big Hop & Model Swap (0.14s)
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.40, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.50, base_scale.y * 1.65, base_scale.z * 1.50), 0.12)

	# Model swap to Demon Nechicko right at the apex of the hop!
	tween.tween_callback(func():
		is_transformed = true
		_load_model(alt_path)
		_trigger_screen_flash(Color(1.0, 0.95, 0.5, 0.45), 0.14)
		_trigger_camera_shake(0.35, 0.16)
		_spawn_mario_powerup_sparks()
		FloatingText3D.spawn(parent_scene, (global_position if is_inside_tree() else position) + Vector3(0, 1.2, 0), "POWER UP!", Color(1.0, 0.85, 0.2), true)
	)

	# 5. Land & Punchy Squash Bounce (0.16s)
	tween.tween_property(self, "position", base_stage_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", Vector3(base_scale.x * 1.35, base_scale.y * 0.85, base_scale.z * 1.35), 0.10)
	tween.tween_property(self, "scale", base_scale * 1.20, 0.14).set_trans(Tween.TRANS_BOUNCE)

## Spawns 8 retro star / spark burst particles on Mario power-up
func _spawn_mario_powerup_sparks() -> void:
	var spark_root := Node3D.new()
	var p: Node = get_parent() if get_parent() else self
	p.add_child(spark_root)
	if spark_root.is_inside_tree():
		spark_root.global_position = base_stage_pos + Vector3(0, 0.5, 0)
	else:
		spark_root.position = base_stage_pos + Vector3(0, 0.5, 0)

	var s_mat := _get_cached_material("mario_powerup_spark", Color(1.0, 0.90, 0.25, 0.95), Color(1.0, 0.85, 0.15), 4.5)

	var spark_count: int = 4 if OS.has_feature("web") else 8
	for i in range(spark_count):
		var spark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.09, 0.09)
		spark.mesh = box
		spark.material_override = s_mat
		spark_root.add_child(spark)

		var ang: float = float(i) * (TAU / float(spark_count))
		var dest := Vector3(cos(ang) * 1.1, randf_range(0.2, 0.9), sin(ang) * 1.1)
		var s_tw := spark.create_tween()
		s_tw.tween_property(spark, "position", dest, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		s_tw.parallel().tween_property(spark, "rotation_degrees", Vector3(180.0, 180.0, 0.0), 0.25)
		s_tw.parallel().tween_property(spark, "scale", Vector3(0.001, 0.001, 0.001), 0.25).set_delay(0.12)

	var root_tw := spark_root.create_tween()
	root_tw.tween_interval(0.38)
	root_tw.chain().tween_callback(spark_root.queue_free)

## Nechicko Demon Form Pacification:
## Demon power is exhausted, Nechicko slumps forward drowsily,
## demonic crimson flames dissolve into a gentle shower of floating pink sakura petals / sparkles,
## and normal rooster Nechicko (with bamboo muzzle) emerges resting peacefully!
func play_nechicko_demon_revert(banner_text: String = "DEMON PACIFIED (SLEEPING)") -> void:
	if is_dead:
		return

	is_transformed = false
	var parent_scene: Node = get_parent() if get_parent() else self
	var standard_scale: Vector3 = untransformed_scale

	_trigger_camera_shake(0.25, 0.18)
	FloatingText3D.spawn(parent_scene, global_position + Vector3(0, 0.9, 0), banner_text, Color.WHITE)

	# Sakura Petals & Sparkle Root
	var sakura_root := Node3D.new()
	parent_scene.add_child(sakura_root)
	sakura_root.global_position = global_position

	var petal_mat := _get_cached_material("nechicko_sakura_petal", Color(1.0, 0.65, 0.85, 0.85), Color(1.0, 0.55, 0.80), 2.0)

	var petal_nodes: Array[MeshInstance3D] = []
	var petal_count: int = 4 if OS.has_feature("web") else 8
	for p in range(petal_count):
		var p_inst := MeshInstance3D.new()
		var p_mesh := SphereMesh.new()
		p_mesh.radius = randf_range(0.18, 0.32)
		p_mesh.height = p_mesh.radius * 2.0
		p_inst.mesh = p_mesh
		p_inst.material_override = petal_mat
		p_inst.position = Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 0.8), randf_range(-0.5, 0.5))
		p_inst.scale = Vector3(0.2, 0.2, 0.2)
		sakura_root.add_child(p_inst)
		petal_nodes.append(p_inst)

	var tween := create_tween()

	# 1. Demon Exhaustion & Sleepy Nod (0.22s)
	tween.tween_property(self, "rotation_degrees:x", base_rot.x + 18.0, 0.22).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, "scale", base_scale * Vector3(1.15, 0.80, 1.15), 0.22)

	# 2. Sakura Petals Drifting Upward & Swirling (0.45s)
	for p_node in petal_nodes:
		var target_scale := Vector3.ONE * randf_range(1.2, 1.8)
		var rise_y := randf_range(1.0, 2.0)
		tween.parallel().tween_property(p_node, "position:y", p_node.position.y + rise_y, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(p_node, "position:x", p_node.position.x * 2.0, 0.45)
		tween.parallel().tween_property(p_node, "position:z", p_node.position.z * 2.0, 0.45)
		tween.parallel().tween_property(p_node, "scale", target_scale, 0.45)

	tween.parallel().tween_property(petal_mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)

	# 3. Model Swap back to Base Nechicko in the middle of petals (at 0.22s)
	tween.tween_callback(func():
		var base_model_path: String = rooster_data.model_path if rooster_data else "res://resources/models/nechicko/Nezuko.vox"
		_load_model(base_model_path)
		base_scale = standard_scale
		rotation_degrees = base_rot
	)

	# 4. Cute Wake-Up / Pacified Resting Settle (0.18s)
	tween.tween_property(self, "scale", standard_scale * 1.12, 0.10).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", standard_scale, 0.12).set_trans(Tween.TRANS_BOUNCE)
	tween.chain().tween_callback(sakura_root.queue_free)

## Nechicko Ketchup Aura:
## Nechicko whips out her beloved 3D voxel ketchup bottle (Ketchup.vox),
## tilts her head back, tips the bottle upside-down directly over her beak, and vigorously
## chugs it down with rhythmic bottle squashes, gulp bobs, and red ketchup droplets!
## Concludes with an energized beak smack and a radiant healing burst (+HEAL)!
func play_nechicko_ketchup_aura(amount: int) -> void:
	if is_dead:
		return

	var text_pos: Vector3 = (global_position if is_inside_tree() else position) + Vector3(0, 0.85, 0)
	FloatingText3D.spawn(get_parent(), text_pos, "+%d KETCHUP AURA (HEAL)" % amount, Color(0.2, 0.95, 0.3), true)

	var orig_pos: Vector3 = position
	var orig_rot: Vector3 = base_rot
	var orig_scale: Vector3 = base_scale

	# 1. Create a dedicated bottle pivot node anchored at the top nozzle
	var bottle_pivot := Node3D.new()
	add_child(bottle_pivot)

	# 2. Instantiate the Voxel Ketchup Bottle (res://resources/world/Ketchup.vox)
	var ketchup_path: String = "res://resources/world/Ketchup.vox"
	var ketchup_node: Node3D = null
	if ResourceLoader.exists(ketchup_path):
		var res = load(ketchup_path)
		if res is PackedScene:
			ketchup_node = res.instantiate()
	
	if not ketchup_node:
		# Fallback stylized voxel bottle if model missing
		ketchup_node = Node3D.new()
		var fb_mesh := CylinderMesh.new()
		fb_mesh.top_radius = 0.08
		fb_mesh.bottom_radius = 0.12
		fb_mesh.height = 0.45
		var fb_inst := MeshInstance3D.new()
		fb_inst.mesh = fb_mesh
		var fb_mat := _get_cached_material("ketchup_fallback_mat", Color(0.85, 0.15, 0.15))
		fb_inst.material_override = fb_mat
		ketchup_node.add_child(fb_inst)

	bottle_pivot.add_child(ketchup_node)
	# Align ketchup_node so its top white nozzle (Y=+4.0) is at (0, 0, 0) of bottle_pivot!
	# The flat red base is at (0, -4.0, 0) of bottle_pivot.
	# Rotated 90 degrees horizontally around local Y axis.
	ketchup_node.position = Vector3(0.0, -4.0, 0.0)
	ketchup_node.rotation_degrees = Vector3(0.0, 90.0, 0.0)

	# Initial spawn: held upright in front of her body, scaling in from 0
	var bottle_base_scale: Vector3 = Vector3(0.22, 0.22, 0.22)
	bottle_pivot.position = Vector3(0.0, 0.65, 0.55)
	bottle_pivot.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	bottle_pivot.scale = Vector3(0.01, 0.01, 0.01)

	# Splatter & text container
	var vfx_root := Node3D.new()
	add_child(vfx_root)

	var tween := create_tween()

	# Phase 1: Pop out bottle upright & tilt head backwards (0.24s)
	# Nechicko hops with excitement as the bottle appears
	tween.tween_property(self, "position:y", orig_pos.y + 0.16, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(bottle_pivot, "scale", bottle_base_scale, 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position:y", orig_pos.y, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Nechicko tilts head back (-26° on X) and bottle tilts upside-down with nozzle directly in her beak
	var chug_head_rot: Vector3 = Vector3(orig_rot.x - 26.0, orig_rot.y, orig_rot.z)
	var chug_nozzle_pos: Vector3 = Vector3(0.0, 0.20, 0.50) # Exact beak position
	var chug_bottle_rot: Vector3 = Vector3(-135.0, 0.0, 0.0) # Base points up into air, nozzle points down into mouth!

	tween.parallel().tween_property(self, "rotation_degrees", chug_head_rot, 0.16).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(bottle_pivot, "position", chug_nozzle_pos, 0.16).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(bottle_pivot, "rotation_degrees", chug_bottle_rot, 0.16).set_trans(Tween.TRANS_BACK)

	# Phase 2: Rapid Chugging Gulp Loop (4 chug-glugs, 0.72s total)
	# Squeezing the bottle, gulps, red ketchup droplets pouring from nozzle into her beak, comic text!
	var gulp_words: Array[String] = ["GLUG!", "GLUG!", "CHUG!", "GULP!"]
	var drop_mat := _get_cached_material("ketchup_drop_mat", Color(0.88, 0.10, 0.10))
	for g in range(4):
		# Gulp step 1: Squeeze bottle & swallow bulge
		var squeeze_scale: Vector3 = bottle_base_scale * Vector3(1.22, 0.78, 1.22)
		var gulp_body_scale: Vector3 = orig_scale * Vector3(1.15, 0.90, 1.15)
		var gulp_pos: Vector3 = chug_nozzle_pos + Vector3(0.0, -0.04, 0.0)

		tween.tween_property(bottle_pivot, "scale", squeeze_scale, 0.08).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(bottle_pivot, "position", gulp_pos, 0.08)
		tween.parallel().tween_property(self, "scale", gulp_body_scale, 0.08).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(self, "rotation_degrees:x", chug_head_rot.x - 5.0, 0.08)

		# Spawn a comic sound label and red ketchup droplets pouring from nozzle
		tween.tween_callback(func():
			if is_instance_valid(vfx_root):
				# Comic sound label
				var sound_lbl := Label3D.new()
				sound_lbl.text = gulp_words[g]
				sound_lbl.font = UIFontStyle.get_anton_font()
				sound_lbl.font_size = 24 + g * 2
				sound_lbl.pixel_size = 0.0011
				sound_lbl.outline_size = 5
				sound_lbl.outline_modulate = Color(0.4, 0.05, 0.05, 1.0)
				sound_lbl.modulate = Color(1.0, 0.25, 0.25)
				sound_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sound_lbl.render_priority = 55
				sound_lbl.position = Vector3(0.35 * (1.0 if g % 2 == 0 else -1.0), 0.75 + float(g) * 0.05, 0.40)
				vfx_root.add_child(sound_lbl)
				
				var stw := sound_lbl.create_tween()
				stw.tween_property(sound_lbl, "position:y", sound_lbl.position.y + 0.35, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				stw.parallel().tween_property(sound_lbl, "scale", Vector3(1.3, 1.3, 1.3), 0.12)
				stw.parallel().tween_property(sound_lbl, "modulate:a", 0.0, 0.15).set_delay(0.12)
				stw.chain().tween_callback(sound_lbl.queue_free)

				# Red ketchup droplets pouring from nozzle (0.0, 0.20, 0.50) into beak (0.0, 0.12, 0.46)
				for _d in range(3):
					var drop := MeshInstance3D.new()
					var drop_mesh := SphereMesh.new()
					drop_mesh.radius = 0.035
					drop_mesh.height = 0.07
					drop.mesh = drop_mesh
					drop.material_override = drop_mat
					drop.position = Vector3(randf_range(-0.03, 0.03), 0.20, 0.50 + randf_range(-0.02, 0.02))
					vfx_root.add_child(drop)

					var dtw := drop.create_tween()
					dtw.tween_property(drop, "position", Vector3(randf_range(-0.02, 0.02), 0.10, 0.46), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					dtw.parallel().tween_property(drop, "scale", Vector3(0.3, 0.3, 0.3), 0.10)
					dtw.chain().tween_callback(drop.queue_free)
		)

		# Gulp step 2: Release bottle squeeze & swallow bounce
		tween.tween_property(bottle_pivot, "scale", bottle_base_scale, 0.10).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(bottle_pivot, "position", chug_nozzle_pos, 0.10)
		tween.parallel().tween_property(self, "scale", orig_scale * Vector3(0.96, 1.10, 0.96), 0.10).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(self, "rotation_degrees:x", chug_head_rot.x + 3.0, 0.10)

	# Phase 3: Satisfying finish! Bottle vanishes, Nechicko pops back upright with an energized hop (0.32s)
	# Bottle pops away
	tween.tween_property(bottle_pivot, "scale", Vector3(0.001, 0.001, 0.001), 0.12).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(bottle_pivot, "position", Vector3(0.0, 1.0, 0.2), 0.12)

	# Nechicko hops and snaps upright with a proud beak smack
	tween.tween_property(self, "position:y", orig_pos.y + 0.22, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees", orig_rot, 0.14).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "scale", orig_scale * Vector3(1.10, 1.18, 1.10), 0.14)

	# Land cleanly back at original resting position and scale
	tween.tween_property(self, "position", orig_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", orig_scale, 0.12).set_trans(Tween.TRANS_BOUNCE)

	# Healing green aura pulse sparkles & cleanup
	tween.chain().tween_callback(func():
		rotation_degrees = orig_rot
		scale = orig_scale
		position = orig_pos
		if is_instance_valid(bottle_pivot):
			bottle_pivot.queue_free()
		if is_instance_valid(vfx_root):
			vfx_root.queue_free()
		_spawn_3d_heal_crosses(amount, "green")
	)




## Animates gaining shield with a procedural transparent circle / sphere aura (Green for Decluck, Purple for Cocktaro, Gold for Hen-Goku, Amber for Cluckey, Blue/Cyan for others)
func play_shield_gain(amount: int, theme: String = "") -> void:
	if is_dead:
		return
	var text_color: Color = Color(0.35, 0.8, 1.0)
	if theme == "gold" or (rooster_data and rooster_data.rooster_id == "hen_goku"):
		text_color = Color.GOLD
	elif theme == "purple" or (rooster_data and rooster_data.rooster_id == "cocktaro"):
		text_color = Color(0.85, 0.45, 1.0)
	elif theme == "amber" or (rooster_data and rooster_data.rooster_id == "cluckey_d_puffy"):
		text_color = Color(1.0, 0.65, 0.2)
	elif theme == "green" or (rooster_data and rooster_data.rooster_id == "decluck"):
		text_color = Color(0.2, 1.0, 0.5)

	FloatingText3D.spawn(get_parent(), global_position, "+%d SHIELD" % amount, text_color)
	_spawn_shield_bubble(theme)

func _spawn_shield_bubble(theme: String = "") -> void:
	var shield_root := Node3D.new()
	get_parent().add_child(shield_root)
	shield_root.global_position = global_position + Vector3(0, 0.6, 0)

	var aura_color: Color = Color(0.2, 0.65, 1.0)
	var glow_color: Color = Color(0.3, 0.8, 1.0)

	if theme == "gold" or (rooster_data and rooster_data.rooster_id == "hen_goku"):
		aura_color = Color(1.0, 0.85, 0.15)
		glow_color = Color(1.0, 0.9, 0.3)
	elif theme == "purple" or (rooster_data and rooster_data.rooster_id == "cocktaro"):
		aura_color = Color(0.65, 0.2, 0.95)
		glow_color = Color(0.85, 0.35, 1.0)
	elif theme == "amber" or (rooster_data and rooster_data.rooster_id == "cluckey_d_puffy"):
		aura_color = Color(1.0, 0.65, 0.15)
		glow_color = Color(1.0, 0.8, 0.25)
	elif theme == "green" or (rooster_data and rooster_data.rooster_id == "decluck"):
		aura_color = Color(0.1, 0.95, 0.45)
		glow_color = Color(0.2, 1.0, 0.5)

	# Sphere bubble
	var sphere_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.15
	sphere_mesh.height = 2.3
	sphere_mesh.radial_segments = 24
	sphere_mesh.rings = 16
	sphere_inst.mesh = sphere_mesh

	var mat := _get_cached_material("generic_shield_" + aura_color.to_html(false), Color(aura_color.r, aura_color.g, aura_color.b, 0.35), glow_color, 2.0, false, true)
	sphere_inst.material_override = mat
	shield_root.add_child(sphere_inst)

	# Ground energy ring
	var ring_inst := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.3
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 12
	ring_inst.mesh = ring_mesh
	ring_inst.position = Vector3(0, -0.55, 0)

	var ring_mat := _get_cached_material("generic_shield_ring_" + glow_color.to_html(false), Color(glow_color.r, glow_color.g, glow_color.b, 0.55), glow_color, 2.4)
	ring_inst.material_override = ring_mat
	shield_root.add_child(ring_inst)

	# Expand, pulse and fade out
	shield_root.scale = Vector3(0.2, 0.2, 0.2)
	var tween := shield_root.create_tween()
	tween.tween_property(shield_root, "scale", Vector3(1.25, 1.25, 1.25), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(shield_root, "scale", Vector3(1.05, 1.05, 1.05), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_delay(0.15)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.22).set_delay(0.15)
	tween.chain().tween_callback(shield_root.queue_free)

## Decluck All For One Cock Full Cowling Transformation:
## Chaotic 3D zigzag One For All emerald lightning strikes down from the sky, detonates with electrical jitter,
## ground shockwave ring erupts, and awakens Decluckpowered.vox with residual Full Cowling crackling arcs!
func play_decluck_power_transformation(alt_path: String, banner_text: String = "ALL FOR ONE: FULL COWLING!") -> void:
	if is_dead:
		return

	if alt_path == "" and rooster_data and rooster_data.alt_model_path != "":
		alt_path = rooster_data.alt_model_path
	if alt_path == "":
		alt_path = "res://resources/models/decluck/Decluckpowered.vox"

	var parent_scene: Node = get_parent() if get_parent() else self
	var stage_target: Vector3 = global_position

	# 1. Screen flash & Camera shake
	_trigger_screen_flash(Color(0.2, 1.0, 0.55, 0.7), 0.18)
	_trigger_camera_shake(0.5, 0.25)

	# 2. Lightning Root Container
	var lightning_root := Node3D.new()
	parent_scene.add_child(lightning_root)
	lightning_root.global_position = stage_target

	# 3. Full Cowling Emerald Lightning Material (matching CharacterSelectController)
	var bolt_mat := _get_cached_material("decluck_power_bolt", Color(0.2, 1.0, 0.6, 0.95), Color(0.15, 1.0, 0.55), 4.8)

	# 4. Generate chaotic 3D zigzag lightning bolts from the sky
	var num_bolts := 3 if OS.has_feature("web") else 7
	var num_segs := 4 if OS.has_feature("web") else 8
	var bolts_data: Array[Dictionary] = []

	for b in range(num_bolts):
		var sky_x: float = randf_range(-3.0, 3.0)
		var sky_z: float = randf_range(-2.2, 2.2)
		var target_x: float = randf_range(-0.35, 0.35)
		var target_z: float = randf_range(-0.35, 0.35)

		# Generate 3D zigzag points from Y = 9.0 to Y = 0 (relative to lightning_root)
		var pts: Array[Vector3] = []
		for i in range(num_segs):
			var t: float = float(i) / float(num_segs - 1)
			var px: float = lerp(sky_x, target_x, t) + (randf_range(-0.45, 0.45) if (i > 0 and i < num_segs - 1) else 0.0)
			var py: float = lerp(9.0, 0.4, t)
			var pz: float = lerp(sky_z, target_z, t) + (randf_range(-0.45, 0.45) if (i > 0 and i < num_segs - 1) else 0.0)
			pts.append(Vector3(px, py, pz))

		var b_dict := {
			"pts": pts,
			"link_nodes": [] as Array[Node3D]
		}

		# Build connected cylinders for each zigzag segment
		for i in range(num_segs - 1):
			var p_start: Vector3 = pts[i]
			var p_end: Vector3 = pts[i + 1]
			var dir := p_end - p_start
			var dist := dir.length()

			var link_node := Node3D.new()
			link_node.position = (p_start + p_end) * 0.5
			lightning_root.add_child(link_node)

			var cyl_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.06
			cyl.bottom_radius = 0.06
			cyl.height = dist + 0.04
			cyl_inst.mesh = cyl
			cyl_inst.material_override = bolt_mat
			cyl_inst.rotation_degrees.x = 90.0
			link_node.add_child(cyl_inst)

			if dist > 0.001:
				var up_v := Vector3.UP if abs(dir.normalized().y) < 0.9 else Vector3.RIGHT
				link_node.look_at(lightning_root.global_position + p_end, up_v)

			b_dict["link_nodes"].append(link_node)

		bolts_data.append(b_dict)

	# 5. Lightning Impact Burst Sphere at Decluck center
	var impact_sphere := MeshInstance3D.new()
	var sph_mesh := SphereMesh.new()
	sph_mesh.radius = 1.5
	sph_mesh.height = 3.0
	impact_sphere.mesh = sph_mesh
	impact_sphere.material_override = bolt_mat
	impact_sphere.position = Vector3(0, 0.65, 0)
	impact_sphere.scale = Vector3(0.001, 0.001, 0.001)
	lightning_root.add_child(impact_sphere)

	# 6. Ground Emerald Shockwave Ring
	var ground_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.9
	ground_ring.mesh = ring_mesh
	ground_ring.position = Vector3(0, 0.06, 0)
	ground_ring.material_override = bolt_mat
	ground_ring.scale = Vector3(0.1, 0.1, 0.1)
	lightning_root.add_child(ground_ring)

	# 7. Animation Tween Execution
	var tween := create_tween()

	# Phase 1: Sky lightning strikes down rapidly with intense jitter and electrical shock (0.22s)
	tween.tween_method(func(_prog: float):
		for b in range(num_bolts):
			var bd: Dictionary = bolts_data[b]
			var link_nodes: Array[Node3D] = bd["link_nodes"]
			for l in link_nodes:
				l.scale = Vector3.ONE * (1.0 + randf_range(-0.35, 0.35))
		# Electrical shock vibration on Decluck
		rotation_degrees.z = base_rot.z + randf_range(-14.0, 14.0)
		rotation_degrees.x = base_rot.x + randf_range(-8.0, 8.0)
	, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Float Decluck slightly into the air during lightning strike
	tween.parallel().tween_property(self, "position:y", base_stage_pos.y + 0.55, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Phase 2: Impact detonation burst, Screen Flash, and Model Swap to Decluckpowered.vox!
	tween.tween_callback(func():
		impact_sphere.scale = Vector3(1.5, 1.5, 1.5)
		ground_ring.scale = Vector3(2.5, 1.0, 2.5)
		_trigger_screen_flash(Color(0.3, 1.0, 0.7, 0.8), 0.15)
		_trigger_camera_shake(0.6, 0.3)
		rotation_degrees = base_rot

		# Load Powered Decluck model and mark transformed
		is_transformed = true
		_load_model(alt_path)

		FloatingText3D.spawn(parent_scene, global_position + Vector3(0, 1.1, 0), banner_text, Color.WHITE, true)
	)

	# Dissolve sky lightning bolts and impact sphere
	tween.tween_property(impact_sphere, "scale", Vector3(0.001, 0.001, 0.001), 0.12).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(lightning_root, "scale", Vector3(0.001, 0.001, 0.001), 0.12)
	tween.tween_callback(lightning_root.queue_free)

	# Phase 3: Heroic Ground Slam Landing with Expanding Shockwave
	tween.tween_property(self, "position", base_stage_pos, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", base_scale * 1.25, 0.16)
	tween.chain().tween_property(self, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BOUNCE)

	# Phase 4: Lingering Full Cowling Electrical Sparks Crackling Around Decluck's Body (0.45s)
	tween.tween_callback(func():
		var aura_sparks := Node3D.new()
		add_child(aura_sparks)
		aura_sparks.position = Vector3(0, 0.6, 0)

		# Spawn 5 orbiting crackling mini-arcs
		var arc_nodes: Array[Node3D] = []
		for a in range(5):
			var a_start := Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
			var a_end := Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.5), randf_range(-0.5, 0.5))
			var arc := _spawn_decluck_zigzag_bolt(aura_sparks, a_start, a_end, 5, 0.22, bolt_mat)
			arc_nodes.append(arc)

		# Jitter arcs and fade out
		var aura_tw := create_tween()
		aura_tw.tween_method(func(_p: float):
			for arc in arc_nodes:
				if is_instance_valid(arc):
					arc.scale = Vector3.ONE * (1.0 + randf_range(-0.3, 0.3))
		, 0.0, 1.0, 0.45)
		aura_tw.parallel().tween_property(aura_sparks, "scale", Vector3(0.001, 0.001, 0.001), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		aura_tw.tween_callback(aura_sparks.queue_free)
	)


## Golden Hen-Goku Super Saiyan Awakening Transition: floats up, golden ki aura erupts, flash swaps model, slams down!
func play_golden_transformation(alt_path: String, banner_text: String = "GOLDEN HEN-GOKU AWAKENED!") -> void:
	if is_dead or alt_path == "":
		return

	# Golden Ki Pillar Root
	var aura_root := Node3D.new()
	get_parent().add_child(aura_root)
	aura_root.global_position = base_stage_pos

	# Golden Ki Cylinder Aura
	var ki_cylinder := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 1.0
	cyl_mesh.bottom_radius = 1.2
	cyl_mesh.height = 3.0
	ki_cylinder.mesh = cyl_mesh
	ki_cylinder.position = Vector3(0, 1.5, 0)

	var ki_mat := _get_cached_material("hengoku_transform_ki", Color(1.0, 0.85, 0.15, 0.45), Color(1.0, 0.85, 0.2), 3.2, false, true)
	ki_cylinder.material_override = ki_mat
	aura_root.add_child(ki_cylinder)

	# Ground Shockwave Ring
	var ground_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.4
	ring_mesh.outer_radius = 0.7
	ground_ring.mesh = ring_mesh
	ground_ring.position = Vector3(0, 0.05, 0)

	var ring_mat := _get_cached_material("hengoku_transform_ring", Color(1.0, 0.9, 0.3, 0.7), Color(1.0, 0.9, 0.3), 3.0)
	ground_ring.material_override = ring_mat
	aura_root.add_child(ground_ring)

	aura_root.scale = Vector3(0.1, 0.1, 0.1)

	var tween := create_tween()
	# 1. Ascension: Float into air + Aura Eruption
	tween.tween_property(self, "position:y", base_stage_pos.y + 0.8, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(aura_root, "scale", Vector3(1.4, 1.4, 1.4), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ground_ring, "scale", Vector3(3.0, 1.0, 3.0), 0.35)

	# 2. Power Flash & Model Swap
	tween.tween_property(self, "scale", base_scale * 1.55, 0.1).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func():
		_load_model(alt_path)
		FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 0.8, 0), banner_text, Color.WHITE, true)
	)

	# 3. Ground Slam Landing
	tween.tween_property(self, "position", base_stage_pos, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", base_scale, 0.15).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(ki_mat, "albedo_color:a", 0.0, 0.2)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(func():
		aura_root.queue_free()
		_trigger_camera_shake(0.35, 0.12)
	)

## Standard transformation for other duelists
func play_transformation(alt_path: String, banner_text: String = "") -> void:
	if is_dead or alt_path == "":
		return

	FloatingText3D.spawn(get_parent(), global_position, banner_text if banner_text != "" else "AWAKEN!", Color.WHITE, true)
	
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale * 1.4, 0.2).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func():
		_load_model(alt_path)
	)
	tween.tween_property(self, "scale", base_scale, 0.2).set_trans(Tween.TRANS_BOUNCE)

## Animates defeat / KO -> swaps model to Fried Chicken with anime poof & steam
func play_death() -> void:
	is_dead = true
	_cleanup_stand()
	_stop_gear5_drums_loop()
	
	_trigger_camera_shake(0.45, 0.16)
	_trigger_screen_flash(Color(1.0, 0.25, 0.2, 0.55), 0.15)
	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.3, 0), "KNOCKOUT!", Color.CRIMSON, true)

	var target_floor_y: float = 0.08 if is_in_arena else base_stage_pos.y
	var fall_pos := Vector3(position.x, target_floor_y, position.z)

	var tween := create_tween()
	# 1. Flinch backward and tumble to the ground
	tween.tween_property(self, "position:y", position.y + 0.35, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "rotation_degrees:x", -75.0, 0.15)
	tween.parallel().tween_property(self, "rotation_degrees:z", 25.0, 0.15)
	
	# 2. Slam to floor
	tween.chain().tween_property(self, "position", fall_pos, 0.14).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# 3. Burst into smoke & poof into crispy fried chicken
	tween.tween_callback(func():
		_spawn_fried_chicken_poof_vfx(global_position)
		_load_model("res://resources/world/friedchicken(dead).vox")
		rotation_degrees = Vector3(0.0, randf_range(-45.0, 45.0), 0.0)
		scale = Vector3(1.15, 1.15, 1.15)
		_spawn_fried_chicken_steam_loop()
	)

## Poof smoke, feathers, and golden crispy crumb burst on defeat
func _spawn_fried_chicken_poof_vfx(origin: Vector3) -> void:
	var poof_root := Node3D.new()
	var p: Node = get_parent() if get_parent() else self
	p.add_child(poof_root)
	poof_root.global_position = origin + Vector3(0, 0.3, 0)

	# Smoke cloud balls
	var smoke_mat := _get_cached_material("friedchicken_poof_smoke", Color(0.9, 0.88, 0.82, 0.85))

	var puff_count: int = 6 if OS.has_feature("web") else 12
	for i in range(puff_count):
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(0.18, 0.32)
		sphere.height = sphere.radius * 2.0
		puff.mesh = sphere
		puff.material_override = smoke_mat
		poof_root.add_child(puff)

		var ang: float = float(i) * (TAU / float(puff_count))
		var dest := Vector3(cos(ang) * randf_range(0.6, 1.4), randf_range(0.1, 0.7), sin(ang) * randf_range(0.6, 1.4))
		var p_tw := puff.create_tween()
		p_tw.tween_property(puff, "position", dest, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		p_tw.parallel().tween_property(puff, "scale", Vector3(1.6, 1.6, 1.6), 0.20)
		p_tw.chain().tween_property(puff, "scale", Vector3.ZERO, 0.20)

	# Golden crispy crumb sparks
	var crumb_mat := _get_cached_material("friedchicken_poof_crumb", Color(0.95, 0.72, 0.18), Color(1.0, 0.7, 0.15), 3.0)

	var crumb_count: int = 4 if OS.has_feature("web") else 8
	for j in range(crumb_count):
		var crumb := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.08, 0.08)
		crumb.mesh = box
		crumb.material_override = crumb_mat
		poof_root.add_child(crumb)

		var c_ang: float = float(j) * (TAU / float(crumb_count)) + 0.3
		var c_dest := Vector3(cos(c_ang) * 0.9, randf_range(0.4, 1.1), sin(c_ang) * 0.9)
		var c_tw := crumb.create_tween()
		c_tw.tween_property(crumb, "position", c_dest, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		c_tw.parallel().tween_property(crumb, "scale", Vector3.ZERO, 0.30)

	var kill_tw := poof_root.create_tween()
	kill_tw.tween_interval(0.55)
	kill_tw.chain().tween_callback(poof_root.queue_free)

## Rising steam wisps floating upward from freshly cooked fried chicken
func _spawn_fried_chicken_steam_loop() -> void:
	if not is_inside_tree():
		return
	var steam_root := Node3D.new()
	add_child(steam_root)
	steam_root.position = Vector3(0, 0.3, 0)

	var s_mat := _get_cached_material("friedchicken_steam_loop", Color(1.0, 1.0, 1.0, 0.45))

	for i in range(3):
		var puff := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.09
		sp.height = 0.18
		puff.mesh = sp
		puff.material_override = s_mat
		puff.position = Vector3(randf_range(-0.15, 0.15), float(i) * 0.25, randf_range(-0.15, 0.15))
		steam_root.add_child(puff)

		var loop_tw := puff.create_tween().set_loops(10)
		loop_tw.tween_property(puff, "position:y", puff.position.y + 0.65, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		loop_tw.parallel().tween_property(puff, "scale", Vector3(1.5, 1.5, 1.5), 0.5)
		loop_tw.chain().tween_property(puff, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
		loop_tw.chain().tween_callback(func(): puff.position.y -= 0.65)

## Celebratory hop, wings flapping, and victory aura when winning the match
func play_victory_celebration() -> void:
	if is_dead:
		return
	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.35, 0), "VICTORY!", Color.GOLD, true)
	
	var tw := create_tween()
	# Joyful double hop
	tw.tween_property(self, "position:y", position.y + 0.8, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation_degrees:y", rotation_degrees.y + 180.0, 0.22)
	tw.chain().tween_property(self, "position:y", position.y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	tw.chain().tween_property(self, "position:y", position.y + 0.6, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation_degrees:y", rotation_degrees.y + 360.0, 0.18)
	tw.chain().tween_property(self, "position:y", position.y, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
