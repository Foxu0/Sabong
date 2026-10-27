extends MultiMeshInstance3D
class_name VoxelBurst3D

## VoxelBurst3D — a burst of small cubes (feathers, sparks, dust, shield shards) that fly
## out, tumble, fall and shrink away. Drawn as one MultiMesh so a burst is a single draw call.

static var _cube: BoxMesh = null
static var _material: StandardMaterial3D = null

var _vel := PackedVector3Array()
var _pos := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _size := PackedFloat32Array()
var _age := 0.0
var _life := 0.7
var _gravity := 9.0
var _floor_y := -INF

## mode: "burst" (sphere spray, biased toward dir), "ring" (flat outward ring, e.g. dust),
## "rise" (slow upward drift, e.g. smoke)
static func spawn(parent: Node, pos: Vector3, colors: Array, count: int = 14, speed: float = 3.0,
		cube_size: float = 0.09, life: float = 0.7, mode: String = "burst", dir: Vector3 = Vector3.ZERO,
		gravity: float = 9.0) -> VoxelBurst3D:
	if not parent or not parent.is_inside_tree() or colors.is_empty():
		return null
	_ensure_shared()
	var burst := VoxelBurst3D.new()
	burst._life = life
	burst._gravity = gravity
	burst._floor_y = pos.y - 0.05 if mode == "ring" else pos.y - 1.2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _cube
	mm.instance_count = count
	burst.multimesh = mm
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.material_override = _material
	parent.add_child(burst)
	burst.global_position = pos

	var bias := dir.normalized() if dir != Vector3.ZERO else Vector3.ZERO
	for i in count:
		var v: Vector3
		match mode:
			"ring":
				var a := randf() * TAU
				v = Vector3(cos(a), randf_range(0.05, 0.35), sin(a)) * speed * randf_range(0.7, 1.1)
			"rise":
				v = Vector3(randf_range(-0.4, 0.4), randf_range(0.6, 1.0), randf_range(-0.4, 0.4)) * speed
			_:
				v = Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
				v = (v + bias * 1.2).normalized() * speed * randf_range(0.55, 1.15)
				v.y += speed * 0.35
		burst._vel.append(v)
		burst._pos.append(Vector3(randf_range(-0.08, 0.08), randf_range(-0.05, 0.1), randf_range(-0.08, 0.08)))
		burst._axis.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
		burst._spin.append(randf_range(-14.0, 14.0))
		burst._angle.append(randf() * TAU)
		burst._size.append(cube_size * randf_range(0.6, 1.3))
		mm.set_instance_color(i, colors[i % colors.size()])
	burst._update_instances()
	return burst

static func _ensure_shared() -> void:
	if _cube:
		return
	_cube = BoxMesh.new()
	_cube.size = Vector3.ONE
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.9

func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	var local_floor := _floor_y - global_position.y
	for i in _vel.size():
		_vel[i].y -= _gravity * delta
		_pos[i] += _vel[i] * delta
		if _pos[i].y < local_floor:
			# Land and skid instead of falling through the floor
			_pos[i].y = local_floor
			_vel[i] = Vector3(_vel[i].x * 0.5, absf(_vel[i].y) * 0.25, _vel[i].z * 0.5)
			_spin[i] *= 0.5
		_angle[i] += _spin[i] * delta
	_update_instances()

func _update_instances() -> void:
	var t := _age / _life
	# Hold full size, then shrink away over the last 40% of the life
	var fade := 1.0 if t < 0.6 else clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
	for i in _vel.size():
		var b := Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * _size[i] * fade)
		multimesh.set_instance_transform(i, Transform3D(b, _pos[i]))
