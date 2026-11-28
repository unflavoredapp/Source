# Telegram IPA relay (VPS)

Bypasses Telegram **Bot API’s ~50 MB upload cap**. Premium on your personal account does **not** raise bot uploads — so large IPAs use your Premium user session to post into a private channel, then the bot **forwards** that message to the recipient (server-side, no re-upload → up to ~4 GB).

```
Phone (decrypt) ──PUT /upload──► VPS
                                  │
                                  ├─ Premium user (MTProto) ──post──► private Channel
                                  └─ Bot API forwardMessage ─────────► recipient chat
```

Sharp cards / commands still run on the phone. The VPS only hosts + delivers oversized IPAs.

## One-time Telegram setup

1. Create a **private channel** (e.g. `UNlicense Drops`).
2. Add your **Premium account** as owner/admin.
3. Add your **bot** as admin (must be able to see posts / forward).
4. Get the channel id (`-100…`) — forward a channel post to [@userinfobot](https://t.me/userinfobot) or use Telethon after login.
5. At [my.telegram.org](https://my.telegram.org) create an API app → `api_id` / `api_hash`.
6. On any machine with Python:

```bash
pip install -r requirements.txt
TELEGRAM_API_ID=… TELEGRAM_API_HASH=… python3 login.py
```

Copy the printed `TELEGRAM_SESSION=…`.

## Docker

```bash
docker build -t unlicense-ipa-relay .
docker run -d --name ipa-relay -p 8787:8787 \
  -e RELAY_TOKEN='long-random-secret' \
  -e PUBLIC_BASE_URL='https://ipa.yourdomain.com' \
  -e TELEGRAM_API_ID='12345' \
  -e TELEGRAM_API_HASH='…' \
  -e TELEGRAM_SESSION='…' \
  -e TELEGRAM_CHANNEL_ID='-100xxxxxxxxxx' \
  -e TELEGRAM_BOT_TOKEN='123456:ABC…' \
  -e TTL_HOURS=24 \
  -v ipa-data:/data \
  unlicense-ipa-relay
```

Put TLS in front (Caddy / nginx / Cloudflare) so `PUBLIC_BASE_URL` is HTTPS.

### Caddy example

```
ipa.yourdomain.com {
  reverse_proxy 127.0.0.1:8787
}
```

## Env

| Variable | Required | Meaning |
| --- | --- | --- |
| `RELAY_TOKEN` | yes | Phone → VPS shared secret |
| `PUBLIC_BASE_URL` | yes | Public origin (fallback download links) |
| `TELEGRAM_API_ID` / `HASH` / `SESSION` | for 4 GB path | Premium user that posts to the channel |
| `TELEGRAM_CHANNEL_ID` | for 4 GB path | Private channel id (`-100…`) |
| `TELEGRAM_BOT_TOKEN` | for 4 GB path | Same bot as the phone worker; admin in channel |
| `PORT` | no | default `8787` |
| `TTL_HOURS` | no | default `24` (local file cleanup) |
| `MAX_BYTES` | no | default 4 GiB |

## App settings

UNlicense → **Settings → Telegram Worker**:

1. Bot token + enable worker  
2. **IPA relay URL** = `https://ipa.yourdomain.com`  
3. **Relay token** = `RELAY_TOKEN`  

When an IPA is over ~50 MB, the phone uploads to the VPS; if channel delivery is configured, you get the file forwarded in chat from the channel. Otherwise you get a download link.

## API

`PUT /upload?name=App.ipa&chat_id=<recipient>&caption=…`  
Headers: `Authorization: Bearer <RELAY_TOKEN>`, `Content-Length`, raw IPA body.

```json
{
  "ok": true,
  "delivered": true,
  "destination": "channel_forward",
  "url": "https://…/d/<id>/App.ipa",
  "channelDelivery": true
}
```
