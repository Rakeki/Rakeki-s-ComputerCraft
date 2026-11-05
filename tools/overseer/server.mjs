// Overseer server: the PC side of computers/overseer-bridge. The bridge computer
// in-game posts every rednet message it hears (and every computer's cc_status
// report) here; this keeps the latest state of each computer and streams it to
// the overseer page in your browser (a live map of where everything is, what
// it's doing, and the messages flying between them).
//
//   node tools/overseer/server.mjs            then open http://localhost:8090
//
// First run makes tools/overseer/data/config.json with a random key and prints
// the two 'set' commands to type on the bridge computer. Change port / host /
// key there, or with OVERSEER_PORT, OVERSEER_HOST, OVERSEER_KEY. No dependencies.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, "public");
const DATA = path.join(HERE, "data");
const CONFIG_FILE = path.join(DATA, "config.json");
const STATE_FILE = path.join(DATA, "state.json");

const OFFLINE_AFTER = 30_000; // ms without a cc_status report before a computer shows offline
const BRIDGE_QUIET = 15_000; // ms without a post before the bridge shows as lost
const RECENT_PACKETS = 400; // messages sent to a page when it opens
const HISTORY_SECONDS = 180; // traffic chart length
const MAX_EVENTS = 30; // activity lines kept per computer
const MAX_TRAIL = 80; // positions kept per turtle
const MAX_BODY = 2 * 1024 * 1024; // biggest post accepted from the bridge
const FLUSH_EVERY = 200; // ms between pushes to the pages
const SAVE_EVERY = 30_000;

const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon" };

// ------------------------------------------------------------ config

function loadConfig() {
  fs.mkdirSync(DATA, { recursive: true });
  let cfg = {};
  let fresh = false;
  try { cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8")); } catch { fresh = true; }
  cfg.port ??= 8090;
  cfg.host ??= "127.0.0.1";
  cfg.key ??= crypto.randomBytes(12).toString("base64url");
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + "\n");
  if (process.env.OVERSEER_PORT) cfg.port = Number(process.env.OVERSEER_PORT);
  if (process.env.OVERSEER_HOST) cfg.host = process.env.OVERSEER_HOST;
  if (process.env.OVERSEER_KEY) cfg.key = process.env.OVERSEER_KEY;
  return { cfg, fresh };
}

const { cfg, fresh } = loadConfig();

// ------------------------------------------------------------ state

// nodes: id -> { id, label, kind, role, state, detail, fuel, fuelLimit, pos, posFrom,
//               uptime, lastSeen, offline, events, trail, sent, recv, bytes, placeholder }
const nodes = new Map();
const recent = [];
const history = []; // { t (s), c: { protocol: count } }
const bridge = { id: null, label: null, lastPost: 0, posts: 0, packets: 0, dropped: 0, startedAt: Date.now() };
let dirty = new Set();
let outbox = [];
let saveDue = false;

function loadState() {
  try {
    const s = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    for (const n of s.nodes || []) { n.offline = true; nodes.set(n.id, n); }
  } catch { /* first run */ }
}

function saveState() {
  const tmp = STATE_FILE + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify({ nodes: [...nodes.values()] }));
  fs.renameSync(tmp, STATE_FILE);
  saveDue = false;
}

function node(id) {
  let n = nodes.get(id);
  if (!n) {
    n = { id, label: null, kind: "computer", state: "unknown", events: [], trail: [], sent: 0, recv: 0, bytes: 0, placeholder: true, lastSeen: 0, offline: true };
    nodes.set(id, n);
    dirty.add(id);
  }
  return n;
}

function addEvent(n, t, text) {
  n.events.push({ t, text });
  if (n.events.length > MAX_EVENTS) n.events.splice(0, n.events.length - MAX_EVENTS);
}

const STATUS_FIELDS = ["label", "kind", "role", "state", "detail", "fuel", "fuelLimit", "uptime"];

function applyStatus(id, s, at) {
  const n = node(id);
  if (n.placeholder) { n.placeholder = false; addEvent(n, at, "first seen"); }
  else if (n.offline) addEvent(n, at, "back online");
  for (const k of STATUS_FIELDS) if (s[k] !== undefined) n[k] = s[k];
  if (s.pos && Number.isFinite(s.pos.x)) {
    const p = { x: s.pos.x, y: s.pos.y, z: s.pos.z };
    const last = n.trail[n.trail.length - 1];
    if (!last || last.x !== p.x || last.y !== p.y || last.z !== p.z) {
      n.trail.push({ ...p, t: at });
      if (n.trail.length > MAX_TRAIL) n.trail.splice(0, n.trail.length - MAX_TRAIL);
    }
    n.pos = p;
    n.posFrom = s.posFrom;
  }
  if (s.event) addEvent(n, at, s.event);
  n.lastSeen = at;
  n.offline = false;
  dirty.add(id);
  saveDue = true;
}

function countTraffic(t, proto) {
  const sec = Math.floor(t / 1000);
  let b = history[history.length - 1];
  if (!b || b.t < sec) {
    b = { t: sec, c: {} };
    history.push(b);
    while (history.length && history[0].t <= sec - HISTORY_SECONDS) history.shift();
  } else if (b.t > sec) {
    b = history.find((h) => h.t === sec) || b; // a slightly late message
  }
  b.c[proto] = (b.c[proto] || 0) + 1;
}

// One post from the bridge: its own status, and every message it heard since the last.
function ingest(body) {
  const now = Date.now();
  const skew = Number.isFinite(body.now) ? now - body.now : 0; // bridge clock -> ours
  if (body.bridge) {
    bridge.id = body.bridge.id;
    bridge.label = body.bridge.label;
    if (body.bridge.status) applyStatus(body.bridge.id, { ...body.bridge.status, kind: body.bridge.status.kind || "computer" }, now);
    const b = node(body.bridge.id);
    if (!b.isBridge) { b.isBridge = true; dirty.add(b.id); }
  }
  bridge.lastPost = now;
  bridge.posts++;
  bridge.dropped += body.dropped || 0;
  // Lua's serializeJSON writes an empty list as {}
  for (const p of Array.isArray(body.packets) ? body.packets : []) {
    if (!p || typeof p !== "object") continue;
    if (!Number.isFinite(p.from)) continue;
    const t = Math.min(now, (Number.isFinite(p.t) ? p.t : now) + skew);
    const packet = { t, from: p.from, to: p.to ?? -1, proto: String(p.proto ?? "?"), type: p.type ?? null, re: p.re ?? null, size: p.size || 0, peek: p.peek && typeof p.peek === "object" && Object.keys(p.peek).length ? p.peek : null, dist: p.dist ?? null };
    if (packet.to === 65535) packet.to = -1; // broadcast
    const from = node(packet.from);
    from.sent++; from.bytes += packet.size; dirty.add(from.id);
    if (packet.to >= 0) { const to = node(packet.to); to.recv++; dirty.add(to.id); }
    if (packet.proto === "cc_status" && p.status) applyStatus(packet.from, p.status, t);
    countTraffic(t, packet.proto);
    recent.push(packet);
    outbox.push(packet);
    bridge.packets++;
  }
  if (recent.length > RECENT_PACKETS) recent.splice(0, recent.length - RECENT_PACKETS);
}

function checkOffline() {
  const now = Date.now();
  for (const n of nodes.values()) {
    if (!n.offline && !n.placeholder && now - n.lastSeen > OFFLINE_AFTER) {
      n.offline = true;
      addEvent(n, now, "went offline");
      dirty.add(n.id);
      saveDue = true;
    }
  }
}

function bridgeInfo() {
  return { ...bridge, online: Date.now() - bridge.lastPost < BRIDGE_QUIET, now: Date.now() };
}

// ------------------------------------------------------------ pages (server-sent events)

const clients = new Set();

function sse(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function flush() {
  if (!dirty.size && !outbox.length) return;
  const changed = [...dirty].map((id) => nodes.get(id)).filter(Boolean);
  const packets = outbox;
  dirty = new Set();
  outbox = [];
  for (const res of clients) {
    if (changed.length) sse(res, "nodes", changed);
    if (packets.length) sse(res, "packets", packets);
  }
}

function openStream(req, res) {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive", "x-accel-buffering": "no" });
  res.write("retry: 3000\n\n");
  sse(res, "snapshot", { nodes: [...nodes.values()], packets: recent, history, bridge: bridgeInfo() });
  clients.add(res);
  req.on("close", () => clients.delete(res));
}

// ------------------------------------------------------------ http

function keyOk(req, body) {
  const given = Buffer.from(String(req.headers["x-overseer-key"] ?? body?.key ?? ""));
  const want = Buffer.from(cfg.key);
  return given.length === want.length && crypto.timingSafeEqual(given, want);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error("too big")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function json(res, code, data) {
  res.writeHead(code, { "content-type": "application/json" }).end(JSON.stringify(data));
}

async function handleIngest(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch (e) { json(res, 400, { ok: false, why: "bad json: " + e.message }); return; }
  if (!keyOk(req, body)) { json(res, 401, { ok: false, why: "wrong key" }); return; }
  if (body.ping) { json(res, 200, { ok: true, ping: true, name: "overseer", nodes: nodes.size }); return; }
  ingest(body);
  json(res, 200, { ok: true, nodes: nodes.size });
}

function serveStatic(req, res) {
  let rel = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (rel === "/") rel = "/index.html";
  const p = path.join(PUBLIC, rel);
  if (!p.startsWith(PUBLIC) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404).end("Not found"); return; }
  res.writeHead(200, { "content-type": (TYPES[path.extname(p)] || "application/octet-stream") + "; charset=utf-8", "cache-control": "no-cache" });
  fs.createReadStream(p).pipe(res);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/api/ingest" && req.method === "POST") { handleIngest(req, res).catch(() => json(res, 500, { ok: false })); return; }
  if (url.pathname === "/api/events") { openStream(req, res); return; }
  if (url.pathname === "/api/state") { json(res, 200, { nodes: [...nodes.values()], bridge: bridgeInfo() }); return; }
  if (req.method !== "GET") { res.writeHead(405).end(); return; }
  serveStatic(req, res);
});

// ------------------------------------------------------------ main

loadState();
setInterval(flush, FLUSH_EVERY);
setInterval(checkOffline, 5000);
setInterval(() => { if (saveDue) saveState(); }, SAVE_EVERY);
// pages see the bridge come and go even when nothing else changes
setInterval(() => { for (const res of clients) sse(res, "bridge", bridgeInfo()) }, 2000);
setInterval(() => { for (const res of clients) res.write(": keep-alive\n\n"); }, 15000);

for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { try { saveState(); } catch { } process.exit(0); });

server.on("error", (e) => {
  if (e.code === "EADDRINUSE") console.error(`Port ${cfg.port} is in use. Change "port" in ${CONFIG_FILE} (or set OVERSEER_PORT).`);
  else console.error(e.message);
  process.exit(1);
});

server.listen(cfg.port, cfg.host, () => {
  const shown = cfg.host === "0.0.0.0" ? "localhost" : cfg.host;
  console.log(`Overseer running on http://${shown}:${cfg.port}`);
  if (fresh) console.log(`Made ${path.relative(process.cwd(), CONFIG_FILE)} with a new key.`);
  console.log("");
  console.log("On the bridge computer in-game, type:");
  console.log(`  set overseer.url http://${shown === "localhost" ? "127.0.0.1" : shown}:${cfg.port}`);
  console.log(`  set overseer.key ${cfg.key}`);
  console.log("  overseer test");
  console.log("");
  console.log("(If the Minecraft server runs on another machine, use this PC's address instead of 127.0.0.1,");
  console.log(` and set "host": "0.0.0.0" in the config so it listens on the network.)`);
});
