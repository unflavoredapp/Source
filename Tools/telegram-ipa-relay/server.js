#!/usr/bin/env node
/**
 * UNlicense Telegram IPA relay
 *
 * Bot API cannot upload >~50 MB (Premium on your account does not lift that).
 * Large IPAs use this path instead:
 *
 *   phone ──PUT──► VPS ──MTProto (Premium user)──► private Channel
 *                     └──Bot API forwardMessage──► user chat
 *
 * forwardMessage is server-side (no re-upload), so 4 GB Premium uploads work.
 * HTTPS download links remain as a fallback if channel delivery is off/fails.
 *
 * Env:
 *   RELAY_TOKEN           required — Authorization: Bearer …
 *   PUBLIC_BASE_URL       required — public https origin
 *   PORT / DATA_DIR / TTL_HOURS / MAX_BYTES
 *   TELEGRAM_API_ID       Premium user (my.telegram.org)
 *   TELEGRAM_API_HASH
 *   TELEGRAM_SESSION      from login.py
 *   TELEGRAM_CHANNEL_ID   private channel id (-100…)
 *   TELEGRAM_BOT_TOKEN    bot that is admin in that channel (forwards to user)
 */

"use strict";

const http = require("http");
const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");
const { pipeline } = require("stream/promises");

const TOKEN = process.env.RELAY_TOKEN || "";
const PUBLIC_BASE = (process.env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
const PORT = Number(process.env.PORT || 8787);
const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(__dirname, "data"));
const TTL_MS = Number(process.env.TTL_HOURS || 24) * 60 * 60 * 1000;
const MAX_BYTES = Number(process.env.MAX_BYTES || 4 * 1024 * 1024 * 1024);
const CHANNEL_ID = Number(process.env.TELEGRAM_CHANNEL_ID || "");
const BOT_TOKEN = (process.env.TELEGRAM_BOT_TOKEN || "").trim();
const CHANNEL_DELIVERY = Boolean(
  process.env.TELEGRAM_API_ID &&
    process.env.TELEGRAM_API_HASH &&
    process.env.TELEGRAM_SESSION &&
    Number.isFinite(CHANNEL_ID) &&
    CHANNEL_ID !== 0 &&
    BOT_TOKEN
);

if (!TOKEN) {
  console.error("RELAY_TOKEN is required");
  process.exit(1);
}
if (!PUBLIC_BASE) {
  console.error("PUBLIC_BASE_URL is required (e.g. https://ipa.example.com)");
  process.exit(1);
}

fs.mkdirSync(DATA_DIR, { recursive: true });

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function unauthorized(res) {
  json(res, 401, { ok: false, error: "unauthorized" });
}

function authorize(req) {
  const header = req.headers.authorization || "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  const presented = match ? match[1].trim() : "";
  if (!presented || presented.length !== TOKEN.length) return false;
  return crypto.timingSafeEqual(Buffer.from(presented), Buffer.from(TOKEN));
}

function safeName(raw) {
  const base = path.basename(String(raw || "app.ipa")).replace(/[^\w.\-()+ ]+/g, "_");
  return base || "app.ipa";
}

function id() {
  return crypto.randomBytes(16).toString("hex");
}

async function cleanup() {
  const now = Date.now();
  let entries;
  try {
    entries = await fsp.readdir(DATA_DIR, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const dir = path.join(DATA_DIR, entry.name);
    const metaPath = path.join(dir, "meta.json");
    try {
      const meta = JSON.parse(await fsp.readFile(metaPath, "utf8"));
      if (now - Number(meta.createdAt || 0) > TTL_MS) {
        await fsp.rm(dir, { recursive: true, force: true });
      }
    } catch {
      // orphan / corrupt — drop if old enough by mtime
      try {
        const st = await fsp.stat(dir);
        if (now - st.mtimeMs > TTL_MS) {
          await fsp.rm(dir, { recursive: true, force: true });
        }
      } catch {
        /* ignore */
      }
    }
  }
}

async function handleUpload(req, res, url) {
  if (!authorize(req)) return unauthorized(res);

  const length = Number(req.headers["content-length"] || 0);
  if (!Number.isFinite(length) || length <= 0) {
    return json(res, 400, { ok: false, error: "Content-Length required" });
  }
  if (length > MAX_BYTES) {
    return json(res, 413, { ok: false, error: `file too large (max ${MAX_BYTES} bytes)` });
  }

  const filename = safeName(url.searchParams.get("name") || req.headers["x-filename"] || "app.ipa");
  const fileId = id();
  const dir = path.join(DATA_DIR, fileId);
  await fsp.mkdir(dir, { recursive: true });
  const dest = path.join(dir, filename);
  const tmp = dest + ".part";

  try {
    await pipeline(req, fs.createWriteStream(tmp));
    const st = await fsp.stat(tmp);
    if (st.size !== length) {
      await fsp.rm(dir, { recursive: true, force: true });
      return json(res, 400, { ok: false, error: "incomplete upload" });
    }
    await fsp.rename(tmp, dest);
    const meta = {
      createdAt: Date.now(),
      filename,
      size: st.size,
    };
    await fsp.writeFile(path.join(dir, "meta.json"), JSON.stringify(meta));
    const downloadURL = `${PUBLIC_BASE}/d/${fileId}/${encodeURIComponent(filename)}`;
    const body = {
      ok: true,
      id: fileId,
      url: downloadURL,
      filename,
      size: st.size,
      expiresIn: Math.floor(TTL_MS / 1000),
      channelDelivery: CHANNEL_DELIVERY,
      delivered: false,
    };

    const recipientRaw = url.searchParams.get("chat_id") || req.headers["x-chat-id"] || "";
    const recipientChatId = Number(recipientRaw);
    const caption = String(url.searchParams.get("caption") || req.headers["x-caption"] || "").slice(0, 1024);

    if (CHANNEL_DELIVERY && Number.isFinite(recipientChatId) && recipientChatId !== 0) {
      const posted = await postIpaToChannel({
        filePath: dest,
        caption,
      });
      if (!posted.ok) {
        body.deliverError = posted.error || "channel upload failed";
        console.error("channel upload failed:", body.deliverError);
      } else {
        body.channelId = posted.channel_id;
        body.channelMessageId = posted.message_id;
        body.premium = Boolean(posted.premium);
        const forwarded = await botForwardToRecipient({
          recipientChatId,
          channelId: posted.channel_id,
          messageId: posted.message_id,
        });
        if (forwarded.ok) {
          body.delivered = true;
          body.destination = "channel_forward";
          body.messageId = forwarded.message_id ?? null;
        } else {
          body.deliverError = forwarded.error || "bot forward failed";
          console.error("bot forward failed:", body.deliverError);
        }
      }
    }

    return json(res, 200, body);
  } catch (err) {
    await fsp.rm(dir, { recursive: true, force: true }).catch(() => {});
    console.error("upload failed", err);
    return json(res, 500, { ok: false, error: "upload failed" });
  }
}

/** Premium user account posts the IPA into the private drop channel. */
function postIpaToChannel({ filePath, caption }) {
  return new Promise((resolve) => {
    const script = path.join(__dirname, "send_user.py");
    const args = ["--channel-id", String(CHANNEL_ID), "--file", filePath];
    if (caption) args.push("--caption", caption);
    const child = spawn("python3", [script, ...args], {
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (err) => resolve({ ok: false, error: err.message }));
    child.on("close", () => {
      const line = stdout.trim().split("\n").filter(Boolean).pop() || "";
      try {
        resolve(JSON.parse(line));
      } catch {
        resolve({
          ok: false,
          error: stderr.trim() || stdout.trim() || "send_user.py returned no JSON",
        });
      }
    });
  });
}

/** Bot API forwardMessage — server-side, no re-upload, works past ~50 MB. */
async function botForwardToRecipient({ recipientChatId, channelId, messageId }) {
  try {
    const api = `https://api.telegram.org/bot${BOT_TOKEN}/forwardMessage`;
    const response = await fetch(api, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: recipientChatId,
        from_chat_id: channelId,
        message_id: messageId,
      }),
    });
    const data = await response.json();
    if (!data.ok) {
      return { ok: false, error: data.description || `forward HTTP ${response.status}` };
    }
    return { ok: true, message_id: data.result?.message_id ?? null };
  } catch (err) {
    return { ok: false, error: err.message || String(err) };
  }
}

async function handleDownload(req, res, fileId, nameParam) {
  if (!/^[a-f0-9]{32}$/.test(fileId)) {
    return json(res, 404, { ok: false, error: "not found" });
  }
  const dir = path.join(DATA_DIR, fileId);
  const metaPath = path.join(dir, "meta.json");
  let meta;
  try {
    meta = JSON.parse(await fsp.readFile(metaPath, "utf8"));
  } catch {
    return json(res, 404, { ok: false, error: "not found" });
  }
  if (Date.now() - Number(meta.createdAt || 0) > TTL_MS) {
    await fsp.rm(dir, { recursive: true, force: true }).catch(() => {});
    return json(res, 410, { ok: false, error: "expired" });
  }
  const filename = safeName(meta.filename || nameParam || "app.ipa");
  const filePath = path.join(dir, filename);
  let st;
  try {
    st = await fsp.stat(filePath);
  } catch {
    return json(res, 404, { ok: false, error: "not found" });
  }

  res.writeHead(200, {
    "Content-Type": "application/octet-stream",
    "Content-Length": st.size,
    "Content-Disposition": `attachment; filename="${filename.replace(/"/g, "")}"`,
    "Cache-Control": "private, no-store",
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  fs.createReadStream(filePath).pipe(res);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, {
        ok: true,
        channelDelivery: CHANNEL_DELIVERY,
        maxBytes: MAX_BYTES,
      });
    }
    if (req.method === "PUT" && url.pathname === "/upload") {
      return await handleUpload(req, res, url);
    }
    const download = /^\/d\/([a-f0-9]{32})\/([^/]+)$/.exec(url.pathname);
    if ((req.method === "GET" || req.method === "HEAD") && download) {
      return await handleDownload(req, res, download[1], decodeURIComponent(download[2]));
    }
    return json(res, 404, { ok: false, error: "not found" });
  } catch (err) {
    console.error(err);
    if (!res.headersSent) json(res, 500, { ok: false, error: "server error" });
  }
});

server.requestTimeout = 0;
server.headersTimeout = 120_000;
server.listen(PORT, () => {
  console.log(`UNlicense IPA relay on :${PORT}`);
  console.log(`Public base: ${PUBLIC_BASE}`);
  console.log(`TTL: ${TTL_MS / 3600000}h  max: ${MAX_BYTES} bytes`);
  console.log(
    CHANNEL_DELIVERY
      ? `Channel delivery: on (channel ${CHANNEL_ID} → bot forward)`
      : "Channel delivery: off — set TELEGRAM_API_ID/HASH/SESSION + TELEGRAM_CHANNEL_ID + TELEGRAM_BOT_TOKEN"
  );
});

setInterval(() => {
  cleanup().catch((err) => console.error("cleanup", err));
}, 15 * 60 * 1000);
cleanup().catch(() => {});
