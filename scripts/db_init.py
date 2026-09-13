import pymysql
import ssl
import sys

HOST = "gateway01.ap-southeast-1.prod.aws.tidbcloud.com"
PORT = 4000
USER = "35JtqKVBmhS4TEY.root"
PASSWORD = "mw1hTTxq5b28o9FB"
DATABASE = "test"

ctx = ssl.create_default_context()

print("Connecting to TiDB Cloud...")
conn = pymysql.connect(
    host=HOST,
    port=PORT,
    user=USER,
    password=PASSWORD,
    database=DATABASE,
    ssl=ctx,
    autocommit=True
)

ddl_statements = [
    "CREATE DATABASE IF NOT EXISTS sabong_roosters_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;",
    "USE sabong_roosters_db;",
    
    # 1. Players Table
    """CREATE TABLE IF NOT EXISTS players (
        player_id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL UNIQUE,
        email VARCHAR(100) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        taya_coins INT UNSIGNED NOT NULL DEFAULT 500,
        total_matches INT UNSIGNED NOT NULL DEFAULT 0,
        wins INT UNSIGNED NOT NULL DEFAULT 0,
        losses INT UNSIGNED NOT NULL DEFAULT 0,
        elo_rating INT NOT NULL DEFAULT 1000,
        rank_tier ENUM('BRONZE', 'SILVER', 'GOLD', 'PLATINUM', 'DIAMOND', 'MASTER', 'GRANDMASTER') NOT NULL DEFAULT 'BRONZE',
        status ENUM('ACTIVE', 'SUSPENDED', 'BANNED') NOT NULL DEFAULT 'ACTIVE',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP NULL DEFAULT NULL,
        INDEX idx_players_elo (elo_rating DESC),
        INDEX idx_players_username (username)
    ) ENGINE=InnoDB;""",

    # 2. Rooster Champions Catalog
    """CREATE TABLE IF NOT EXISTS roosters (
        rooster_id VARCHAR(32) PRIMARY KEY,
        display_name VARCHAR(64) NOT NULL,
        anime_reference VARCHAR(100) NOT NULL,
        base_hp INT UNSIGNED NOT NULL DEFAULT 20,
        passive_name VARCHAR(64) NOT NULL,
        passive_description TEXT NOT NULL,
        model_path VARCHAR(255) NOT NULL,
        dice_model_path VARCHAR(255) NULL,
        theme_color VARCHAR(16) NOT NULL DEFAULT '#FF4D4D',
        is_unlocked_default BOOLEAN NOT NULL DEFAULT TRUE
    ) ENGINE=InnoDB;""",

    # 3. Card Catalog
    """CREATE TABLE IF NOT EXISTS cards (
        card_id VARCHAR(64) PRIMARY KEY,
        display_name VARCHAR(64) NOT NULL,
        card_type ENUM('ATTACK', 'GUARD', 'HEAL', 'DOT', 'SPECIAL') NOT NULL,
        is_universal BOOLEAN NOT NULL DEFAULT FALSE,
        character_id VARCHAR(32) NULL,
        taya_cost TINYINT UNSIGNED NOT NULL DEFAULT 1,
        is_variable_cost BOOLEAN NOT NULL DEFAULT FALSE,
        dice_requirement TINYINT UNSIGNED NOT NULL DEFAULT 1,
        base_value INT NOT NULL DEFAULT 0,
        value_per_taya INT NOT NULL DEFAULT 0,
        self_damage INT UNSIGNED NOT NULL DEFAULT 0,
        usage_gate ENUM('ALWAYS', 'STATE_LOCKED', 'ONCE_PER_MATCH', 'REACTIVE') NOT NULL DEFAULT 'ALWAYS',
        buff_stat VARCHAR(32) NULL,
        buff_amount INT NOT NULL DEFAULT 0,
        buff_duration TINYINT UNSIGNED NOT NULL DEFAULT 0,
        art_path VARCHAR(255) NOT NULL,
        vfx_type VARCHAR(32) NULL,
        FOREIGN KEY (character_id) REFERENCES roosters(rooster_id) ON DELETE SET NULL
    ) ENGINE=InnoDB;""",

    # 4. Player Custom Decks
    """CREATE TABLE IF NOT EXISTS decks (
        deck_id INT AUTO_INCREMENT PRIMARY KEY,
        player_id INT NOT NULL,
        deck_name VARCHAR(64) NOT NULL DEFAULT 'Custom Deck',
        rooster_id VARCHAR(32) NOT NULL,
        is_active BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
        FOREIGN KEY (rooster_id) REFERENCES roosters(rooster_id) ON DELETE RESTRICT
    ) ENGINE=InnoDB;""",

    # 5. Deck Cards Junction
    """CREATE TABLE IF NOT EXISTS deck_cards (
        id INT AUTO_INCREMENT PRIMARY KEY,
        deck_id INT NOT NULL,
        card_id VARCHAR(64) NOT NULL,
        slot_index TINYINT UNSIGNED NOT NULL,
        quantity TINYINT UNSIGNED NOT NULL DEFAULT 1,
        FOREIGN KEY (deck_id) REFERENCES decks(deck_id) ON DELETE CASCADE,
        FOREIGN KEY (card_id) REFERENCES cards(card_id) ON DELETE RESTRICT,
        UNIQUE KEY uq_deck_slot (deck_id, slot_index)
    ) ENGINE=InnoDB;""",

    # 6. Match Sessions
    """CREATE TABLE IF NOT EXISTS matches (
        match_id INT AUTO_INCREMENT PRIMARY KEY,
        player1_id INT NOT NULL,
        player2_id INT NOT NULL,
        p1_rooster_id VARCHAR(32) NOT NULL,
        p2_rooster_id VARCHAR(32) NOT NULL,
        game_mode ENUM('VERSUS_1V1', 'CASUAL_BOTS', 'TOURNAMENT_ONLINE', 'TUTORIAL') NOT NULL DEFAULT 'TOURNAMENT_ONLINE',
        taya_wager INT UNSIGNED NOT NULL DEFAULT 0,
        winner_id INT NULL,
        total_turns INT UNSIGNED NOT NULL DEFAULT 0,
        match_duration_sec INT UNSIGNED NOT NULL DEFAULT 0,
        status ENUM('PENDING', 'IN_PROGRESS', 'FINISHED', 'FORFEITED', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ended_at TIMESTAMP NULL DEFAULT NULL,
        FOREIGN KEY (player1_id) REFERENCES players(player_id) ON DELETE RESTRICT,
        FOREIGN KEY (player2_id) REFERENCES players(player_id) ON DELETE RESTRICT,
        FOREIGN KEY (p1_rooster_id) REFERENCES roosters(rooster_id) ON DELETE RESTRICT,
        FOREIGN KEY (p2_rooster_id) REFERENCES roosters(rooster_id) ON DELETE RESTRICT,
        FOREIGN KEY (winner_id) REFERENCES players(player_id) ON DELETE SET NULL,
        INDEX idx_matches_p1 (player1_id),
        INDEX idx_matches_p2 (player2_id),
        INDEX idx_matches_status (status)
    ) ENGINE=InnoDB;""",

    # 7. Match Turn Logs
    """CREATE TABLE IF NOT EXISTS match_turn_logs (
        turn_log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
        match_id INT NOT NULL,
        turn_number INT UNSIGNED NOT NULL,
        p1_dice_roll TINYINT UNSIGNED NOT NULL,
        p2_dice_roll TINYINT UNSIGNED NOT NULL,
        p1_submitted_cards JSON NOT NULL,
        p2_submitted_cards JSON NOT NULL,
        p1_hp_start INT NOT NULL,
        p2_hp_start INT NOT NULL,
        p1_hp_end INT NOT NULL,
        p2_hp_end INT NOT NULL,
        events_json JSON NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE CASCADE,
        INDEX idx_turn_logs_match (match_id, turn_number)
    ) ENGINE=InnoDB;""",

    # 8. Taya Currency Transaction Ledger
    """CREATE TABLE IF NOT EXISTS taya_transactions (
        transaction_id BIGINT AUTO_INCREMENT PRIMARY KEY,
        player_id INT NOT NULL,
        match_id INT NULL,
        transaction_type ENUM('MATCH_WAGER_ESCROW', 'WIN_PAYOUT', 'REFUND', 'DAILY_LOGIN', 'ADMIN_ADJUSTMENT') NOT NULL,
        amount INT NOT NULL,
        balance_before INT UNSIGNED NOT NULL,
        balance_after INT UNSIGNED NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        description VARCHAR(255) NULL,
        FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE RESTRICT,
        FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE SET NULL,
        INDEX idx_trans_player (player_id, timestamp DESC)
    ) ENGINE=InnoDB;""",

    # 9. Competitive Leaderboards
    """CREATE TABLE IF NOT EXISTS leaderboards (
        leaderboard_id INT AUTO_INCREMENT PRIMARY KEY,
        player_id INT NOT NULL UNIQUE,
        season_number INT UNSIGNED NOT NULL DEFAULT 1,
        elo_rating INT NOT NULL DEFAULT 1000,
        rank_tier ENUM('BRONZE', 'SILVER', 'GOLD', 'PLATINUM', 'DIAMOND', 'MASTER', 'GRANDMASTER') NOT NULL DEFAULT 'BRONZE',
        wins INT UNSIGNED NOT NULL DEFAULT 0,
        losses INT UNSIGNED NOT NULL DEFAULT 0,
        win_rate DECIMAL(5, 2) DEFAULT 0.00,
        peak_elo INT NOT NULL DEFAULT 1000,
        last_calculated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
        INDEX idx_leaderboard_rank (season_number, elo_rating DESC)
    ) ENGINE=InnoDB;""",

    # 10. System Audit Logs
    """CREATE TABLE IF NOT EXISTS system_audit_logs (
        log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
        admin_id INT NULL,
        action_type VARCHAR(64) NOT NULL,
        target_entity VARCHAR(64) NOT NULL,
        target_id VARCHAR(64) NOT NULL,
        old_values JSON NULL,
        new_values JSON NULL,
        ip_address VARCHAR(45) NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_audit_timestamp (timestamp DESC)
    ) ENGINE=InnoDB;"""
]

with conn.cursor() as cursor:
    for idx, stmt in enumerate(ddl_statements):
        try:
            cursor.execute(stmt)
            print(f"[{idx+1}/{len(ddl_statements)}] Executed DDL successfully.")
        except Exception as e:
            print(f"[ERROR] Step {idx+1} failed: {e}")
            sys.exit(1)

    cursor.execute("USE sabong_roosters_db;")
    cursor.execute("SHOW TABLES;")
    tables = cursor.fetchall()
    print("\n[SUCCESS] All tables created in 'sabong_roosters_db':")
    for t in tables:
        print(f"  - {t[0]}")

conn.close()
print("\n>>> DATABASE INITIALIZATION COMPLETED WITH 100% SUCCESS! <<<")
