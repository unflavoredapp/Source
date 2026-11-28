# Telegram IPA relay (VPS) — GramJS + PM2

Large IPAs (past Bot API ~50 MB) use your **Premium Telegram account** the same way AirShare does: `api_id` + `api_hash` + session string in **Node.js** (`teleproto` / GramJS fork), kept alive with **PM2**.

```
Phone (decrypt) ──PUT──► VPS (PM2)
                           │
                           ├─ GramJS Premium user ──post──► private Channel
                           └─ Bot API forwardMessage ─────► recipient chat
```

## VPS quick start

```bash
cd Tools/telegram-ipa-relay
chmod +x setup-vps.sh
./setup-vps.sh          # npm install + creates .env first time
# edit .env — then:
npm run login           # phone + code, or: npm run login -- --session '…'
./setup-vps.sh          # pm2 start
```

### `.env` (AirShare-style keys)

| Key | Source |
| --- | --- |
| `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` | [my.telegram.org](https://my.telegram.org) → API development tools |
| `TELEGRAM_SESSION` | `npm run login` (or paste an existing session string) |
| `TELEGRAM_CHANNEL_ID` | Private channel id (`-100…`) |
| `TELEGRAM_BOT_TOKEN` | Same bot as the phone worker; **admin** in that channel |
| `RELAY_TOKEN` / `PUBLIC_BASE_URL` | Phone ↔ VPS auth + public HTTPS origin |

`npm run login` mirrors AirShare: enter api keys, phone (+country code), login code — or expand “paste a session string” via `--session`.

### PM2

```bash
pm2 start ecosystem.config.cjs
pm2 logs unlicense-ipa-relay
pm2 restart unlicense-ipa-relay
pm2 save && pm2 startup    # survive reboot
```

### Channel setup

1. Private channel (e.g. UNlicense Drops).  
2. Add your **Premium account** (the one you log in with).  
3. Add the **bot** as admin.  
4. Put channel id in `TELEGRAM_CHANNEL_ID`.

## App settings

UNlicense → **Settings → Telegram Worker**: bot token, **IPA relay URL**, **relay token**.

IPAs ≤~50 MB still go through Bot API `sendDocument`. Larger ones hit this relay → channel → forward.

## API

`PUT /upload?name=App.ipa&chat_id=<recipient>&caption=…`  
`Authorization: Bearer <RELAY_TOKEN>`

`GET /health` → `{ ok, channelDelivery, telegramUser: { username, premium } }`

## Docker (optional)

```bash
docker build -t unlicense-ipa-relay .
docker run -d --env-file .env -p 8787:8787 -v ipa-data:/data unlicense-ipa-relay
```

Prefer PM2 on a plain VPS if you want the AirShare-like always-on user session.
