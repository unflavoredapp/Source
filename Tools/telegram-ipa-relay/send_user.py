#!/usr/bin/env python3
"""Post an IPA to a Telegram channel as your Premium user (MTProto, up to ~4 GB).

The Node relay then has the *bot* forward that channel message to the user —
forwardMessage does not re-upload, so Bot API’s ~50 MB cap does not apply.

Usage:
  python3 send_user.py --channel-id -100… --file /path/to.ipa [--caption "…"]

Env: TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_SESSION
Prints one JSON object on stdout.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys

from telethon import TelegramClient
from telethon.sessions import StringSession


async def run(channel_id: int, path: str, caption: str) -> dict:
    api_id = os.environ.get("TELEGRAM_API_ID", "").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
    session = os.environ.get("TELEGRAM_SESSION", "").strip()
    if not api_id or not api_hash or not session:
        return {"ok": False, "error": "TELEGRAM_API_ID / TELEGRAM_API_HASH / TELEGRAM_SESSION required"}

    client = TelegramClient(StringSession(session), int(api_id), api_hash)
    await client.connect()
    if not await client.is_user_authorized():
        await client.disconnect()
        return {"ok": False, "error": "TELEGRAM_SESSION is not authorized — run login.py"}

    me = await client.get_me()
    entity = await client.get_entity(channel_id)
    message = await client.send_file(
        entity,
        path,
        caption=caption or None,
        force_document=True,
        allow_cache=False,
    )
    await client.disconnect()

    # Prefer the channel peer id Telethon used (always -100… for megagroups/channels).
    resolved_channel = channel_id
    if getattr(message, "peer_id", None) is not None:
        peer = message.peer_id
        channel_peer = getattr(peer, "channel_id", None)
        if channel_peer is not None:
            resolved_channel = int(f"-100{channel_peer}")

    return {
        "ok": True,
        "channel_id": resolved_channel,
        "message_id": int(message.id),
        "from_user_id": me.id,
        "premium": bool(getattr(me, "premium", False)),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel-id", type=int, required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--caption", default="")
    args = parser.parse_args()

    if not os.path.isfile(args.file):
        print(json.dumps({"ok": False, "error": f"file not found: {args.file}"}))
        return 1

    try:
        result = asyncio.run(run(args.channel_id, args.file, args.caption))
    except Exception as exc:  # noqa: BLE001 — surface to Node as JSON
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
