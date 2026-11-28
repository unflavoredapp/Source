# Telegram phone worker

Control fetch + decrypt from Telegram. The **iPhone** is the worker (FairPlay). The bot is remote control. A **VPS relay** delivers IPAs over Bot API’s ~50 MB cap using your **Premium account + a private channel**.

```
You ──/fd──► Bot ◄──poll── iPhone (fetch + decrypt)
                              │
                              │  IPA > ~50 MB
                              ▼
                            VPS relay
                              │
                 Premium user posts IPA ──► private Channel
                              │
                 Bot forwardMessage ──────► you (recipient)
```

Bot API cannot upload 4 GB even if you have Premium. Channel post (as Premium user) + bot **forward** does — Telegram does not re-upload on forward.

## Setup (phone)

1. [@BotFather](https://t.me/BotFather) → bot token.
2. Message the bot once.
3. APP → **Settings → Telegram Worker**: paste token, enable, optional chat id lock.
4. Stay signed into an App Store account; keep APP open while jobs run.

## Setup (VPS — large IPAs / Premium channel)

Full steps: [`Tools/telegram-ipa-relay/README.md`](Tools/telegram-ipa-relay/README.md).

1. Private channel; add **your Premium account** + **the bot** as admins.
2. On the VPS: `./setup-vps.sh` then `npm run login` (AirShare-style `api_id` / `api_hash` / phone or session string).
3. Fill `.env` (`RELAY_TOKEN`, `PUBLIC_BASE_URL`, `TELEGRAM_CHANNEL_ID`, `TELEGRAM_BOT_TOKEN`, session keys) and start with **PM2**.
4. In the app: **IPA relay URL** + **relay token**.

## Commands

| Command | Action |
| --- | --- |
| `/fd <bundleId\|adamId\|url\|name>` | Fetch + decrypt, send IPA (or channel-forward if large) |
| `/fetch <target>` | Download only |
| `/decrypt <bundleId\|filename>` | Decrypt on-device IPA |
| `/status` | Sharp status card |
| `/help` | Command list |

## Notes

- iOS **17.4+**, FairPlay-capable signature (`dynamic-codesigning`).
- Sharp cards are rendered on-device.
- BotFather tokens: no spaces (app strips whitespace on save).
