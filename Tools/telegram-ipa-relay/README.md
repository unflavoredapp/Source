# Telegram IPA relay (VPS)

Bypasses Telegram Bot API’s ~50 MB `sendDocument` cap. The **phone still does fetch + decrypt**; the VPS only hosts the finished IPA and returns a download link the bot posts in chat.

```
Phone (UNlicense) ──PUT /upload──► VPS relay ──HTTPS link──► Telegram message
                                      │
                                      └─ GET /d/<id>/<name>.ipa
```

## Quick start (Docker)

```bash
docker build -t unlicense-ipa-relay .
docker run -d --name ipa-relay -p 8787:8787 \
  -e RELAY_TOKEN='long-random-secret' \
  -e PUBLIC_BASE_URL='https://ipa.yourdomain.com' \
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

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `RELAY_TOKEN` | yes | — | Shared secret; phone sends `Authorization: Bearer …` |
| `PUBLIC_BASE_URL` | yes | — | Public origin used in download URLs |
| `PORT` | no | `8787` | Listen port |
| `DATA_DIR` | no | `./data` | Storage root |
| `TTL_HOURS` | no | `24` | Auto-delete age |
| `MAX_BYTES` | no | 2 GiB | Reject larger uploads |

## API

`PUT /upload?name=App.ipa`  
Headers: `Authorization: Bearer <RELAY_TOKEN>`, `Content-Length`, body = raw IPA bytes.

```json
{ "ok": true, "url": "https://…/d/<id>/App.ipa", "expiresIn": 86400 }
```

`GET /d/<id>/<filename>` — public download (unguessable id).  
`GET /health` — liveness.

## App settings

In UNlicense → **Settings → Telegram Worker**:

1. Bot token + enable worker (as usual)
2. **IPA relay URL** = `https://ipa.yourdomain.com`
3. **Relay token** = same `RELAY_TOKEN`

When an IPA is over ~50 MB (or Telegram rejects the upload), the phone uploads to the relay and posts the link instead.
