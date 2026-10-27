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
	_apply_touch_ui_scale()

## The UI is laid out for 1920x1080 and shrinks with the window. On a landscape phone
## that left text and buttons about a third of their size, too small to read or tap,
## so touch devices draw the UI larger: 1.5x on phones, 1.25x on tablets.
func _apply_touch_ui_scale() -> void:
	var touch := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not touch:
		return
	var screen := DisplayServer.screen_get_size()
	var dpi := maxi(DisplayServer.screen_get_dpi(), 1)
	var short_inches := float(mini(screen.x, screen.y)) / dpi
	get_tree().root.content_scale_factor = 1.5 if short_inches < 3.6 else 1.25

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

var _hit_stop_active: bool = false

## Briefly slows the game to near-still on a heavy hit. Lives here (always loaded) so time
## can't stay slowed if the rooster that triggered it is freed mid-freeze.
func hit_stop(seconds: float) -> void:
	if _hit_stop_active:
		return
	_hit_stop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false

var _changing_scene: bool = false
var _loading_screen: LoadingScreen = null

## Switches scene behind a loading screen. Loading the arena froze the browser build for
## ~1 s with the old screen still showing, which looked like a hang.
func change_scene(target_path: String) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	Engine.time_scale = 1.0
	var mm = get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("handle_scene_transition"):
		mm.handle_scene_transition(target_path)

	if not is_instance_valid(_loading_screen):
		_loading_screen = LoadingScreen.new()
		add_child(_loading_screen)
	# Let the loading screen reach the display before the (possibly blocking) load starts
	await get_tree().process_frame
	await get_tree().process_frame

	var packed: PackedScene = null
	if ResourceLoader.load_threaded_request(target_path) == OK:
		var progress: Array = []
		while ResourceLoader.load_threaded_get_status(target_path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if is_instance_valid(_loading_screen) and not progress.is_empty():
				_loading_screen.set_progress(progress[0])
			await get_tree().process_frame
		packed = ResourceLoader.load_threaded_get(target_path) as PackedScene
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(target_path)

	# Keep covering the screen until the new scene has drawn its first frames
	if is_instance_valid(_loading_screen):
		_loading_screen.set_progress(1.0)
	for i in 3:
		await get_tree().process_frame
	if is_instance_valid(_loading_screen):
		_loading_screen.fade_out()
	_loading_screen = null
	_changing_scene = false

## Resets online match state — called when returning to main menu or after forfeit
func reset_online_state() -> void:
	is_online_match = false
	is_spectator = false
	if network_manager:
		network_manager.disconnect_from_match()
