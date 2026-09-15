# Sabong Roosters: Comprehensive DDoS, Sybil & Abuse Defense Architecture

## 1. Executive Summary & Defense-in-Depth Model

Online multiplayer games with open account creation face three major threats:
1. **Application-Layer DDoS (L7)**: Flooding endpoints like `/leaderboard` or `/rooms` to exhaust server CPU and database connections.
2. **Sybil Attacks / Botnet Account Spawning**: Scripted bots rapidly generating thousands of fake accounts to pollute leaderboards, hoard usernames, or manipulate matchmaking.
3. **Credential Stuffing & Brute-Force**: Automated password dictionaries hammering `/auth/login` to compromise user accounts.

To solve this while keeping development local and prepared for cloud hosting, Sabong Roosters employs a **two-tier defense architecture**:
- **Tier 1 (In-Code Application Defense)**: Real-time sliding-window rate limiting, payload capping, memory caching, and brute-force lockouts directly in Python with **zero database load**.
- **Tier 2 (Cloudflare Edge Shield)**: When deployed to production, all traffic routes through Cloudflare’s global Anycast network, stopping volumetric attacks at the edge before packets even reach your host.

---

## 2. In-Code Application Security Engine (`security.py`)

The game server is protected by an in-memory, thread-safe security engine that operates in $O(1)$ time per request:

| Protection Mechanism | Policy / Limit | Action on Breach | Header / Signal |
| :--- | :--- | :--- | :--- |
| **Payload Size Capping** | Max 64 KB (65,536 bytes) | Immediate rejection without buffering | `HTTP 413 Payload Too Large` |
| **Account Creation Throttle** | Max 3 accounts per 10 min per IP | Blocks registration | `HTTP 429 Too Many Requests`<br>`Retry-After: <seconds>` |
| **Brute-Force Login Lockout** | Max 5 failed attempts per 5 min | Locks IP out from login for 5 min (15 min quarantine if persistent) | `HTTP 429 Too Many Requests`<br>`Retry-After: <seconds>` |
| **General REST API Limit** | Max 60 requests per 1 min per IP | Throttles `/leaderboard` & `/rooms` | `HTTP 429 Too Many Requests`<br>`Retry-After: <seconds>` |
| **WebSocket Concurrency** | Max 4 simultaneous connections per IP | Rejects new connection | WS Close Code `1008 Policy Violation` |
| **Database Shield Caching** | 5-second TTL on `/leaderboard` | Serves hot cache in $< 1\text{ms}$ | Eliminates WAN database strain |

### IP Extraction & Trusted Proxy Support
The security engine intelligently extracts the true client IP using the following hierarchy:
1. `CF-Connecting-IP` (Cloudflare edge proxy header)
2. `X-Forwarded-For` (Standard reverse proxy header, taking the leftmost public IP)
3. Socket Remote Address (`self.client_address[0]`)

---

## 3. Production Cloudflare Edge Deployment Guide

When you are ready to transition from local development to public cloud hosting, follow these steps to enable enterprise-grade DDoS mitigation:

```
[ Player Client / Browser ]
             │
             ▼  HTTPS / WSS (Port 443)
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare Edge Network                  │
│  - 300+ PoPs Anycast DDoS Scrubbing (Tbps capacity)        │
│  - Cloudflare WAF & Bot Management                         │
│  - Cloudflare Turnstile (Invisible Bot Detection)           │
│  - Edge SSL Termination & HTTP/2 / HTTP/3 Multiplexing      │
└─────────────────────────────────────────────────────────────┘
             │
             ▼  Encrypted Tunnel (Cloudflare Tunnel / Origin CA)
┌─────────────────────────────────────────────────────────────┐
│                   Your Dedicated Server / VM                │
│  - Origin IP completely hidden (Cloaked)                   │
│  - Firewall (UFW) drops all packets NOT from Cloudflare IPs │
│  - Sabong Roosters Backend (`server.py` + `security.py`)     │
│  - TiDB Serverless Cloud Database (TLS 1.3)                 │
└─────────────────────────────────────────────────────────────┘
```

### Step 3.1: Domain Setup & DNS Proxying
1. Add your domain to Cloudflare (Free or Pro plan).
2. Point DNS `A` or `CNAME` records to your server IP.
3. Toggle the proxy status to **Proxied** (Orange Cloud icon enabled).

### Step 3.2: Origin IP Cloaking (Prevent Direct IP Bypasses)
Attackers who discover your origin IP can bypass Cloudflare entirely. To prevent this:
1. Configure your host firewall (e.g. `ufw` on Linux or Windows Firewall):
   - Only allow incoming TCP ports `80`, `443`, `10005`, `10006` from [Cloudflare IP Ranges](https://www.cloudflare.com/ips/).
   - Drop all other incoming connections.
2. Alternatively, use **Cloudflare Tunnel (`cloudflared`)**:
   - Zero open inbound ports required on your firewall.
   - The lightweight `cloudflared` daemon creates an outbound-only tunnel to Cloudflare edge.

### Step 3.3: Cloudflare WAF Custom Rules (Free Plan)
In the Cloudflare Dashboard $\rightarrow$ **Security** $\rightarrow$ **WAF** $\rightarrow$ **Custom Rules**:

1. **Rule 1: Block High-Threat Scores on Auth Endpoints**
   - *Expression*: `(http.request.uri.path contains "/auth/" and cf.threat_score gt 20)`
   - *Action*: **Managed Challenge** (prompts bots with an invisible browser verification).

2. **Rule 2: Protect WebSocket Relay Endpoint**
   - Enable WebSockets in Cloudflare Dashboard $\rightarrow$ **Network** $\rightarrow$ **WebSockets** (Toggle **ON**).
   - Ensure WebSocket connections pass through proxy with automatic keepalive.

### Step 3.4: Cloudflare Turnstile Integration (Optional Captcha)
For 100% defense against automated registration scripts without annoying human players:
1. In Cloudflare Dashboard, create a **Turnstile** widget (Mode: *Managed / Invisible*).
2. In the Godot registration UI, obtain the one-time Turnstile token before submitting.
3. In `server.py`, verify the token with Cloudflare's `/turnstile/v0/siteverify` API endpoint before creating the user in TiDB.

---

## 4. Legitimate Player UX & Retry-After Handling

When a player hits a rate limit (e.g., rapid clicking or re-submitting):
- The server responds with `HTTP 429 Too Many Requests`.
- The response JSON includes a friendly error message:
  ```json
  {
    "success": false,
    "error": "Registration rate limit reached. Please wait 592s before creating another account."
  }
  ```
- The standard `Retry-After: <seconds>` HTTP header is included.
- Godot's `AuthManager.gd` displays this message directly on the auth dialog so the player knows exactly when to retry.

---

## 5. Automated Verification Test Suite

You can verify all 5 layers of defense at any time by running:
```powershell
python -u scratch/test_ddos_rate_limit.py
```

The test script automatically validates:
1. **Oversized Payload Rejection**: 100 KB request rejected with `HTTP 413` without memory buffering.
2. **Registration Flood**: Max 3 accounts created; attempts 4 and 5 rejected with `HTTP 429`.
3. **Brute-Force Lockout**: 5 failed logins permitted; attempts 6 and 7 locked out with `HTTP 429`.
4. **Endpoint Throttling**: 65 rapid leaderboard requests capped at exactly 60 allowed, 5 blocked.
5. **Clean Player Independence**: Other IPs are completely unaffected and register cleanly.
