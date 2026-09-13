"""
Sabong Roosters - Cloud Database Manager
Interfacing with TiDB Cloud MySQL 8.0 (sabong_roosters_db)
"""

import os
import ssl
import logging
import hashlib
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

    def get_leaderboard(self, limit: int = 10) -> List[Dict[str, Any]]:
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                sql = """
                    SELECT 
                        p.username, 
                        l.rank_tier, 
                        l.elo_rating, 
                        l.wins, 
                        l.losses, 
                        p.taya_coins
                    FROM leaderboards l
                    JOIN players p ON l.player_id = p.player_id
                    ORDER BY l.elo_rating DESC
                    LIMIT %s;
                """
                cur.execute(sql, (limit,))
                results = cur.fetchall()
            conn.close()
            return results
        except Exception as e:
            log.error("[DB] Error fetching leaderboard: %s", e)
            return []

    def register_player(self, username: str, email: str, password: str) -> Dict[str, Any]:
        username = username.strip()
        email = email.strip()
        if len(username) < 3 or len(password) < 4:
            return {"success": False, "error": "Username/Password too short"}
        
        pw_hash = _hash_password(password)
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                # Check existing
                cur.execute("SELECT player_id FROM players WHERE username=%s OR email=%s;", (username, email))
                if cur.fetchone():
                    conn.close()
                    return {"success": False, "error": "Username or Email already registered"}

                sql_insert = """
                    INSERT INTO players (username, email, password_hash, taya_coins, elo_rating, rank_tier)
                    VALUES (%s, %s, %s, 500, 1000, 'BRONZE');
                """
                cur.execute(sql_insert, (username, email, pw_hash))
                pid = cur.lastrowid

                # Create initial leaderboard record
                sql_lb = """
                    INSERT INTO leaderboards (player_id, season_number, elo_rating, rank_tier, wins, losses, peak_elo)
                    VALUES (%s, 1, 1000, 'BRONZE', 0, 0, 1000);
                """
                cur.execute(sql_lb, (pid,))

            conn.close()
            return {
                "success": True,
                "player_id": pid,
                "username": username,
                "taya_coins": 500,
                "elo_rating": 1000,
                "rank_tier": "BRONZE"
            }
        except Exception as e:
            log.error("[DB] Registration error: %s", e)
            return {"success": False, "error": str(e)}

    def authenticate_player(self, username: str, password: str) -> Dict[str, Any]:
        pw_hash = _hash_password(password)
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                sql = """
                    SELECT player_id, username, taya_coins, elo_rating, rank_tier, wins, losses, total_matches
                    FROM players
                    WHERE (username=%s OR email=%s) AND password_hash=%s AND status='ACTIVE';
                """
                cur.execute(sql, (username, username, pw_hash))
                player = cur.fetchone()
                if not player:
                    conn.close()
                    return {"success": False, "error": "Invalid username or password"}

                cur.execute("UPDATE players SET last_login=NOW() WHERE player_id=%s;", (player["player_id"],))
            conn.close()
            return {
                "success": True,
                "player_id": player["player_id"],
                "username": player["username"],
                "taya_coins": player["taya_coins"],
                "elo_rating": player["elo_rating"],
                "rank_tier": player["rank_tier"],
                "wins": player["wins"],
                "losses": player["losses"],
                "total_matches": player["total_matches"]
            }
        except Exception as e:
            log.error("[DB] Auth error: %s", e)
            return {"success": False, "error": str(e)}

    def record_match_result(self, winner_username: str, loser_username: str, winner_rooster: str, loser_rooster: str, game_mode: str = "TOURNAMENT_ONLINE", taya_wager: int = 50, turns: int = 3, duration_sec: int = 45) -> bool:
        try:
            conn = self.get_connection()
            with conn.cursor() as cur:
                # Find player IDs if exist
                cur.execute("SELECT player_id, elo_rating, taya_coins FROM players WHERE username=%s;", (winner_username,))
                w_row = cur.fetchone()
                cur.execute("SELECT player_id, elo_rating, taya_coins FROM players WHERE username=%s;", (loser_username,))
                l_row = cur.fetchone()

                w_id = w_row["player_id"] if w_row else None
                l_id = l_row["player_id"] if l_row else None

                if w_id and l_id:
                    # Update wins, losses, elo (+25 / -20)
                    new_w_elo = w_row["elo_rating"] + 25
                    new_l_elo = max(800, l_row["elo_rating"] - 20)
                    prize = taya_wager * 2

                    cur.execute("""
                        UPDATE players 
                        SET wins = wins + 1, total_matches = total_matches + 1, elo_rating = %s, taya_coins = taya_coins + %s
                        WHERE player_id = %s;
                    """, (new_w_elo, prize, w_id))

                    cur.execute("""
                        UPDATE players 
                        SET losses = losses + 1, total_matches = total_matches + 1, elo_rating = %s
                        WHERE player_id = %s;
                    """, (new_l_elo, l_id))

                    # Update leaderboards
                    cur.execute("""
                        UPDATE leaderboards
                        SET wins = wins + 1, elo_rating = %s, peak_elo = GREATEST(peak_elo, %s)
                        WHERE player_id = %s;
                    """, (new_w_elo, new_w_elo, w_id))

                    cur.execute("""
                        UPDATE leaderboards
                        SET losses = losses + 1, elo_rating = %s
                        WHERE player_id = %s;
                    """, (new_l_elo, l_id))

                    # Insert match record
                    cur.execute("""
                        INSERT INTO matches (player1_id, player2_id, p1_rooster_id, p2_rooster_id, game_mode, taya_wager, winner_id, total_turns, match_duration_sec, status, ended_at)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'FINISHED', NOW());
                    """, (w_id, l_id, winner_rooster, loser_rooster, game_mode, taya_wager, w_id, turns, duration_sec))

                    # Insert taya payout transaction
                    cur.execute("""
                        INSERT INTO taya_transactions (player_id, transaction_type, amount, balance_before, balance_after, description)
                        VALUES (%s, 'WIN_PAYOUT', %s, %s, %s, 'Tournament Match Victory');
                    """, (w_id, prize, w_row["taya_coins"], w_row["taya_coins"] + prize))

            conn.close()
            log.info("[DB] Successfully recorded match outcome between %s and %s", winner_username, loser_username)
            return True
        except Exception as e:
            log.error("[DB] Error recording match result: %s", e)
            return False

# Global instance
db = DatabaseManager()
