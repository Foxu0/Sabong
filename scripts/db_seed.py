import pymysql
import ssl
import hashlib

HOST = "gateway01.ap-southeast-1.prod.aws.tidbcloud.com"
PORT = 4000
USER = "35JtqKVBmhS4TEY.root"
PASSWORD = "mw1hTTxq5b28o9FB"
DATABASE = "sabong_roosters_db"

ctx = ssl.create_default_context()
conn = pymysql.connect(
    host=HOST, port=PORT, user=USER, password=PASSWORD,
    database=DATABASE, ssl=ctx, autocommit=True
)

roosters_data = [
    ("hen_goku", "Hen-Goku", "Dragon Ball parody", 20, "Saiyan Grit", "Deals bonus damage when missing HP", "res://resources/roosters/hen_goku.tres", None, "#FFA500", True),
    ("cocktaro", "Cocktaro", "JoJo's Bizarre Adventure parody", 20, "Stand Aura", "Chance to counter-attack on shield block", "res://resources/roosters/cocktaro.tres", None, "#800080", True),
    ("decluck", "Decluck", "My Hero Academia parody", 20, "One For Cluck", "Variable taya scaling and full power strikes", "res://resources/roosters/decluck.tres", None, "#008000", True),
    ("cluckey_d_puffy", "Cluckey D Puffy", "One Piece parody", 20, "Rubber Body", "Absorbs physical impact and gear awakening", "res://resources/roosters/cluckey_d_puffy.tres", None, "#DC143C", True),
    ("eren_pecker", "Eren Pecker", "Attack on Titan parody", 20, "Titan Shifter", "Consumes HP for colossal strike damage", "res://resources/roosters/eren_pecker.tres", None, "#8B4513", True),
    ("chick_yagami", "Chick Yagami", "Death Note parody", 20, "Death Peck", "Applies deadly damage-over-time poison ticks", "res://resources/roosters/chick_yagami.tres", None, "#2F4F4F", True),
    ("nechicko", "Nechicko", "Demon Slayer parody", 20, "Blood Demon Cluck", "Charges Demonic Aura stacks for burst finish", "res://resources/roosters/nechicko.tres", None, "#FF69B4", True),
    ("daniel", "Daniel", "Re:Zero parody", 20, "Return by Death", "Turn-scaling claw power and survival revive", "res://resources/roosters/daniel.tres", None, "#4682B4", True),
]

def hash_pw(pw: str) -> str:
    return hashlib.sha256(pw.encode()).hexdigest()

players_data = [
    ("admin", "admin@sabong.ph", hash_pw("admin123"), 10000, 50, 42, 8, 1850, "GRANDMASTER"),
    ("DuelMaster_Goku", "goku@sabong.ph", hash_pw("goku123"), 2500, 20, 16, 4, 1520, "MASTER"),
    ("Vegeta_Pecker", "pecker@sabong.ph", hash_pw("pecker123"), 1200, 15, 9, 6, 1280, "DIAMOND"),
    ("Cocktaro_Fan", "jojo@sabong.ph", hash_pw("jojo123"), 800, 10, 5, 5, 1100, "GOLD"),
]

with conn.cursor() as cursor:
    print("Seeding Rooster Champions...")
    sql_rooster = """
        INSERT INTO roosters (rooster_id, display_name, anime_reference, base_hp, passive_name, passive_description, model_path, dice_model_path, theme_color, is_unlocked_default)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE display_name=VALUES(display_name), base_hp=VALUES(base_hp);
    """
    cursor.executemany(sql_rooster, roosters_data)
    print(f"  Inserted/Updated {len(roosters_data)} champions.")

    print("Seeding Demo Players & Leaderboard...")
    sql_player = """
        INSERT INTO players (username, email, password_hash, taya_coins, total_matches, wins, losses, elo_rating, rank_tier)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE elo_rating=VALUES(elo_rating), rank_tier=VALUES(rank_tier);
    """
    cursor.executemany(sql_player, players_data)
    
    # Sync leaderboard
    cursor.execute("""
        INSERT INTO leaderboards (player_id, season_number, elo_rating, rank_tier, wins, losses, peak_elo)
        SELECT player_id, 1, elo_rating, rank_tier, wins, losses, elo_rating
        FROM players
        ON DUPLICATE KEY UPDATE elo_rating=VALUES(elo_rating), rank_tier=VALUES(rank_tier), wins=VALUES(wins), losses=VALUES(losses);
    """)
    print(f"  Inserted/Updated {len(players_data)} demo players & synchronized leaderboards.")

    # Show leaderboard results
    cursor.execute("""
        SELECT p.username, l.rank_tier, l.elo_rating, l.wins, l.losses, p.taya_coins
        FROM leaderboards l
        JOIN players p ON l.player_id = p.player_id
        ORDER BY l.elo_rating DESC;
    """)
    rows = cursor.fetchall()
    print("\n--- CLOUD LEADERBOARD PREVIEW ---")
    for r in rows:
        print(f"  {r[0]:<16} | Tier: {r[1]:<12} | ELO: {r[2]} | W/L: {r[3]}/{r[4]} | Taya: {r[5]}")

conn.close()
print("\n>>> SEEDING COMPLETED SUCCESSFULLY! <<<")
