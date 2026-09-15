extends Node

## AuthManager — Global authentication, player profile, and Taya wallet manager.
## Connects to the local/cloud backend for player registration, sign-in, and real-time Taya balances.

signal login_succeeded(user_data: Dictionary)
signal login_failed(error_msg: String)
signal otp_sent(message: String, dev_otp: String)
signal otp_failed(error_msg: String)
signal password_reset_succeeded(message: String)
signal password_reset_failed(error_msg: String)
signal taya_balance_updated(new_balance: int)
signal rank_tier_changed(new_tier: String, old_tier: String)
signal logged_out

var is_logged_in: bool = false
var player_id: int = 0
var username: String = "Guest"
var email: String = ""
var avatar_url: String = ""
var taya_points: int = 500
var rank_tier: String = "SILVER"
var wins: int = 0
var losses: int = 0

const API_BASE_URL := "http://localhost:10006"
const SESSION_FILE := "user://player_session.json"

var _http_request: HTTPRequest = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_request_completed)

	load_saved_session()

## Checks if an account is an administrator
static func is_admin_username(user: String, em: String = "") -> bool:
	var u := user.strip_edges().to_lower()
	var e := em.strip_edges().to_lower()
	return u == "admin" or e == "admin@sabong.ph" or u.begins_with("admin_")

## Computes competitive prestige rank tier from Taya points:
## Bronze -> Silver -> Gold -> Platinum -> Diamond -> Master -> Grandmaster
## Note: Admin accounts are assigned UNRANK
static func compute_rank_tier(taya: int, user: String = "", em: String = "") -> String:
	if is_admin_username(user, em):
		return "UNRANK"
	if taya >= 20000:
		return "GRANDMASTER"
	elif taya >= 10000:
		return "MASTER"
	elif taya >= 5000:
		return "DIAMOND"
	elif taya >= 2500:
		return "PLATINUM"
	elif taya >= 1000:
		return "GOLD"
	elif taya >= 500:
		return "SILVER"
	else:
		return "BRONZE"

static func get_rank_color(tier: String) -> Color:
	match tier.to_upper():
		"UNRANK":      return Color(0.70, 0.78, 0.95) # Celestial Lavender / Silver-Cyan Glow
		"GRANDMASTER": return Color(1.0, 0.25, 0.15) # Blazing Crimson
		"MASTER":      return Color(0.95, 0.75, 0.20) # Bright Gold
		"DIAMOND":     return Color(0.30, 0.85, 1.00) # Electric Cyan
		"PLATINUM":    return Color(0.40, 0.95, 0.70) # Emerald/Platinum
		"GOLD":        return Color(0.90, 0.75, 0.30) # Warm Gold
		"SILVER":      return Color(0.80, 0.85, 0.92) # Sleek Silver
		_:             return Color(0.80, 0.55, 0.35) # Bronze

static func get_rank_card_texture(tier: String) -> Texture2D:
	var path := "res://resources/ranks/%s.png" % tier.to_lower().strip_edges()
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Returns the competitive prestige ladder ranks (The 7 Standard Ranks).
## Note: UNRANK is an exclusive administrative card and is intentionally omitted from the public competitive ladder.
static func get_rank_definitions() -> Array[Dictionary]:
	return [
		{
			"tier": "BRONZE",
			"name": "BRONZE",
			"min_taya": 0,
			"max_taya": 499,
			"desc": "Novice Contender • Welcome to the Cockpit",
			"color": Color(0.80, 0.55, 0.35),
			"texture_path": "res://resources/ranks/bronze.png"
		},
		{
			"tier": "SILVER",
			"name": "SILVER",
			"min_taya": 500,
			"max_taya": 999,
			"desc": "Starter Tier • 500 Starter Taya Coins",
			"color": Color(0.80, 0.85, 0.92),
			"texture_path": "res://resources/ranks/silver.png"
		},
		{
			"tier": "GOLD",
			"name": "GOLD",
			"min_taya": 1000,
			"max_taya": 2499,
			"desc": "Veteran Duelist • Proven Arena Competitor",
			"color": Color(0.90, 0.75, 0.30),
			"texture_path": "res://resources/ranks/gold.png"
		},
		{
			"tier": "PLATINUM",
			"name": "PLATINUM",
			"min_taya": 2500,
			"max_taya": 4999,
			"desc": "Elite Duelist • High-Stakes Cockpit Fighter",
			"color": Color(0.40, 0.95, 0.70),
			"texture_path": "res://resources/ranks/platinum.png"
		},
		{
			"tier": "DIAMOND",
			"name": "DIAMOND",
			"min_taya": 5000,
			"max_taya": 9999,
			"desc": "Master Tactician • Premier Arena Champion",
			"color": Color(0.30, 0.85, 1.00),
			"texture_path": "res://resources/ranks/diamond.png"
		},
		{
			"tier": "MASTER",
			"name": "MASTER",
			"min_taya": 10000,
			"max_taya": 19999,
			"desc": "Cockpit Legend • Feared Across the Islands",
			"color": Color(0.95, 0.75, 0.20),
			"texture_path": "res://resources/ranks/master.png"
		},
		{
			"tier": "GRANDMASTER",
			"name": "GRANDMASTER",
			"min_taya": 20000,
			"max_taya": 999999999,
			"desc": "Apex Champion • Supreme Sabong Legend",
			"color": Color(1.0, 0.25, 0.15),
			"texture_path": "res://resources/ranks/grandmaster.png"
		}
	]

## ---------------------------------------------------------------------------
## API Calls
## ---------------------------------------------------------------------------

func login_email(user_or_email: String, password: String) -> void:
	var payload := {
		"username": user_or_email,
		"password": password
	}
	_post_json("/auth/login", payload)

func send_otp(target_email: String, purpose: String = "register") -> void:
	var payload := {
		"email": target_email,
		"purpose": purpose
	}
	_post_json("/auth/send-otp", payload)

func register_account(new_user: String, new_email: String, password: String, otp: String = "") -> void:
	var payload := {
		"username": new_user,
		"email": new_email,
		"password": password,
		"otp": otp
	}
	_post_json("/auth/register", payload)

func reset_password(target_email: String, otp: String, new_password: String) -> void:
	var payload := {
		"email": target_email,
		"otp": otp,
		"new_password": new_password
	}
	_post_json("/auth/reset-password", payload)

func place_bet(side: String, amount: int, room_code: String = "") -> void:
	if not is_logged_in:
		# Guest betting
		if taya_points >= amount:
			update_taya_balance(taya_points - amount)
		return
	var payload := {
		"player_id": player_id,
		"username": username,
		"side": side.to_upper(),
		"amount": amount,
		"room_code": room_code
	}
	_post_json("/bet/place", payload)

func update_taya_balance(new_amount: int) -> void:
	var old_tier := rank_tier
	taya_points = maxi(0, new_amount)
	if is_admin_username(username, email):
		rank_tier = "UNRANK"
	else:
		rank_tier = compute_rank_tier(taya_points, username, email)
	taya_balance_updated.emit(taya_points)
	if rank_tier != old_tier:
		rank_tier_changed.emit(rank_tier, old_tier)
	save_session()

func logout() -> void:
	is_logged_in = false
	player_id = 0
	username = "Guest"
	email = ""
	avatar_url = ""
	taya_points = 500
	rank_tier = "SILVER"
	wins = 0
	losses = 0
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(SESSION_FILE)
	logged_out.emit()

## ---------------------------------------------------------------------------
## Session Persistence
## ---------------------------------------------------------------------------

func save_session() -> void:
	if not is_logged_in: return
	var data := {
		"player_id": player_id,
		"username": username,
		"email": email,
		"avatar_url": avatar_url,
		"taya_points": taya_points,
		"rank_tier": rank_tier,
		"wins": wins,
		"losses": losses
	}
	var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_saved_session() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		# Default initial guest state
		rank_tier = compute_rank_tier(taya_points)
		return
	var f := FileAccess.open(SESSION_FILE, FileAccess.READ)
	if f:
		var txt := f.get_as_text()
		f.close()
		var json_obj = JSON.parse_string(txt)
		if json_obj is Dictionary:
			_apply_user_data(json_obj)

func _apply_user_data(data: Dictionary) -> void:
	player_id = int(data.get("player_id", 0))
	username = str(data.get("username", "Challenger"))
	email = str(data.get("email", ""))
	avatar_url = str(data.get("avatar_url", ""))
	taya_points = int(data.get("taya_coins", data.get("taya_points", 500)))
	if is_admin_username(username, email) or str(data.get("rank_tier", "")).to_upper() == "UNRANK":
		rank_tier = "UNRANK"
	else:
		rank_tier = compute_rank_tier(taya_points, username, email)
	wins = int(data.get("wins", 0))
	losses = int(data.get("losses", 0))
	is_logged_in = (player_id > 0)
	save_session()
	login_succeeded.emit(data)
	taya_balance_updated.emit(taya_points)

## ---------------------------------------------------------------------------
## Network HTTP Helper
## ---------------------------------------------------------------------------

var _current_endpoint: String = ""

func get_api_base_url() -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin")
		if origin != null and str(origin) != "null" and str(origin) != "":
			return str(origin)
	if NetworkManager and not NetworkManager.use_local_relay:
		return "https://sabong-inxt.onrender.com"
	return API_BASE_URL

func _post_json(endpoint: String, payload: Dictionary) -> void:
	_current_endpoint = endpoint
	var url := get_api_base_url() + endpoint
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(payload)
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		login_failed.emit("Failed to send network request (error %d)" % err)

func _on_http_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_text := body.get_string_from_utf8()
	var json_res = JSON.parse_string(response_text)

	if response_code >= 200 and response_code < 300:
		if json_res is Dictionary:
			if json_res.get("success", true):
				if _current_endpoint == "/auth/send-otp":
					var msg: String = str(json_res.get("message", "Verification code sent."))
					var dev_otp: String = str(json_res.get("dev_otp", ""))
					otp_sent.emit(msg, dev_otp)
				elif _current_endpoint == "/auth/reset-password":
					var msg: String = str(json_res.get("message", "Password reset successfully."))
					password_reset_succeeded.emit(msg)
				elif _current_endpoint.begins_with("/auth/"):
					_apply_user_data(json_res)
				elif _current_endpoint == "/bet/place":
					var new_bal: int = int(json_res.get("new_balance", taya_points))
					update_taya_balance(new_bal)
			else:
				var err_msg: String = str(json_res.get("error", "Request failed"))
				_handle_http_error(err_msg)
	else:
		var err_msg := "Server returned error %d" % response_code
		if json_res is Dictionary and json_res.has("error"):
			err_msg = str(json_res["error"])
		_handle_http_error(err_msg)

func _handle_http_error(err_msg: String) -> void:
	if _current_endpoint == "/auth/send-otp":
		otp_failed.emit(err_msg)
	elif _current_endpoint == "/auth/reset-password":
		password_reset_failed.emit(err_msg)
	else:
		login_failed.emit(err_msg)
