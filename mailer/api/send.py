"""
Sabong Roosters mailer (Vercel serverless function)
===================================================
Sends one email through Gmail SMTP on behalf of the game server.

Why it exists: Render's free plan blocks outbound SMTP ports (25/465/587), so the
game server calls this function over HTTPS instead and this function talks SMTP.

POST /api/send
  Authorization: Bearer <MAILER_SECRET>
  {"to": "player@example.com", "subject": "...", "text": "...", "html": "..."(optional)}

Environment variables (set in the Vercel project):
  MAILER_SECRET  shared secret; the game server sends the same value
  SMTP_USER      Gmail address the app password belongs to
  SMTP_PASS      Gmail app password (spaces are ignored)
  SMTP_FROM      optional, e.g. "Sabong Roosters <you@gmail.com>"
  SMTP_HOST      optional, default smtp.gmail.com
"""

import hmac
import json
import os
import re
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from http.server import BaseHTTPRequestHandler

MAX_BODY_BYTES = 32 * 1024
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _send_smtp(to_addr: str, subject: str, text: str, html: str) -> None:
    user = os.environ.get("SMTP_USER", "")
    password = os.environ.get("SMTP_PASS", "").replace(" ", "")
    host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    sender = os.environ.get("SMTP_FROM") or f"Sabong Roosters <{user}>"
    if not user or not password:
        raise RuntimeError("Mailer is missing SMTP_USER or SMTP_PASS")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = to_addr
    msg.attach(MIMEText(text, "plain", "utf-8"))
    if html:
        msg.attach(MIMEText(html, "html", "utf-8"))

    # Implicit TLS first, STARTTLS as a fallback
    try:
        with smtplib.SMTP_SSL(host, 465, timeout=8) as s:
            s.login(user, password)
            s.send_message(msg)
        return
    except smtplib.SMTPAuthenticationError:
        raise
    except Exception:
        pass
    with smtplib.SMTP(host, 587, timeout=8) as s:
        s.starttls()
        s.login(user, password)
        s.send_message(msg)


class handler(BaseHTTPRequestHandler):
    def _reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # Lets you open the URL in a browser to confirm the deploy works (sends nothing)
        configured = bool(os.environ.get("MAILER_SECRET") and os.environ.get("SMTP_USER") and os.environ.get("SMTP_PASS"))
        self._reply(200, {"ok": True, "configured": configured})

    def do_POST(self):
        secret = os.environ.get("MAILER_SECRET", "")
        auth = self.headers.get("Authorization", "")
        token = auth[7:] if auth.lower().startswith("bearer ") else ""
        if not secret or not hmac.compare_digest(token, secret):
            self._reply(401, {"ok": False, "error": "unauthorized"})
            return

        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0 or length > MAX_BODY_BYTES:
            self._reply(413, {"ok": False, "error": "bad body size"})
            return
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            self._reply(400, {"ok": False, "error": "invalid json"})
            return

        to_addr = str(data.get("to", "")).strip()
        subject = str(data.get("subject", "")).strip()[:200]
        text = str(data.get("text", ""))
        html = str(data.get("html", ""))
        if not EMAIL_RE.match(to_addr) or not subject or not text:
            self._reply(400, {"ok": False, "error": "need a valid 'to', 'subject' and 'text'"})
            return

        try:
            _send_smtp(to_addr, subject, text, html)
        except smtplib.SMTPAuthenticationError:
            self._reply(502, {"ok": False, "error": "Gmail rejected the login. Check SMTP_USER / SMTP_PASS."})
            return
        except Exception as e:
            self._reply(502, {"ok": False, "error": f"send failed: {type(e).__name__}"})
            return
        self._reply(200, {"ok": True})
