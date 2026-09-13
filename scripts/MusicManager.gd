extends Node

## MusicManager — Global Background Music Singleton
## Manages BGM playback, seamless cross-fading, track progression, and volume syncing with GameManager.

const TRACK_RETRO_LOUNGE: String = "res://resources/Game music options/Week 1 - Retro Lounge MELODY.ogg"
const TRACK_RUINED_LANDS: String = "res://resources/Game music options/Week 2 - Ruined Lands WASTELAND.ogg"
const TRACK_LOST_IN_SPACE: String = "res://resources/Game music options/Week 11 - Lost in Space.ogg"

const TRACK_TITLES: Dictionary = {
	TRACK_RETRO_LOUNGE: "Retro Lounge (Melody)",
	TRACK_RUINED_LANDS: "Ruined Lands (Wasteland)",
	TRACK_LOST_IN_SPACE: "Lost in Space"
}

const PLAYLIST: Array[String] = [
	TRACK_RETRO_LOUNGE,
	TRACK_RUINED_LANDS,
	TRACK_LOST_IN_SPACE
]

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _current_path: String = ""
var _current_index: int = 0
var _fade_tween: Tween
var _loaded_streams: Dictionary = {}
var is_muted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus = "Master"
	_player_a.process_mode = Node.PROCESS_MODE_ALWAYS
	_player_a.finished.connect(func(): _on_player_finished(_player_a))
	add_child(_player_a)
	
	_player_b = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus = "Master"
	_player_b.process_mode = Node.PROCESS_MODE_ALWAYS
	_player_b.finished.connect(func(): _on_player_finished(_player_b))
	add_child(_player_b)
	
	_active_player = _player_a
	
	# Start menu theme automatically on launch
	play_menu_theme()

func _unhandled_input(event: InputEvent) -> void:
	# HTML5 / Web Audio context unlock: Browser requires user interaction before audio starts
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		if _active_player and not _active_player.playing and not _current_path.is_empty() and not is_muted:
			_active_player.play()

func get_stream(path: String) -> AudioStream:
	if _loaded_streams.has(path):
		return _loaded_streams[path]
	
	var stream: AudioStream = null
	
	# 1. Standard ResourceLoader / load() (used in PCK / exported builds and imported editor assets)
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			stream = res
	
	# 2. Runtime fallback via AudioStreamOggVorbis.load_from_file if not yet imported by Godot editor
	if not stream and FileAccess.file_exists(path):
		if ClassDB.class_exists("AudioStreamOggVorbis") and AudioStreamOggVorbis.has_method("load_from_file"):
			stream = AudioStreamOggVorbis.load_from_file(path)
	
	if stream:
		if "loop" in stream:
			stream.loop = true
		_loaded_streams[path] = stream
		return stream
	
	push_warning("MusicManager: Could not load track at: " + path)
	return null

func _get_target_db() -> float:
	if is_muted:
		return -80.0
	
	var gm = get_node_or_null("/root/GameManager")
	var m_vol: float = gm.music_volume if gm else 1.0
	var master_vol: float = gm.master_volume if gm else 1.0
	var effective: float = clampf(m_vol * master_vol, 0.0, 1.0)
	
	if effective <= 0.001:
		return -80.0
	return linear_to_db(effective)

func update_volume() -> void:
	if _fade_tween and _fade_tween.is_valid():
		# Let the tween handle volume
		return
	if _active_player:
		_active_player.volume_db = _get_target_db()

func set_volume(val: float) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.music_volume = clampf(val, 0.0, 1.0)
	update_volume()

func play_track(path: String, crossfade_duration: float = 0.8) -> void:
	if _current_path == path and _active_player and _active_player.playing:
		return # Already playing this track
	
	var stream := get_stream(path)
	if not stream:
		return
	
	_current_path = path
	_current_index = PLAYLIST.find(path)
	if _current_index == -1:
		_current_index = 0
	
	var target_player := _player_b if _active_player == _player_a else _player_a
	var fading_player := _active_player
	_active_player = target_player
	
	target_player.stream = stream
	var target_db := _get_target_db()
	
	if fading_player and fading_player.playing and crossfade_duration > 0.0:
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		
		target_player.volume_db = -80.0
		target_player.play()
		
		_fade_tween = create_tween().set_parallel(true)
		_fade_tween.tween_property(target_player, "volume_db", target_db, crossfade_duration)
		_fade_tween.tween_property(fading_player, "volume_db", -80.0, crossfade_duration)
		_fade_tween.chain().tween_callback(func():
			fading_player.stop()
		)
	else:
		target_player.volume_db = target_db
		target_player.play()

func play_menu_theme() -> void:
	play_track(TRACK_RETRO_LOUNGE)

func play_battle_theme() -> void:
	play_track(TRACK_RUINED_LANDS)

func play_tournament_theme() -> void:
	play_track(TRACK_LOST_IN_SPACE)

func next_track() -> void:
	var next_idx := (_current_index + 1) % PLAYLIST.size()
	play_track(PLAYLIST[next_idx])

func prev_track() -> void:
	var prev_idx := (_current_index - 1 + PLAYLIST.size()) % PLAYLIST.size()
	play_track(PLAYLIST[prev_idx])

func toggle_mute() -> bool:
	is_muted = not is_muted
	update_volume()
	return is_muted

func get_current_track_title() -> String:
	if TRACK_TITLES.has(_current_path):
		return TRACK_TITLES[_current_path]
	return "None"

func handle_scene_transition(scene_path: String) -> void:
	var lower := scene_path.to_lower()
	if "arena" in lower:
		play_battle_theme()
	elif "bracket" in lower:
		play_tournament_theme()
	elif "menu" in lower or "character" in lower or "lobby" in lower:
		play_menu_theme()

func _on_player_finished(player_node: AudioStreamPlayer) -> void:
	if player_node == _active_player and not is_muted:
		# Seamless loop replay
		player_node.play()
