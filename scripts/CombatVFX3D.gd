extends Node3D
class_name CombatVFX3D

## CombatVFX3D — Handles spawning 3D Billboard Sprite effects in the Arena pit.
## All PNGs are horizontal-strip spritesheets (or 2D grids for platinumshield).
## Grid layouts are measured from actual pixel dimensions. FPS scales with frame count.

# Each entry: { "path": ..., "cols": N, "rows": M }
const VFX_DATA := {
	"slash":          { "path": "res://resources/spritesheets/normalslash.png",        "cols": 8,  "rows": 1 },
	"tripleslash":    { "path": "res://resources/spritesheets/tripleslash.png",         "cols": 14, "rows": 1 },
	"shield":         { "path": "res://resources/spritesheets/normalshield.png",        "cols": 8,  "rows": 1 },
	"bulkiershield":  { "path": "res://resources/spritesheets/bulkiershield.png",       "cols": 8,  "rows": 1 },
	"nugget":         { "path": "res://resources/spritesheets/nuggets.png",             "cols": 4,  "rows": 1 },
	"friedchicken":   { "path": "res://resources/spritesheets/friedchicken.png",        "cols": 7,  "rows": 1 },
	"normalpoop":     { "path": "res://resources/spritesheets/normalpoop.png",          "cols": 8,  "rows": 1 },
	"poopturd":       { "path": "res://resources/spritesheets/poopturd.png",            "cols": 5,  "rows": 1 },
	"kamecock":       { "path": "res://resources/models/hen_goku/Kamecock.png",         "cols": 8,  "rows": 1 },
	"allforonepunch": { "path": "res://resources/models/decluck/allforonepunch.png",    "cols": 3,  "rows": 1 },
	"allforoneheart": { "path": "res://resources/models/decluck/allforoneheart.png",    "cols": 3,  "rows": 1 },
	"clawstomp":      { "path": "res://resources/models/eren_pecker/clawstomp.png",    "cols": 3,  "rows": 1 },
	"titanstomp":     { "path": "res://resources/models/eren_pecker/titanstomp.png",   "cols": 3,  "rows": 1 },
	"gumslash":       { "path": "res://resources/models/cluckey_d_puffy/gumslash.png", "cols": 5,  "rows": 1 },
	"gumbarrier":     { "path": "res://resources/models/cluckey_d_puffy/gumbarrier.png","cols": 6, "rows": 1 },
	"chicknote":      { "path": "res://resources/models/chick_yagami/chixecution.png", "cols": 8,  "rows": 1 },
	"chixecution":    { "path": "res://resources/models/chick_yagami/chixecution.png", "cols": 8,  "rows": 1 },
	"oraora":         { "path": "res://resources/models/cocktaro/oraora.png",          "cols": 8,  "rows": 1 },
	"standcounter":   { "path": "res://resources/models/cocktaro/oraora.png",          "cols": 8,  "rows": 1 },
	"platinumshield": { "path": "res://resources/models/cocktaro/platinumshield.png",  "cols": 2,  "rows": 3 },
	"peckbreaker":    { "path": "res://resources/models/nechicko/peckbreaker.png",     "cols": 7,  "rows": 1 },
	"ketchup":        { "path": "res://resources/models/nechicko/ketchup.png",         "cols": 5,  "rows": 1 },
	"unseenclaw":     { "path": "res://resources/models/daniel/unseenclaw.png",        "cols": 5,  "rows": 1 },
	"chickenheart":   { "path": "res://resources/models/daniel/chickenheart.png",      "cols": 8,  "rows": 1 },
}

## FPS tuned by frame count: fewer frames = slower playback so each frame is visible.
static func _fps_for_frames(n: int) -> float:
	match n:
		1:  return 1.0
		2:  return 3.0
		3:  return 5.0
		4:  return 7.0
		5:  return 8.0
		6:  return 9.0
		7:  return 10.0
		_:  return 12.0  # 8+ frames: full speed

static func play_effect(parent: Node3D, pos: Vector3, vfx_key: String, _duration: float = -1.0) -> void:
	var data: Dictionary = VFX_DATA.get(vfx_key, VFX_DATA["slash"])
	var path: String  = data["path"]
	var cols: int     = data["cols"]
	var rows: int     = data["rows"]

	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return

	var total_frames: int = cols * rows
	var fps: float = _fps_for_frames(total_frames)

	# Build AnimatedSprite3D
	var sprite := AnimatedSprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.position = pos + Vector3(0, 0.85, 0)
	sprite.pixel_size = 0.025
	sprite.scale = Vector3(1.4, 1.4, 1.4)

	# Build SpriteFrames from atlas slices
	var frames_res := SpriteFrames.new()
	frames_res.remove_animation("default")
	frames_res.add_animation("play")
	frames_res.set_animation_speed("play", fps)
	frames_res.set_animation_loop("play", false)

	var frame_w: int = tex.get_width()  / cols
	var frame_h: int = tex.get_height() / rows
	for row in range(rows):
		for col in range(cols):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames_res.add_frame("play", atlas)

	sprite.sprite_frames = frames_res
	parent.add_child(sprite)
	sprite.play("play")

	# Fade out just before the last frame, then free
	var anim_duration: float = float(total_frames) / fps
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.2).set_delay(maxf(anim_duration - 0.2, 0.05))
	tween.tween_callback(sprite.queue_free)
