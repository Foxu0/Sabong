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

func change_scene(target_path: String) -> void:
	get_tree().change_scene_to_file(target_path)

## Resets online match state — called when returning to main menu or after forfeit
func reset_online_state() -> void:
	is_online_match = false
	if network_manager:
		network_manager.disconnect_from_match()
