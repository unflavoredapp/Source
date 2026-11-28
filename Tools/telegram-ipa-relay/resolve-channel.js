#!/usr/bin/env node
"use strict";

/**
 * Resolve a private invite link to TELEGRAM_CHANNEL_ID.
 *
 *   node resolve-channel.js 'https://t.me/+e3BiOpG8QEw5MTEx'
 *
 * Requires TELEGRAM_API_ID / HASH / SESSION in .env (npm run login first).
 */

require("dotenv").config();

const telegramUser = require("./telegramUser");

async function main() {
  const invite = process.argv[2] || process.env.TELEGRAM_CHANNEL_INVITE;
  if (invite) {
    process.env.TELEGRAM_CHANNEL_INVITE = invite;
    delete process.env.TELEGRAM_CHANNEL_ID;
  }
  if (!telegramUser.isConfigured()) {
    console.error("Need TELEGRAM_API_ID / TELEGRAM_API_HASH / TELEGRAM_SESSION + invite or channel id");
    process.exit(1);
  }
  await telegramUser.connect();
  const id = await telegramUser.resolveChannelId();
  console.log("");
  console.log(`TELEGRAM_CHANNEL_ID=${id}`);
  if (invite) console.log(`TELEGRAM_CHANNEL_INVITE=${invite}`);
  console.log("");
  console.log("Put TELEGRAM_CHANNEL_ID (or INVITE) in .env. Bot must be admin in this channel.");
  await telegramUser.disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
