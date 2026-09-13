extends Node

## NetworkManager — Authoritative Godot 4 High-Level Multiplayer Manager for Sabong Roosters.
## Implements the server-authoritative model from Database System Blueprint §11:
##   - Host peer = authoritative game server: rolls dice, runs CombatEngine, broadcasts results.
##   - Client peer = presentation layer: sends card IDs only, receives resolved events.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal match_ready(p1_rooster_id: String, p2_rooster_id: String)
signal turn_received_from_host(events: Array[Dictionary])
signal dice_rolls_received(meron_roll: int, wala_roll: int)
signal opponent_disconnected_forfeit
## LAN discovery signals
signal host_discovered(ip: String, host_name: String)
signal hosts_cleared
## Online relay signals
signal room_code_received(code: String)   ## Host gets their 4-char room code
signal online_rooms_updated(rooms: Array) ## Client gets fresh room list
signal online_connection_failed(reason: String)

## Tournament Signals
signal tournament_roster_updated(roster: Dictionary)
signal tournament_bracket_received(bracket_data: Dictionary)
signal tournament_match_started(match_id: String, p1_peer: int, p2_peer: int)

enum MatchMode { DUEL_1V1, TOURNAMENT }
var current_match_mode: MatchMode = MatchMode.DUEL_1V1
var tournament_roster: Dictionary = {} # peer_id -> { "name": String, "rooster_id": String, "ready": bool }
var active_tournament_match_id: String = ""
var active_p1_peer: int = 0
var active_p2_peer: int = 0
var max_tournament_players: int = 8

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 1
## Blueprint §12 Risk: 30-second reconnect window before forfeit
const FORFEIT_TIMEOUT_SEC := 30.0

## UDP Discovery constants
const DISCOVERY_PORT := 7778
const DISCOVERY_BROADCAST_INTERVAL := 1.0  ## seconds between host beacon pulses
const DISCOVERY_MAGIC := "SABONG_HOST_BEACON_V1"

## Online relay server URL (update after Render.com deploy)
const RELAY_URL := "wss://sabong-inxt.onrender.com"
const RELAY_URL_LOCAL := "ws://127.0.0.1:10005"
var use_local_relay: bool = false

var peer: ENetMultiplayerPeer
var is_host: bool = false
var local_peer_id: int = 1
var opponent_peer_id: int = -1

# Lobby & Player Selection State
var p1_rooster_id: String = ""
var p2_rooster_id: String = ""
var p1_submitted_cards: Array[String] = []
var p2_submitted_cards: Array[String] = []
var p1_has_locked_turn: bool = false
var p2_has_locked_turn: bool = false

# Online session data (aligns with Blueprint matches table fields)
var online_match_data: Dictionary = {
	"match_id": "",          # Future: DB-assigned match_id
	"game_mode": "TOURNAMENT_ONLINE",
	"taya_wager": 0,
	"p1_player_id_db": 0,   # Future: DB player_id
	"p2_player_id_db": 0,
	"status": "PENDING"
}

# Stored Duelist references — set by DuelPhaseManager when online match starts
# Host uses these to run CombatEngine authoritatively
var _p1_duelist: Duelist = null
var _p2_duelist: Duelist = null

# Disconnect forfeit timer
var _forfeit_timer: SceneTreeTimer = null
var _disconnected_peer: int = -1

# ---------------------------------------------------------------------------
# LAN Discovery State
# ---------------------------------------------------------------------------
var _udp_broadcast: PacketPeerUDP = null   ## Host: sends beacons
var _udp_listener: PacketPeerUDP = null    ## Client: receives beacons
var _broadcast_timer: float = 0.0
var _is_scanning: bool = false
var _discovered_hosts: Dictionary = {}     ## ip -> host_name

# ---------------------------------------------------------------------------
# Online Relay State
# ---------------------------------------------------------------------------
var _relay_ws: WebSocketPeer = null        ## WebSocket connection to relay server
var _relay_role: String = ""               ## "host" or "client"
var _relay_room_code: String = ""
var _relay_room_fetch_timer: float = 0.0
var _is_fetching_rooms: bool = false
var _upnp: UPNP = null
var _upnp_thread: Thread = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	# Host: periodically broadcast LAN presence beacon
	if is_host and _udp_broadcast != null:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = DISCOVERY_BROADCAST_INTERVAL
			_send_discovery_beacon()
	# Client LAN scanning: poll for incoming beacon packets
	if _is_scanning and _udp_listener != null:
		_poll_discovery_listener()
	# Online relay: poll the control WebSocket
	if _relay_ws != null:
		_relay_ws.poll()
		_poll_relay_control_messages()
	# Online room list refresh (client side, every 4s)
	if _is_fetching_rooms:
		_relay_room_fetch_timer -= delta
		if _relay_room_fetch_timer <= 0.0:
			_relay_room_fetch_timer = 4.0
			_fetch_online_rooms()

## Starts hosting a match on specified port.
## Also starts UDP discovery beacon so clients can find this host automatically.
func host_match(port: int = DEFAULT_PORT, mode: MatchMode = MatchMode.DUEL_1V1, max_players: int = 2) -> Error:
	current_match_mode = mode
	if OS.has_feature("web"):
		push_warning("[NetworkManager] Direct UDP LAN hosting is not supported in Web browsers. Please use Online Relay rooms.")
		return ERR_UNAVAILABLE
	peer = ENetMultiplayerPeer.new()
	var max_clients: int = 1
	if mode == MatchMode.TOURNAMENT:
		max_clients = max(1, max_players - 1)
		tournament_roster.clear()
		var host_name := OS.get_model_name() if OS.get_model_name() != "" else "Host"
		tournament_roster[1] = {
			"name": host_name,
			"rooster_id": p1_rooster_id,
			"ready": p1_rooster_id != ""
		}
	var error := peer.create_server(port, max_clients)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	is_host = true
	local_peer_id = 1
	online_match_data["status"] = "PENDING"
	_start_discovery_beacon()
	_start_upnp_async()
	return OK

## Joins an existing host
func join_match(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	stop_lan_scan()
	if OS.has_feature("web"):
		push_warning("[NetworkManager] Direct UDP LAN join is not supported in Web browsers. Please use Online Relay rooms.")
		return ERR_UNAVAILABLE
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	is_host = false
	# local_peer_id will be confirmed once connection is established
	return OK

# ---------------------------------------------------------------------------
# LAN Discovery — Host Side
# ---------------------------------------------------------------------------

## Starts sending UDP broadcast beacons so clients on the LAN can find this host.
func _start_discovery_beacon() -> void:
	if OS.has_feature("web"): return
	_stop_discovery_beacon()
	_udp_broadcast = PacketPeerUDP.new()
	_udp_broadcast.set_broadcast_enabled(true)
	_broadcast_timer = 0.0  # fire immediately on next _process

func _stop_discovery_beacon() -> void:
	if _udp_broadcast != null:
		_udp_broadcast.close()
		_udp_broadcast = null

func _get_subnet_broadcast_addresses() -> Array[String]:
	var result: Array[String] = ["255.255.255.255"]
	for ip in IP.get_local_addresses():
		if ":" in ip or ip.begins_with("127."):
			continue
		var parts := ip.split(".")
		if parts.size() == 4:
			var bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if bcast not in result:
				result.append(bcast)
	return result

func _send_discovery_beacon() -> void:
	if _udp_broadcast == null:
		return
	var host_name := OS.get_model_name() if OS.get_model_name() != "" else "Host"
	var payload := "%s|%s" % [DISCOVERY_MAGIC, host_name]
	var packet := payload.to_utf8_buffer()
	# Broadcast on the local subnets
	for bcast in _get_subnet_broadcast_addresses():
		_udp_broadcast.set_dest_address(bcast, DISCOVERY_PORT)
		_udp_broadcast.put_packet(packet)

# ---------------------------------------------------------------------------
# LAN Discovery — Client Side
# ---------------------------------------------------------------------------

## Starts listening for host beacons on the LAN.
## Emits host_discovered(ip, host_name) for each unique host found.
func start_lan_scan() -> void:
	if OS.has_feature("web"): return
	stop_lan_scan()
	_discovered_hosts.clear()
	hosts_cleared.emit()
	_udp_listener = PacketPeerUDP.new()
	_udp_listener.set_broadcast_enabled(true)
	var bind_err := _udp_listener.bind(DISCOVERY_PORT, "0.0.0.0")
	if bind_err != OK:
		push_warning("NetworkManager: Could not bind UDP discovery port %d (err %d). Is another instance running?" % [DISCOVERY_PORT, bind_err])
		_udp_listener = null
		return
	_is_scanning = true

func stop_lan_scan() -> void:
	_is_scanning = false
	if _udp_listener != null:
		_udp_listener.close()
		_udp_listener = null

func _poll_discovery_listener() -> void:
	if _udp_listener == null:
		return
	while _udp_listener.get_available_packet_count() > 0:
		var packet := _udp_listener.get_packet()
		var sender_ip := _udp_listener.get_packet_ip()
		var text := packet.get_string_from_utf8()
		if text.begins_with(DISCOVERY_MAGIC + "|"):
			var parts := text.split("|")
			var h_name := parts[1] if parts.size() > 1 else sender_ip
			if sender_ip not in _discovered_hosts:
				_discovered_hosts[sender_ip] = h_name
				host_discovered.emit(sender_ip, h_name)

func get_discovered_hosts() -> Dictionary:
	return _discovered_hosts

# ---------------------------------------------------------------------------
# Online Relay -- Public API
# ---------------------------------------------------------------------------

func _get_relay_base_url() -> String:
	return RELAY_URL_LOCAL if use_local_relay else RELAY_URL

## Host online: start ENet server first, then register with relay for discovery.
func host_online(mode: MatchMode = MatchMode.DUEL_1V1, max_players: int = 8) -> void:
	_close_relay_ws()
	_relay_role = "host"
	current_match_mode = mode
	max_tournament_players = max_players
	# Start the ENet game server (same as LAN host)
	var err := host_match(DEFAULT_PORT, mode, max_players)
	if err != OK:
		online_connection_failed.emit("Could not start server on port %d." % DEFAULT_PORT)
		return
	# Now connect control WebSocket to relay to announce the room
	_relay_ws = WebSocketPeer.new()
	var url := _get_relay_base_url() + "/ws/new/host"
	var conn_err := _relay_ws.connect_to_url(url)
	if conn_err != OK:
		online_connection_failed.emit("Could not connect to relay server.")
		_relay_ws = null
		return
	# Relay will record our public IP and send back a room code

func host_online_match(mode: MatchMode = MatchMode.DUEL_1V1, max_players: int = 8) -> void:
	host_online(mode, max_players)

## Client: join an online room by 4-char code.
func join_online(room_code: String) -> void:
	_close_relay_ws()
	stop_online_room_fetch()
	_relay_role = "client"
	_relay_room_code = room_code.strip_edges().to_upper()
	_relay_ws = WebSocketPeer.new()
	var url := _get_relay_base_url() + "/ws/" + _relay_room_code + "/join"
	var err := _relay_ws.connect_to_url(url)
	if err != OK:
		online_connection_failed.emit("Could not connect to relay server.")
		_relay_ws = null
		return

func join_online_match(room_code: String) -> void:
	join_online(room_code)

## Start periodically fetching the online room list from the relay REST endpoint.
func start_online_room_fetch() -> void:
	_is_fetching_rooms = true
	_relay_room_fetch_timer = 0.0  ## fetch immediately on next process tick

func stop_online_room_fetch() -> void:
	_is_fetching_rooms = false

func _fetch_online_rooms() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var arr = json.get_data()
			if arr is Array:
				online_rooms_updated.emit(arr)
	)
	var url := _get_relay_base_url().replace("ws://", "http://").replace("wss://", "https://") + "/rooms"
	http.request(url)

# ---------------------------------------------------------------------------
# Online Relay -- Internal WebSocket polling
# ---------------------------------------------------------------------------

func _poll_relay_control_messages() -> void:
	if _relay_ws == null:
		return
	var state := _relay_ws.get_ready_state()

	# Waiting for connection
	if state == WebSocketPeer.STATE_CONNECTING:
		return

	# Connection opened -- send handshake depending on role
	if state == WebSocketPeer.STATE_OPEN:
		# Host: send our name and local IP once relay connects
		if _relay_role == "host" and _relay_room_code == "":
			var host_name := OS.get_model_name() if OS.get_model_name() != "" else "Sabong Host"
			var local_ip := _get_local_ipv4()
			var payload := {
				"host_name": host_name,
				"local_ip": local_ip,
				"port": DEFAULT_PORT,
				"mode": "tournament" if current_match_mode == MatchMode.TOURNAMENT else "duel",
				"max_players": max_tournament_players if current_match_mode == MatchMode.TOURNAMENT else 2
			}
			_relay_ws.send_text(JSON.stringify(payload))
			_relay_room_code = "PENDING"  ## Prevent re-sending

		# Read any control messages
		while _relay_ws.get_available_packet_count() > 0:
			var packet := _relay_ws.get_packet()
			var text := packet.get_string_from_utf8()
			var json := JSON.new()
			if json.parse(text) != OK:
				continue
			var data: Dictionary = json.get_data()
			_handle_relay_control(data)
		return

	# Connection closed -- only report error if we haven't started a game yet
	if state == WebSocketPeer.STATE_CLOSED:
		if _relay_role != "" and not is_host:
			online_connection_failed.emit("Relay connection closed.")
		_close_relay_ws()


func _handle_relay_control(data: Dictionary) -> void:
	var msg_type: String = data.get("type", "")
	match msg_type:
		"room_created":
			_relay_room_code = data.get("code", "")
			room_code_received.emit(_relay_room_code)
			# ENet server already running -- just wait for client
		"client_joined":
			# Relay confirms a client joined; ENet peer_connected will fire when they arrive
			pass
		"host_ready":
			# Client received host's public IP from relay -- connect via ENet
			var ip: String = data.get("host_ip", "")
			var port: int = data.get("host_port", DEFAULT_PORT)
			var mode_str: String = data.get("mode", "duel")
			current_match_mode = MatchMode.TOURNAMENT if mode_str == "tournament" else MatchMode.DUEL_1V1
			if ip.is_empty():
				online_connection_failed.emit("Relay did not provide host address.")
				return
			var err := join_match(ip, port)
			if err != OK:
				online_connection_failed.emit("Could not reach host at %s:%d.\nHost may need to forward port %d." % [ip, port, port])
		"host_left", "client_left":
			_on_server_disconnected()
		"error":
			online_connection_failed.emit(data.get("msg", "Unknown relay error"))
			_close_relay_ws()


func _close_relay_ws() -> void:
	if _relay_ws != null:
		_relay_ws.close()
		_relay_ws = null
	_relay_role = ""
	_relay_room_code = ""

## Called by DuelPhaseManager when online duel starts — gives host access to Duelist objects
func register_duelists(p1: Duelist, p2: Duelist) -> void:
	_p1_duelist = p1
	_p2_duelist = p2

# ---------------------------------------------------------------------------
# Rooster Selection Sync
# ---------------------------------------------------------------------------

## Syncs chosen rooster to other player (Blueprint §9: "Initialize match session")
func submit_rooster_choice(rooster_id: String) -> void:
	if is_host:
		p1_rooster_id = rooster_id
		rpc("rpc_sync_rooster", 1, rooster_id)
		_check_both_roosters_ready()
	else:
		rpc_id(1, "rpc_submit_client_rooster", rooster_id)

@rpc("any_peer", "reliable")
func rpc_submit_client_rooster(rooster_id: String) -> void:
	if not is_host: return
	p2_rooster_id = rooster_id
	rpc("rpc_sync_rooster", 2, rooster_id)
	_check_both_roosters_ready()

@rpc("authority", "reliable")
func rpc_sync_rooster(player_num: int, rooster_id: String) -> void:
	if player_num == 1: p1_rooster_id = rooster_id
	elif player_num == 2: p2_rooster_id = rooster_id

func _check_both_roosters_ready() -> void:
	if not is_host: return
	if p1_rooster_id != "" and p2_rooster_id != "" and online_match_data["status"] != "IN_PROGRESS":
		online_match_data["status"] = "IN_PROGRESS"
		rpc("rpc_start_match", p1_rooster_id, p2_rooster_id)

@rpc("authority", "call_local", "reliable")
func rpc_start_match(p1_id: String, p2_id: String) -> void:
	p1_rooster_id = p1_id
	p2_rooster_id = p2_id
	match_ready.emit(p1_id, p2_id)

# ---------------------------------------------------------------------------
# Dice Roll Broadcast (Blueprint §9: "Roll round dice & replenish energy")
# Host generates authoritative rolls, broadcasts to client
# ---------------------------------------------------------------------------

## Host calls this to broadcast dice rolls to both peers
func broadcast_dice_rolls(meron_roll: int, wala_roll: int) -> void:
	if not is_host: return
	rpc("rpc_receive_dice_rolls", meron_roll, wala_roll)

@rpc("authority", "reliable")
func rpc_receive_dice_rolls(meron_roll: int, wala_roll: int) -> void:
	dice_rolls_received.emit(meron_roll, wala_roll)

# ---------------------------------------------------------------------------
# Turn Card Submission (Blueprint §9: "Submit locked turn cards")
# Client submits only card IDs — host is authoritative
# ---------------------------------------------------------------------------

## Submits turn cards secretly to host (client submits IDs only per Blueprint §11)
func submit_turn(card_ids: Array) -> void:
	var typed_cards: Array[String] = []
	for c in card_ids:
		typed_cards.append(str(c))

	if is_host:
		if current_match_mode == MatchMode.TOURNAMENT:
			var my_id := multiplayer.get_unique_id()
			if my_id == active_p1_peer:
				p1_submitted_cards = typed_cards
				p1_has_locked_turn = true
			elif my_id == active_p2_peer:
				p2_submitted_cards = typed_cards
				p2_has_locked_turn = true
		else:
			p1_submitted_cards = typed_cards
			p1_has_locked_turn = true
		_check_both_turns_ready()
	else:
		rpc_id(1, "rpc_client_submit_turn", typed_cards)

@rpc("any_peer", "reliable")
func rpc_client_submit_turn(card_ids: Array) -> void:
	if not is_host: return
	var typed_cards: Array[String] = []
	for c in card_ids:
		typed_cards.append(str(c))
	var sender_id := multiplayer.get_remote_sender_id()
	if current_match_mode == MatchMode.TOURNAMENT:
		if sender_id == active_p1_peer:
			p1_submitted_cards = typed_cards
			p1_has_locked_turn = true
		elif sender_id == active_p2_peer:
			p2_submitted_cards = typed_cards
			p2_has_locked_turn = true
		else:
			push_warning("[NetworkManager] Received turn submission from non-contender peer %d" % sender_id)
			return
	else:
		p2_submitted_cards = typed_cards
		p2_has_locked_turn = true
	_check_both_turns_ready()

## Blueprint §9: "Execute authoritative combat resolution"
## Host: once both turns locked → apply cards to Duelists → run CombatEngine → broadcast
func _check_both_turns_ready() -> void:
	if not is_host: return
	if not (p1_has_locked_turn and p2_has_locked_turn):
		return

	# Reset turn locks immediately
	p1_has_locked_turn = false
	p2_has_locked_turn = false

	# Apply submitted card IDs to Duelist queued_cards
	# (Validation: host verifies cards exist, owner has them)
	if _p1_duelist and _p2_duelist:
		_apply_card_ids_to_duelist(_p1_duelist, p1_submitted_cards)
		_apply_card_ids_to_duelist(_p2_duelist, p2_submitted_cards)

	p1_submitted_cards.clear()
	p2_submitted_cards.clear()

	# Signal the host DuelPhaseManager that both sides are locked
	# DuelPhaseManager will call CombatEngine and then call broadcast_turn_events()
	turn_received_from_host.emit([])  # Empty signal = "both sides ready" trigger for host's own DuelPhaseManager

## Applies card ID array to a Duelist's queued_cards by looking up CardData resources
func _apply_card_ids_to_duelist(duelist: Duelist, card_ids: Array[String]) -> void:
	duelist.queued_cards.clear()
	for cid in card_ids:
		var found_card: CardData = null
		# 1. Search hand
		for card in duelist.hand:
			if card and card.card_id == cid:
				found_card = card
				break
		# 2. Search deck
		if not found_card:
			for card in duelist.deck:
				if card and card.card_id == cid:
					found_card = card
					break
		# 3. Search discard pile
		if not found_card:
			for card in duelist.discard_pile:
				if card and card.card_id == cid:
					found_card = card
					break
		# 4. Search moveset
		if not found_card and duelist.rooster_data:
			for card in duelist.rooster_data.moveset:
				if card and card.card_id == cid:
					found_card = card.duplicate()
					break
		# 5. Direct resource fallback
		if not found_card:
			var path := "res://resources/cards/%s.tres" % cid
			if ResourceLoader.exists(path):
				found_card = load(path)
		
		if found_card:
			duelist.queued_cards.append(found_card)

## Called by host DuelPhaseManager AFTER CombatEngine resolves the turn
## Broadcasts the full events array to all clients (Blueprint §9: "broadcast live VFX, damage & HP sync")
func broadcast_turn_events(events: Array[Dictionary]) -> void:
	if not is_host: return
	rpc("rpc_broadcast_turn_resolution", events)

@rpc("authority", "reliable")
func rpc_broadcast_turn_resolution(events: Array[Dictionary]) -> void:
	turn_received_from_host.emit(events)

# ---------------------------------------------------------------------------
# Tournament Network Coordination & RPCs
# ---------------------------------------------------------------------------

func register_local_tournament_player(player_name: String, rooster_id: String) -> void:
	var my_id := multiplayer.get_unique_id()
	local_peer_id = my_id
	if is_host:
		tournament_roster[1] = {
			"peer_id": 1,
			"name": player_name,
			"rooster_id": rooster_id,
			"ready": true
		}
		_sync_tournament_roster_to_all()
	else:
		rpc_id(1, "rpc_submit_tournament_registration", player_name, rooster_id)

@rpc("any_peer", "reliable")
func rpc_submit_tournament_registration(player_name: String, rooster_id: String) -> void:
	if not is_host: return
	var sender_id := multiplayer.get_remote_sender_id()
	tournament_roster[sender_id] = {
		"peer_id": sender_id,
		"name": player_name,
		"rooster_id": rooster_id,
		"ready": true
	}
	print("[NetworkManager] Registered tournament participant: peer %d (%s, %s)" % [sender_id, player_name, rooster_id])
	_sync_tournament_roster_to_all()

func _sync_tournament_roster_to_all() -> void:
	if not is_host: return
	tournament_roster_updated.emit(tournament_roster)
	rpc("rpc_sync_tournament_roster", tournament_roster)

@rpc("authority", "reliable")
func rpc_sync_tournament_roster(roster: Dictionary) -> void:
	tournament_roster = roster
	tournament_roster_updated.emit(tournament_roster)

func broadcast_start_tournament(bracket_data: Dictionary) -> void:
	if not is_host: return
	rpc("rpc_sync_tournament_bracket", bracket_data)

@rpc("authority", "call_local", "reliable")
func rpc_sync_tournament_bracket(bracket_data: Dictionary) -> void:
	print("[NetworkManager] Received tournament bracket sync (%d nodes)." % bracket_data.get("nodes", []).size())
	TournamentManager.deserialize_bracket(bracket_data)
	TournamentManager.is_online_tournament = true
	TournamentManager.is_tournament_active = true
	tournament_bracket_received.emit(bracket_data)

func broadcast_start_tournament_match(match_id: String, p1_peer: int, p2_peer: int, p1_rooster: String, p2_rooster: String) -> void:
	if not is_host: return
	active_tournament_match_id = match_id
	active_p1_peer = p1_peer
	active_p2_peer = p2_peer
	rpc("rpc_start_tournament_match", match_id, p1_peer, p2_peer, p1_rooster, p2_rooster)

@rpc("authority", "call_local", "reliable")
func rpc_start_tournament_match(match_id: String, p1_peer: int, p2_peer: int, p1_rooster: String, p2_rooster: String) -> void:
	active_tournament_match_id = match_id
	active_p1_peer = p1_peer
	active_p2_peer = p2_peer
	p1_rooster_id = p1_rooster
	p2_rooster_id = p2_rooster
	tournament_match_started.emit(match_id, p1_peer, p2_peer)

func broadcast_tournament_match_result(winner_rooster_id: String, updated_bracket: Dictionary) -> void:
	if not is_host: return
	rpc("rpc_sync_tournament_match_result", winner_rooster_id, updated_bracket)

@rpc("authority", "call_local", "reliable")
func rpc_sync_tournament_match_result(_winner_rooster_id: String, updated_bracket: Dictionary) -> void:
	TournamentManager.deserialize_bracket(updated_bracket)
	TournamentManager.tournament_state_changed.emit()

# ---------------------------------------------------------------------------
# Disconnect & Forfeit Handling (Blueprint §12 Risk: "Player disconnects mid-match")
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host:
		if current_match_mode == MatchMode.DUEL_1V1:
			if opponent_peer_id != -1 and id != opponent_peer_id and id != _disconnected_peer:
				push_warning("[NetworkManager] Rejecting extra peer %d: match is 1v1." % id)
				if peer:
					peer.disconnect_peer(id)
				return
			opponent_peer_id = id
		else:
			# Tournament mode
			if tournament_roster.size() >= max_tournament_players and not tournament_roster.has(id):
				push_warning("[NetworkManager] Rejecting peer %d: tournament room full (%d/%d)." % [id, tournament_roster.size(), max_tournament_players])
				if peer:
					peer.disconnect_peer(id)
				return
			print("[NetworkManager] Host: peer %d connected to tournament." % id)

	local_peer_id = multiplayer.get_unique_id()
	player_connected.emit(id)
	# Cancel any pending forfeit timer if opponent reconnected
	if id == _disconnected_peer:
		_disconnected_peer = -1
		_forfeit_timer = null

func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	player_connected.emit(1)

func _on_connection_failed() -> void:
	online_connection_failed.emit("Failed to connect to host.")
	server_disconnected.emit()

func _on_peer_disconnected(id: int) -> void:
	if current_match_mode == MatchMode.DUEL_1V1:
		if is_host and id != opponent_peer_id:
			return
		player_disconnected.emit(id)
		_disconnected_peer = id
		# Blueprint §12: 30-second reconnect window, then auto-forfeit
		if is_inside_tree():
			_forfeit_timer = get_tree().create_timer(FORFEIT_TIMEOUT_SEC)
			_forfeit_timer.timeout.connect(_on_forfeit_timeout)
	else:
		# Tournament mode
		player_disconnected.emit(id)
		if is_host:
			if tournament_roster.has(id):
				var p_info = tournament_roster[id]
				print("[NetworkManager] Tournament player %s (peer %d) disconnected." % [p_info.get("name", "Unknown"), id])
				tournament_roster.erase(id)
				_sync_tournament_roster_to_all()
			if id == active_p1_peer or id == active_p2_peer:
				print("[NetworkManager] Active tournament contender %d disconnected mid-duel." % id)
				opponent_disconnected_forfeit.emit()

func _on_forfeit_timeout() -> void:
	if _disconnected_peer != -1:
		online_match_data["status"] = "FORFEITED"
		opponent_disconnected_forfeit.emit()

func _on_server_disconnected() -> void:
	online_match_data["status"] = "FORFEITED"
	server_disconnected.emit()

## Cleanly disconnect and reset all state
func disconnect_from_match() -> void:
	p1_rooster_id = ""
	p2_rooster_id = ""
	p1_submitted_cards.clear()
	p2_submitted_cards.clear()
	p1_has_locked_turn = false
	p2_has_locked_turn = false
	_p1_duelist = null
	_p2_duelist = null
	_disconnected_peer = -1
	opponent_peer_id = -1
	tournament_roster.clear()
	active_tournament_match_id = ""
	active_p1_peer = 0
	active_p2_peer = 0
	online_match_data["status"] = "CANCELLED"
	_stop_discovery_beacon()
	stop_lan_scan()
	stop_online_room_fetch()
	_close_relay_ws()
	_cleanup_upnp()
	if peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer.multiplayer_peer = null
	peer = null

func _get_local_ipv4() -> String:
	for ip in IP.get_local_addresses():
		if ":" in ip:
			continue
		if ip.begins_with("127."):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return ""

func _start_upnp_async() -> void:
	if OS.has_feature("web"): return
	_cleanup_upnp()
	_upnp_thread = Thread.new()
	_upnp_thread.start(func():
		var upnp := UPNP.new()
		var err := upnp.discover()
		if err == UPNP.UPNP_RESULT_SUCCESS:
			var gw := upnp.get_gateway()
			if gw and gw.is_valid_gateway():
				var res := upnp.add_port_mapping(DEFAULT_PORT, DEFAULT_PORT, "SabongRoosters", "UDP")
				if res == UPNP.UPNP_RESULT_SUCCESS:
					_upnp = upnp
					print("[NetworkManager] UPnP: Port %d forwarded successfully." % DEFAULT_PORT)
	)

func _cleanup_upnp() -> void:
	if _upnp_thread != null:
		if _upnp_thread.is_started():
			_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(DEFAULT_PORT, "UDP")
		_upnp = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_upnp()
