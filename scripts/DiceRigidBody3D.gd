extends RigidBody3D
class_name DiceRigidBody3D

## DiceRigidBody3D — a real RigidBody3D die. Gravity, collision with the table,
## friction and bounce all come from the physics engine itself, so the toss/tumble
## looks natural without hand-tuning bounce heights or timings.
##
## IMPORTANT: the handoff to the corrective face-snap happens EARLY — while the die
## is still visibly slowing down/tumbling (SOFT_* thresholds), not after it has
## already come to a full stop. If you wait until it's fully at rest first, any
## correction reads as an obvious "it landed on 5, then teleported to 2" snap.
## Handing off while there's still visible motion lets the correction blend into
## what looks like the die's own natural deceleration into its final resting face.

signal settled(value: int)

var roll_value: int = 1
var theme_color: Color = Color.WHITE
var title: String = ""
var spawn_parent: Node = null
var landing_center: Vector3 = Vector3.ZERO # target AREA to land near — not a forced exact point
var resting_y: float = 0.0 # exact table-flush height, set by DiceRoller3D

var _has_settled: bool = false
var _elapsed_physics_time: float = 0.0
var _settle_tween: Tween = null

# Trigger the corrective handoff as soon as the die drops below THESE thresholds —
# deliberately higher than "fully stopped" so there's still a little visible motion
# left for the correction to hide inside.
const SOFT_LINEAR_THRESHOLD: float = 0.45
const SOFT_ANGULAR_THRESHOLD: float = 3.2

# How far the die is allowed to rest from landing_center before we nudge it back
# (e.g. it bounced further than expected and ended up too close to the cards).
# Physics-decided positions inside this radius are left completely untouched —
# that's what removes the teleport, since we're no longer forcing an exact point.
const MAX_DRIFT_RADIUS: float = 0.35

## Returns the exact 3D Basis orientation ensuring the selected face (1 to 6) points directly UP
static func get_face_basis(val: int) -> Basis:
	match val:
		1: return Basis(Vector3.FORWARD, -PI * 0.5) # 1 is on +X (right)
		2: return Basis.IDENTITY                    # 2 is on +Y (top)
		3: return Basis(Vector3.RIGHT, PI * 0.5)    # 3 is on -Z (back)
		4: return Basis(Vector3.RIGHT, -PI * 0.5)   # 4 is on +Z (front)
		5: return Basis(Vector3.RIGHT, PI)          # 5 is on -Y (bottom)
		6: return Basis(Vector3.FORWARD, PI * 0.5)  # 6 is on -X (left)
		_: return Basis.IDENTITY

func _physics_process(delta: float) -> void:
	if _has_settled:
		return

	_elapsed_physics_time += delta
	# Physics failsafe: if tumbling exceeds 1.35s or die falls through table, force settle
	if _elapsed_physics_time >= 1.35 or global_position.y < (resting_y - 0.25):
		_settle(Vector3.ZERO)
		return

	# Hand off as soon as it's clearly winding down — NOT once it's already still.
	if linear_velocity.length() < SOFT_LINEAR_THRESHOLD and angular_velocity.length() < SOFT_ANGULAR_THRESHOLD:
		_settle(angular_velocity)

func _settle(exit_angular_velocity: Vector3) -> void:
	_has_settled = true

	# Stop simulating physics on this body from here on — we take over the last
	# bit of motion manually so it can be steered onto the correct face.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	var target_basis: Basis = get_face_basis(roll_value)
	var start_quat: Quaternion = Quaternion(global_transform.basis.orthonormalized())
	var target_quat: Quaternion = Quaternion(target_basis).normalized()

	# Take the shorter rotational path
	if start_quat.dot(target_quat) < 0.0:
		target_quat = -target_quat

	# Scale the correction's duration by how much motion the die still had when we
	# grabbed it — a die caught while spinning faster gets a slightly longer,
	# more decelerated finish; one caught almost still gets a short, gentle finish.
	# Either way it reads as "still slowing down," never as a snap.
	var motion_amount: float = clampf(exit_angular_velocity.length() / SOFT_ANGULAR_THRESHOLD, 0.0, 1.0)
	var settle_duration: float = lerpf(0.16, 0.30, motion_amount)

	# ── Position: trust wherever physics actually left it. ──
	# Only pull it back if it drifted outside the safe radius, and even then only
	# just enough to be back inside that radius — never snap to the exact center.
	var current_pos: Vector3 = global_position
	var horizontal_offset: Vector3 = current_pos - landing_center
	horizontal_offset.y = 0.0

	var final_pos: Vector3 = current_pos
	if horizontal_offset.length() > MAX_DRIFT_RADIUS:
		var clamped_horizontal: Vector3 = horizontal_offset.normalized() * MAX_DRIFT_RADIUS
		final_pos = landing_center + clamped_horizontal
	final_pos.y = resting_y # always correct height so it sits flush on the table

	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
	_settle_tween = create_tween()
	var tw: Tween = _settle_tween
	tw.set_parallel(true)

	tw.tween_method(
		func(t: float):
			if not is_instance_valid(self):
				return
			global_transform.basis = Basis(start_quat.slerp(target_quat, t)),
		0.0, 1.0, settle_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.tween_property(self, "global_position", final_pos, settle_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# A small decaying wobble after landing on the target face sells it as the die settling naturally
	tw.chain().tween_callback(func():
		if not is_instance_valid(self):
			return
		var base_rot: Vector3 = rotation_degrees
		var wobble_tw := create_tween()
		wobble_tw.tween_property(self, "rotation_degrees", base_rot + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), 0.05).set_trans(Tween.TRANS_SINE)
		wobble_tw.tween_property(self, "rotation_degrees", base_rot, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	tw.chain().tween_callback(func():
		if spawn_parent and is_instance_valid(spawn_parent):
			FloatingText3D.spawn(spawn_parent, final_pos + Vector3(0, 0.28, 0), "%s: %d" % [title, roll_value], theme_color, true)
		settled.emit(roll_value)
	)

func _exit_tree() -> void:
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
