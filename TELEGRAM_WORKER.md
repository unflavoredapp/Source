# Telegram phone worker

Control fetch + decrypt from Telegram. The **iPhone running APP** is the worker — FairPlay decrypt has to happen on-device — and the bot is just the remote control / file drop.

```
You (Telegram) ──commands──► Bot API ◄──poll── APP on iPhone
                                    │
                                    ├─ /fd bundle.id  → App Store download → decrypt → send IPA
                                    ├─ /fetch …       → download only
                                    └─ /decrypt …     → decrypt on-device IPA
```

## Setup

1. Create a bot with [@BotFather](https://t.me/BotFather) → copy the token.
2. Message the bot once from your phone.
3. In APP → **Settings → Telegram Worker**:
   - Paste the bot token (stored in Keychain)
   - Optional: lock to your chat id (or leave empty — first chat that talks is locked in)
   - Enable the worker
4. Keep APP open (or recently used) while jobs run. Sign in to an App Store account in APP first.

## Commands

| Command | Action |
| --- | --- |
| `/fd <bundleId\|adamId\|url\|name>` | Fetch + decrypt, then send the decrypted IPA |
| `/fetch <target>` | Download only (encrypted IPA) |
| `/decrypt <bundleId\|filename>` | Decrypt an IPA already on the phone |
| `/status` | Worker / account / readiness |
| `/help` | Command list |

## Notes

- Requires iOS **17.4+** (APP deployment target) and a signature that allows FairPlay decrypt (`dynamic-codesigning`).
- Telegram bot file uploads are capped (~50 MB). Larger IPAs stay on-device; use Files / the Decrypt tab.
- Complementary: CI can also push built `APP.ipa` to Telegram when `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` repo secrets are set (see Build IPA workflow).
