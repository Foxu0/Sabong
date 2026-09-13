class_name TableDiscardPile3D
extends Node3D

## TableDiscardPile3D — Physical 3D discard pile on the duel tabletop.
## Displays a card tray with the top discarded card resting face-up,
## and a clean 3D counter label showing how many cards have been discarded.

const CARD_W: float = 0.32
const CARD_H: float = 0.461

var card_count: int = 0
var top_card: CardData = null

var tray_mesh: MeshInstance3D
var top_card_mesh: MeshInstance3D
var count_label: Label3D
var top_card_material: StandardMaterial3D

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Base Tray on Table (Dark mahogany / obsidian mat)
	tray_mesh = MeshInstance3D.new()
	var tray_box := BoxMesh.new()
	tray_box.size = Vector3(CARD_W * 1.08, 0.004, CARD_H * 1.08)
	tray_mesh.mesh = tray_box
	var tray_mat := StandardMaterial3D.new()
	tray_mat.albedo_color = Color(0.12, 0.08, 0.09, 0.90)
	tray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tray_mat.roughness = 0.65
	tray_mesh.material_override = tray_mat
	tray_mesh.position = Vector3(0, 0.002, 0)
	add_child(tray_mesh)

	# 2. Subtle Gold Border Accent Rim
	var border := MeshInstance3D.new()
	var border_mesh := BoxMesh.new()
	border_mesh.size = Vector3(CARD_W * 1.12, 0.002, CARD_H * 1.12)
	border.mesh = border_mesh
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.72, 0.52, 0.22, 0.65)
	border.material_override = b_mat
	border.position = Vector3(0, 0.001, 0)
	add_child(border)

	# 3. Top Face-Up Card Mesh (shows face/art of the top discarded card)
	top_card_mesh = MeshInstance3D.new()
	var card_quad := QuadMesh.new()
	card_quad.size = Vector2(CARD_W, CARD_H)
	top_card_mesh.mesh = card_quad
	top_card_material = StandardMaterial3D.new()
	top_card_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	top_card_material.alpha_scissor_threshold = 0.5
	top_card_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	top_card_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	top_card_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	top_card_mesh.material_override = top_card_material
	top_card_mesh.rotation_degrees = Vector3(-90.0, 90.0, 0.0) # Flat face-up
	top_card_mesh.position = Vector3(0, 0.006, 0)
	top_card_mesh.visible = false
	add_child(top_card_mesh)

	# 4. 3D Status & Count Label
	count_label = Label3D.new()
	count_label.font = UIFontStyle.get_anton_font()
	count_label.font_size = 20
	count_label.pixel_size = 0.00085
	count_label.outline_size = 5
	count_label.outline_modulate = Color.BLACK
	count_label.modulate = Color(0.96, 0.96, 0.98) # Clean white
	count_label.render_priority = 45
	count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count_label.position = Vector3(0, 0.08, CARD_H * 0.56)
	count_label.text = "DISCARD PILE (0)"
	add_child(count_label)

## Updates the discard pile with new cards and displays the top card face-up
func update_discard_pile(cards: Array, new_top_card: CardData = null) -> void:
	card_count = cards.size()
	if new_top_card:
		top_card = new_top_card
	elif cards.size() > 0 and cards[-1] is CardData:
		top_card = cards[-1]
	else:
		top_card = null

	if count_label:
		count_label.text = "DISCARD PILE (%d)" % card_count

	if top_card and top_card_material:
		var tex: Texture2D = null
		if top_card.art_path != "" and ResourceLoader.exists(top_card.art_path):
			tex = load(top_card.art_path)
		
		if tex:
			top_card_material.albedo_texture = tex
			top_card_mesh.visible = true
			top_card_mesh.position.y = 0.006 + minf(float(card_count) * 0.0015, 0.035)
		else:
			top_card_material.albedo_color = Color(0.18, 0.18, 0.22)
			top_card_mesh.visible = true
	else:
		if top_card_mesh:
			top_card_mesh.visible = false

## Play a little bounce pulse when a card lands in the discard pile
func play_discard_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.06, 0.90, 1.06), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BOUNCE)
