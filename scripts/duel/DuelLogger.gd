class_name DuelLogger
extends RefCounted

## DuelLogger — Dedicated authoritative diagnostic logging system for Sabong Roosters.
## Logs all phase transitions, player inputs, card actions, state changes, and detects
## unexpected behaviors (e.g. stale queued cards, illegal attacks, double-clicks, stuck hovers).
## Writes to both console and persistent log files ('res://duel_debug.log' and 'user://duel_debug.log').

const LOG_FILE_RES: String = "res://duel_debug.log"
const LOG_FILE_USER: String = "user://duel_debug.log"

static var _is_initialized: bool = false

static func _init_log_file() -> void:
	if _is_initialized:
		return
	_is_initialized = true

	# Start new log session header
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	var sep: String = "================================================================================"
	var header: String = "\n" + sep + "\n"
	header += "=== SABONG ROOSTERS DUEL DIAGNOSTIC LOG SESSION STARTED: %s ===\n" % timestamp
	header += sep + "\n"
	_write_raw(header)

static func _format_prefix(level: String) -> String:
	var time_str: String = Time.get_time_string_from_system()
	var msec: int = Time.get_ticks_msec() % 1000
	return "[%s.%03d] [%s]" % [time_str, msec, level]

## Lines are buffered and written in one batch about once a second. Opening, flushing and
## closing both log files for every line stalled phase changes (and on the web each close
## syncs browser storage).
const FLUSH_INTERVAL_SEC: float = 1.0
const MAX_LOG_BYTES: int = 2 * 1024 * 1024
static var _pending: PackedStringArray = []
static var _flush_scheduled: bool = false

static func _write_raw(text: String) -> void:
	_pending.append(text)
	if _flush_scheduled:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		_flush_scheduled = true
		tree.create_timer(FLUSH_INTERVAL_SEC, true).timeout.connect(flush)
	else:
		flush()

## Writes buffered lines to disk now (also called on a timer).
static func flush() -> void:
	_flush_scheduled = false
	if _pending.is_empty():
		return
	var text := "".join(_pending)
	_pending.clear()
	# In the browser user:// lives in IndexedDB and every write syncs the whole file back,
	# which froze the game for hundreds of ms. Lines still go to the browser console.
	if OS.has_feature("web"):
		return
	_append_to(LOG_FILE_USER, text)
	# res:// is only writable when running from the editor
	if OS.has_feature("editor"):
		_append_to(LOG_FILE_RES, text)

static func _append_to(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.READ_WRITE)
	if fa and fa.get_length() > MAX_LOG_BYTES:
		fa = null # start over instead of growing forever
	if not fa:
		fa = FileAccess.open(path, FileAccess.WRITE)
	if fa:
		fa.seek_end()
		fa.store_string(text)

static func _log(level: String, context: String, message: String) -> void:
	_init_log_file()
	var line: String = "%s [%s] %s\n" % [_format_prefix(level), context, message]
	_write_raw(line)
	
	# Also output to Godot engine console
	match level:
		"ERROR":
			push_error("[DuelLogger] " + line.strip_edges())
		"WARN":
			push_warning("[DuelLogger] " + line.strip_edges())
		_:
			print("[DuelLogger] " + line.strip_edges())

## Public logging API
static func info(context: String, message: String) -> void:
	_log("INFO", context, message)

static func action(player_id: String, action_name: String, details: String = "") -> void:
	var msg: String = "Player %s executed action '%s'" % [player_id, action_name]
	if details != "":
		msg += " | Details: %s" % details
	_log("ACTION", player_id, msg)

static func warn(context: String, message: String) -> void:
	_log("WARN", context, message)

static func error(context: String, message: String) -> void:
	_log("ERROR", context, message)

static func phase(phase_name: String, round_num: int, extra_info: String = "") -> void:
	var msg: String = "=== ENTERED PHASE: %s (ROUND %d) ===" % [phase_name, round_num]
	if extra_info != "":
		msg += " | %s" % extra_info
	_log("PHASE", "DuelPhaseManager", msg)

static func combat_event(event: Dictionary) -> void:
	var type_val = event.get("type", -1)
	var attacker: int = int(event.get("attacker", 0))
	var card_id: String = str(event.get("card_id", ""))
	var dmg: int = int(event.get("actual_hp_damage", 0))
	var raw: int = int(event.get("raw_damage", 0))
	var msg: String = "Combat Event type=%s | Attacker=%d | Card=%s | RawDmg=%d | ActualDmg=%d" % [str(type_val), attacker, card_id, raw, dmg]
	_log("COMBAT", "CombatEngine", msg)
