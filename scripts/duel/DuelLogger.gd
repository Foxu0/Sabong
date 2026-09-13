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

static func _write_raw(text: String) -> void:
	# 1. Write to res:// (directly in project workspace)
	var fa_res := FileAccess.open(LOG_FILE_RES, FileAccess.READ_WRITE)
	if not fa_res:
		fa_res = FileAccess.open(LOG_FILE_RES, FileAccess.WRITE)
	if fa_res:
		fa_res.seek_end()
		fa_res.store_string(text)
		fa_res.flush()

	# 2. Write to user:// (persistent application data)
	var fa_user := FileAccess.open(LOG_FILE_USER, FileAccess.READ_WRITE)
	if not fa_user:
		fa_user = FileAccess.open(LOG_FILE_USER, FileAccess.WRITE)
	if fa_user:
		fa_user.seek_end()
		fa_user.store_string(text)
		fa_user.flush()

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
