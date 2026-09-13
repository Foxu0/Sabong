class_name TableDeck3D
extends Node3D

## A realistic 3D playing card deck stack with BackCard.png face on top.
## The deck sits flat on the table surface. It is a solid block whose
## side faces show alternating light/dark card-edge stripes via a
## programmatically-generated texture, giving the appearance of a thick
## stack of individual cards.

const CARD_W: float = 0.32      # card width  (matches Card3D)
const CARD_H: float = 0.461     # card height (matches Card3D)
const DECK_THICK: float = 0.034 # total thickness (~19 cards at 1.8mm each)


const BACK_CARD_PATH: String = "res://resources/cards/BackCard.png"

var top_quad: MeshInstance3D

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()

	# ── 1. Main solid block (card edges) ────────────────────────────────
	# Use a BoxMesh with a stripe texture on the sides to look like stacked cards.
	var block := MeshInstance3D.new()
	var box   := BoxMesh.new()
	box.size = Vector3(CARD_W, DECK_THICK, CARD_H)
	block.mesh = box

	# Generate a small stripe texture (1 pixel wide, 18 alternating rows)
	var stripe_img := Image.create(1, 36, false, Image.FORMAT_RGBA8)
	for row in range(36):
		var bright: float = 0.90 if (row % 2 == 0) else 0.72
		stripe_img.set_pixel(0, row, Color(bright, bright * 0.96, bright * 0.90))
	var stripe_tex := ImageTexture.create_from_image(stripe_img)

	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_texture = stripe_tex
	side_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	# UV repeats along the Y axis of the mesh = card thickness direction
	side_mat.uv1_triplanar = true
	side_mat.uv1_triplanar_sharpness = 10.0
	side_mat.roughness = 0.75
	block.material_override = side_mat

	block.position = Vector3(0.0, DECK_THICK * 0.5, 0.0)
	add_child(block)

	# ── 2. Top face cover with the BackCard.png texture ──────────────────
	# A separate thin box flush on top — this gives us full texture control
	# for the top face without fighting the stripe material.
	var top_box_mi := MeshInstance3D.new()
	var top_box    := BoxMesh.new()
	top_box.size = Vector3(CARD_W, 0.001, CARD_H)
	top_box_mi.mesh = top_box
	var top_mat := StandardMaterial3D.new()
	top_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	top_mat.alpha_scissor_threshold = 0.5
	top_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	top_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	top_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(BACK_CARD_PATH):
		top_mat.albedo_texture = load(BACK_CARD_PATH)
	else:
		top_mat.albedo_color = Color(0.15, 0.15, 0.35) # fallback navy
	top_box_mi.material_override = top_mat
	# Flat directly on top of the block
	top_box_mi.position = Vector3(0.0, DECK_THICK + 0.001, 0.0)
	# No rotation needed — box top face is already facing +Y (up)
	add_child(top_box_mi)

	# ── 3. One slightly askew card on top (natural tabletop feel) ─────────
	# This is a flat quad with BackCard.png rotated ~1.5 degrees
	top_quad = MeshInstance3D.new()
	var q   := QuadMesh.new()
	q.size  = Vector2(CARD_W, CARD_H)
	top_quad.mesh = q
	var q_mat := StandardMaterial3D.new()
	q_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	q_mat.alpha_scissor_threshold = 0.5
	q_mat.shading_mode  = StandardMaterial3D.SHADING_MODE_UNSHADED
	q_mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	q_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(BACK_CARD_PATH):
		q_mat.albedo_texture = load(BACK_CARD_PATH)
	else:
		q_mat.albedo_color = Color(0.15, 0.15, 0.35)
	top_quad.material_override = q_mat
	# Flat on top of the block, slight organic tilt
	top_quad.position = Vector3(0.002, DECK_THICK + 0.003, 0.001)
	# -90 deg X = lying flat, slight Y rotation for the "human placed it" feel
	top_quad.rotation_degrees = Vector3(-90.0, 1.5, 0.0)
	add_child(top_quad)

func play_draw_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.04, 0.88, 1.04), 0.05).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BOUNCE)
