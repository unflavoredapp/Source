"use strict";

/**
 * Premium user client (GramJS) — same style as AirShare:
 * api_id + api_hash + session string from my.telegram.org / login.js
 */

const { TelegramClient, Api } = require("teleproto");
const { StringSession } = require("teleproto/sessions");

let client = null;
let meCache = null;

function config() {
  const apiId = Number(process.env.TELEGRAM_API_ID || "");
  const apiHash = (process.env.TELEGRAM_API_HASH || "").trim();
  const session = (process.env.TELEGRAM_SESSION || "").trim();
  const channelId = Number(process.env.TELEGRAM_CHANNEL_ID || "");
  return { apiId, apiHash, session, channelId };
}

function isConfigured() {
  const { apiId, apiHash, session, channelId } = config();
  return Boolean(apiId && apiHash && session && channelId);
}

async function connect() {
  if (client) return client;
  const { apiId, apiHash, session } = config();
  if (!apiId || !apiHash || !session) {
    throw new Error("TELEGRAM_API_ID / TELEGRAM_API_HASH / TELEGRAM_SESSION required");
  }

  client = new TelegramClient(new StringSession(session), apiId, apiHash, {
    connectionRetries: 5,
    useWSS: true,
    deviceModel: "UNlicense IPA Relay",
    appVersion: "1.1.0",
  });

  await client.connect();
  if (!(await client.checkAuthorization())) {
    await client.disconnect();
    client = null;
    throw new Error("TELEGRAM_SESSION is not authorized — run: npm run login");
  }

  meCache = await client.getMe();
  const name = [meCache.firstName, meCache.lastName].filter(Boolean).join(" ") || "user";
  const uname = meCache.username ? `@${meCache.username}` : "(no username)";
  console.log(`Telegram user connected as ${name} (${uname}) id=${meCache.id}`);
  console.log(`Premium: ${Boolean(meCache.premium)}`);
  return client;
}

async function getMe() {
  await connect();
  return meCache;
}

/**
 * Post IPA to the private drop channel as the Premium user.
 * @returns {{ ok: true, channel_id: number, message_id: number, premium: boolean } | { ok: false, error: string }}
 */
async function postToChannel({ filePath, caption }) {
  try {
    const { channelId } = config();
    if (!channelId) return { ok: false, error: "TELEGRAM_CHANNEL_ID required" };

    const c = await connect();
    const entity = await c.getEntity(channelId);
    const result = await c.sendFile(entity, {
      file: filePath,
      caption: caption || undefined,
      forceDocument: true,
      workers: 4,
    });

    const messageId = Number(result?.id);
    let resolvedChannel = channelId;
    // Normalize to Bot API style -100… when we have a channel peer.
    const peer = result?.peerId;
    const channelPeerId = peer?.channelId ?? (peer instanceof Api.PeerChannel ? peer.channelId : null);
    if (channelPeerId != null) {
      resolvedChannel = Number(`-100${channelPeerId}`);
    }

    return {
      ok: true,
      channel_id: resolvedChannel,
      message_id: messageId,
      premium: Boolean(meCache?.premium),
    };
  } catch (err) {
    return { ok: false, error: err?.message || String(err) };
  }
}

async function disconnect() {
  if (!client) return;
  try {
    await client.disconnect();
  } catch {
    /* ignore */
  }
  client = null;
  meCache = null;
}

module.exports = {
  isConfigured,
  connect,
  getMe,
  postToChannel,
  disconnect,
};
