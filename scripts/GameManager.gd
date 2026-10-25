extends Node

## GameManager — Global state singleton managing game mode, chosen rosters, settings, and scene transitions.
## Online match state aligns with Database System Blueprint §8 (matches table fields).

enum GameMode { TUTORIAL, VERSUS_1V1, CASUAL_BOTS, TOURNAMENT_ONLINE }

var selected_game_mode: GameMode = GameMode.VERSUS_1V1
var selected_player_rooster: RoosterData = null
var selected_opponent_rooster: RoosterData = null

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0

## Online multiplayer state (Blueprint §8 matches table)
var is_online_match: bool = false
var is_spectator: bool = false
## Convenience reference to the NetworkManager autoload
var network_manager: Node = null

const ALL_ROOSTER_PATHS: Array[String] = [
	"res://resources/roosters/hen_goku.tres",
	"res://resources/roosters/cocktaro.tres",
	"res://resources/roosters/cluckey_d_puffy.tres",
	"res://resources/roosters/daniel.tres",
	"res://resources/roosters/decluck.tres",
	"res://resources/roosters/eren_pecker.tres",
	"res://resources/roosters/nechicko.tres",
	"res://resources/roosters/chick_yagami.tres"
]

var all_roosters: Array[RoosterData] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all_roosters()
	# Cache NetworkManager autoload reference
	network_manager = get_node_or_null("/root/NetworkManager")

func _load_all_roosters() -> void:
	all_roosters.clear()
	for path in ALL_ROOSTER_PATHS:
		if ResourceLoader.exists(path):
			var r: RoosterData = load(path)
			all_roosters.append(r)
	
	if all_roosters.size() > 0:
		selected_player_rooster = all_roosters[0]
		selected_opponent_rooster = all_roosters[1 if all_roosters.size() > 1 else 0]

func get_random_opponent(exclude_rooster: RoosterData = null) -> RoosterData:
	if all_roosters.is_empty():
		return null
	var pool := all_roosters.duplicate()
	if exclude_rooster and pool.size() > 1:
		pool.erase(exclude_rooster)
	return pool[randi() % pool.size()]

## Look up a RoosterData by its rooster_id string
func get_rooster_by_id(rooster_id: String) -> RoosterData:
	for r in all_roosters:
		if r.rooster_id == rooster_id:
			return r
	return null

var _changing_scene: bool = false
var _loading_layer: CanvasLayer = null

## Switches scene behind a "LOADING" screen. Loading the arena froze the browser build for
## ~1 s with the old screen still showing, which looked like a hang.
func change_scene(target_path: String) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	var mm = get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("handle_scene_transition"):
		mm.handle_scene_transition(target_path)

	_show_loading_screen()
	# Let the loading screen reach the display before the (possibly blocking) load starts
	await get_tree().process_frame
	await get_tree().process_frame

	var packed: PackedScene = null
	if ResourceLoader.load_threaded_request(target_path) == OK:
		while ResourceLoader.load_threaded_get_status(target_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		packed = ResourceLoader.load_threaded_get(target_path) as PackedScene
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(target_path)

	# Keep covering the screen until the new scene has drawn its first frames
	for i in 3:
		await get_tree().process_frame
	_hide_loading_screen()
	_changing_scene = false

func _show_loading_screen() -> void:
	if is_instance_valid(_loading_layer):
		return
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 128
	add_child(_loading_layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.INK
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_layer.add_child(bg)
	var lbl := Label.new()
	lbl.text = "LOADING..."
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_title(lbl, 64, UITheme.STRAW)
	_loading_layer.add_child(lbl)

func _hide_loading_screen() -> void:
	if not is_instance_valid(_loading_layer):
		return
	var layer := _loading_layer
	_loading_layer = null
	var tw := create_tween()
	for child in layer.get_children():
		tw.parallel().tween_property(child, "modulate:a", 0.0, 0.2)
	tw.tween_callback(layer.queue_free)

## Resets online match state — called when returning to main menu or after forfeit
func reset_online_state() -> void:
	is_online_match = false
	is_spectator = false
	if network_manager:
		network_manager.disconnect_from_match()
