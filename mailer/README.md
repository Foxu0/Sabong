# Mailer (Vercel)

A single Vercel function that sends the game's verification emails through Gmail.
Render's free plan blocks email ports, so the game server calls this over HTTPS instead.

- Deploy: import this GitHub repo in Vercel and set **Root Directory** to `mailer`.
- Vercel environment variables: `MAILER_SECRET`, `SMTP_USER`, `SMTP_PASS` (optional `SMTP_FROM`).
- Render environment variables: `MAILER_URL` = `https://<your-project>.vercel.app/api/send`,
  `MAILER_SECRET` = the same secret as on Vercel.
- Check it: open `https://<your-project>.vercel.app/api/send` in a browser; it should show
  `{"ok": true, "configured": true}`.
