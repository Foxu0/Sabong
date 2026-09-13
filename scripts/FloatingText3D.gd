extends Label3D
class_name FloatingText3D

## FloatingText3D — 3D combat numbers/text floating over roosters during combat.

static func spawn(parent: Node, pos: Vector3, p_text: String, color: Color = Color.WHITE, is_crit: bool = false) -> void:
	var label: Label3D = Label3D.new()
	label.text = p_text
	label.font = UIFontStyle.get_popup_font()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_modulate = Color.BLACK
	label.outline_size = 10
	label.font_size = 52 if not is_crit else 72
	label.position = pos + Vector3(randf_range(-0.3, 0.3), 1.2, randf_range(-0.3, 0.3))
	parent.add_child(label)

	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3(1.3, 1.3, 1.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)
