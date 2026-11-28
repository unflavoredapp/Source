# Telegram phone worker

Control fetch + decrypt from Telegram. The **iPhone running APP** is the worker — FairPlay decrypt has to happen on-device — and the bot is just the remote control / file drop. A small **VPS relay** is optional for IPAs over Telegram’s ~50 MB Bot API cap.

```
You (Telegram) ──commands──► Bot API ◄──poll── APP on iPhone
                                    │
                                    ├─ /fd bundle.id  → App Store download → decrypt → send IPA
                                    ├─ /fetch …       → download only
                                    └─ /decrypt …     → decrypt on-device IPA

Large IPA (>~50 MB):
  iPhone ──PUT /upload──► VPS relay ──HTTPS link──► Telegram message
```

## Setup (phone)

1. Create a bot with [@BotFather](https://t.me/BotFather) → copy the token.
2. Message the bot once from your phone.
3. In APP → **Settings → Telegram Worker**:
   - Paste the bot token (stored in Keychain)
   - Optional: lock to your chat id (or leave empty — first chat that talks is locked in)
   - Enable the worker
4. Keep APP open (or recently used) while jobs run. Sign in to an App Store account in APP first.

## Setup (VPS relay — for large IPAs)

See [`Tools/telegram-ipa-relay/README.md`](Tools/telegram-ipa-relay/README.md).

```bash
cd Tools/telegram-ipa-relay
docker build -t unlicense-ipa-relay .
docker run -d --name ipa-relay -p 8787:8787 \
  -e RELAY_TOKEN='long-random-secret' \
  -e PUBLIC_BASE_URL='https://ipa.yourdomain.com' \
  -v ipa-data:/data \
  unlicense-ipa-relay
```

Put TLS in front of `:8787`, then in **Settings → Telegram Worker** set:

- **IPA relay URL** = `https://ipa.yourdomain.com`
- **Relay token** = same `RELAY_TOKEN`

When an IPA is over ~50 MB, the phone uploads it to the relay and posts the download link in chat (sharp cards still show progress).

## Commands

| Command | Action |
| --- | --- |
| `/fd <bundleId\|adamId\|url\|name>` | Fetch + decrypt, then send the decrypted IPA (or relay link) |
| `/fetch <target>` | Download only (encrypted IPA) |
| `/decrypt <bundleId\|filename>` | Decrypt an IPA already on the phone |
| `/status` | Sharp status card |
| `/help` | Command list |

## Notes

- Requires iOS **17.4+** (APP deployment target) and a signature that allows FairPlay decrypt (`dynamic-codesigning`).
- Telegram bot file uploads are capped (~50 MB). With a relay configured, larger IPAs get a VPS download link; without one they stay on-device.
- Job progress and `/status` send UNlicense **sharp cards** (console + progress photo) generated on-device.
- Paste BotFather tokens with **no spaces** (e.g. `123456:ABC…`); the app strips whitespace on save.
- Complementary: CI can also push built `APP.ipa` to Telegram when `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` repo secrets are set (see Build IPA workflow).
