extends CanvasLayer
class_name LoadingScreen

## LoadingScreen — full-screen cover shown while GameManager switches scenes. Matches the
## web startup page: wood planks, game title, a progress bar fed from the threaded load,
## and a gameplay tip.

const PLANK_HEIGHT := 135.0
const PLANK_GAP := 6.0
const PLANK_LINE := Color("2f1d11")
const TIPS: Array[String] = [
	"A higher dice roll strikes first and unlocks stronger cards.",
	"You discard as many cards as your roll, then refill your hand.",
	"Each round gives you 3 Taya. Most cards cost 1.",
	"Shields only last for the round you play them.",
	"Decluck's All For One cards grow with every extra Taya.",
	"Daniel comes back once at a third of his HP.",
	"Chick Yagami's poop stacks hurt more the longer they stay.",
	"Equal dice rolls mean a clash: both attacks land at once.",
]

var _root: Control
var _fill: ColorRect
var _track: Panel
var _shown_progress: float = 0.0
var _target_progress: float = 0.0

func _init() -> void:
	layer = 128

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw_planks)
	_root.resized.connect(_root.queue_redraw)
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := Label.new()
	title.text = "SABONG LEGENDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(title, 120, UITheme.STRAW)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "CLUCK COCK"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(sub, 52, UITheme.CREAM)
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)

	# Progress bar: cream track with a heavy ink bottom edge, barn-red fill
	_track = Panel.new()
	_track.custom_minimum_size = Vector2(760, 48)
	_track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.CREAM
	sb.border_color = UITheme.INK
	sb.set_border_width_all(5)
	sb.border_width_bottom = 12
	sb.set_corner_radius_all(UITheme.CORNER)
	_track.add_theme_stylebox_override("panel", sb)
	col.add_child(_track)
	_fill = ColorRect.new()
	_fill.color = UITheme.BARN_RED
	_fill.position = Vector2(5, 5)
	_fill.size = Vector2(0, 48 - 17)
	_track.add_child(_fill)

	var lbl := Label.new()
	lbl.text = "LOADING..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(lbl, 36, UITheme.CREAM)
	col.add_child(lbl)

	var tip := Label.new()
	tip.text = "TIP   " + TIPS[randi() % TIPS.size()]
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(900, 0)
	UITheme.style_text(tip, 26, UITheme.MUTED, true)
	col.add_child(tip)

## progress: 0..1 from ResourceLoader.load_threaded_get_status.
func set_progress(progress: float) -> void:
	_target_progress = clampf(progress, _target_progress, 1.0)

func _process(delta: float) -> void:
	if not _fill:
		return
	_shown_progress = move_toward(_shown_progress, _target_progress, delta * 2.5)
	_fill.size.x = (_track.size.x - 10.0) * _shown_progress

func fade_out() -> void:
	set_progress(1.0)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)

func _draw_planks() -> void:
	var h := _root.size.y
	var w := _root.size.x
	_root.draw_rect(Rect2(0, 0, w, h), UITheme.WOOD_DARK)
	var y := PLANK_HEIGHT
	while y < h:
		_root.draw_rect(Rect2(0, y, w, PLANK_GAP), PLANK_LINE)
		y += PLANK_HEIGHT + PLANK_GAP
