extends Node
class_name DiceRoller3D

## DiceRoller3D — spawns physics-driven dice (DiceRigidBody3D). The toss, bounce,
## friction, and tumble all come from Godot's physics engine; this script only
## sets the initial throw velocity/spin and where the die should end up.

# Tabletop surface height in arena.tscn (prop_table_light_brown & prop_table_light_brown2)
const TABLE_TOP_Y: float = 0.837
# Arena pit floor height in arena.tscn
const ARENA_FLOOR_Y: float = 0.45

static var active_dice: Array[Node3D] = []

static func clear_active_dice(animate: bool = true) -> void:
	for die in active_dice:
		if is_instance_valid(die):
			if animate and die.is_inside_tree():
				var tw := die.create_tween()
				if tw:
					tw.tween_property(die, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_QUAD)
					tw.chain().tween_callback(die.queue_free)
				else:
					die.queue_free()
			else:
				die.queue_free()
	active_dice.clear()

static func roll_duel_dice(parent: Node, p1_model_path: String, p2_model_path: String, p1_roll: int, p2_roll: int, in_arena: bool = false) -> void:
	if not parent:
		return

	# Smoothly clear previous round's dice before rolling new ones
	clear_active_dice(true)

	if in_arena:
		# Roll directly in the center of the Arena pit between the roosters
		var p1_die := _roll_procedural_dice(
			parent,
			p1_model_path,
			Vector3(1.6, 3.2, 0.8),
			Vector3(0.55, 0.0, 0.0),
			p1_roll,
			Color(1.0, 0.35, 0.35),
			"MERON",
			0.20,
			ARENA_FLOOR_Y
		)
		if p1_die:
			active_dice.append(p1_die)

		var p2_die := _roll_procedural_dice(
			parent,
			p2_model_path,
			Vector3(-1.6, 3.2, -0.8),
			Vector3(-0.55, 0.0, 0.0),
			p2_roll,
			Color(0.35, 0.75, 1.0),
			"WALA",
			0.20,
			ARENA_FLOOR_Y
		)
		if p2_die:
			active_dice.append(p2_die)
	else:
		# Roll Meron die on Table 1 (+X side, Player 1's side)
		var p1_die := _roll_procedural_dice(
			parent,
			p1_model_path,
			Vector3(3.90, 1.75, 0.60),
			Vector3(3.20, 0.0, 0.60),
			p1_roll,
			Color(1.0, 0.35, 0.35),
			"MERON",
			0.10,
			TABLE_TOP_Y
		)
		if p1_die:
			active_dice.append(p1_die)

		# Roll Wala die on Table 2 (-X side, Player 2's side)
		var p2_die := _roll_procedural_dice(
			parent,
			p2_model_path,
			Vector3(-3.90, 1.75, -0.60),
			Vector3(-3.20, 0.0, -0.60),
			p2_roll,
			Color(0.35, 0.75, 1.0),
			"WALA",
			0.10,
			TABLE_TOP_Y
		)
		if p2_die:
			active_dice.append(p2_die)

const DiceRigidBody3DScript = preload("res://scripts/DiceRigidBody3D.gd")

static func _roll_procedural_dice(parent: Node, model_path: String, start_pos: Vector3, end_pos_xz: Vector3, roll_value: int, theme_color: Color, title: String, target_scale: float = 0.09, floor_y: float = TABLE_TOP_Y) -> Node3D:
	var die: RigidBody3D = DiceRigidBody3DScript.new()
	die.roll_value = roll_value
	die.theme_color = theme_color
	die.title = title
	die.spawn_parent = parent
	die.position = start_pos

	var half_extent: Vector3 = Vector3(target_scale, target_scale, target_scale)

	# Instantiate the voxel model
	if model_path != "" and ResourceLoader.exists(model_path):
		var res = load(model_path)
		if res is PackedScene:
			var model_inst: Node3D = res.instantiate()
			die.add_child(model_inst)
			model_inst.scale = Vector3(target_scale, target_scale, target_scale)

			# Center the cube geometry exactly at (0,0,0) so physics rotates around the true center
			for child in model_inst.find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D and child.mesh:
					var child_aabb: AABB = child.mesh.get_aabb()
					half_extent = child_aabb.size * 0.5 * target_scale
					model_inst.position = -child.position * target_scale
					break

	# Box collision shape matching the die's actual size
	var shape := BoxShape3D.new()
	shape.size = half_extent * 2.0
	var col := CollisionShape3D.new()
	col.shape = shape
	die.add_child(col)

	# Tabletop/Arena-appropriate physics material: some bounce, decent friction so it doesn't slide forever
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.25
	die.physics_material_override = mat
	die.mass = 0.05
	die.gravity_scale = 2.4
	die.continuous_cd = true

	# Match collision layer/mask with arena floor/table StaticBody3D
	die.collision_layer = 1
	die.collision_mask = 1

	var resting_y: float = floor_y + half_extent.y
	var landing_pos: Vector3 = Vector3(end_pos_xz.x, resting_y, end_pos_xz.z)
	die.landing_center = landing_pos
	die.resting_y = resting_y

	# Aim the toss at the landing spot: horizontal velocity covers the distance in ~0.45s,
	# vertical velocity gives it a believable arc height.
	var dir: Vector3 = landing_pos - start_pos
	dir.y = 0.0
	var flight_time: float = 0.45
	var toss_speed: float = dir.length() / flight_time
	var toss_dir: Vector3 = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD

	die.linear_velocity = toss_dir * toss_speed + Vector3.UP * 4.2

	# Random tumbling spin (rad/sec) — physics friction naturally decays this over the bounces
	die.angular_velocity = Vector3(
		randf_range(-18.0, 18.0),
		randf_range(-18.0, 18.0),
		randf_range(-18.0, 18.0)
	)

	parent.add_child.call_deferred(die)

	return die
