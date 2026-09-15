extends Node

## BettingManager — Global client betting controller.
## Tracks active wagers on MERON vs WALA, live odds, pools, and payout resolution.

signal bet_placed(side: String, amount: int)
signal pool_updated(meron: int, wala: int)
signal odds_updated(meron_odds: float, wala_odds: float)
signal spectator_count_changed(count: int)
signal bet_resolved(won: bool, payout: int, new_balance: int)
signal bet_cleared

var active_room_code: String = ""
var meron_pool: int = 0
var wala_pool: int = 0
var meron_odds: float = 1.95
var wala_odds: float = 1.95
var spectator_count: int = 0
const FIXED_ODDS: float = 1.95

var player_bet_side: String = ""
var player_bet_amount: int = 0
var is_betting_locked: bool = false
var has_active_bet: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset_match_betting(room_code: String = "") -> void:
	active_room_code = room_code
	meron_pool = 0
	wala_pool = 0
	meron_odds = 1.95
	wala_odds = 1.95
	player_bet_side = ""
	player_bet_amount = 0
	is_betting_locked = false
	has_active_bet = false
	bet_cleared.emit()
	odds_updated.emit(meron_odds, wala_odds)

func can_place_bet(amount: int) -> bool:
	if is_betting_locked or has_active_bet:
		return false
	if not AuthManager:
		return false
	return amount > 0 and AuthManager.taya_points >= amount

func place_bet(side: String, amount: int) -> bool:
	if not can_place_bet(amount):
		return false

	side = side.to_upper()
	if side != "MERON" and side != "WALA":
		return false

	player_bet_side = side
	player_bet_amount = amount
	has_active_bet = true

	# Deduct from local wallet immediately and notify backend
	AuthManager.update_taya_balance(AuthManager.taya_points - amount)
	AuthManager.place_bet(side, amount, active_room_code)

	# Also send to relay WebSocket if connected in spectator arena
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("send_relay_bet"):
		nm.send_relay_bet(side, amount)

	# Update local pool estimation
	if side == "MERON":
		meron_pool += amount
	else:
		wala_pool += amount

	# Recalculate local projected odds
	_recalculate_local_odds()

	bet_placed.emit(side, amount)
	pool_updated.emit(meron_pool, wala_pool)
	odds_updated.emit(meron_odds, wala_odds)
	return true

func lock_betting() -> void:
	is_betting_locked = true

func set_spectator_count(count: int) -> void:
	spectator_count = count
	spectator_count_changed.emit(spectator_count)

func update_pool_from_server(m_pool: int, w_pool: int, m_odds: float = 1.95, w_odds: float = 1.95) -> void:
	meron_pool = m_pool
	wala_pool = w_pool
	meron_odds = m_odds
	wala_odds = w_odds
	pool_updated.emit(meron_pool, wala_pool)
	odds_updated.emit(meron_odds, wala_odds)

func _recalculate_local_odds() -> void:
	var total: int = meron_pool + wala_pool
	if total == 0:
		meron_odds = 1.95
		wala_odds = 1.95
		return
	if meron_pool == 0:
		meron_odds = 1.95
		wala_odds = 1.05
		return
	if wala_pool == 0:
		meron_odds = 1.05
		wala_odds = 1.95
		return
	meron_odds = snappedf(maxf(1.05, float(total) / float(meron_pool)), 0.01)
	wala_odds = snappedf(maxf(1.05, float(total) / float(wala_pool)), 0.01)

func resolve_winner(winner_side: String, server_payouts: Array = [], winning_odds: float = 0.0) -> void:
	winner_side = winner_side.to_upper()
	var won := false
	var payout := 0

	if has_active_bet:
		if player_bet_side == winner_side:
			won = true
			# Find server payout if authenticated
			var found_payout := false
			for p in server_payouts:
				if p is Dictionary and int(p.get("player_id", 0)) == AuthManager.player_id:
					payout = int(p.get("payout", 0))
					found_payout = true
					break
			if not found_payout:
				var payout_multiplier: float = winning_odds if winning_odds > 0.0 else (meron_odds if winner_side == "MERON" else wala_odds)
				payout = int(round(player_bet_amount * payout_multiplier))

			var new_bal := AuthManager.taya_points + payout
			AuthManager.update_taya_balance(new_bal)
		else:
			won = false
			payout = 0

		bet_resolved.emit(won, payout, AuthManager.taya_points)

	has_active_bet = false

func get_projected_payout(side_or_amount, maybe_amount = null) -> int:
	if maybe_amount != null:
		var side: String = str(side_or_amount).to_upper()
		var amt: int = int(maybe_amount)
		var odds: float = meron_odds if side == "MERON" else wala_odds
		return int(round(amt * odds))
	else:
		var amt: int = int(side_or_amount)
		return int(round(amt * FIXED_ODDS))
