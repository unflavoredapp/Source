#!/usr/bin/env node
"use strict";

/**
 * AirShare-style Telegram login for the Premium account used by the IPA relay.
 *
 * 1) Get api_id / api_hash from https://my.telegram.org → API development tools
 * 2) Either:
 *      node login.js                  # phone + login code
 *      node login.js --session PASTE  # paste an existing GramJS/Telethon-compatible string
 *
 * Prints env lines to drop into .env (or PM2 env).
 */

require("dotenv").config();

const fs = require("fs");
const path = require("path");
const { TelegramClient } = require("teleproto");
const { StringSession } = require("teleproto/sessions");
const input = require("input");

async function main() {
  const args = process.argv.slice(2);
  const sessionFlag = args.indexOf("--session");
  const pasted =
    sessionFlag >= 0 ? (args[sessionFlag + 1] || "").trim() : "";

  let apiId = (process.env.TELEGRAM_API_ID || "").trim();
  let apiHash = (process.env.TELEGRAM_API_HASH || "").trim();

  if (!apiId) apiId = (await input.text("api_id (from my.telegram.org): ")).trim();
  if (!apiHash) apiHash = (await input.text("api_hash: ")).trim();
  if (!apiId || !apiHash) {
    console.error("api_id and api_hash are required");
    process.exit(1);
  }

  const stringSession = new StringSession(pasted);
  const client = new TelegramClient(stringSession, Number(apiId), apiHash, {
    connectionRetries: 5,
    useWSS: true,
    deviceModel: "UNlicense IPA Relay Login",
    appVersion: "1.1.0",
  });

  if (pasted) {
    await client.connect();
    if (!(await client.checkAuthorization())) {
      console.error("That session string is not authorized.");
      process.exit(1);
    }
  } else {
    await client.start({
      phoneNumber: async () =>
        (await input.text("Phone (with country code, e.g. +15551234567): ")).trim(),
      password: async () => await input.text("2FA password (if any, else empty): "),
      phoneCode: async () => (await input.text("Login code from Telegram: ")).trim(),
      onError: (err) => console.error(err),
    });
  }

  const me = await client.getMe();
  const session = client.session.save();
  await client.disconnect();

  const name = [me.firstName, me.lastName].filter(Boolean).join(" ") || "user";
  console.log("");
  console.log(`Connected as ${name} (@${me.username || "—"}) id=${me.id}`);
  console.log(`Premium: ${Boolean(me.premium)}`);
  console.log("");
  console.log("Add to Tools/telegram-ipa-relay/.env (then pm2 restart):");
  console.log(`TELEGRAM_API_ID=${apiId}`);
  console.log(`TELEGRAM_API_HASH=${apiHash}`);
  console.log(`TELEGRAM_SESSION=${session}`);
  console.log("");
  console.log("Also set TELEGRAM_CHANNEL_ID=-100… and TELEGRAM_BOT_TOKEN=…");
  console.log("Bot must be admin in that channel; this Premium account posts IPAs there.");

  const envPath = path.join(__dirname, ".env");
  const write = await input.confirm("Write/update TELEGRAM_* keys in .env now?", false);
  if (write) {
    let existing = "";
    try {
      existing = fs.readFileSync(envPath, "utf8");
    } catch {
      existing = "";
    }
    const upsert = (text, key, value) => {
      const re = new RegExp(`^${key}=.*$`, "m");
      const line = `${key}=${value}`;
      return re.test(text) ? text.replace(re, line) : `${text.trimEnd()}\n${line}\n`;
    };
    let next = existing || "";
    next = upsert(next, "TELEGRAM_API_ID", apiId);
    next = upsert(next, "TELEGRAM_API_HASH", apiHash);
    next = upsert(next, "TELEGRAM_SESSION", session);
    fs.writeFileSync(envPath, next.startsWith("\n") ? next.slice(1) : next, { mode: 0o600 });
    console.log(`Updated ${envPath}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
