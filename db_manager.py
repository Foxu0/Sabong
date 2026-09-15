"""
Sabong Roosters - Cloud Database Manager
Interfacing with TiDB Cloud MySQL 8.0 (sabong_roosters_db)
"""

import os
import ssl
import logging
import hashlib
import random
import string
from typing import Optional, Dict, Any, List
import pymysql

log = logging.getLogger("sabong-db")

DB_HOST = os.environ.get("DB_HOST", "gateway01.ap-southeast-1.prod.aws.tidbcloud.com")
DB_PORT = int(os.environ.get("DB_PORT", 4000))
DB_USER = os.environ.get("DB_USER", "35JtqKVBmhS4TEY.root")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "mw1hTTxq5b28o9FB")
DB_NAME = os.environ.get("DB_NAME", "sabong_roosters_db")

def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def compute_rank_tier(taya_coins: int) -> str:
    """
    Computes player competitive rank tier based strictly on accumulated Taya points:
      - BRONZE: 0 - 499
      - SILVER: 500 - 999 (New players start at 500)
      - GOLD: 1,000 - 2,499
      - PLATINUM: 2,500 - 4,999
      - DIAMOND: 5,000 - 9,999
      - MASTER: 10,000 - 19,999
      - GRANDMASTER: 20,000+
    """
    if taya_coins >= 20000:
        return "GRANDMASTER"
    elif taya_coins >= 10000:
        return "MASTER"
    elif taya_coins >= 5000:
        return "DIAMOND"
    elif taya_coins >= 2500:
        return "PLATINUM"
    elif taya_coins >= 1000:
        return "GOLD"
    elif taya_coins >= 500:
        return "SILVER"
    else:
        return "BRONZE"

class DatabaseManager:
    def __init__(self):
        self.host = DB_HOST
        self.port = DB_PORT
        self.user = DB_USER
        self.password = DB_PASSWORD
        self.database = DB_NAME
        self.enabled = True
        self._ctx = ssl.create_default_context()

    def get_connection(self):
        return pymysql.connect(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            database=self.database,
            ssl=self._ctx,
            autocommit=True,
            connect_timeout=10,
            cursorclass=pymysql.cursors.DictCursor
        )

    def test_connection(self) -> bool:
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
            conn.close()
            log.info("[DB] Successfully connected to cloud MySQL at %s:%d", self.host, self.port)
            return True
        except Exception as e:
            log.error("[DB] Failed to connect to database: %s", e)
            return False

    def get_leaderboard(self, limit: int = 20) -> List[Dict[str, Any]]:
        """
        Retrieves top champions ranked strictly by Taya points, then by wins.
        Dynamically computes and syncs rank_tier (Master, Grandmaster, etc.).
        """
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                sql = """
                    SELECT 
                        p.player_id,
                        p.username, 
                        p.taya_coins,
                        p.wins, 
                        p.losses, 
                        p.total_matches,
                        p.rank_tier,
                        p.avatar_url
                    FROM players p
                    WHERE p.status = 'ACTIVE'
                    ORDER BY p.taya_coins DESC, p.wins DESC
                    LIMIT %s;
                """
                cur.execute(sql, (limit,))
                results = cur.fetchall()

                # Recalculate rank tier based on current Taya coins
                formatted = []
                for idx, row in enumerate(results):
                    if row["username"].lower() == "admin" or (row.get("email") or "").lower() == "admin@sabong.ph":
                        current_tier = "UNRANK"
                    else:
                        current_tier = compute_rank_tier(row["taya_coins"])
                    if current_tier != row["rank_tier"]:
                        # Sync tier update
                        cur.execute("UPDATE players SET rank_tier = %s WHERE player_id = %s;", (current_tier, row["player_id"]))
                        cur.execute("UPDATE leaderboards SET rank_tier = %s WHERE player_id = %s;", (current_tier, row["player_id"]))
                        row["rank_tier"] = current_tier

                    formatted.append({
                        "rank": idx + 1,
                        "player_id": row["player_id"],
                        "username": row["username"],
                        "taya_coins": row["taya_coins"],
                        "rank_tier": row["rank_tier"],
                        "wins": row["wins"],
                        "losses": row["losses"],
                        "avatar_url": row.get("avatar_url") or ""
                    })

            conn.close()
            return formatted
        except Exception as e:
            log.error("[DB] Error fetching leaderboard: %s", e)
            return []

    def authenticate_or_register_google(self, google_id: str, email: str, name: str, avatar_url: str = "") -> Dict[str, Any]:
        """
        1-Click Google Sign-In: Authenticates existing user or creates a new account with 500 starter Taya points.
        """
        google_id = str(google_id).strip()
        email = str(email).strip().lower()
        name = str(name).strip()
        if not google_id or not email:
            return {"success": False, "error": "Invalid Google credential payload"}

        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                # 1. Lookup by google_id or email
                cur.execute("""
                    SELECT player_id, username, email, taya_coins, rank_tier, wins, losses, total_matches, avatar_url, google_id
                    FROM players
                    WHERE (google_id = %s OR email = %s) AND status = 'ACTIVE';
                """, (google_id, email))
                player = cur.fetchone()

                if player:
                    # Update last login, link google_id & avatar if missing
                    tier = compute_rank_tier(player["taya_coins"])
                    cur.execute("""
                        UPDATE players 
                        SET last_login = NOW(), 
                            google_id = COALESCE(google_id, %s),
                            avatar_url = COALESCE(%s, avatar_url),
                            rank_tier = %s
                        WHERE player_id = %s;
                    """, (google_id, avatar_url or None, tier, player["player_id"]))

                    conn.close()
                    return {
                        "success": True,
                        "is_new": False,
                        "player_id": player["player_id"],
                        "username": player["username"],
                        "email": player["email"],
                        "taya_coins": player["taya_coins"],
                        "rank_tier": tier,
                        "wins": player["wins"],
                        "losses": player["losses"],
                        "avatar_url": avatar_url or player.get("avatar_url", "")
                    }

                # 2. Register new player from Google profile
                # Generate clean unique username
                base_user = "".join(c for c in name if c.isalnum() or c == "_")[:20]
                if not base_user or len(base_user) < 3:
                    base_user = "Challenger"

                cur.execute("SELECT 1 FROM players WHERE username = %s;", (base_user,))
                if cur.fetchone():
                    username = f"{base_user}_{random.randint(100, 999)}"
                else:
                    username = base_user

                starter_taya = 500
                initial_tier = compute_rank_tier(starter_taya) # SILVER

                cur.execute("""
                    INSERT INTO players (username, email, google_id, avatar_url, taya_coins, elo_rating, rank_tier, last_login)
                    VALUES (%s, %s, %s, %s, %s, 1000, %s, NOW());
                """, (username, email, google_id, avatar_url or None, starter_taya, initial_tier))
                pid = cur.lastrowid

                # Create initial leaderboard record
                cur.execute("""
                    INSERT INTO leaderboards (player_id, season_number, elo_rating, rank_tier, wins, losses, peak_elo)
                    VALUES (%s, 1, 1000, %s, 0, 0, 1000);
                """, (pid, initial_tier))

                # Log starter welcome taya bonus
                cur.execute("""
                    INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                    VALUES (%s, 'DAILY_LOGIN', %s, 0, %s, 'Welcome Starter Taya Bonus');
                """, (pid, starter_taya, starter_taya))

            conn.close()
            log.info("[DB] Registered new player via Google Auth: %s (%s)", username, email)
            return {
                "success": True,
                "is_new": True,
                "player_id": pid,
                "username": username,
                "email": email,
                "taya_coins": starter_taya,
                "rank_tier": initial_tier,
                "wins": 0,
                "losses": 0,
                "avatar_url": avatar_url
            }
        except Exception as e:
            log.error("[DB] Google authentication error: %s", e)
            return {"success": False, "error": str(e)}

    def register_player(self, username: str, email: str, password: str) -> Dict[str, Any]:
        username = username.strip()
        email = email.strip().lower()
        if len(username) < 3 or len(password) < 4:
            return {"success": False, "error": "Username/Password too short"}
        
        pw_hash = _hash_password(password)
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                # Check existing username or email
                if email:
                    cur.execute("SELECT player_id, username, email FROM players WHERE username=%s OR email=%s;", (username, email))
                    existing = cur.fetchone()
                    if existing:
                        conn.close()
                        if existing.get("username", "").lower() == username.lower():
                            return {"success": False, "error": "This username is already taken. Please choose another."}
                        else:
                            return {"success": False, "error": "This email is already registered. Please sign in or reset password."}
                else:
                    cur.execute("SELECT player_id FROM players WHERE username=%s;", (username,))
                    if cur.fetchone():
                        conn.close()
                        return {"success": False, "error": "This username is already taken. Please choose another."}

                starter_taya = 500
                initial_tier = compute_rank_tier(starter_taya)

                sql_insert = """
                    INSERT INTO players (username, email, password_hash, taya_coins, elo_rating, rank_tier, last_login)
                    VALUES (%s, %s, %s, %s, 1000, %s, NOW());
                """
                cur.execute(sql_insert, (username, email or None, pw_hash, starter_taya, initial_tier))
                pid = cur.lastrowid

                # Create initial leaderboard record
                sql_lb = """
                    INSERT INTO leaderboards (player_id, season_number, elo_rating, rank_tier, wins, losses, peak_elo)
                    VALUES (%s, 1, 1000, %s, 0, 0, 1000);
                """
                cur.execute(sql_lb, (pid, initial_tier))

                # Log starter welcome taya bonus
                cur.execute("""
                    INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                    VALUES (%s, 'DAILY_LOGIN', %s, 0, %s, 'Welcome Starter Taya Bonus');
                """, (pid, starter_taya, starter_taya))

            conn.close()
            return {
                "success": True,
                "player_id": pid,
                "username": username,
                "email": email,
                "taya_coins": starter_taya,
                "rank_tier": initial_tier,
                "wins": 0,
                "losses": 0
            }
        except Exception as e:
            log.error("[DB] Registration error: %s", e)
            return {"success": False, "error": str(e)}

    def check_email_exists(self, email: str) -> bool:
        email = email.strip().lower()
        if not email:
            return False
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM players WHERE email = %s AND status = 'ACTIVE' LIMIT 1;", (email,))
                exists = cur.fetchone() is not None
            conn.close()
            return exists
        except Exception as e:
            log.error("[DB] Error checking email: %s", e)
            return False

    def check_username_exists(self, username: str) -> bool:
        username = username.strip()
        if not username:
            return False
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM players WHERE username = %s AND status = 'ACTIVE' LIMIT 1;", (username,))
                exists = cur.fetchone() is not None
            conn.close()
            return exists
        except Exception as e:
            log.error("[DB] Error checking username: %s", e)
            return False

    def reset_password(self, email: str, new_password: str) -> Dict[str, Any]:
        email = email.strip().lower()
        if not email:
            return {"success": False, "error": "Email is required"}
        if len(new_password) < 4:
            return {"success": False, "error": "Password must be at least 4 characters long"}
        pw_hash = _hash_password(new_password)
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT player_id FROM players WHERE email = %s AND status = 'ACTIVE';", (email,))
                player = cur.fetchone()
                if not player:
                    conn.close()
                    return {"success": False, "error": "No active player found with that email"}
                cur.execute("UPDATE players SET password_hash = %s WHERE player_id = %s;", (pw_hash, player["player_id"]))
            conn.close()
            log.info("[DB] Reset password for player_id %s (%s)", player["player_id"], email)
            return {"success": True, "message": "Password reset successfully"}
        except Exception as e:
            log.error("[DB] Password reset error: %s", e)
            return {"success": False, "error": str(e)}

    def authenticate_player(self, username_or_email: str, password: str) -> Dict[str, Any]:
        pw_hash = _hash_password(password)
        u_in = username_or_email.strip()
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                sql = """
                    SELECT player_id, username, email, taya_coins, elo_rating, rank_tier, wins, losses, total_matches, avatar_url
                    FROM players
                    WHERE (username=%s OR email=%s) AND password_hash=%s AND status='ACTIVE';
                """
                cur.execute(sql, (u_in, u_in.lower(), pw_hash))
                player = cur.fetchone()
                if not player:
                    conn.close()
                    return {"success": False, "error": "Invalid username or password"}

                if player["username"].lower() == "admin" or (player.get("email") or "").lower() == "admin@sabong.ph":
                    tier = "UNRANK"
                else:
                    tier = compute_rank_tier(player["taya_coins"])
                cur.execute("UPDATE players SET last_login=NOW(), rank_tier=%s WHERE player_id=%s;", (tier, player["player_id"]))
            conn.close()
            return {
                "success": True,
                "player_id": player["player_id"],
                "username": player["username"],
                "email": player["email"],
                "taya_coins": player["taya_coins"],
                "elo_rating": player["elo_rating"],
                "rank_tier": tier,
                "wins": player["wins"],
                "losses": player["losses"],
                "total_matches": player["total_matches"],
                "avatar_url": player.get("avatar_url") or ""
            }
        except Exception as e:
            log.error("[DB] Auth error: %s", e)
            return {"success": False, "error": str(e)}

    def check_email_exists(self, email: str) -> bool:
        email = email.strip().lower()
        if not email:
            return False
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT player_id FROM players WHERE email=%s LIMIT 1;", (email,))
                exists = cur.fetchone() is not None
            conn.close()
            return exists
        except Exception as e:
            log.error("[DB] check_email_exists error: %s", e)
            return False

    def check_username_exists(self, username: str) -> bool:
        username = username.strip()
        if not username:
            return False
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT player_id FROM players WHERE username=%s LIMIT 1;", (username,))
                exists = cur.fetchone() is not None
            conn.close()
            return exists
        except Exception as e:
            log.error("[DB] check_username_exists error: %s", e)
            return False

    def reset_password(self, email: str, new_password: str) -> Dict[str, Any]:
        email = email.strip().lower()
        if len(new_password) < 6:
            return {"success": False, "error": "New password must be at least 6 characters"}
        pw_hash = _hash_password(new_password)
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT player_id, username FROM players WHERE email=%s AND status='ACTIVE';", (email,))
                player = cur.fetchone()
                if not player:
                    conn.close()
                    return {"success": False, "error": "No active account found with this email address"}
                cur.execute("UPDATE players SET password_hash=%s, last_login=NOW() WHERE player_id=%s;", (pw_hash, player["player_id"]))
            conn.close()
            log.info("[DB] Password reset successfully for player %s (%s)", player["username"], email)
            return {"success": True, "message": "Password updated successfully"}
        except Exception as e:
            log.error("[DB] Password reset error: %s", e)
            return {"success": False, "error": str(e)}

    def place_bet(self, player_id: int, side: str, amount: int, match_id: Optional[int] = None) -> Dict[str, Any]:
        """
        Deducts bet amount into escrow from player's Taya coins.
        """
        amount = int(amount)
        side = side.strip().upper()
        if amount <= 0:
            return {"success": False, "error": "Bet amount must be greater than 0"}
        if side not in ["MERON", "WALA"]:
            return {"success": False, "error": "Invalid bet side (must be MERON or WALA)"}

        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT taya_coins, username FROM players WHERE player_id = %s;", (player_id,))
                p = cur.fetchone()
                if not p:
                    conn.close()
                    return {"success": False, "error": "Player not found"}

                if p["taya_coins"] < amount:
                    conn.close()
                    return {"success": False, "error": f"Insufficient Taya coins (Available: {p['taya_coins']})"}

                new_balance = p["taya_coins"] - amount
                new_tier = compute_rank_tier(new_balance)

                cur.execute("UPDATE players SET taya_coins = %s, rank_tier = %s WHERE player_id = %s;", (new_balance, new_tier, player_id))
                cur.execute("""
                    INSERT INTO taya_transactions (player_id, match_id, transaction_type, amount, balance_before, balance_after, description)
                    VALUES (%s, %s, 'BET_ESCROW', %s, %s, %s, %s);
                """, (player_id, match_id, -amount, p["taya_coins"], new_balance, f"Bet on {side}"))

            conn.close()
            log.info("[DB] Player %s placed bet of %d Taya on %s. New balance: %d", p["username"], amount, side, new_balance)
            return {
                "success": True,
                "player_id": player_id,
                "side": side,
                "amount": amount,
                "new_balance": new_balance,
                "new_tier": new_tier
            }
        except Exception as e:
            log.error("[DB] Bet placement error: %s", e)
            return {"success": False, "error": str(e)}

    def resolve_bets(self, winner_side: str, bets: List[Dict[str, Any]], odds: float = 1.95) -> List[Dict[str, Any]]:
        """
        Settles all bets placed on a match:
          - Winning side receives amount * odds credited to their balance.
          - Updates player rank tiers and records ledger transactions.
        """
        winner_side = winner_side.strip().upper()
        payouts = []

        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                for bet in bets:
                    pid = int(bet.get("player_id", 0))
                    side = str(bet.get("side", "")).strip().upper()
                    amt = int(bet.get("amount", 0))
                    username = str(bet.get("username", "Spectator"))

                    if pid <= 0 or amt <= 0:
                        continue

                    if winner_side in ["DRAW", "CANCELLED", "REFUND", "ABORTED"]:
                        payout = amt
                        cur.execute("SELECT taya_coins FROM players WHERE player_id = %s;", (pid,))
                        row = cur.fetchone()
                        if row:
                            curr_bal = row["taya_coins"]
                            new_bal = curr_bal + payout
                            new_tier = compute_rank_tier(new_bal)

                            cur.execute("UPDATE players SET taya_coins = %s, rank_tier = %s WHERE player_id = %s;", (new_bal, new_tier, pid))
                            cur.execute("UPDATE leaderboards SET rank_tier = %s WHERE player_id = %s;", (new_tier, pid))
                            cur.execute("""
                                INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                                VALUES (%s, 'REFUND', %s, %s, %s, %s);
                            """, (pid, payout, curr_bal, new_bal, f"Bet refunded due to {winner_side}"))

                            payouts.append({
                                "player_id": pid,
                                "username": username,
                                "won": False,
                                "refunded": True,
                                "payout": payout,
                                "new_balance": new_bal,
                                "rank_tier": new_tier
                            })
                            log.info("[DB] Bet refunded: %s (+%d Taya, new balance: %d)", username, payout, new_bal)

                    elif side == winner_side:
                        payout = int(amt * odds)
                        cur.execute("SELECT taya_coins FROM players WHERE player_id = %s;", (pid,))
                        row = cur.fetchone()
                        if row:
                            curr_bal = row["taya_coins"]
                            new_bal = curr_bal + payout
                            new_tier = compute_rank_tier(new_bal)

                            cur.execute("UPDATE players SET taya_coins = %s, rank_tier = %s WHERE player_id = %s;", (new_bal, new_tier, pid))
                            cur.execute("UPDATE leaderboards SET rank_tier = %s WHERE player_id = %s;", (new_tier, pid))
                            cur.execute("""
                                INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                                VALUES (%s, 'BET_PAYOUT', %s, %s, %s, %s);
                            """, (pid, payout, curr_bal, new_bal, f"Won bet on {side} ({odds}x)"))

                            payouts.append({
                                "player_id": pid,
                                "username": username,
                                "won": True,
                                "refunded": False,
                                "payout": payout,
                                "new_balance": new_bal,
                                "rank_tier": new_tier
                            })
                            log.info("[DB] Bet won: %s (+%d Taya, new balance: %d, tier: %s)", username, payout, new_bal, new_tier)
                    else:
                        cur.execute("SELECT taya_coins, rank_tier FROM players WHERE player_id = %s;", (pid,))
                        row = cur.fetchone()
                        bal = row["taya_coins"] if row else 0
                        tier = row["rank_tier"] if row else "BRONZE"
                        payouts.append({
                            "player_id": pid,
                            "username": username,
                            "won": False,
                            "refunded": False,
                            "payout": 0,
                            "new_balance": bal,
                            "rank_tier": tier
                        })
            conn.close()
        except Exception as e:
            log.error("[DB] Error resolving bets: %s", e)

        return payouts

    def record_match_result(self, winner_username: str, loser_username: str, winner_rooster: str, loser_rooster: str, game_mode: str = "TOURNAMENT_ONLINE", taya_wager: int = 50, turns: int = 3, duration_sec: int = 45) -> bool:
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT player_id, elo_rating, taya_coins FROM players WHERE username=%s;", (winner_username,))
                w_row = cur.fetchone()
                cur.execute("SELECT player_id, elo_rating, taya_coins FROM players WHERE username=%s;", (loser_username,))
                l_row = cur.fetchone()

                w_id = w_row["player_id"] if w_row else None
                l_id = l_row["player_id"] if l_row else None

                if w_id and l_id:
                    new_w_elo = w_row["elo_rating"] + 25
                    new_l_elo = max(800, l_row["elo_rating"] - 20)
                    prize = taya_wager * 2 if taya_wager > 0 else 50 # Default win bounty if casual/tournament

                    new_w_bal = w_row["taya_coins"] + prize
                    new_w_tier = compute_rank_tier(new_w_bal)

                    cur.execute("""
                        UPDATE players 
                        SET wins = wins + 1, total_matches = total_matches + 1, elo_rating = %s, taya_coins = %s, rank_tier = %s
                        WHERE player_id = %s;
                    """, (new_w_elo, new_w_bal, new_w_tier, w_id))

                    cur.execute("""
                        UPDATE players 
                        SET losses = losses + 1, total_matches = total_matches + 1, elo_rating = %s
                        WHERE player_id = %s;
                    """, (new_l_elo, l_id))

                    cur.execute("""
                        UPDATE leaderboards
                        SET wins = wins + 1, elo_rating = %s, peak_elo = GREATEST(peak_elo, %s), rank_tier = %s
                        WHERE player_id = %s;
                    """, (new_w_elo, new_w_elo, new_w_tier, w_id))

                    cur.execute("""
                        UPDATE leaderboards
                        SET losses = losses + 1, elo_rating = %s
                        WHERE player_id = %s;
                    """, (new_l_elo, l_id))

                    cur.execute("""
                        INSERT INTO matches (player1_id, player2_id, p1_rooster_id, p2_rooster_id, game_mode, taya_wager, winner_id, total_turns, match_duration_sec, status, ended_at)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'FINISHED', NOW());
                    """, (w_id, l_id, winner_rooster, loser_rooster, game_mode, taya_wager, w_id, turns, duration_sec))

                    cur.execute("""
                        INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                        VALUES (%s, 'WIN_PAYOUT', %s, %s, %s, 'Match Victory Bounty');
                    """, (w_id, prize, w_row["taya_coins"], new_w_bal))

            conn.close()
            log.info("[DB] Recorded match: %s won against %s (+%d Taya)", winner_username, loser_username, prize)
            return True
        except Exception as e:
            log.error("[DB] Error recording match result: %s", e)
            return False

# Global instance
db = DatabaseManager()
