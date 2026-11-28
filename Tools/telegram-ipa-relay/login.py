#!/usr/bin/env python3
"""One-time login: creates a Telethon StringSession for your Premium account.

Get api_id / api_hash from https://my.telegram.org → API development tools.
Then:

  pip install -r requirements.txt
  python3 login.py

Paste the printed TELEGRAM_SESSION into the relay env (or Docker).
"""

from __future__ import annotations

import asyncio
import os
import sys

from telethon import TelegramClient
from telethon.sessions import StringSession


async def main() -> int:
    api_id = os.environ.get("TELEGRAM_API_ID") or input("api_id: ").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH") or input("api_hash: ").strip()
    if not api_id or not api_hash:
        print("api_id and api_hash are required", file=sys.stderr)
        return 1

    client = TelegramClient(StringSession(), int(api_id), api_hash)
    await client.start()
    me = await client.get_me()
    session = client.session.save()
    await client.disconnect()

    print()
    print(f"Logged in as {me.first_name} (@{me.username or '—'}) id={me.id}")
    print("Premium:", getattr(me, "premium", False))
    print()
    print("Add this to the relay environment (plus TELEGRAM_CHANNEL_ID + TELEGRAM_BOT_TOKEN):")
    print(f"TELEGRAM_API_ID={api_id}")
    print(f"TELEGRAM_API_HASH={api_hash}")
    print(f"TELEGRAM_SESSION={session}")
    print()
    print("Flow: this Premium account posts IPAs to your private channel;")
    print("the bot (admin in that channel) forwards each post to the recipient.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
