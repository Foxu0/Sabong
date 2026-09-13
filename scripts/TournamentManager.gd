extends Node

## TournamentManager — Global singleton managing Sabong Cockpit tournaments.
## Supports configurable bot deployment (3, 7, 15 bots -> 4, 8, 16 duelists),
## Single & Double Elimination formats, 3D bracket coordinates,
## match results tracking, and final rank leaderboard calculation.

enum Format {
	SINGLE_ELIMINATION,
	DOUBLE_ELIMINATION
}

var is_tournament_active: bool = false
var current_format: Format = Format.SINGLE_ELIMINATION
var current_bot_count: int = 7 # 3, 7, or 15 bots
var player_rooster: RoosterData = null
var participant_roosters: Array[RoosterData] = []
var matches: Array[Dictionary] = []
var current_match_id: String = ""
var tournament_completed: bool = false
var final_leaderboard: Array[Dictionary] = []
var is_online_tournament: bool = false
var online_participants: Array[Dictionary] = []

signal tournament_state_changed()
signal match_completed(match_id: String, winner: RoosterData)
signal tournament_finished(leaderboard: Array[Dictionary])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _get_all_roosters() -> Array[RoosterData]:
	var gm: Node = get_node_or_null("/root/GameManager") if is_inside_tree() else null
	if gm and gm.get("all_roosters") and not gm.all_roosters.is_empty():
		return gm.all_roosters
	var list: Array[RoosterData] = []
	var paths: Array[String] = [
		"res://resources/roosters/hen_goku.tres",
		"res://resources/roosters/cocktaro.tres",
		"res://resources/roosters/cluckey_d_puffy.tres",
		"res://resources/roosters/daniel.tres",
		"res://resources/roosters/decluck.tres",
		"res://resources/roosters/eren_pecker.tres",
		"res://resources/roosters/nechicko.tres",
		"res://resources/roosters/chick_yagami.tres"
	]
	for p in paths:
		if ResourceLoader.exists(p):
			var r = load(p)
			if r is RoosterData:
				list.append(r)
	return list

func _get_rooster_by_id(id: String) -> RoosterData:
	for r in _get_all_roosters():
		if r and r.rooster_id == id:
			return r
	var path := "res://resources/roosters/%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Starts a dynamic online tournament with arbitrary player count (2 to 16) and byes
func build_dynamic_online_tournament(players: Array[Dictionary], format: Format = Format.SINGLE_ELIMINATION) -> void:
	is_tournament_active = true
	is_online_tournament = true
	current_format = format
	tournament_completed = false
	final_leaderboard.clear()
	online_participants = players.duplicate()
	participant_roosters.clear()

	for p in players:
		var r: RoosterData = p.get("rooster", null)
		if not r and p.get("rooster_id", "") != "":
			r = _get_rooster_by_id(p["rooster_id"])
			p["rooster"] = r
		if r:
			participant_roosters.append(r)

	player_rooster = participant_roosters[0] if not participant_roosters.is_empty() else null
	var total_players: int = players.size()

	# Choose bracket tier
	var bracket_size: int = 4
	if total_players <= 4:
		bracket_size = 4
		current_bot_count = 3
	elif total_players <= 8:
		bracket_size = 8
		current_bot_count = 7
	else:
		bracket_size = 16
		current_bot_count = 15

	matches.clear()

	if bracket_size == 4:
		_build_dynamic_bracket_4(players)
	elif bracket_size == 8:
		_build_dynamic_bracket_8(players)
	else:
		_build_dynamic_bracket_16(players)

	# Auto-resolve all initial BYE matches so bye players are immediately promoted to Round 2!
	_resolve_initial_byes()

	_find_and_set_next_player_match()
	tournament_state_changed.emit()

func _build_dynamic_bracket_4(players: Array[Dictionary]) -> void:
	var p0 = players[0] if players.size() > 0 else {}
	var p1 = players[1] if players.size() > 1 else {}
	var p2 = players[2] if players.size() > 2 else {}
	var p3 = players[3] if players.size() > 3 else {}

	var sf1_slot1: Dictionary = p0
	var sf1_slot2: Dictionary = {}
	var sf2_slot1: Dictionary = {}
	var sf2_slot2: Dictionary = {}

	if players.size() == 4:
		sf1_slot2 = p1
		sf2_slot1 = p2
		sf2_slot2 = p3
	elif players.size() == 3:
		# P0 gets Bye in SF1 (advances to GF), P1 vs P2 battle in SF2!
		sf1_slot2 = {}
		sf2_slot1 = p1
		sf2_slot2 = p2
	elif players.size() == 2:
		# P0 gets Bye, P1 gets Bye (both advance to GF!)
		sf1_slot2 = {}
		sf2_slot1 = p1
		sf2_slot2 = {}

	matches.append({
		"id": "SF1", "name": "SEMIFINAL 1", "round": 1,
		"rooster_1": sf1_slot1.get("rooster", null),
		"rooster_2": sf1_slot2.get("rooster", null),
		"p1_name": sf1_slot1.get("name", "Player 1"),
		"p2_name": sf1_slot2.get("name", "BYE" if sf1_slot2.is_empty() else "Player 2"),
		"p1_peer_id": sf1_slot1.get("peer_id", 0),
		"p2_peer_id": sf1_slot2.get("peer_id", 0),
		"winner": null, "loser": null,
		"winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": sf1_slot2.is_empty(),
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-6.2, 0.0, 0.0),
		"target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "3RD", "loser_target_slot": 1
	})

	matches.append({
		"id": "SF2", "name": "SEMIFINAL 2", "round": 1,
		"rooster_1": sf2_slot1.get("rooster", null),
		"rooster_2": sf2_slot2.get("rooster", null),
		"p1_name": sf2_slot1.get("name", "Player 2"),
		"p2_name": sf2_slot2.get("name", "BYE" if sf2_slot2.is_empty() else "Player 3"),
		"p1_peer_id": sf2_slot1.get("peer_id", 0),
		"p2_peer_id": sf2_slot2.get("peer_id", 0),
		"winner": null, "loser": null,
		"winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": sf2_slot2.is_empty(),
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(6.2, 0.0, 0.0),
		"target_match_id": "GF", "target_slot": 2,
		"loser_target_match_id": "3RD", "loser_target_slot": 2
	})

	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 2,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -3.2), "target_match_id": "", "target_slot": 0
	})

	matches.append({
		"id": "3RD", "name": "3RD PLACE MATCH", "round": 2,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 3.8), "target_match_id": "", "target_slot": 0
	})

func _build_dynamic_bracket_8(players: Array[Dictionary]) -> void:
	var total_p: int = players.size()
	var num_byes: int = 8 - total_p
	# Match pairings for Round 1: QF1, QF2, QF3, QF4
	# Distribute byes across matches
	var qf_configs: Array[Dictionary] = [
		{"id": "QF1", "name": "QUARTERFINAL 1", "pos": Vector3(-9.2, 0.0, -4.5), "target": "SF1", "slot": 1},
		{"id": "QF2", "name": "QUARTERFINAL 2", "pos": Vector3(-9.2, 0.0, 4.5),  "target": "SF1", "slot": 2},
		{"id": "QF3", "name": "QUARTERFINAL 3", "pos": Vector3(9.2, 0.0, -4.5),  "target": "SF2", "slot": 1},
		{"id": "QF4", "name": "QUARTERFINAL 4", "pos": Vector3(9.2, 0.0, 4.5),   "target": "SF2", "slot": 2}
	]

	# Bye distribution: QF1 (1st bye), QF3 (2nd bye), QF2 (3rd bye)
	var bye_matches: Array[String] = []
	if num_byes >= 1: bye_matches.append("QF1")
	if num_byes >= 2: bye_matches.append("QF3")
	if num_byes >= 3: bye_matches.append("QF2")

	var player_idx: int = 0
	for cfg in qf_configs:
		var is_bye_match: bool = cfg["id"] in bye_matches
		var p_slot1: Dictionary = players[player_idx] if player_idx < total_p else {}
		player_idx += 1

		var p_slot2: Dictionary = {}
		if not is_bye_match and player_idx < total_p:
			p_slot2 = players[player_idx]
			player_idx += 1

		matches.append({
			"id": cfg["id"], "name": cfg["name"], "round": 1,
			"rooster_1": p_slot1.get("rooster", null),
			"rooster_2": p_slot2.get("rooster", null),
			"p1_name": p_slot1.get("name", "Player"),
			"p2_name": p_slot2.get("name", "BYE" if is_bye_match else "Player"),
			"p1_peer_id": p_slot1.get("peer_id", 0),
			"p2_peer_id": p_slot2.get("peer_id", 0),
			"winner": null, "loser": null,
			"winner_peer_id": -1, "loser_peer_id": -1,
			"is_bye": is_bye_match,
			"is_completed": false, "is_player_match": false,
			"pos": cfg["pos"],
			"target_match_id": cfg["target"], "target_slot": cfg["slot"]
		})

	# Round 2: Semifinals
	matches.append({
		"id": "SF1", "name": "SEMIFINAL A", "round": 2,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-4.5, 0.0, 0.0), "target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "3RD", "loser_target_slot": 1
	})
	matches.append({
		"id": "SF2", "name": "SEMIFINAL B", "round": 2,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(4.5, 0.0, 0.0), "target_match_id": "GF", "target_slot": 2,
		"loser_target_match_id": "3RD", "loser_target_slot": 2
	})

	# Round 3: Grand Finals & 3rd Place
	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 3,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -3.2), "target_match_id": "", "target_slot": 0
	})
	matches.append({
		"id": "3RD", "name": "3RD PLACE MATCH", "round": 3,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 3.8), "target_match_id": "", "target_slot": 0
	})

func _build_dynamic_bracket_16(players: Array[Dictionary]) -> void:
	var total_p: int = players.size()
	var num_byes: int = 16 - total_p
	var r16_configs: Array[Dictionary] = []
	for i in range(8):
		var target_qf: String = "QF%d" % (int(float(i) / 2.0) + 1)
		var target_slot: int = (i % 2) + 1
		var x_pos: float = -14.0 if i < 4 else 14.0
		var z_pos: float = -9.0 + (float(i % 4) * 6.0)
		r16_configs.append({
			"id": "R16_%d" % (i + 1), "name": "ROUND OF 16 - #%d" % (i + 1),
			"pos": Vector3(x_pos, 0.0, z_pos), "target": target_qf, "slot": target_slot
		})

	var player_idx: int = 0
	for i in range(8):
		var cfg = r16_configs[i]
		var is_bye_match: bool = i < num_byes
		var p_slot1: Dictionary = players[player_idx] if player_idx < total_p else {}
		player_idx += 1
		var p_slot2: Dictionary = {}
		if not is_bye_match and player_idx < total_p:
			p_slot2 = players[player_idx]
			player_idx += 1

		matches.append({
			"id": cfg["id"], "name": cfg["name"], "round": 1,
			"rooster_1": p_slot1.get("rooster", null),
			"rooster_2": p_slot2.get("rooster", null),
			"p1_name": p_slot1.get("name", "Player"),
			"p2_name": p_slot2.get("name", "BYE" if is_bye_match else "Player"),
			"p1_peer_id": p_slot1.get("peer_id", 0),
			"p2_peer_id": p_slot2.get("peer_id", 0),
			"winner": null, "loser": null,
			"winner_peer_id": -1, "loser_peer_id": -1,
			"is_bye": is_bye_match,
			"is_completed": false, "is_player_match": false,
			"pos": cfg["pos"],
			"target_match_id": cfg["target"], "target_slot": cfg["slot"]
		})

	# Round 2: Quarterfinals
	for q in range(4):
		var target_sf: String = "SF1" if q < 2 else "SF2"
		var target_slot: int = (q % 2) + 1
		var x_pos: float = -7.5 if q < 2 else 7.5
		var z_pos: float = -4.5 if (q % 2) == 0 else 4.5
		matches.append({
			"id": "QF%d" % (q + 1), "name": "QUARTERFINAL %d" % (q + 1), "round": 2,
			"rooster_1": null, "rooster_2": null,
			"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
			"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
			"is_bye": false, "is_completed": false, "is_player_match": false,
			"pos": Vector3(x_pos, 0.0, z_pos), "target_match_id": target_sf, "target_slot": target_slot
		})

	# Round 3: Semifinals
	matches.append({
		"id": "SF1", "name": "SEMIFINAL A", "round": 3,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-4.0, 0.0, 0.0), "target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "3RD", "loser_target_slot": 1
	})
	matches.append({
		"id": "SF2", "name": "SEMIFINAL B", "round": 3,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(4.0, 0.0, 0.0), "target_match_id": "GF", "target_slot": 2,
		"loser_target_match_id": "3RD", "loser_target_slot": 2
	})

	# Round 4: Finals
	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 4,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -3.2), "target_match_id": "", "target_slot": 0
	})
	matches.append({
		"id": "3RD", "name": "3RD PLACE MATCH", "round": 4,
		"rooster_1": null, "rooster_2": null,
		"p1_name": "", "p2_name": "", "p1_peer_id": 0, "p2_peer_id": 0,
		"winner": null, "loser": null, "winner_peer_id": -1, "loser_peer_id": -1,
		"is_bye": false, "is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 3.8), "target_match_id": "", "target_slot": 0
	})

func _resolve_initial_byes() -> void:
	for m in matches:
		if m.get("is_bye", false) and not m["is_completed"]:
			m["is_completed"] = true
			var winner: RoosterData = m["rooster_1"]
			m["winner"] = winner
			m["winner_peer_id"] = m.get("p1_peer_id", 0)
			if m.get("target_match_id", "") != "":
				var next_m: Dictionary = get_match(m["target_match_id"])
				if not next_m.is_empty():
					if m.get("target_slot", 1) == 1:
						next_m["rooster_1"] = winner
						next_m["p1_name"] = m.get("p1_name", "")
						next_m["p1_peer_id"] = m.get("p1_peer_id", 0)
					else:
						next_m["rooster_2"] = winner
						next_m["p2_name"] = m.get("p1_name", "")
						next_m["p2_peer_id"] = m.get("p1_peer_id", 0)

func serialize_bracket() -> Dictionary:
	var match_list: Array[Dictionary] = []
	for m in matches:
		var r1_id: String = m["rooster_1"].rooster_id if m["rooster_1"] else ""
		var r2_id: String = m["rooster_2"].rooster_id if m["rooster_2"] else ""
		var win_id: String = m["winner"].rooster_id if m["winner"] else ""
		var lose_id: String = m["loser"].rooster_id if m["loser"] else ""
		var pos_v: Vector3 = m.get("pos", Vector3.ZERO)
		match_list.append({
			"id": m.get("id", ""),
			"name": m.get("name", ""),
			"round": m.get("round", 1),
			"r1_id": r1_id,
			"r2_id": r2_id,
			"p1_name": m.get("p1_name", ""),
			"p2_name": m.get("p2_name", ""),
			"p1_peer_id": m.get("p1_peer_id", 0),
			"p2_peer_id": m.get("p2_peer_id", 0),
			"winner_id": win_id,
			"loser_id": lose_id,
			"winner_peer_id": m.get("winner_peer_id", -1),
			"loser_peer_id": m.get("loser_peer_id", -1),
			"is_bye": m.get("is_bye", false),
			"is_completed": m.get("is_completed", false),
			"is_player_match": m.get("is_player_match", false),
			"pos": [pos_v.x, pos_v.y, pos_v.z],
			"target_match_id": m.get("target_match_id", ""),
			"target_slot": m.get("target_slot", 1),
			"loser_target_match_id": m.get("loser_target_match_id", ""),
			"loser_target_slot": m.get("loser_target_slot", 1)
		})
	return {
		"matches": match_list,
		"current_match_id": current_match_id,
		"is_online_tournament": is_online_tournament,
		"current_bot_count": current_bot_count,
		"tournament_completed": tournament_completed
	}

func deserialize_bracket(data: Dictionary) -> void:
	is_tournament_active = true
	is_online_tournament = data.get("is_online_tournament", true)
	current_match_id = data.get("current_match_id", "")
	current_bot_count = data.get("current_bot_count", 7)
	tournament_completed = data.get("tournament_completed", false)
	matches.clear()

	var raw_matches: Array = data.get("matches", [])
	for rm in raw_matches:
		var r1: RoosterData = null
		var r2: RoosterData = null
		var win: RoosterData = null
		var lose: RoosterData = null
		if rm.get("r1_id", "") != "":
			r1 = _get_rooster_by_id(rm["r1_id"])
		if rm.get("r2_id", "") != "":
			r2 = _get_rooster_by_id(rm["r2_id"])
		if rm.get("winner_id", "") != "":
			win = _get_rooster_by_id(rm["winner_id"])
		if rm.get("loser_id", "") != "":
			lose = _get_rooster_by_id(rm["loser_id"])

		var pos_arr: Array = rm.get("pos", [0, 0, 0])
		var pos_v := Vector3(pos_arr[0], pos_arr[1], pos_arr[2]) if pos_arr.size() == 3 else Vector3.ZERO

		matches.append({
			"id": rm.get("id", ""),
			"name": rm.get("name", ""),
			"round": rm.get("round", 1),
			"rooster_1": r1,
			"rooster_2": r2,
			"p1_name": rm.get("p1_name", ""),
			"p2_name": rm.get("p2_name", ""),
			"p1_peer_id": rm.get("p1_peer_id", 0),
			"p2_peer_id": rm.get("p2_peer_id", 0),
			"winner": win,
			"loser": lose,
			"winner_peer_id": rm.get("winner_peer_id", -1),
			"loser_peer_id": rm.get("loser_peer_id", -1),
			"is_bye": rm.get("is_bye", false),
			"is_completed": rm.get("is_completed", false),
			"is_player_match": rm.get("is_player_match", false),
			"pos": pos_v,
			"target_match_id": rm.get("target_match_id", ""),
			"target_slot": rm.get("target_slot", 1),
			"loser_target_match_id": rm.get("loser_target_match_id", ""),
			"loser_target_slot": rm.get("loser_target_slot", 1)
		})
	tournament_state_changed.emit()

## Starts a brand new tournament with configurable bot count
func start_new_tournament(p_rooster: RoosterData, format: Format = Format.SINGLE_ELIMINATION, bot_count: int = 7) -> void:
	is_tournament_active = true
	current_format = format
	current_bot_count = bot_count
	tournament_completed = false
	final_leaderboard.clear()

	var all_r: Array[RoosterData] = _get_all_roosters()
	player_rooster = p_rooster if p_rooster else (all_r[0] if not all_r.is_empty() else null)
	
	var total_duelists: int = current_bot_count + 1
	participant_roosters.clear()
	if player_rooster:
		participant_roosters.append(player_rooster)
	
	var others: Array[RoosterData] = []
	for r in all_r:
		if r != player_rooster:
			others.append(r)
	others.shuffle()
	
	for o in others:
		participant_roosters.append(o)
		if participant_roosters.size() >= total_duelists:
			break
			
	# If repository has fewer roosters than requested, fill with unique cloned bot roosters
	var bot_suffix_counter: int = 2
	while participant_roosters.size() < total_duelists:
		var source_r: RoosterData = participant_roosters[randi() % participant_roosters.size()]
		var clone_r: RoosterData = source_r.duplicate(true)
		clone_r.display_name = "%s #%d" % [source_r.display_name, bot_suffix_counter]
		bot_suffix_counter += 1
		participant_roosters.append(clone_r)

	# Build appropriate bracket structure based on bot count and format
	if current_format == Format.SINGLE_ELIMINATION:
		if total_duelists <= 4:
			_build_single_elim_4()
		elif total_duelists <= 8:
			_build_single_elim_8()
		else:
			_build_single_elim_16()
	else:
		if total_duelists <= 4:
			_build_double_elim_4()
		else:
			_build_double_elim_8()

	_find_and_set_next_player_match()
	tournament_state_changed.emit()

## ---------------------------------------------------------------------------
## Single Elimination: 4 Duelists (3 Bots)
## ---------------------------------------------------------------------------
func _build_single_elim_4() -> void:
	matches.clear()

	matches.append({
		"id": "SF1",
		"name": "SEMIFINAL 1",
		"round": 1,
		"rooster_1": participant_roosters[0], # Player
		"rooster_2": participant_roosters[1],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": true,
		"pos": Vector3(-6.2, 0.0, 0.0),
		"target_match_id": "GF",
		"target_slot": 1,
		"loser_target_match_id": "3RD",
		"loser_target_slot": 1
	})
	matches.append({
		"id": "SF2",
		"name": "SEMIFINAL 2",
		"round": 1,
		"rooster_1": participant_roosters[2],
		"rooster_2": participant_roosters[3],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(6.2, 0.0, 0.0),
		"target_match_id": "GF",
		"target_slot": 2,
		"loser_target_match_id": "3RD",
		"loser_target_slot": 2
	})
	matches.append({
		"id": "GF",
		"name": "GRAND FINALS",
		"round": 2,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(0.0, 0.0, -3.2),
		"target_match_id": "",
		"target_slot": 0
	})
	matches.append({
		"id": "3RD",
		"name": "3RD PLACE MATCH",
		"round": 2,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(0.0, 0.0, 3.8),
		"target_match_id": "",
		"target_slot": 0
	})

## ---------------------------------------------------------------------------
## Single Elimination: 8 Duelists (7 Bots) - Inward Cliff Clearance
## ---------------------------------------------------------------------------
func _build_single_elim_8() -> void:
	matches.clear()

	# Quarterfinals (Round 1) - Brought inward to X = +/- 9.2
	matches.append({
		"id": "QF1",
		"name": "QUARTERFINAL 1",
		"round": 1,
		"rooster_1": participant_roosters[0], # Player
		"rooster_2": participant_roosters[1],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": true,
		"pos": Vector3(-9.2, 0.0, -4.5),
		"target_match_id": "SF1",
		"target_slot": 1
	})
	matches.append({
		"id": "QF2",
		"name": "QUARTERFINAL 2",
		"round": 1,
		"rooster_1": participant_roosters[2],
		"rooster_2": participant_roosters[3],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(-9.2, 0.0, 4.5),
		"target_match_id": "SF1",
		"target_slot": 2
	})
	matches.append({
		"id": "QF3",
		"name": "QUARTERFINAL 3",
		"round": 1,
		"rooster_1": participant_roosters[4],
		"rooster_2": participant_roosters[5],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(9.2, 0.0, -4.5),
		"target_match_id": "SF2",
		"target_slot": 1
	})
	matches.append({
		"id": "QF4",
		"name": "QUARTERFINAL 4",
		"round": 1,
		"rooster_1": participant_roosters[6],
		"rooster_2": participant_roosters[7],
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(9.2, 0.0, 4.5),
		"target_match_id": "SF2",
		"target_slot": 2
	})

	# Semifinals (Round 2)
	matches.append({
		"id": "SF1",
		"name": "SEMIFINAL A",
		"round": 2,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(-4.5, 0.0, 0.0),
		"target_match_id": "GF",
		"target_slot": 1,
		"loser_target_match_id": "3RD",
		"loser_target_slot": 1
	})
	matches.append({
		"id": "SF2",
		"name": "SEMIFINAL B",
		"round": 2,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(4.5, 0.0, 0.0),
		"target_match_id": "GF",
		"target_slot": 2,
		"loser_target_match_id": "3RD",
		"loser_target_slot": 2
	})

	# Finals (Round 3)
	matches.append({
		"id": "GF",
		"name": "GRAND FINALS",
		"round": 3,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(0.0, 0.0, -2.5),
		"target_match_id": "",
		"target_slot": 0
	})
	matches.append({
		"id": "3RD",
		"name": "3RD PLACE MATCH",
		"round": 3,
		"rooster_1": null,
		"rooster_2": null,
		"winner": null,
		"loser": null,
		"is_completed": false,
		"is_player_match": false,
		"pos": Vector3(0.0, 0.0, 4.8),
		"target_match_id": "",
		"target_slot": 0
	})

## ---------------------------------------------------------------------------
## Single Elimination: 16 Duelists (15 Bots)
## ---------------------------------------------------------------------------
func _build_single_elim_16() -> void:
	matches.clear()

	# Round of 16 (8 Matches) - Left Wing
	matches.append({
		"id": "R16_1", "name": "R16 - 1", "round": 1,
		"rooster_1": participant_roosters[0], "rooster_2": participant_roosters[1],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": true,
		"pos": Vector3(-10.2, 0.0, -6.0), "target_match_id": "QF1", "target_slot": 1
	})
	matches.append({
		"id": "R16_2", "name": "R16 - 2", "round": 1,
		"rooster_1": participant_roosters[2], "rooster_2": participant_roosters[3],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-10.2, 0.0, -3.8), "target_match_id": "QF1", "target_slot": 2
	})
	matches.append({
		"id": "R16_3", "name": "R16 - 3", "round": 1,
		"rooster_1": participant_roosters[4], "rooster_2": participant_roosters[5],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-10.2, 0.0, 3.8), "target_match_id": "QF2", "target_slot": 1
	})
	matches.append({
		"id": "R16_4", "name": "R16 - 4", "round": 1,
		"rooster_1": participant_roosters[6], "rooster_2": participant_roosters[7],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-10.2, 0.0, 6.0), "target_match_id": "QF2", "target_slot": 2
	})

	# Round of 16 - Right Wing
	matches.append({
		"id": "R16_5", "name": "R16 - 5", "round": 1,
		"rooster_1": participant_roosters[8], "rooster_2": participant_roosters[9],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(10.2, 0.0, -6.0), "target_match_id": "QF3", "target_slot": 1
	})
	matches.append({
		"id": "R16_6", "name": "R16 - 6", "round": 1,
		"rooster_1": participant_roosters[10], "rooster_2": participant_roosters[11],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(10.2, 0.0, -3.8), "target_match_id": "QF3", "target_slot": 2
	})
	matches.append({
		"id": "R16_7", "name": "R16 - 7", "round": 1,
		"rooster_1": participant_roosters[12], "rooster_2": participant_roosters[13],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(10.2, 0.0, 3.8), "target_match_id": "QF4", "target_slot": 1
	})
	matches.append({
		"id": "R16_8", "name": "R16 - 8", "round": 1,
		"rooster_1": participant_roosters[14], "rooster_2": participant_roosters[15],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(10.2, 0.0, 6.0), "target_match_id": "QF4", "target_slot": 2
	})

	# Quarterfinals (4 Matches)
	matches.append({
		"id": "QF1", "name": "QUARTERFINAL 1", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-6.2, 0.0, -4.8), "target_match_id": "SF1", "target_slot": 1
	})
	matches.append({
		"id": "QF2", "name": "QUARTERFINAL 2", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-6.2, 0.0, 4.8), "target_match_id": "SF1", "target_slot": 2
	})
	matches.append({
		"id": "QF3", "name": "QUARTERFINAL 3", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(6.2, 0.0, -4.8), "target_match_id": "SF2", "target_slot": 1
	})
	matches.append({
		"id": "QF4", "name": "QUARTERFINAL 4", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(6.2, 0.0, 4.8), "target_match_id": "SF2", "target_slot": 2
	})

	# Semifinals
	matches.append({
		"id": "SF1", "name": "SEMIFINAL A", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-3.2, 0.0, 0.0), "target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "3RD", "loser_target_slot": 1
	})
	matches.append({
		"id": "SF2", "name": "SEMIFINAL B", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(3.2, 0.0, 0.0), "target_match_id": "GF", "target_slot": 2,
		"loser_target_match_id": "3RD", "loser_target_slot": 2
	})

	# Finals
	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 4,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -2.5), "target_match_id": "", "target_slot": 0
	})
	matches.append({
		"id": "3RD", "name": "3RD PLACE MATCH", "round": 4,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 4.5), "target_match_id": "", "target_slot": 0
	})

## ---------------------------------------------------------------------------
## Double Elimination: 4 Duelists
## ---------------------------------------------------------------------------
func _build_double_elim_4() -> void:
	matches.clear()

	matches.append({
		"id": "WB_SF1", "name": "WINNERS SEMI 1", "round": 1,
		"rooster_1": participant_roosters[0], "rooster_2": participant_roosters[1],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": true,
		"pos": Vector3(-6.5, 0.0, -3.5), "target_match_id": "WB_F", "target_slot": 1,
		"loser_target_match_id": "LB_R1", "loser_target_slot": 1
	})
	matches.append({
		"id": "WB_SF2", "name": "WINNERS SEMI 2", "round": 1,
		"rooster_1": participant_roosters[2], "rooster_2": participant_roosters[3],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(6.5, 0.0, -3.5), "target_match_id": "WB_F", "target_slot": 2,
		"loser_target_match_id": "LB_R1", "loser_target_slot": 2
	})
	matches.append({
		"id": "WB_F", "name": "WINNERS FINALS", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -4.8), "target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "LB_F", "loser_target_slot": 2
	})
	matches.append({
		"id": "LB_R1", "name": "LOSERS ROUND 1", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 2.2), "target_match_id": "LB_F", "target_slot": 1
	})
	matches.append({
		"id": "LB_F", "name": "LOSERS FINALS", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 4.8), "target_match_id": "GF", "target_slot": 2
	})
	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 4,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 0.0), "target_match_id": "", "target_slot": 0
	})

## ---------------------------------------------------------------------------
## Double Elimination: 8 Duelists
## ---------------------------------------------------------------------------
func _build_double_elim_8() -> void:
	matches.clear()

	# Winners Bracket Round 1 (Inward X = +/- 9.2)
	matches.append({
		"id": "WB_M1", "name": "WINNERS R1 - A", "round": 1,
		"rooster_1": participant_roosters[0], "rooster_2": participant_roosters[1],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": true,
		"pos": Vector3(-9.2, 0.0, -5.5), "target_match_id": "WB_SF1", "target_slot": 1,
		"loser_target_match_id": "LB_R1_1", "loser_target_slot": 1
	})
	matches.append({
		"id": "WB_M2", "name": "WINNERS R1 - B", "round": 1,
		"rooster_1": participant_roosters[2], "rooster_2": participant_roosters[3],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(-9.2, 0.0, -2.0), "target_match_id": "WB_SF1", "target_slot": 2,
		"loser_target_match_id": "LB_R1_1", "loser_target_slot": 2
	})
	matches.append({
		"id": "WB_M3", "name": "WINNERS R1 - C", "round": 1,
		"rooster_1": participant_roosters[4], "rooster_2": participant_roosters[5],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(9.2, 0.0, -5.5), "target_match_id": "WB_SF2", "target_slot": 1,
		"loser_target_match_id": "LB_R1_2", "loser_target_slot": 1
	})
	matches.append({
		"id": "WB_M4", "name": "WINNERS R1 - D", "round": 1,
		"rooster_1": participant_roosters[6], "rooster_2": participant_roosters[7],
		"winner": null, "loser": null, "is_completed": false, "is_player_match": false,
		"pos": Vector3(9.2, 0.0, -2.0), "target_match_id": "WB_SF2", "target_slot": 2,
		"loser_target_match_id": "LB_R1_2", "loser_target_slot": 2
	})

	# Winners Semifinals
	matches.append({
		"id": "WB_SF1", "name": "WINNERS SEMI 1", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-4.5, 0.0, -3.8), "target_match_id": "WB_F", "target_slot": 1,
		"loser_target_match_id": "LB_R2_2", "loser_target_slot": 2
	})
	matches.append({
		"id": "WB_SF2", "name": "WINNERS SEMI 2", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(4.5, 0.0, -3.8), "target_match_id": "WB_F", "target_slot": 2,
		"loser_target_match_id": "LB_R2_1", "loser_target_slot": 2
	})

	# Winners Finals
	matches.append({
		"id": "WB_F", "name": "WINNERS FINALS", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, -4.8), "target_match_id": "GF", "target_slot": 1,
		"loser_target_match_id": "LB_F", "loser_target_slot": 2
	})

	# Losers Bracket Round 1
	matches.append({
		"id": "LB_R1_1", "name": "LOSERS R1 - A", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-7.5, 0.0, 2.5), "target_match_id": "LB_R2_1", "target_slot": 1
	})
	matches.append({
		"id": "LB_R1_2", "name": "LOSERS R1 - B", "round": 2,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(7.5, 0.0, 2.5), "target_match_id": "LB_R2_2", "target_slot": 1
	})

	# Losers Bracket Round 2
	matches.append({
		"id": "LB_R2_1", "name": "LOSERS R2 - A", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(-3.5, 0.0, 3.8), "target_match_id": "LB_F", "target_slot": 1
	})
	matches.append({
		"id": "LB_R2_2", "name": "LOSERS R2 - B", "round": 3,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(3.5, 0.0, 3.8), "target_match_id": "LB_F", "target_slot": 2
	})

	# Losers Finals
	matches.append({
		"id": "LB_F", "name": "LOSERS FINALS", "round": 4,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 5.2), "target_match_id": "GF", "target_slot": 2
	})

	# Grand Finals
	matches.append({
		"id": "GF", "name": "GRAND FINALS", "round": 5,
		"rooster_1": null, "rooster_2": null, "winner": null, "loser": null,
		"is_completed": false, "is_player_match": false,
		"pos": Vector3(0.0, 0.0, 0.0), "target_match_id": "", "target_slot": 0
	})

## ---------------------------------------------------------------------------
## Querying & Progression Helpers
## ---------------------------------------------------------------------------

func get_match(match_id: String) -> Dictionary:
	for m in matches:
		if m["id"] == match_id:
			return m
	return {}

func get_current_match() -> Dictionary:
	return get_match(current_match_id)

func _find_and_set_next_player_match() -> void:
	current_match_id = ""
	if is_online_tournament:
		# In online tournaments, active match is the lowest round match with both contestants ready
		for r_num in [1, 2, 3, 4]:
			for m in matches:
				if m.get("round", 1) == r_num and not m["is_completed"]:
					if m["rooster_1"] != null and m["rooster_2"] != null:
						current_match_id = m["id"]
						return
		for m in matches:
			if not m["is_completed"]:
				current_match_id = m["id"]
				return
		return

	# Find lowest round uncompleted match where player is a contestant
	for m in matches:
		if not m["is_completed"]:
			if m["rooster_1"] == player_rooster or m["rooster_2"] == player_rooster:
				m["is_player_match"] = true
				current_match_id = m["id"]
				return

	# If player was eliminated or has no match, pick next pending match to simulate or spectate
	for m in matches:
		if not m["is_completed"] and m["rooster_1"] != null and m["rooster_2"] != null:
			current_match_id = m["id"]
			return

## Records result for the active match (or specific match_id if supplied)
func record_match_result(winner: RoosterData, match_id: String = "") -> void:
	var target_id := match_id if match_id != "" else current_match_id
	if target_id == "":
		return
	var m: Dictionary = get_match(target_id)
	if m.is_empty():
		return

	var is_p1_winner: bool = false
	if m.get("rooster_1") != null and winner != null:
		if winner == m["rooster_1"] or winner.rooster_id == m["rooster_1"].rooster_id:
			is_p1_winner = true

	var loser: RoosterData = m["rooster_2"] if is_p1_winner else m["rooster_1"]
	var win_peer: int = m.get("p1_peer_id", 0) if is_p1_winner else m.get("p2_peer_id", 0)
	var lose_peer: int = m.get("p2_peer_id", 0) if is_p1_winner else m.get("p1_peer_id", 0)
	var win_name: String = m.get("p1_name", "") if is_p1_winner else m.get("p2_name", "")
	var lose_name: String = m.get("p2_name", "") if is_p1_winner else m.get("p1_name", "")

	m["winner"] = winner
	m["loser"] = loser
	m["winner_peer_id"] = win_peer
	m["loser_peer_id"] = lose_peer
	m["is_completed"] = true

	# Propagate winner forward
	if m.get("target_match_id", "") != "":
		var next_m: Dictionary = get_match(m["target_match_id"])
		if not next_m.is_empty():
			if m.get("target_slot", 1) == 1:
				next_m["rooster_1"] = winner
				next_m["p1_name"] = win_name
				next_m["p1_peer_id"] = win_peer
			else:
				next_m["rooster_2"] = winner
				next_m["p2_name"] = win_name
				next_m["p2_peer_id"] = win_peer

	# Propagate loser
	if m.get("loser_target_match_id", "") != "":
		var loser_m: Dictionary = get_match(m["loser_target_match_id"])
		if not loser_m.is_empty():
			if m.get("loser_target_slot", 1) == 1:
				loser_m["rooster_1"] = loser
				loser_m["p1_name"] = lose_name
				loser_m["p1_peer_id"] = lose_peer
			else:
				loser_m["rooster_2"] = loser
				loser_m["p2_name"] = lose_name
				loser_m["p2_peer_id"] = lose_peer

	match_completed.emit(m["id"], winner)

	# Simulate any pending CPU vs CPU matches only if not in online tournament
	if not is_online_tournament:
		simulate_pending_ai_matches()

	# Check if entire tournament is finished
	_check_tournament_completion()

	_find_and_set_next_player_match()
	tournament_state_changed.emit()

## Simulates AI vs AI matches that have both contestants ready
func simulate_pending_ai_matches() -> void:
	var simulated_any: bool = true
	var safety_counter: int = 0
	
	while simulated_any and safety_counter < 16:
		simulated_any = false
		safety_counter += 1

		for m in matches:
			if not m["is_completed"] and m["rooster_1"] != null and m["rooster_2"] != null:
				if m["rooster_1"] == player_rooster or m["rooster_2"] == player_rooster:
					continue

				var r1: RoosterData = m["rooster_1"]
				var r2: RoosterData = m["rooster_2"]
				var r1_hp: int = r1.base_hp if r1 else 20
				var r2_hp: int = r2.base_hp if r2 else 20
				
				var r1_chance: float = float(r1_hp) / float(r1_hp + r2_hp)
				var sim_winner: RoosterData = r1 if randf() < r1_chance else r2
				var sim_loser: RoosterData = r2 if sim_winner == r1 else r1

				m["winner"] = sim_winner
				m["loser"] = sim_loser
				m["is_completed"] = true

				if m.get("target_match_id", "") != "":
					var next_m: Dictionary = get_match(m["target_match_id"])
					if not next_m.is_empty():
						if m.get("target_slot", 1) == 1:
							next_m["rooster_1"] = sim_winner
						else:
							next_m["rooster_2"] = sim_winner

				if m.get("loser_target_match_id", "") != "":
					var loser_m: Dictionary = get_match(m["loser_target_match_id"])
					if not loser_m.is_empty():
						if m.get("loser_target_slot", 1) == 1:
							loser_m["rooster_1"] = sim_loser
						else:
							loser_m["rooster_2"] = sim_loser

				simulated_any = true
				match_completed.emit(m["id"], sim_winner)
				break

func _check_tournament_completion() -> void:
	var gf: Dictionary = get_match("GF")
	if not gf.is_empty() and gf["is_completed"]:
		tournament_completed = true
		_generate_leaderboard()
		tournament_finished.emit(final_leaderboard)

## Generates full 1st through Nth placements
func _generate_leaderboard() -> void:
	final_leaderboard.clear()
	var gf: Dictionary = get_match("GF")
	if gf.is_empty() or not gf["is_completed"]:
		return

	var champion: RoosterData = gf["winner"]
	var runner_up: RoosterData = gf["loser"]
	
	var third_place: RoosterData = null
	var fourth_place: RoosterData = null

	var third_m: Dictionary = get_match("3RD")
	if not third_m.is_empty() and third_m["is_completed"]:
		third_place = third_m["winner"]
		fourth_place = third_m["loser"]
	else:
		var lb_f: Dictionary = get_match("LB_F")
		if not lb_f.is_empty():
			third_place = lb_f["loser"]
		var lb_r1: Dictionary = get_match("LB_R1")
		if not lb_r1.is_empty():
			fourth_place = lb_r1["loser"]

	# 1st Place
	final_leaderboard.append({
		"rank": 1, "title": "CHAMPION", "rooster": champion,
		"badge": "CIRCUIT GRANDMASTER", "color": Color.GOLD
	})
	# 2nd Place
	final_leaderboard.append({
		"rank": 2, "title": "RUNNER-UP", "rooster": runner_up,
		"badge": "MASTER DUELIST", "color": Color(0.85, 0.88, 0.95)
	})
	# 3rd Place
	if third_place:
		final_leaderboard.append({
			"rank": 3, "title": "3RD PLACE", "rooster": third_place,
			"badge": "DIAMOND BRACKET", "color": Color(0.85, 0.55, 0.25)
		})
	# 4th Place
	if fourth_place:
		final_leaderboard.append({
			"rank": 4, "title": "4TH PLACE", "rooster": fourth_place,
			"badge": "PLATINUM BRACKET", "color": Color(0.65, 0.75, 0.85)
		})

	# Remaining places: gather losers from completed matches from later rounds down to earlier rounds
	var accounted: Array[RoosterData] = [champion, runner_up]
	if third_place: accounted.append(third_place)
	if fourth_place: accounted.append(fourth_place)

	var sorted_matches: Array[Dictionary] = matches.duplicate()
	sorted_matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("round", 0) > b.get("round", 0)
	)

	for m in sorted_matches:
		var loser: RoosterData = m.get("loser", null)
		if loser and not loser in accounted:
			var curr_rank: int = final_leaderboard.size() + 1
			final_leaderboard.append({
				"rank": curr_rank,
				"title": "%dTH PLACE" % curr_rank,
				"rooster": loser,
				"badge": "CHALLENGER",
				"color": Color(0.5, 0.55, 0.65)
			})
			accounted.append(loser)

	# Fallback if any participant wasn't reached
	for r in participant_roosters:
		if not r in accounted:
			var curr_rank: int = final_leaderboard.size() + 1
			final_leaderboard.append({
				"rank": curr_rank,
				"title": "%dTH PLACE" % curr_rank,
				"rooster": r,
				"badge": "CHALLENGER",
				"color": Color(0.5, 0.55, 0.65)
			})
			accounted.append(r)
