extends RefCounted
class_name ShaderWarmup

## ShaderWarmup — draws one tiny sample of everything that first appears mid-match (card,
## dice, effect materials, debris, floating text, sprite effect) so their shaders compile
## during the MATCH START pause. Browsers compile shaders the first time they are drawn on
## every page load, which froze the opening dice roll, fight and discard.
## The samples sit just in front of the camera at a scale too small to see.

const SAMPLE_SCALE := 0.004
const FRAMES_TO_DRAW := 3

static func run(arena: Node3D, camera: Camera3D, roosters: Array, sample_card: CardData) -> void:
	if not arena or not camera or not arena.is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "ShaderWarmup"
	arena.add_child(root)
	root.global_transform = camera.global_transform.translated_local(Vector3(0, 0, -1.0))
	root.scale = Vector3.ONE * SAMPLE_SCALE

	# A table card with all its layers
	if sample_card:
		var card := Card3D.new()
		card.card_data = sample_card
		root.add_child(card)

	# Each player's dice model
	for r in roosters:
		if r and r.dice_model_path != "" and ResourceLoader.exists(r.dice_model_path):
			var res = load(r.dice_model_path)
			if res is PackedScene:
				root.add_child(res.instantiate())

	# Every combination of effect-material settings, on a voxel shape (vertex colours)
	var shape := VoxelSphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	var i := 0
	for emissive in [false, true]:
		for unshaded in [false, true]:
			for cull_off in [false, true]:
				var mi := MeshInstance3D.new()
				mi.mesh = shape
				mi.material_override = RoosterVisual3D._get_cached_material(
					"warmup_%d" % i, Color(1, 1, 1, 0.5),
					Color.WHITE if emissive else Color.BLACK, 1.0 if emissive else 0.0, unshaded, cull_off)
				root.add_child(mi)
				i += 1

	# Debris cubes, a floating number and a sprite-sheet effect
	VoxelBurst3D.spawn(root, root.global_position, [Color.WHITE], 2, 0.0, 0.05, 1.0, "burst", Vector3.ZERO, 0.0)
	FloatingText3D.spawn(root, Vector3.ZERO, "0")
	CombatVFX3D.play_effect(root, Vector3.ZERO, "slash")

	var tree := arena.get_tree()
	for f in FRAMES_TO_DRAW:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(root):
			return
	root.queue_free()
	# Clear the throwaway materials from the effect material cache
	for k in i:
		RoosterVisual3D._vfx_mat_cache.erase("warmup_%d" % k)
	if tree:
		await tree.process_frame
