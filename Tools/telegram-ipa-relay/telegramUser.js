"use strict";

/**
 * Premium user client (GramJS / teleproto) — AirShare-style:
 * api_id + api_hash + session string from my.telegram.org / login.js
 *
 * Drop channel: TELEGRAM_CHANNEL_ID (-100…) or TELEGRAM_CHANNEL_INVITE (t.me/+…).
 */

const { TelegramClient, Api } = require("teleproto");
const { StringSession } = require("teleproto/sessions");

let client = null;
let meCache = null;
/** @type {number|null} Bot API style channel id (-100…) */
let resolvedChannelId = null;

function config() {
  const apiId = Number(process.env.TELEGRAM_API_ID || "");
  const apiHash = (process.env.TELEGRAM_API_HASH || "").trim();
  const session = (process.env.TELEGRAM_SESSION || "").trim();
  const channelId = Number(process.env.TELEGRAM_CHANNEL_ID || "");
  const invite = (process.env.TELEGRAM_CHANNEL_INVITE || "").trim();
  return { apiId, apiHash, session, channelId, invite };
}

function inviteHash(raw) {
  const s = String(raw || "").trim();
  if (!s) return null;
  let m = s.match(/t\.me\/\+([A-Za-z0-9_-]+)/i);
  if (m) return m[1];
  m = s.match(/^\+([A-Za-z0-9_-]+)$/);
  if (m) return m[1];
  m = s.match(/joinchat\/([A-Za-z0-9_-]+)/i);
  if (m) return m[1];
  // bare hash
  if (/^[A-Za-z0-9_-]{8,}$/.test(s) && !s.startsWith("-")) return s;
  return null;
}

function channelIdFromChat(chat) {
  if (!chat || chat.id == null) return null;
  // Channels/supergroups use -100 prefix for Bot API.
  const className = chat.className || chat.className;
  const isChannel =
    className === "Channel" ||
    chat.broadcast === true ||
    chat.megagroup === true ||
    typeof chat.username !== "undefined";
  if (isChannel || String(chat.id).length >= 10) {
    return Number(`-100${chat.id}`);
  }
  return Number(`-100${chat.id}`);
}

function isConfigured() {
  const { apiId, apiHash, session, channelId, invite } = config();
  return Boolean(apiId && apiHash && session && (channelId || inviteHash(invite)));
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
 * Resolve TELEGRAM_CHANNEL_ID or join/check TELEGRAM_CHANNEL_INVITE.
 * @returns {Promise<number>} Bot API channel id (-100…)
 */
async function resolveChannelId() {
  if (resolvedChannelId) return resolvedChannelId;

  const { channelId, invite } = config();
  if (Number.isFinite(channelId) && channelId !== 0) {
    resolvedChannelId = channelId;
    console.log(`Drop channel id: ${resolvedChannelId}`);
    return resolvedChannelId;
  }

  const hash = inviteHash(invite);
  if (!hash) {
    throw new Error("Set TELEGRAM_CHANNEL_ID (-100…) or TELEGRAM_CHANNEL_INVITE (https://t.me/+…)");
  }

  const c = await connect();
  let chat = null;

  try {
    const checked = await c.invoke(new Api.messages.CheckChatInvite({ hash }));
    if (checked?.chat) {
      chat = checked.chat;
    } else if (checked?.className === "ChatInviteAlready" && checked.chat) {
      chat = checked.chat;
    } else {
      // Not a member yet — join via invite.
      const updates = await c.invoke(new Api.messages.ImportChatInvite({ hash }));
      chat =
        updates?.chats?.find((x) => x.className === "Channel") ||
        updates?.chats?.[0] ||
        null;
    }
  } catch (err) {
    const msg = err?.errorMessage || err?.message || String(err);
    if (/USER_ALREADY_PARTICIPANT|already/i.test(msg)) {
      const checked = await c.invoke(new Api.messages.CheckChatInvite({ hash }));
      chat = checked?.chat || null;
    } else {
      throw new Error(`Invite resolve failed (${hash}): ${msg}`);
    }
  }

  const id = channelIdFromChat(chat);
  if (!id) {
    throw new Error(
      "Could not resolve channel from invite — open the link while logged in as this Premium account, or set TELEGRAM_CHANNEL_ID"
    );
  }

  resolvedChannelId = id;
  console.log(`Drop channel from invite: ${resolvedChannelId}`);
  return resolvedChannelId;
}

/**
 * Post IPA to the private drop channel as the Premium user.
 */
async function postToChannel({ filePath, caption }) {
  try {
    const channelId = await resolveChannelId();
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
    const peer = result?.peerId;
    const channelPeerId =
      peer?.channelId ?? (peer instanceof Api.PeerChannel ? peer.channelId : null);
    if (channelPeerId != null) {
      resolvedChannel = Number(`-100${channelPeerId}`);
      resolvedChannelId = resolvedChannel;
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
  resolvedChannelId = null;
}

module.exports = {
  isConfigured,
  connect,
  getMe,
  resolveChannelId,
  inviteHash,
  postToChannel,
  disconnect,
};
