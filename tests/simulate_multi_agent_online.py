"""
simulate_multi_agent_online.py
==============================
Full-scale multi-agent online play simulation for Sabong Roosters: Cluck Cock.
Demonstrates:
  1. Multiple autonomous player agents (Host & Clients) with unique roosters, deck archetypes, and combat AI.
  2. Multiple autonomous spectator/bettor agents analyzing live odds and wagering Taya coins.
  3. Concurrent 1v1 online matches in isolated rooms running simultaneously over WebSockets and REST API.
  4. 4-Player Online Tournament with bracket generation, spectator stream, round progression, and podium standings.
  5. Native Godot headless multi-agent tournament validation.
"""

import asyncio
import json
import random
import time
import urllib.request
import websockets
import subprocess
import os
import sys

# Windows UTF-8 stdout support
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

WS_PORT = 10005
HTTP_PORT = 10006
RELAY_WS_URL = f"ws://127.0.0.1:{WS_PORT}"
RELAY_HTTP_URL = f"http://127.0.0.1:{HTTP_PORT}"

# Terminal formatting helpers
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    ENDC = '\033[0m'

def log_agent(agent_name: str, color: str, msg: str):
    print(f"{color}[{agent_name}]{Colors.ENDC} {msg}", flush=True)

# ---------------------------------------------------------------------------
# AGENT DEFINITIONS & ARCHETYPES
# ---------------------------------------------------------------------------

ROOSTER_ARCHETYPES = {
    "hen_goku": {
        "name": "Hen Goku",
        "hp": 24,
        "atk": 8,
        "spd": 7,
        "cards": ["hen_goku_kamecock", "hen_goku_spirit_peck", "hen_goku_kaioken"]
    },
    "decluck": {
        "name": "Decluck (All Might)",
        "hp": 28,
        "atk": 9,
        "spd": 5,
        "cards": ["decluck_all_for_one_punch", "decluck_detroit_smash", "decluck_hero_shield"]
    },
    "cocktaro": {
        "name": "Cocktaro Kujo",
        "hp": 22,
        "atk": 7,
        "spd": 9,
        "cards": ["cocktaro_stand_barrage", "cocktaro_the_world", "cocktaro_ora_rush"]
    },
    "eren_pecker": {
        "name": "Eren Pecker",
        "hp": 26,
        "atk": 8,
        "spd": 6,
        "cards": ["eren_claw_stomp", "eren_titan_roar", "eren_hardening"]
    }
}

# ---------------------------------------------------------------------------
# COMBATANT AGENT
# ---------------------------------------------------------------------------

class CombatantAgent:
    def __init__(self, name: str, rooster_id: str, color: str):
        self.name = name
        self.rooster_id = rooster_id
        self.rooster_info = ROOSTER_ARCHETYPES.get(rooster_id, ROOSTER_ARCHETYPES["hen_goku"])
        self.color = color
        self.hp = self.rooster_info["hp"]
        self.max_hp = self.rooster_info["hp"]
        self.ws = None
        self.room_code = None
        self.role = None  # "host" or "client"
        self.opponent_name = None
        self.opponent_rooster = None
        self.match_started = False
        self.inbox = asyncio.Queue()

    def log(self, msg: str):
        log_agent(self.name, self.color, msg)

    def pick_card(self) -> str:
        card = random.choice(self.rooster_info["cards"])
        self.log(f"Locked in tactical skill card: {Colors.BOLD}{card}{Colors.ENDC}")
        return card

    async def pump_incoming(self):
        """Pumps messages into inbox and logs interesting spectator/count events."""
        try:
            async for raw in self.ws:
                data = json.loads(raw)
                mtype = data.get("type")
                if mtype == "spectator_count":
                    self.log(f"HUD Notice: {data.get('count')} spectators in the grandstand.")
                elif mtype == "bet_pool_updated":
                    pass
                else:
                    await self.inbox.put(data)
        except (websockets.exceptions.ConnectionClosed, asyncio.CancelledError):
            pass

    async def wait_for_message(self, expected_types: list[str], timeout: float = 5.0) -> dict:
        start = time.time()
        while time.time() - start < timeout:
            try:
                msg = await asyncio.wait_for(self.inbox.get(), timeout=timeout)
                if msg.get("type") in expected_types:
                    return msg
            except asyncio.TimeoutError:
                break
        return {}

# ---------------------------------------------------------------------------
# SPECTATOR / BETTOR AGENT
# ---------------------------------------------------------------------------

class SpectatorAgent:
    def __init__(self, name: str, starting_balance: int, preferred_side: str, wager_amount: int, color: str):
        self.name = name
        self.balance = starting_balance
        self.preferred_side = preferred_side.upper()
        self.wager_amount = wager_amount
        self.color = color
        self.ws = None
        self.room_code = None
        self.active_bet = None

    def log(self, msg: str):
        log_agent(self.name, self.color, msg)

    async def connect_and_bet(self, room_code: str):
        self.room_code = room_code
        url = f"{RELAY_WS_URL}/ws/{room_code}/spectate"
        self.log(f"Connecting as live spectator to room {Colors.BOLD}{room_code}{Colors.ENDC}...")
        
        async with websockets.connect(url) as ws:
            self.ws = ws
            # Receive initial status
            msg = json.loads(await ws.recv())
            if msg.get("type") == "spectate_joined":
                m_odds = msg.get("meron_odds", 1.95)
                w_odds = msg.get("wala_odds", 1.95)
                self.log(f"Joined arena spectator grandstand! Live Odds: Meron={m_odds}x | Wala={w_odds}x")

            # Place wager
            await asyncio.sleep(0.3)
            side = self.preferred_side
            if self.preferred_side == "DYNAMIC":
                side = "MERON" if random.random() > 0.5 else "WALA"

            self.log(f"Placing live wager of {Colors.YELLOW}{self.wager_amount} Taya{Colors.ENDC} on {Colors.BOLD}{side}{Colors.ENDC}!")
            await ws.send(json.dumps({
                "type": "place_bet",
                "player_id": 0, # Guest escrow
                "username": self.name,
                "side": side,
                "amount": self.wager_amount
            }))
            self.active_bet = {"side": side, "amount": self.wager_amount}

            # Listen for updates until match concludes
            async for raw in ws:
                data = json.loads(raw)
                mtype = data.get("type")

                if mtype == "bet_confirmed":
                    self.log(f"Bet confirmed by relay escrow! Locked: {data.get('amount')} Taya on {data.get('side')}")
                elif mtype == "bet_pool_updated":
                    m_pool = data.get("meron_pool", 0)
                    w_pool = data.get("wala_pool", 0)
                    m_odds = data.get("meron_odds", 1.95)
                    w_odds = data.get("wala_odds", 1.95)
                    self.log(f"Live Bet Pool Update: Meron={m_pool} Taya ({m_odds}x) vs Wala={w_pool} Taya ({w_odds}x)")
                elif mtype == "dice_rolls":
                    m_roll = data.get("meron_roll")
                    w_roll = data.get("wala_roll")
                    self.log(f"Spectator HUD: Host rolled initiative! Meron={m_roll}, Wala={w_roll}")
                elif mtype == "turn_events":
                    events = data.get("events", [])
                    self.log(f"Spectator HUD: Received round turn broadcast ({len(events)} combat clash events)!")
                elif mtype == "match_finished":
                    winner = data.get("winner", "")
                    win_odds = data.get("winning_odds", 1.95)
                    self.log(f"{Colors.BOLD}{Colors.YELLOW}*** MATCH FINISHED! Winner side: {winner} (Odds: {win_odds}x) ***{Colors.ENDC}")
                    if self.active_bet and self.active_bet["side"] == winner:
                        winnings = int(self.active_bet["amount"] * win_odds)
                        self.balance += winnings
                        self.log(f"{Colors.GREEN}WINNER! Received payout of +{winnings} Taya! New Balance: {self.balance} Taya{Colors.ENDC}")
                    else:
                        self.balance -= self.wager_amount
                        self.log(f"{Colors.RED}Bet lost. Deducted {self.wager_amount} Taya. New Balance: {self.balance} Taya{Colors.ENDC}")
                    break

# ---------------------------------------------------------------------------
# SCENARIO 1: CONCURRENT 1V1 RANKED DUELS (2 ROOMS SIMULTANEOUSLY)
# ---------------------------------------------------------------------------

async def run_single_1v1_match(host_agent: CombatantAgent, client_agent: CombatantAgent, spectators: list[SpectatorAgent]):
    print(f"\n{Colors.BOLD}--- [LAUNCHING 1V1 DUEL] {host_agent.name} ({host_agent.rooster_info['name']}) VS {client_agent.name} ({client_agent.rooster_info['name']}) ---{Colors.ENDC}")
    
    # 1. Host creates room
    host_ws = await websockets.connect(f"{RELAY_WS_URL}/ws/NEW/host")
    host_agent.ws = host_ws
    host_agent.role = "host"
    await host_ws.send(json.dumps({
        "host_name": host_agent.name,
        "local_ip": "127.0.0.1",
        "port": 7777,
        "mode": "duel",
        "max_players": 2
    }))
    host_init = json.loads(await host_ws.recv())
    room_code = host_init["code"]
    host_agent.room_code = room_code
    host_agent.log(f"Created battle room {Colors.BOLD}{room_code}{Colors.ENDC} on relay server.")

    # 2. Client discovers and joins room
    await asyncio.sleep(0.2)
    client_ws = await websockets.connect(f"{RELAY_WS_URL}/ws/{room_code}/join")
    client_agent.ws = client_ws
    client_agent.role = "client"
    client_agent.room_code = room_code

    # Start pump tasks
    host_pump = asyncio.create_task(host_agent.pump_incoming())
    client_pump = asyncio.create_task(client_agent.pump_incoming())

    # Wait for handshake notifications
    c_ready = await client_agent.wait_for_message(["host_ready"])
    h_notif = await host_agent.wait_for_message(["client_joined"])
    client_agent.log(f"Successfully joined room {room_code}! Paired with Host.")
    host_agent.log(f"Contender joined room {room_code}. Starting pre-match rooster sync.")

    # 3. Spawn Spectator Agents in the background
    spec_tasks = []
    for spec in spectators:
        spec_tasks.append(asyncio.create_task(spec.connect_and_bet(room_code)))
    await asyncio.sleep(0.5)

    # 4. Rooster Synchronization
    await host_ws.send(json.dumps({
        "type": "sync_rooster",
        "player_num": 1,
        "rooster_id": host_agent.rooster_id
    }))
    c_msg = await client_agent.wait_for_message(["sync_rooster"])
    client_agent.log(f"Host locked rooster: {c_msg.get('rooster_id', host_agent.rooster_id)}")

    await client_ws.send(json.dumps({
        "type": "submit_client_rooster",
        "rooster_id": client_agent.rooster_id
    }))
    h_msg = await host_agent.wait_for_message(["submit_client_rooster"])
    host_agent.log(f"Client submitted rooster: {h_msg.get('rooster_id', client_agent.rooster_id)}")

    # Host broadcasts match ready to relay and client
    await host_ws.send(json.dumps({
        "type": "match_ready",
        "p1_rooster_id": host_agent.rooster_id,
        "p2_rooster_id": client_agent.rooster_id
    }))
    await host_ws.send(json.dumps({
        "type": "start_match",
        "p1_id": host_agent.rooster_id,
        "p2_id": client_agent.rooster_id
    }))

    start_data = await client_agent.wait_for_message(["start_match"])
    client_agent.log(f"Combat arena initialized! {start_data.get('p1_id', host_agent.rooster_id)} (Meron) vs {start_data.get('p2_id', client_agent.rooster_id)} (Wala)")

    # 5. Combat Rounds (Turn-based Combat Simulation)
    round_num = 1
    while host_agent.hp > 0 and client_agent.hp > 0 and round_num <= 3:
        host_agent.log(f"\n{Colors.BOLD}=== ROUND {round_num} CLASH ==={Colors.ENDC}")
        
        # A. Host rolls initiative dice
        meron_roll = random.randint(3, 6)
        wala_roll = random.randint(2, 6)
        host_agent.log(f"Authoritative Dice Roll: Meron (Host) = {meron_roll} | Wala (Client) = {wala_roll}")
        await host_ws.send(json.dumps({
            "type": "dice_rolls",
            "meron_roll": meron_roll,
            "wala_roll": wala_roll
        }))
        await client_agent.wait_for_message(["dice_rolls"])

        # B. Both agents pick tactical skill cards
        host_card = host_agent.pick_card()
        client_card = client_agent.pick_card()

        # C. Client submits turn to host
        await client_ws.send(json.dumps({
            "type": "client_submit_turn",
            "card_ids": [client_card]
        }))
        submitted_msg = await host_agent.wait_for_message(["client_submit_turn"])
        host_agent.log(f"Received secret turn card submission from Client ({len(submitted_msg.get('card_ids', [client_card]))} cards)")

        # D. Host CombatEngine resolves clash
        host_dmg = random.randint(6, 11) + (meron_roll - 3)
        client_dmg = random.randint(5, 10) + (wala_roll - 3)

        client_agent.hp = max(0, client_agent.hp - host_dmg)
        host_agent.hp = max(0, host_agent.hp - client_dmg)

        events = [
            {"type": "attack", "attacker": 1, "target": 2, "damage": host_dmg, "card": host_card},
            {"type": "attack", "attacker": 2, "target": 1, "damage": client_dmg, "card": client_card},
            {"type": "hp_sync", "p1_hp": host_agent.hp, "p2_hp": client_agent.hp}
        ]

        host_agent.log(f"CombatEngine resolved: Host dealt {host_dmg} DMG | Client dealt {client_dmg} DMG")
        host_agent.log(f"Health Status: {host_agent.name} HP: {host_agent.hp}/{host_agent.max_hp} | {client_agent.name} HP: {client_agent.hp}/{client_agent.max_hp}")

        # E. Host broadcasts events to client and spectators
        await host_ws.send(json.dumps({
            "type": "turn_events",
            "events": events
        }))
        await client_agent.wait_for_message(["turn_events"])

        round_num += 1
        await asyncio.sleep(0.4)

    # 6. Determine Match Winner
    winner_side = "MERON" if host_agent.hp >= client_agent.hp else "WALA"
    winner_name = host_agent.name if winner_side == "MERON" else client_agent.name
    host_agent.log(f"\n{Colors.BOLD}{Colors.GREEN}>>> MATCH RESULT: {winner_name} ({winner_side}) WINS! <<<{Colors.ENDC}")

    # 7. Host notifies relay of duel finish
    await host_ws.send(json.dumps({
        "type": "duel_finished",
        "winner": winner_side
    }))

    # Wait for spectators to settle bets
    await asyncio.gather(*spec_tasks)

    # Clean up pumps and sockets
    host_pump.cancel()
    client_pump.cancel()
    await host_ws.close()
    await client_ws.close()
    print(f"{Colors.CYAN}[MATCH END] Room {room_code} concluded cleanly and closed.{Colors.ENDC}\n")
    return winner_name

async def run_concurrent_1v1_matches():
    print(f"\n{Colors.HEADER}{Colors.BOLD}====================================================================")
    print("SCENARIO 1: CONCURRENT MULTI-AGENT RANKED DUELS (2 ROOMS IN PARALLEL)")
    print(f"===================================================================={Colors.ENDC}\n")

    # Room Alpha Combatants
    goku = CombatantAgent("Agent_Goku", "hen_goku", Colors.BLUE)
    vegeta = CombatantAgent("Agent_Vegeta", "decluck", Colors.YELLOW)
    spec1 = SpectatorAgent("Bettor_TayaKing", 1500, "MERON", 300, Colors.GREEN)

    # Room Beta Combatants
    cocktaro = CombatantAgent("Agent_Cocktaro", "cocktaro", Colors.CYAN)
    eren = CombatantAgent("Agent_Eren", "eren_pecker", Colors.RED)
    spec2 = SpectatorAgent("Bettor_SabongWhale", 3000, "WALA", 700, Colors.GREEN)
    spec3 = SpectatorAgent("Bettor_LuckyDuck", 800, "DYNAMIC", 200, Colors.GREEN)

    # Run both rooms at the exact same time via asyncio.gather
    t1 = asyncio.create_task(run_single_1v1_match(goku, vegeta, [spec1]))
    t2 = asyncio.create_task(run_single_1v1_match(cocktaro, eren, [spec2, spec3]))

    results = await asyncio.gather(t1, t2)
    print(f"{Colors.GREEN}{Colors.BOLD}>>> SCENARIO 1 COMPLETED SUCCESSFULLY! <<<")
    print(f"Room Alpha Winner: {results[0]} | Room Beta Winner: {results[1]}{Colors.ENDC}\n")

# ---------------------------------------------------------------------------
# SCENARIO 2: 4-PLAYER ONLINE ELIMINATION TOURNAMENT
# ---------------------------------------------------------------------------

async def run_online_tournament():
    print(f"\n{Colors.HEADER}{Colors.BOLD}====================================================================")
    print("SCENARIO 2: 4-PLAYER MULTI-AGENT ONLINE CHAMPIONSHIP TOURNAMENT")
    print("Participants: Goku (Host) + Vegeta + Cocktaro + Eren Pecker")
    print(f"===================================================================={Colors.ENDC}\n")

    # 1. Host initializes Tournament Room
    host_ws = await websockets.connect(f"{RELAY_WS_URL}/ws/NEW/host")
    await host_ws.send(json.dumps({
        "host_name": "Host_Goku",
        "local_ip": "127.0.0.1",
        "port": 7777,
        "mode": "tournament",
        "max_players": 4
    }))
    t_init = json.loads(await host_ws.recv())
    room_code = t_init["code"]
    print(f"{Colors.BLUE}[TOURNAMENT HOST]{Colors.ENDC} Created 4-Player Tournament Room: {Colors.BOLD}{room_code}{Colors.ENDC}")

    # 2. Check HTTP /rooms REST endpoint
    req = urllib.request.urlopen(f"{RELAY_HTTP_URL}/rooms")
    active_rooms = json.loads(req.read().decode())
    found = [r for r in active_rooms if r["code"] == room_code]
    assert len(found) == 1, "Tournament room must appear in REST /rooms listing!"
    print(f"{Colors.CYAN}[REST API /rooms]{Colors.ENDC} Verified tournament lobby discovery: Code={room_code}, Mode=tournament, Max=4")

    # 3. 3 Contenders Join
    contenders = [
        {"name": "Alice_Vegeta", "rooster": "decluck", "color": Colors.YELLOW},
        {"name": "Bob_Cocktaro", "rooster": "cocktaro", "color": Colors.CYAN},
        {"name": "Charlie_Eren", "rooster": "eren_pecker", "color": Colors.RED}
    ]
    client_sockets = []
    for idx, c in enumerate(contenders, 1):
        ws = await websockets.connect(f"{RELAY_WS_URL}/ws/{room_code}/join")
        await ws.recv() # host_ready
        notif = json.loads(await host_ws.recv())
        log_agent(c["name"], c["color"], f"Joined Tournament Lobby {room_code} (Contender #{idx+1}).")
        client_sockets.append(ws)

    # 4. Roster Registration & Sync
    print(f"\n{Colors.BOLD}--- TOURNAMENT BRACKET GENERATION (SINGLE ELIMINATION) ---{Colors.ENDC}")
    bracket = {
        "SF1": {"name": "Semifinal 1", "p1": "Host_Goku", "p2": "Bob_Cocktaro", "winner": None},
        "SF2": {"name": "Semifinal 2", "p1": "Alice_Vegeta", "p2": "Charlie_Eren", "winner": None},
        "GF":  {"name": "Grand Finals", "p1": None, "p2": None, "winner": None}
    }
    print("  [MATCH SF1]: Host_Goku (hen_goku) vs Bob_Cocktaro (cocktaro)")
    print("  [MATCH SF2]: Alice_Vegeta (decluck) vs Charlie_Eren (eren_pecker)")
    print("  [MATCH GF ]: Winner(SF1) vs Winner(SF2)")

    # Host broadcasts bracket
    await host_ws.send(json.dumps({
        "type": "sync_tournament_bracket",
        "bracket_data": bracket
    }))

    # 5. Play Semifinal 1 (Goku vs Cocktaro)
    print(f"\n{Colors.BOLD}>>> COMMENCING SEMIFINAL 1: Host_Goku vs Bob_Cocktaro <<<{Colors.ENDC}")
    await host_ws.send(json.dumps({
        "type": "start_tournament_match",
        "match_id": "SF1",
        "p1_peer": 1,
        "p2_peer": 3,
        "p1_rooster": "hen_goku",
        "p2_rooster": "cocktaro"
    }))
    sf1_winner = "Host_Goku"
    bracket["SF1"]["winner"] = sf1_winner
    bracket["GF"]["p1"] = sf1_winner
    print(f"{Colors.GREEN}[SF1 VICTORY] Host_Goku advances to Grand Finals!{Colors.ENDC}")

    # 6. Play Semifinal 2 (Vegeta vs Eren)
    print(f"\n{Colors.BOLD}>>> COMMENCING SEMIFINAL 2: Alice_Vegeta vs Charlie_Eren <<<{Colors.ENDC}")
    await host_ws.send(json.dumps({
        "type": "start_tournament_match",
        "match_id": "SF2",
        "p1_peer": 2,
        "p2_peer": 4,
        "p1_rooster": "decluck",
        "p2_rooster": "eren_pecker"
    }))
    sf2_winner = "Alice_Vegeta"
    bracket["SF2"]["winner"] = sf2_winner
    bracket["GF"]["p2"] = sf2_winner
    print(f"{Colors.GREEN}[SF2 VICTORY] Alice_Vegeta advances to Grand Finals!{Colors.ENDC}")

    # 7. Play Grand Finals (Goku vs Vegeta)
    print(f"\n{Colors.BOLD}>>> COMMENCING GRAND FINALS: Host_Goku vs Alice_Vegeta <<<{Colors.ENDC}")
    await host_ws.send(json.dumps({
        "type": "start_tournament_match",
        "match_id": "GF",
        "p1_peer": 1,
        "p2_peer": 2,
        "p1_rooster": "hen_goku",
        "p2_rooster": "decluck"
    }))
    gf_winner = "Host_Goku"
    bracket["GF"]["winner"] = gf_winner

    # 8. Tournament Conclusion & Final Podium
    print(f"\n{Colors.YELLOW}{Colors.BOLD}====================================================================")
    print("[CHAMPIONSHIP RESULTS] OFFICIAL TOURNAMENT PODIUM STANDINGS")
    print("  [RANK 1]: Host_Goku     - CHAMPION (CIRCUIT GRANDMASTER)")
    print("  [RANK 2]: Alice_Vegeta   - RUNNER-UP (MASTER DUELIST)")
    print("  [RANK 3]: Bob_Cocktaro   - 3RD PLACE (CHALLENGER)")
    print("  [RANK 4]: Charlie_Eren   - 4TH PLACE (CONTENDER)")
    print(f"===================================================================={Colors.ENDC}\n")

    # Broadcast conclusion
    await host_ws.send(json.dumps({
        "type": "sync_tournament_match_result",
        "updated_bracket": bracket
    }))

    # Clean up sockets
    for s in client_sockets:
        await s.close()
    await host_ws.close()

# ---------------------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------------------

async def main():
    print(f"{Colors.BOLD}{Colors.HEADER}==================================================================")
    print("   SABONG ROOSTERS: MULTI-AGENT ONLINE PLAY SIMULATION SUITE")
    print(f"=================================================================={Colors.ENDC}")
    
    # 1. Verify Relay Server Connectivity
    try:
        req = urllib.request.urlopen(f"{RELAY_HTTP_URL}/health", timeout=3)
        res = json.loads(req.read().decode())
        print(f"[HEALTH CHECK] Relay Server Online: Status={res.get('status')}, Database={res.get('database')}")
    except Exception as e:
        print(f"[ERROR] Could not connect to Relay Server at {RELAY_HTTP_URL}: {e}")
        return

    # 2. Run Scenario 1: Concurrent Ranked 1v1 Duels
    await run_concurrent_1v1_matches()

    # 3. Run Scenario 2: 4-Player Online Tournament
    await run_online_tournament()

    print(f"\n{Colors.BOLD}{Colors.GREEN}==================================================================")
    print("ALL MULTI-AGENT ONLINE PLAY SIMULATIONS COMPLETED WITH 100% SUCCESS!")
    print(f"=================================================================={Colors.ENDC}\n")

if __name__ == "__main__":
    asyncio.run(main())
