// Overseer page: a live map of every computer and turtle the bridge hears, the
// rednet messages flying between them, a fleet list, a traffic chart and a
// packet log. Data comes from tools/overseer/server.mjs as server-sent events
// (api/events); with no server (or ?demo) it runs the demo world in demo.js.
"use strict";
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const params = new URLSearchParams(location.search);

  // ------------------------------------------------------------ tunables
  const LIVE_DELAY = 1100; // ms: the bridge posts about once a second, so play messages back at their real spacing
  const MAX_FLIGHTS = 500; // messages in the air at once; more and the oldest land early
  const LOG_ROWS = 160;
  const KEEP_PACKETS = 600;
  const CHART_SECONDS = 120;
  const EDGE_FADE = 90_000; // ms a link between two computers stays drawn after their last message

  const PROTO_COLORS = {
    cc_status: "#2fd6a4", storage: "#ffb02e", automine: "#ff6a3d", projector_build: "#5aa8ff",
    village_plan: "#b38cff", village_crew: "#9d7bff", craft_overseer: "#ff3fd2", storage_crafter: "#ff8ae0",
    factory: "#ffe45c", instabuild: "#5effa0", dns: "#7d93ad",
  };
  const STATE_COLORS = {
    lime: ["running", "working", "mining", "digging", "building", "serving", "sealing", "farming", "harvesting", "crafting", "clearing", "paving", "surveying", "filling", "planting", "smelting", "posting", "listening"],
    blue: ["restocking", "checking", "docking", "returning", "traveling", "travelling", "unloading", "moving"],
    yellow: ["waiting"], orange: ["stuck", "paused"], red: ["error", "alert"], gray: ["idle", "starting", "unknown"], green: ["done"],
  };
  const PALETTE = { lime: "#8cff3f", blue: "#3fc4ff", yellow: "#ffe45c", orange: "#ff9a3d", red: "#ff4d5e", gray: "#9fb3c8", green: "#3fe08a" };
  const STATE_OF = {};
  for (const [c, words] of Object.entries(STATE_COLORS)) for (const w of words) STATE_OF[w] = PALETTE[c];
  const ALERT = new Set(["error", "alert", "stuck"]);
  const OFF = "#3a4658";

  const hashColors = {};
  function protoColor(p) {
    if (PROTO_COLORS[p]) return PROTO_COLORS[p];
    if (!hashColors[p]) {
      let h = 0;
      for (const ch of String(p)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
      hashColors[p] = `hsl(${h % 360} 90% 64%)`;
    }
    return hashColors[p];
  }
  function stateColor(n) {
    if (n.placeholder || n.offline) return OFF;
    return STATE_OF[n.state] || "#d8ecff";
  }

  // ------------------------------------------------------------ store
  const S = {
    nodes: new Map(),
    packets: [],
    total: 0,
    buckets: new Map(), // second -> { proto: count }
    protoTotals: {},
    hidden: new Set(),
    edges: new Map(),
    pending: [],
    flights: [],
    rings: [],
    sparks: [],
    sel: null,
    hover: null,
    mode: "connecting",
    bridge: null,
    delay: LIVE_DELAY,
    paused: false,
    opts: { trails: true, beats: true, labels: true, follow: false },
    fleetDirty: true,
    protosDirty: true,
    fitted: false,
    autoFit: true, // keep fitting everything in view until the player pans, zooms or picks something
    snapped: false, // the first fit jumps there; later ones glide
  };

  const name = (id) => {
    if (id < 0) return "everyone";
    const n = S.nodes.get(id);
    return (n && n.label) || `#${id}`;
  };

  function applyNode(raw) {
    let n = S.nodes.get(raw.id);
    if (!n) {
      n = { born: performance.now(), pulse: 0, peers: {}, hist: new Map(), vx: null, vz: null };
      S.nodes.set(raw.id, n);
      if (S.autoFit) S.fitted = false; // a newcomer may be off-screen: fit again until the player moves the map
    } else if (S.autoFit && raw.pos && !n.pos) S.fitted = false;
    const wasOff = n.offline, oldState = n.state;
    Object.assign(n, raw);
    if (n.pos && n.vx == null) { n.vx = n.pos.x; n.vz = n.pos.z; }
    if (!n.placeholder && wasOff === true && !n.offline) n.pulse = 1.4;
    if (oldState !== n.state && ALERT.has(n.state)) n.pulse = 1.6;
    S.fleetDirty = true;
    if (S.sel === n.id) drawerDirty = true;
  }

  function count(p) {
    const sec = Math.floor(p.t / 1000);
    let b = S.buckets.get(sec);
    if (!b) { b = {}; S.buckets.set(sec, b); }
    b[p.proto] = (b[p.proto] || 0) + 1;
    if (!(p.proto in S.protoTotals)) S.protosDirty = true;
    S.protoTotals[p.proto] = (S.protoTotals[p.proto] || 0) + 1;
  }

  function remember(p) {
    S.total++;
    count(p);
    S.packets.push(p);
    if (S.packets.length > KEEP_PACKETS) S.packets.splice(0, S.packets.length - KEEP_PACKETS);
    const a = S.nodes.get(p.from), b = p.to >= 0 ? S.nodes.get(p.to) : null;
    const sec = Math.floor(p.t / 1000);
    for (const n of [a, b]) if (n) n.hist.set(sec, (n.hist.get(sec) || 0) + 1);
    if (a && b) {
      a.peers[p.to] = (a.peers[p.to] || 0) + 1;
      b.peers[p.from] = (b.peers[p.from] || 0) + 1;
      const key = p.from < p.to ? `${p.from}:${p.to}` : `${p.to}:${p.from}`;
      const e = S.edges.get(key) || { a: Math.min(p.from, p.to), b: Math.max(p.from, p.to), w: 0 };
      e.w++; e.last = Date.now(); e.proto = p.proto;
      S.edges.set(key, e);
    }
  }

  function addPackets(list, animate) {
    if (!list.length) return;
    const now = performance.now();
    const newest = Math.max(...list.map((p) => p.t));
    for (const p of list) {
      remember(p);
      if (!animate || S.paused) continue;
      const at = now + S.delay - Math.min(S.delay, newest - p.t);
      S.pending.push({ p, at });
      logRow(p, true);
    }
    if (S.pending.length > MAX_FLIGHTS * 2) S.pending.splice(0, S.pending.length - MAX_FLIGHTS * 2);
  }

  function applySnapshot(s) {
    S.nodes.clear(); S.packets = []; S.total = 0; S.buckets.clear(); S.protoTotals = {}; S.edges.clear();
    for (const n of s.nodes || []) applyNode(n);
    for (const h of s.history || []) {
      S.buckets.set(h.t, { ...h.c });
      for (const [k, v] of Object.entries(h.c)) S.protoTotals[k] = (S.protoTotals[k] || 0) + v;
    }
    const packs = s.packets || [];
    for (const p of packs) { S.packets.push(p); S.total++; }
    for (const p of packs.slice(-LOG_ROWS)) logRow(p, false);
    if (s.bridge) setBridge(s.bridge);
    S.protosDirty = true;
    S.fitted = false;
  }

  function setBridge(b) {
    S.bridge = b;
    if (S.mode === "demo") return;
    setMode(b.online ? "live" : "warn");
  }

  // ------------------------------------------------------------ link indicator
  function setMode(mode) {
    S.mode = mode;
    const el = $("#link"), text = $("#linkText");
    el.dataset.mode = mode;
    const b = S.bridge;
    text.textContent = {
      live: `LIVE · BRIDGE ${b && b.id != null ? "#" + b.id : ""}`,
      warn: b && b.posts ? "SERVER OK · BRIDGE SILENT" : "SERVER OK · NO BRIDGE YET",
      down: "LINK LOST · RETRYING",
      demo: "DEMO WORLD",
      connecting: "CONNECTING",
    }[mode] || mode;
    $("#demoBanner").hidden = mode !== "demo";
  }

  // ------------------------------------------------------------ formatting
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const pad = (n) => String(n).padStart(2, "0");
  const hms = (t) => { const d = new Date(t); return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };
  function fmtNum(n) {
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e4) return (n / 1e3).toFixed(1) + "k";
    return String(Math.round(n));
  }
  function fmtBytes(n) {
    if (n >= 1 << 20) return (n / (1 << 20)).toFixed(1) + " MB";
    if (n >= 1024) return (n / 1024).toFixed(1) + " kB";
    return `${n} B`;
  }
  function fmtDur(s) {
    s = Math.max(0, Math.floor(s));
    if (s < 60) return `${s}s`;
    if (s < 3600) return `${Math.floor(s / 60)}m ${pad(s % 60)}s`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ${pad(Math.floor(s / 60) % 60)}m`;
    return `${Math.floor(s / 86400)}d ${Math.floor(s / 3600) % 24}h`;
  }
  const ago = (t) => (t ? fmtDur((Date.now() - t) / 1000) + " ago" : "never");
  function fuelText(n) {
    if (n.fuel == null) return null;
    if (n.fuel === "unlimited" || n.fuelLimit === "unlimited") return "∞";
    return fmtNum(n.fuel);
  }
  function fuelFrac(n) {
    if (typeof n.fuel !== "number" || typeof n.fuelLimit !== "number" || !n.fuelLimit) return null;
    return Math.max(0, Math.min(1, n.fuel / n.fuelLimit));
  }
  function peekText(p) {
    if (!p.peek) return "";
    return Object.entries(p.peek).map(([k, v]) => `${k}=${v}`).join("  ");
  }
  const typeText = (p) => (p.re ? `↩ ${p.re}` : p.type || "·");

  function iconSvg(n, c) {
    let shape;
    if (n.isBridge) shape = `<path d="M14 3l9.5 5.5v11L14 25l-9.5-5.5v-11z" fill="none" stroke="${c}" stroke-width="2"/><circle cx="14" cy="14" r="3.5" fill="${c}"/>`;
    else if (n.kind === "turtle") shape = `<path d="M14 3l11 11-11 11L3 14z" fill="${c}22" stroke="${c}" stroke-width="2"/><path d="M10 16l4-5 4 5" fill="none" stroke="${c}" stroke-width="2"/>`;
    else if (n.kind === "pocket") shape = `<circle cx="14" cy="14" r="9.5" fill="${c}22" stroke="${c}" stroke-width="2"/><rect x="11" y="9" width="6" height="7" rx="1" fill="${c}"/>`;
    else shape = `<rect x="4.5" y="4.5" width="19" height="19" rx="4" fill="${c}22" stroke="${c}" stroke-width="2"/><rect x="9" y="9" width="10" height="7" rx="1" fill="${c}"/>`;
    return `<svg viewBox="0 0 28 28" width="28" height="28" style="filter:drop-shadow(0 0 5px ${c})">${shape}</svg>`;
  }

  // ------------------------------------------------------------ map: camera
  const canvas = $("#map");
  const ctx = canvas.getContext("2d");
  let W = 0, H = 0, DPR = 1;
  const cam = { x: 0, z: 0, s: 2 };
  const goal = { x: 0, z: 0, s: 2 };

  function resize() {
    DPR = Math.min(2, window.devicePixelRatio || 1);
    const r = canvas.getBoundingClientRect();
    W = r.width; H = r.height;
    canvas.width = Math.round(W * DPR); canvas.height = Math.round(H * DPR);
    for (const c of [chart, spark()].filter(Boolean)) sizeCanvas(c);
  }
  function sizeCanvas(c) {
    const r = c.getBoundingClientRect();
    c.width = Math.round(r.width * DPR); c.height = Math.round(r.height * DPR);
  }
  const sx = (x) => (x - cam.x) * cam.s + W / 2;
  const sz = (z) => (z - cam.z) * cam.s + H / 2;
  const wx = (px) => (px - W / 2) / cam.s + cam.x;
  const wz = (py) => (py - H / 2) / cam.s + cam.z;

  // Where each node is drawn: its position, or (no GPS) on a slow ring round the middle.
  let ringCenter = { x: 0, z: 0 }, ringR = 40;
  function layout(t) {
    const placed = [], loose = [];
    for (const n of S.nodes.values()) (n.pos ? placed : loose).push(n);
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const n of placed) {
      minX = Math.min(minX, n.pos.x); maxX = Math.max(maxX, n.pos.x);
      minZ = Math.min(minZ, n.pos.z); maxZ = Math.max(maxZ, n.pos.z);
    }
    const br = S.bridge && S.nodes.get(S.bridge.id);
    if (br && br.pos) ringCenter = { x: br.pos.x, z: br.pos.z };
    else if (placed.length) ringCenter = { x: (minX + maxX) / 2, z: (minZ + maxZ) / 2 };
    ringR = placed.length ? Math.max(30, Math.max(maxX - minX, maxZ - minZ) * 0.12) : 40;
    loose.sort((a, b) => a.id - b.id);
    loose.forEach((n, i) => {
      const a = (i / loose.length) * Math.PI * 2 + t * 0.00004;
      n.loose = true;
      n.gx = ringCenter.x + Math.cos(a) * ringR;
      n.gz = ringCenter.z + Math.sin(a) * ringR;
    });
    for (const n of placed) { n.loose = false; n.gx = n.pos.x; n.gz = n.pos.z; }
    return placed.length ? { minX, maxX, minZ, maxZ } : null;
  }

  function fit(bounds) {
    bounds = bounds || layout(performance.now());
    if (!bounds) { goal.x = ringCenter.x; goal.z = ringCenter.z; goal.s = 3; return; }
    const dx = Math.max(24, bounds.maxX - bounds.minX + ringR), dz = Math.max(24, bounds.maxZ - bounds.minZ + ringR);
    goal.x = (bounds.minX + bounds.maxX) / 2;
    goal.z = (bounds.minZ + bounds.maxZ) / 2;
    goal.s = Math.max(0.04, Math.min(16, Math.min((W - 120) / dx, (H - 120) / dz)));
    S.opts.follow = false; pressed("#bFollow", false);
  }
  function flyTo(n, zoom) {
    if (n.gx == null) return;
    S.autoFit = false;
    goal.x = n.gx; goal.z = n.gz;
    if (zoom) goal.s = Math.max(goal.s, 5);
  }

  // ------------------------------------------------------------ map: drawing
  function grid() {
    const steps = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192];
    const step = steps.find((s) => s * cam.s >= 34) || 8192;
    const major = step * 4;
    const x0 = Math.floor(wx(0) / step) * step, x1 = wx(W);
    const z0 = Math.floor(wz(0) / step) * step, z1 = wz(H);
    ctx.lineWidth = 1;
    for (let pass = 0; pass < 2; pass++) {
      ctx.beginPath();
      for (let x = x0; x <= x1; x += step) if ((x % major === 0) === !!pass) { const p = Math.round(sx(x)) + 0.5; ctx.moveTo(p, 0); ctx.lineTo(p, H); }
      for (let z = z0; z <= z1; z += step) if ((z % major === 0) === !!pass) { const p = Math.round(sz(z)) + 0.5; ctx.moveTo(0, p); ctx.lineTo(W, p); }
      ctx.strokeStyle = pass ? "rgba(63,224,255,0.13)" : "rgba(63,224,255,0.045)";
      ctx.stroke();
    }
    // origin cross
    ctx.strokeStyle = "rgba(255,63,210,0.28)";
    ctx.beginPath();
    ctx.moveTo(sx(0), 0); ctx.lineTo(sx(0), H); ctx.moveTo(0, sz(0)); ctx.lineTo(W, sz(0));
    ctx.stroke();
    ctx.fillStyle = "rgba(125,147,173,0.55)";
    ctx.font = "600 10px 'JetBrains Mono', monospace";
    ctx.textBaseline = "top";
    for (let x = Math.ceil(wx(0) / major) * major; x <= x1; x += major) ctx.fillText(String(x), sx(x) + 4, H - 16);
    for (let z = Math.ceil(wz(0) / major) * major; z <= z1; z += major) ctx.fillText(String(z), 6, sz(z) + 4);
    $("#zoomInfo").textContent = `grid ${step} · ${cam.s >= 1 ? cam.s.toFixed(1) + " px/block" : (1 / cam.s).toFixed(1) + " blocks/px"}`;
  }

  function radar(t) {
    if (!ctx.createConicGradient) return;
    const cx = sx(ringCenter.x), cy = sz(ringCenter.z);
    const a = (t / 1000) * 0.7;
    const R = Math.hypot(W, H);
    const g = ctx.createConicGradient(a, cx, cy);
    g.addColorStop(0, "rgba(63,224,255,0.10)");
    g.addColorStop(0.07, "rgba(63,224,255,0.0)");
    g.addColorStop(1, "rgba(63,224,255,0.0)");
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fill();
    for (let i = 1; i <= 4; i++) {
      ctx.strokeStyle = `rgba(63,224,255,${0.06 - i * 0.008})`;
      ctx.beginPath(); ctx.arc(cx, cy, Math.min(W, H) * 0.14 * i, 0, Math.PI * 2); ctx.stroke();
    }
    S.sweep = a;
  }

  function shapePath(n, x, y, r) {
    ctx.beginPath();
    if (n.isBridge) {
      for (let i = 0; i < 6; i++) { const a = Math.PI / 6 + (i * Math.PI) / 3; ctx.lineTo(x + Math.cos(a) * r * 1.25, y + Math.sin(a) * r * 1.25); }
      ctx.closePath();
    } else if (n.kind === "turtle") {
      ctx.moveTo(x, y - r * 1.15); ctx.lineTo(x + r * 1.15, y); ctx.lineTo(x, y + r * 1.15); ctx.lineTo(x - r * 1.15, y); ctx.closePath();
    } else if (n.kind === "pocket") {
      ctx.arc(x, y, r, 0, Math.PI * 2);
    } else {
      const k = r * 0.95, rr = r * 0.35;
      ctx.roundRect ? ctx.roundRect(x - k, y - k, k * 2, k * 2, rr) : ctx.rect(x - k, y - k, k * 2, k * 2);
    }
  }

  function glow(x, y, r, color, alpha) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, withAlpha(color, alpha));
    g.addColorStop(1, withAlpha(color, 0));
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
  }
  const alphaCache = new Map();
  function withAlpha(color, a) {
    let rgb = alphaCache.get(color);
    if (!rgb) {
      const c = document.createElement("canvas").getContext("2d");
      c.fillStyle = color; c.fillRect(0, 0, 1, 1);
      const d = c.getImageData(0, 0, 1, 1).data;
      rgb = `${d[0]},${d[1]},${d[2]}`;
      alphaCache.set(color, rgb);
    }
    return `rgba(${rgb},${Math.max(0, Math.min(1, a))})`;
  }

  function nodeRadius() { return Math.max(6, Math.min(13, 5 + cam.s * 0.9)); }

  function drawEdges(now) {
    ctx.lineCap = "round";
    for (const [key, e] of S.edges) {
      const age = now - e.last;
      if (age > EDGE_FADE) { S.edges.delete(key); continue; }
      if (S.hidden.has(e.proto)) continue;
      const a = S.nodes.get(e.a), b = S.nodes.get(e.b);
      if (!a || !b || a.vx == null || b.vx == null) continue;
      const k = 1 - age / EDGE_FADE;
      const ax = sx(a.vx), ay = sz(a.vz), bx = sx(b.vx), by = sz(b.vz);
      const sel = S.sel != null && (e.a === S.sel || e.b === S.sel);
      ctx.strokeStyle = withAlpha(protoColor(e.proto), (sel ? 0.45 : 0.14) * k);
      ctx.lineWidth = Math.min(4, 0.8 + Math.log2(1 + e.w) * 0.35) * (sel ? 1.5 : 1);
      ctx.setLineDash(sel ? [] : [2, 6]);
      ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke();
    }
    ctx.setLineDash([]);
  }

  function drawTrails() {
    if (!S.opts.trails) return;
    for (const n of S.nodes.values()) {
      if (!n.trail || n.trail.length < 2 || n.loose) continue;
      const c = n.offline ? OFF : stateColor(n);
      const pts = n.trail;
      for (let i = 1; i < pts.length; i++) {
        const k = i / pts.length;
        ctx.strokeStyle = withAlpha(c, 0.06 + k * (S.sel === n.id ? 0.6 : 0.3));
        ctx.lineWidth = 1 + k * 1.5;
        ctx.beginPath(); ctx.moveTo(sx(pts[i - 1].x), sz(pts[i - 1].z)); ctx.lineTo(sx(pts[i].x), sz(pts[i].z)); ctx.stroke();
      }
    }
  }

  function bezier(f, t) {
    const u = 1 - t;
    return [u * u * f.ax + 2 * u * t * f.cx + t * t * f.bx, u * u * f.ay + 2 * u * t * f.cy + t * t * f.by];
  }

  function launch(p, now) {
    const a = S.nodes.get(p.from);
    if (!a || a.vx == null) return;
    a.pulse = Math.max(a.pulse, 0.6);
    flashRow(p.from, protoColor(p.proto));
    if (p.to < 0) {
      if (p.proto === "cc_status" && !S.opts.beats) return;
      S.rings.push({ id: p.from, t0: now, color: protoColor(p.proto), faint: p.proto === "cc_status", dur: p.proto === "cc_status" ? 1400 : 1900 });
      return;
    }
    const b = S.nodes.get(p.to);
    if (!b || b.vx == null || b === a) return;
    const dist = Math.hypot(sx(a.vx) - sx(b.vx), sz(a.vz) - sz(b.vz));
    S.flights.push({ p, a, b, t0: now, dur: 420 + Math.min(1300, dist * 1.3), color: protoColor(p.proto), size: p.size || 0 });
    if (S.flights.length > MAX_FLIGHTS) S.flights.shift();
  }

  function drawFlights(now) {
    ctx.globalCompositeOperation = "lighter";
    const keep = [];
    for (const f of S.flights) {
      if (S.hidden.has(f.p.proto)) continue;
      const t = (now - f.t0) / f.dur;
      const A = f.a, B = f.b;
      f.ax = sx(A.vx); f.ay = sz(A.vz); f.bx = sx(B.vx); f.by = sz(B.vz);
      const mx = (f.ax + f.bx) / 2, my = (f.ay + f.by) / 2;
      const dx = f.bx - f.ax, dy = f.by - f.ay, len = Math.hypot(dx, dy) || 1;
      const bend = Math.min(len * 0.22, 90) * (f.p.from < f.p.to ? 1 : -1);
      f.cx = mx - (dy / len) * bend; f.cy = my + (dx / len) * bend;
      if (t >= 1) {
        B.pulse = Math.max(B.pulse, 0.8);
        flashRow(B.id, f.color);
        for (let i = 0; i < 7; i++) {
          const a = Math.random() * Math.PI * 2, v = 30 + Math.random() * 70;
          S.sparks.push({ n: B, vx: Math.cos(a) * v, vy: Math.sin(a) * v, t0: now, color: f.color });
        }
        continue;
      }
      keep.push(f);
      const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; // ease in-out
      const size = 2.2 + Math.min(4, Math.log2(1 + f.size / 64));
      // the arc it's on, faintly
      ctx.strokeStyle = withAlpha(f.color, 0.08);
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(f.ax, f.ay); ctx.quadraticCurveTo(f.cx, f.cy, f.bx, f.by); ctx.stroke();
      // tail
      const TAIL = 10;
      let [px, py] = bezier(f, Math.max(0, e - 0.22));
      for (let i = 1; i <= TAIL; i++) {
        const tt = Math.max(0, e - 0.22 + (0.22 * i) / TAIL);
        const [qx, qy] = bezier(f, tt);
        ctx.strokeStyle = withAlpha(f.color, (i / TAIL) * 0.8);
        ctx.lineWidth = (i / TAIL) * size * 1.4;
        ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(qx, qy); ctx.stroke();
        px = qx; py = qy;
      }
      const [hx, hy] = bezier(f, e);
      glow(hx, hy, size * 5, f.color, 0.55);
      ctx.fillStyle = "#fff";
      ctx.beginPath(); ctx.arc(hx, hy, size * 0.65, 0, Math.PI * 2); ctx.fill();
    }
    S.flights = keep;

    const rings = [];
    for (const r of S.rings) {
      const t = (now - r.t0) / r.dur;
      if (t >= 1) continue;
      rings.push(r);
      const n = S.nodes.get(r.id);
      if (!n || n.vx == null) continue;
      const x = sx(n.vx), y = sz(n.vz);
      const R = nodeRadius() + (r.faint ? 26 : 70) * Math.sqrt(t);
      ctx.strokeStyle = withAlpha(r.color, (1 - t) * (r.faint ? 0.35 : 0.8));
      ctx.lineWidth = r.faint ? 1.2 : 2.2 * (1 - t) + 0.5;
      ctx.beginPath(); ctx.arc(x, y, R, 0, Math.PI * 2); ctx.stroke();
    }
    S.rings = rings;

    const sparks = [];
    for (const s of S.sparks) {
      const age = (now - s.t0) / 1000;
      if (age > 0.6) continue;
      sparks.push(s);
      const x = sx(s.n.vx) + s.vx * age, y = sz(s.n.vz) + s.vy * age;
      ctx.fillStyle = withAlpha(s.color, 1 - age / 0.6);
      ctx.fillRect(x - 1.2, y - 1.2, 2.4, 2.4);
    }
    S.sparks = sparks;
    ctx.globalCompositeOperation = "source-over";
  }

  function drawNodes(now, dt) {
    const r = nodeRadius();
    const list = [...S.nodes.values()].filter((n) => n.vx != null).sort((a, b) => (a.id === S.sel) - (b.id === S.sel) || (a.id === S.hover) - (b.id === S.hover));
    const taken = [];
    for (const n of list) {
      const c = stateColor(n);
      const x = sx(n.vx), y = sz(n.vz);
      if (x < -60 || y < -60 || x > W + 60 || y > H + 60) continue;
      const spawn = Math.min(1, (now - n.born) / 600);
      const pul = n.pulse;
      n.pulse = Math.max(0, n.pulse - dt * 2.2);
      const rr = r * (0.3 + 0.7 * spawn) * (1 + Math.min(0.4, pul * 0.3));
      const live = !n.offline && !n.placeholder;

      // radar sweep lights up what it passes
      if (live && S.sweep != null) {
        const ang = Math.atan2(y - sz(ringCenter.z), x - sx(ringCenter.x));
        let d = (S.sweep - ang) % (Math.PI * 2); if (d < 0) d += Math.PI * 2;
        if (d < 0.5) n.pulse = Math.max(n.pulse, 0.35 * (1 - d / 0.5));
      }

      ctx.globalCompositeOperation = "lighter";
      if (live) glow(x, y, rr * (3.2 + pul * 2), c, 0.22 + pul * 0.3);
      if (n.isBridge && live) {
        ctx.strokeStyle = withAlpha("#3fe0ff", 0.55);
        ctx.lineWidth = 1.5;
        ctx.setLineDash([3, 5]);
        ctx.lineDashOffset = -now / 40;
        ctx.beginPath(); ctx.arc(x, y, rr * 2.4, 0, Math.PI * 2); ctx.stroke();
        ctx.setLineDash([]);
      }
      if (live && ALERT.has(n.state)) {
        const t = (now % 1200) / 1200;
        ctx.strokeStyle = withAlpha(c, 1 - t);
        ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(x, y, rr * (1.4 + t * 2.4), 0, Math.PI * 2); ctx.stroke();
      }
      ctx.globalCompositeOperation = "source-over";

      shapePath(n, x, y, rr);
      ctx.fillStyle = "rgba(4,10,20,0.92)";
      ctx.fill();
      ctx.lineWidth = n.isBridge ? 2.4 : 2;
      ctx.strokeStyle = c;
      if (n.loose || !live) ctx.setLineDash([3, 3]);
      ctx.stroke();
      ctx.setLineDash([]);
      if (live) {
        ctx.fillStyle = c;
        if (n.kind === "turtle" && !n.isBridge) {
          ctx.beginPath(); ctx.moveTo(x - rr * 0.38, y + rr * 0.22); ctx.lineTo(x, y - rr * 0.3); ctx.lineTo(x + rr * 0.38, y + rr * 0.22); ctx.lineWidth = 2; ctx.strokeStyle = c; ctx.stroke();
        } else {
          ctx.beginPath(); ctx.arc(x, y, rr * 0.32, 0, Math.PI * 2); ctx.fill();
        }
      } else if (n.loose) {
        ctx.fillStyle = OFF; ctx.font = `800 ${Math.round(rr)}px Orbitron, sans-serif`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
        ctx.fillText("?", x, y + 1); ctx.textAlign = "left";
      }

      if (n.id === S.sel) reticle(x, y, rr, c, now);

      const showLabel = n.id === S.sel || n.id === S.hover || (S.opts.labels && (cam.s > 0.9 || n.isBridge || (live && ALERT.has(n.state))));
      if (showLabel) {
        // skip a label that would overlap one already drawn (the selected and hovered ones always show)
        const ly = y + rr * 1.3 + 6;
        ctx.font = "700 12px Rajdhani, sans-serif";
        const half = Math.max(40, ctx.measureText(n.label || `#${n.id}`).width / 2 + 4);
        const box = [x - half, ly, x + half, ly + 26];
        const must = n.id === S.sel || n.id === S.hover;
        if (!must && taken.some((b) => box[0] < b[2] && box[2] > b[0] && box[1] < b[3] && box[3] > b[1])) continue;
        taken.push(box);
        label(n, x, ly, c, live);
      }
    }
  }

  function label(n, x, y, c, live) {
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.font = "700 12px Rajdhani, sans-serif";
    const title = n.label || `#${n.id}`;
    ctx.shadowColor = "rgba(0,0,0,0.9)"; ctx.shadowBlur = 6;
    ctx.fillStyle = live ? "#e8f6ff" : "#5c6f86";
    ctx.fillText(title, x, y);
    ctx.font = "600 10px 'JetBrains Mono', monospace";
    ctx.fillStyle = live ? c : "#4a5d75";
    const sub = n.loose ? "no GPS" : live ? `${n.state || ""}${n.pos ? " · y" + n.pos.y : ""}` : n.placeholder ? "heard only" : "offline";
    ctx.fillText(sub, x, y + 14);
    ctx.shadowBlur = 0;
    ctx.textAlign = "left";
  }

  function reticle(x, y, r, c, now) {
    const R = r * 2.1 + Math.sin(now / 300) * 1.5;
    ctx.strokeStyle = c;
    ctx.lineWidth = 2;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(now / 1600);
    for (let i = 0; i < 4; i++) {
      ctx.rotate(Math.PI / 2);
      ctx.beginPath(); ctx.arc(0, 0, R, -0.35, 0.35); ctx.stroke();
    }
    ctx.restore();
    ctx.strokeStyle = withAlpha(c, 0.5);
    ctx.lineWidth = 1;
    const L = R + 10;
    ctx.beginPath();
    ctx.moveTo(x - L - 8, y); ctx.lineTo(x - L, y); ctx.moveTo(x + L, y); ctx.lineTo(x + L + 8, y);
    ctx.moveTo(x, y - L - 8); ctx.lineTo(x, y - L); ctx.moveTo(x, y + L); ctx.lineTo(x, y + L + 8);
    ctx.stroke();
  }

  let last = performance.now();
  let frameErrors = 0;
  function frame(now) {
    // one bad frame (odd data from a computer) must never stop the map for good
    try { draw(now); } catch (e) { if (frameErrors++ < 5) console.error("overseer frame:", e); }
    requestAnimationFrame(frame);
  }
  function draw(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    const bounds = layout(now);
    if (!S.fitted && W && H && S.nodes.size) {
      fit(bounds);
      if (!S.snapped) { Object.assign(cam, goal); S.snapped = true; }
      S.fitted = true;
    }
    if (S.opts.follow && S.sel != null) { const n = S.nodes.get(S.sel); if (n && n.gx != null) { goal.x = n.gx; goal.z = n.gz; } }
    const k = 1 - Math.exp(-dt * 7);
    cam.x += (goal.x - cam.x) * k; cam.z += (goal.z - cam.z) * k;
    cam.s *= Math.pow(goal.s / cam.s, k);
    const m = 1 - Math.exp(-dt * 4);
    for (const n of S.nodes.values()) {
      if (n.gx == null) continue;
      if (n.vx == null) { n.vx = n.gx; n.vz = n.gz; }
      n.vx += (n.gx - n.vx) * m; n.vz += (n.gz - n.vz) * m;
    }
    if (!S.paused) {
      const due = [];
      S.pending = S.pending.filter((q) => (q.at <= now ? (due.push(q), false) : true));
      for (const q of due) launch(q.p, now);
    }

    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const bg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, Math.hypot(W, H) / 1.6);
    bg.addColorStop(0, "#081626"); bg.addColorStop(1, "#03060c");
    ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
    grid();
    radar(now);
    drawEdges(Date.now());
    drawTrails();
    drawFlights(now);
    drawNodes(now, dt);
    if (!S.nodes.size) {
      ctx.fillStyle = "rgba(125,147,173,0.8)"; ctx.font = "600 13px 'JetBrains Mono', monospace"; ctx.textAlign = "center";
      ctx.fillText("Waiting for the bridge to hear something…", W / 2, H / 2 + 60); ctx.textAlign = "left";
    }
  }

  // ------------------------------------------------------------ map: input
  const pointers = new Map();
  let drag = null, moved = 0;
  function hit(px, py) {
    const r = nodeRadius() + 7;
    let best = null, bd = r * r;
    for (const n of S.nodes.values()) {
      if (n.vx == null) continue;
      const dx = sx(n.vx) - px, dy = sz(n.vz) - py, d = dx * dx + dy * dy;
      if (d < bd) { bd = d; best = n; }
    }
    return best;
  }
  function local(e) { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  canvas.addEventListener("pointerdown", (e) => {
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, local(e));
    if (pointers.size === 1) { drag = { x: e.clientX, y: e.clientY }; moved = 0; canvas.classList.add("dragging"); }
  });
  canvas.addEventListener("pointermove", (e) => {
    const [px, py] = local(e);
    $("#cursor").textContent = `X ${Math.round(wx(px))}  Z ${Math.round(wz(py))}`;
    if (pointers.has(e.pointerId)) {
      const prev = pointers.get(e.pointerId);
      pointers.set(e.pointerId, [px, py]);
      if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        const other = [...pointers.entries()].find(([id]) => id !== e.pointerId)[1];
        const d0 = Math.hypot(prev[0] - other[0], prev[1] - other[1]), d1 = Math.hypot(a[0] - b[0], a[1] - b[1]);
        if (d0 > 0) zoomAt((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, d1 / d0);
        moved += 10;
        return;
      }
      if (drag) {
        const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
        moved += Math.abs(dx) + Math.abs(dy);
        cam.x -= dx / cam.s; cam.z -= dy / cam.s; goal.x = cam.x; goal.z = cam.z;
        drag = { x: e.clientX, y: e.clientY };
        if (moved > 4) { S.opts.follow = false; S.autoFit = false; pressed("#bFollow", false); }
      }
      return;
    }
    const n = hit(px, py);
    setHover(n, e.clientX, e.clientY);
  });
  const endPointer = (e) => {
    const [px, py] = local(e);
    pointers.delete(e.pointerId);
    if (!pointers.size) {
      canvas.classList.remove("dragging");
      if (drag && moved < 5) { const n = hit(px, py); select(n ? n.id : null); }
      drag = null;
    }
  };
  canvas.addEventListener("pointerup", endPointer);
  canvas.addEventListener("pointercancel", endPointer);
  canvas.addEventListener("pointerleave", () => setHover(null));
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    const [px, py] = local(e);
    zoomAt(px, py, Math.exp(-e.deltaY * 0.0015));
  }, { passive: false });
  canvas.addEventListener("dblclick", (e) => {
    const [px, py] = local(e);
    const n = hit(px, py);
    if (n) { flyTo(n, true); return; }
    goal.x = wx(px); goal.z = wz(py); goal.s = Math.min(16, goal.s * 2);
  });
  function zoomAt(px, py, f) {
    S.autoFit = false;
    const s = Math.max(0.03, Math.min(24, cam.s * f));
    const bx = wx(px), bz = wz(py);
    cam.s = s;
    cam.x = bx - (px - W / 2) / s; cam.z = bz - (py - H / 2) / s;
    Object.assign(goal, cam);
  }

  const tip = $("#tip");
  function setHover(n, cx, cy) {
    S.hover = n ? n.id : null;
    canvas.classList.toggle("pointing", !!n);
    if (!n) { tip.classList.remove("on"); return; }
    const c = stateColor(n);
    const pos = n.pos ? `X ${n.pos.x}  Y ${n.pos.y}  Z ${n.pos.z}` : "no position (no GPS)";
    const fuel = fuelText(n);
    tip.innerHTML = `<h4 style="color:${c}">${esc(n.label || "#" + n.id)}</h4>
      <div class="k">#${n.id} · ${esc(n.kind || "computer")}${n.role ? " · " + esc(n.role) : ""}</div>
      <div>${esc(n.placeholder ? "heard on the network, never reported" : n.offline ? "offline · last seen " + ago(n.lastSeen) : (n.state || "") + (n.detail ? " · " + n.detail : ""))}</div>
      <div class="k">${pos}${fuel ? " · fuel " + fuel : ""}</div>`;
    const r = canvas.parentElement.getBoundingClientRect();
    let x = cx - r.left + 16, y = cy - r.top + 16;
    if (x + 290 > r.width) x = cx - r.left - 290;
    if (y + 110 > r.height) y = cy - r.top - 110;
    tip.style.left = x + "px"; tip.style.top = y + "px";
    tip.classList.add("on");
  }

  // ------------------------------------------------------------ selection + drawer
  const drawer = $("#drawer");
  let drawerDirty = false;
  function select(id) {
    S.sel = id;
    S.fleetDirty = true;
    drawerDirty = true;
    if (id == null) { drawer.classList.remove("open"); S.opts.follow = false; pressed("#bFollow", false); }
    else { drawer.classList.add("open"); }
    for (const row of logEl.children) row.classList.toggle("hl", id != null && (+row.dataset.from === id || +row.dataset.to === id));
  }

  function spark() { return $("#spark"); }

  function renderDrawer() {
    drawerDirty = false;
    const n = S.nodes.get(S.sel);
    if (!n) { drawer.classList.remove("open"); return; }
    const c = stateColor(n);
    const live = !n.offline && !n.placeholder;
    const frac = fuelFrac(n);
    const fuel = fuelText(n);
    const peers = Object.entries(n.peers).sort((a, b) => b[1] - a[1]).slice(0, 6);
    const evs = (n.events || []).slice().reverse().slice(0, 14);
    const ring = frac == null ? "" : (() => {
      const R = 22, L = 2 * Math.PI * R, col = frac < 0.1 ? "#ff4d5e" : "#8cff3f";
      return `<svg viewBox="0 0 54 54"><circle cx="27" cy="27" r="${R}" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="5"/>
        <circle cx="27" cy="27" r="${R}" fill="none" stroke="${col}" stroke-width="5" stroke-linecap="round" stroke-dasharray="${L * frac} ${L}" transform="rotate(-90 27 27)" style="filter:drop-shadow(0 0 4px ${col})"/>
        <text x="27" y="31" text-anchor="middle" fill="#fff" font-size="12" font-family="Orbitron" font-weight="800">${Math.round(frac * 100)}</text></svg>`;
    })();
    drawer.style.setProperty("--c", c);
    drawer.innerHTML = `
      <div class="hero" style="--c:${c}">
        <button class="tbtn x" id="dClose">Esc</button>
        <h3>${esc(n.label || "Computer #" + n.id)}</h3>
        <div class="sub">#${n.id} · ${esc(n.kind || "computer")}${n.role ? " · " + esc(n.role) : ""}${n.isBridge ? " · overseer bridge" : ""}</div>
        <span class="chip" style="--c:${c}">${esc(n.placeholder ? "heard only" : n.offline ? "offline" : n.state || "?")}</span>
        <div class="detail">${esc(n.placeholder ? "This computer sent or received messages but has never sent a status report (it doesn't use lib/report.lua)." : n.detail || "")}</div>
        <div class="acts"><button class="tbtn" id="dFly">Fly to</button><button class="tbtn" id="dFollow" aria-pressed="${S.opts.follow}">Follow</button></div>
      </div>
      <div class="body">
        <div class="stats">
          <div class="stat wide"><span>Position${n.posFrom ? " · " + esc(n.posFrom) : ""}</span><b>${n.pos ? `X ${n.pos.x} &nbsp; Y ${n.pos.y} &nbsp; Z ${n.pos.z}` : "unknown"}</b></div>
          ${fuel ? `<div class="stat wide gauge">${ring}<div><span>Fuel</span><b>${fuel}${typeof n.fuelLimit === "number" ? ` <small style="color:var(--dim);font-size:11px">/ ${fmtNum(n.fuelLimit)}</small>` : ""}</b></div></div>` : ""}
          <div class="stat"><span>Last seen</span><b>${live ? "now" : ago(n.lastSeen)}</b></div>
          <div class="stat"><span>Uptime</span><b>${n.uptime != null ? fmtDur(n.uptime) : "—"}</b></div>
          <div class="stat"><span>Sent</span><b style="color:var(--cyan)">${fmtNum(n.sent || 0)}</b></div>
          <div class="stat"><span>Received</span><b style="color:var(--magenta)">${fmtNum(n.recv || 0)}</b></div>
          <div class="stat wide"><span>Data sent</span><b>${fmtBytes(n.bytes || 0)}</b></div>
        </div>
        <h5>Messages · last minute</h5>
        <canvas id="spark"></canvas>
        ${peers.length ? `<h5>Talks to</h5><div class="peers">${peers.map(([id, k]) => `<div data-id="${id}"><span>${esc(name(+id))}</span><b>${fmtNum(k)}</b></div>`).join("")}</div>` : ""}
        ${evs.length ? `<h5>Activity</h5><div class="events">${evs.map((e) => `<div><time>${hms(e.t)} · ${ago(e.t)}</time>${esc(e.text)}</div>`).join("")}</div>` : ""}
      </div>`;
    $("#dClose").onclick = () => select(null);
    $("#dFly").onclick = () => flyTo(n, true);
    $("#dFollow").onclick = () => { toggle("follow", "#bFollow"); $("#dFollow").setAttribute("aria-pressed", S.opts.follow); if (S.opts.follow) flyTo(n, true); };
    drawer.querySelectorAll(".peers div").forEach((d) => (d.onclick = () => { select(+d.dataset.id); const m = S.nodes.get(+d.dataset.id); if (m) flyTo(m); }));
    sizeCanvas(spark());
    drawSpark(n, c);
  }

  function drawSpark(n, c) {
    const el = spark();
    if (!el) return;
    const g = el.getContext("2d");
    const w = el.width, h = el.height;
    g.clearRect(0, 0, w, h);
    const now = Math.floor(Date.now() / 1000);
    const vals = [];
    for (let s = now - 59; s <= now; s++) vals.push(n.hist.get(s) || 0);
    const max = Math.max(2, ...vals);
    const grad = g.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, withAlpha(c, 0.5)); grad.addColorStop(1, withAlpha(c, 0));
    g.beginPath(); g.moveTo(0, h);
    vals.forEach((v, i) => g.lineTo((i / 59) * w, h - (v / max) * (h - 4 * DPR)));
    g.lineTo(w, h); g.closePath(); g.fillStyle = grad; g.fill();
    g.beginPath();
    vals.forEach((v, i) => g[i ? "lineTo" : "moveTo"]((i / 59) * w, h - (v / max) * (h - 4 * DPR)));
    g.strokeStyle = c; g.lineWidth = 1.5 * DPR; g.shadowColor = c; g.shadowBlur = 8; g.stroke();
  }

  // ------------------------------------------------------------ fleet list
  const fleetEl = $("#fleet");
  const rows = new Map();
  const search = $("#search");
  search.addEventListener("input", () => (S.fleetDirty = true));

  function rank(n) {
    if (n.placeholder) return 4;
    if (n.offline) return 3;
    if (ALERT.has(n.state)) return 0;
    return n.isBridge ? 1 : 2;
  }
  function renderFleet() {
    S.fleetDirty = false;
    const q = search.value.trim().toLowerCase();
    const list = [...S.nodes.values()]
      .filter((n) => !q || `${n.label} ${n.id} ${n.role} ${n.state} ${n.detail} ${n.kind}`.toLowerCase().includes(q))
      .sort((a, b) => rank(a) - rank(b) || String(a.label || "~").localeCompare(String(b.label || "~")) || a.id - b.id);
    const seen = new Set();
    fleetEl.querySelector(".empty")?.remove();
    let cursor = fleetEl.firstChild; // only move rows that are out of place: moving one under the mouse cancels its click
    for (const n of list) {
      seen.add(n.id);
      let el = rows.get(n.id);
      if (!el) {
        el = document.createElement("div");
        el.className = "unit";
        el.onclick = () => { select(n.id); flyTo(S.nodes.get(n.id), true); };
        rows.set(n.id, el);
      }
      const c = stateColor(n);
      const frac = fuelFrac(n);
      const live = !n.offline && !n.placeholder;
      const stateWord = n.placeholder ? "heard" : n.offline ? "offline" : n.state || "?";
      const sig = [c, n.label, stateWord, n.detail, n.role, frac == null ? "" : Math.round(frac * 50), S.sel === n.id, live ? 0 : Math.floor((Date.now() - (n.lastSeen || 0)) / 10000)].join("|");
      if (el.dataset.sig !== sig) {
        el.dataset.sig = sig;
        el.innerHTML = `${iconSvg(n, c)}
          <div class="nm">${esc(n.label || "Computer")}<i>#${n.id}</i></div>
          <span class="chip" style="--c:${c}">${esc(stateWord)}</span>
          <div class="dt">${esc(live ? n.detail || n.role || "" : n.placeholder ? "never reported (no lib/report.lua)" : "last seen " + ago(n.lastSeen))}</div>
          ${frac != null ? `<div class="fuel ${frac < 0.1 ? "low" : ""}"><i style="width:${(frac * 100).toFixed(1)}%"></i></div>` : ""}`;
        el.classList.toggle("off", !live);
        el.classList.toggle("sel", S.sel === n.id);
      }
      if (el === cursor) cursor = cursor.nextSibling;
      else fleetEl.insertBefore(el, cursor);
    }
    for (const [id, el] of rows) if (!seen.has(id)) { el.remove(); if (!S.nodes.has(id)) rows.delete(id); }
    if (!list.length) fleetEl.insertAdjacentHTML("beforeend", `<div class="empty">${S.nodes.size ? "Nothing matches." : "No computers yet.<br>Anything using lib/report.lua shows up here."}</div>`);
  }
  function flashRow(id, color) {
    const el = rows.get(id);
    if (!el || el.classList.contains("flash")) return;
    el.style.setProperty("--c", color);
    el.classList.add("flash");
    setTimeout(() => el.classList.remove("flash"), 700);
  }

  // ------------------------------------------------------------ traffic chart + protocol chips
  const chart = $("#chart");
  const protosEl = $("#protos");
  const chips = new Map();
  function protoOrder() { return Object.keys(S.protoTotals).sort((a, b) => S.protoTotals[b] - S.protoTotals[a]); }
  function renderProtos() {
    const order = protoOrder();
    for (const p of order) {
      let el = chips.get(p);
      if (!el) {
        el = document.createElement("button");
        el.className = "proto";
        el.style.setProperty("--c", protoColor(p));
        el.title = "Click to hide or show this protocol";
        el.onclick = () => { S.hidden.has(p) ? S.hidden.delete(p) : S.hidden.add(p); el.classList.toggle("off", S.hidden.has(p)); };
        el.innerHTML = `<i></i><span>${esc(p)}</span><b></b>`;
        chips.set(p, el);
      }
      el.querySelector("b").textContent = fmtNum(S.protoTotals[p]);
      protosEl.appendChild(el);
    }
  }
  function drawChart() {
    const g = chart.getContext("2d");
    const w = chart.width, h = chart.height;
    g.clearRect(0, 0, w, h);
    const now = Math.floor(Date.now() / 1000) - 1; // the current second is still filling
    for (const s of S.buckets.keys()) if (s < now - CHART_SECONDS - 5) S.buckets.delete(s);
    const order = protoOrder().filter((p) => !S.hidden.has(p)).reverse();
    const cols = [];
    let max = 1;
    for (let i = 0; i < CHART_SECONDS; i++) {
      const b = S.buckets.get(now - CHART_SECONDS + 1 + i) || {};
      let sum = 0;
      const col = order.map((p) => (sum += b[p] || 0));
      cols.push(col);
      max = Math.max(max, sum);
    }
    max = Math.ceil(max * 1.15);
    const X = (i) => (i / (CHART_SECONDS - 1)) * w;
    const Y = (v) => h - 14 * DPR - (v / max) * (h - 22 * DPR);
    // guide lines
    g.strokeStyle = "rgba(63,224,255,0.08)"; g.lineWidth = 1;
    for (let k = 1; k <= 3; k++) { const y = Math.round(Y((max * k) / 4)) + 0.5; g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke(); }
    for (let j = order.length - 1; j >= 0; j--) {
      const c = protoColor(order[j]);
      const grad = g.createLinearGradient(0, 0, 0, h);
      grad.addColorStop(0, withAlpha(c, 0.75)); grad.addColorStop(1, withAlpha(c, 0.12));
      g.beginPath(); g.moveTo(0, Y(0));
      cols.forEach((col, i) => g.lineTo(X(i), Y(col[j])));
      g.lineTo(w, Y(0)); g.closePath();
      g.fillStyle = grad; g.fill();
    }
    if (order.length) {
      g.beginPath();
      cols.forEach((col, i) => g[i ? "lineTo" : "moveTo"](X(i), Y(col[col.length - 1])));
      g.strokeStyle = "#e9fbff"; g.lineWidth = 1.2 * DPR; g.shadowColor = "#3fe0ff"; g.shadowBlur = 10; g.stroke(); g.shadowBlur = 0;
    }
    g.fillStyle = "rgba(125,147,173,0.8)"; g.font = `600 ${9 * DPR}px 'JetBrains Mono', monospace`;
    g.textBaseline = "bottom";
    g.fillText("-2m", 4 * DPR, h - 1); g.fillText("-1m", w / 2 - 10 * DPR, h - 1); g.fillText("now", w - 24 * DPR, h - 1);
    g.textBaseline = "top"; g.fillText(`${max}/s`, 4 * DPR, 3 * DPR);
  }

  // ------------------------------------------------------------ packet log
  const logEl = $("#log");
  function logRow(p, fresh) {
    if (S.hidden.has(p.proto)) return;
    if (p.proto === "cc_status" && !S.opts.beats) return;
    const c = protoColor(p.proto);
    const el = document.createElement("div");
    el.className = "row" + (fresh ? " new" : "");
    el.dataset.from = p.from; el.dataset.to = p.to;
    el.style.setProperty("--c", c);
    if (S.sel != null && (p.from === S.sel || p.to === S.sel)) el.classList.add("hl");
    el.innerHTML = `<span class="tm">${hms(p.t)}</span>
      <span class="pr"><span class="chip" style="--c:${c}">${esc(p.proto)}</span></span>
      <span class="rt">${esc(name(p.from))}<em>${p.to < 0 ? "⇉" : "→"}</em>${esc(name(p.to))}</span>
      <span class="ty">${esc(typeText(p))}</span>
      <span class="pk">${esc(peekText(p))}</span>
      <span class="sz">${fmtBytes(p.size || 0)}</span>`;
    el.onclick = () => { select(p.from); const n = S.nodes.get(p.from); if (n) flyTo(n); };
    logEl.insertBefore(el, logEl.firstChild);
    while (logEl.children.length > LOG_ROWS) logEl.lastChild.remove();
  }

  // ------------------------------------------------------------ header numbers
  const kpiVals = {};
  function kpi(id, v, alert) {
    const el = $("#" + id);
    const text = typeof v === "number" ? fmtNum(v) : v;
    if (kpiVals[id] !== text) {
      $("b", el).textContent = text;
      if (kpiVals[id] !== undefined) { el.classList.remove("bump"); void el.offsetWidth; el.classList.add("bump"); }
      kpiVals[id] = text;
    }
    el.classList.toggle("alert", !!alert);
  }
  function renderKpis() {
    let online = 0, turtles = 0, alerts = 0;
    for (const n of S.nodes.values()) {
      if (n.offline || n.placeholder) continue;
      online++;
      if (n.kind === "turtle") turtles++;
      if (ALERT.has(n.state)) alerts++;
    }
    const now = Math.floor(Date.now() / 1000);
    let recent = 0;
    for (let s = now - 5; s < now; s++) { const b = S.buckets.get(s); if (b) for (const v of Object.values(b)) recent += v; }
    kpi("kOnline", online);
    kpi("kTurtles", turtles);
    kpi("kRate", (recent / 5).toFixed(1));
    kpi("kTotal", S.total);
    kpi("kErr", alerts, alerts > 0);
    const d = new Date();
    $("#clock").innerHTML = `<b>${hms(d)}</b>${S.nodes.size} known · ${S.edges.size} links`;
    $("#logMeta").textContent = S.paused ? "PAUSED" : `${fmtNum(S.total)} captured`;
  }

  // ------------------------------------------------------------ buttons + keys
  function pressed(sel, on) { $(sel).setAttribute("aria-pressed", String(on)); }
  function toggle(opt, sel) { S.opts[opt] = !S.opts[opt]; pressed(sel, S.opts[opt]); }
  $("#bFit").onclick = () => { S.autoFit = true; fit(); };
  $("#bFollow").onclick = () => { toggle("follow", "#bFollow"); const n = S.nodes.get(S.sel); if (S.opts.follow && n) flyTo(n, true); };
  $("#bTrails").onclick = () => toggle("trails", "#bTrails");
  $("#bBeats").onclick = () => toggle("beats", "#bBeats");
  $("#bLabels").onclick = () => toggle("labels", "#bLabels");
  $("#bPause").onclick = () => { S.paused = !S.paused; pressed("#bPause", S.paused); if (!S.paused) S.pending = []; };
  document.addEventListener("keydown", (e) => {
    if (e.target === search) { if (e.key === "Escape") { search.value = ""; search.blur(); S.fleetDirty = true; } return; }
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toLowerCase();
    if (k === "f") { S.autoFit = true; fit(); }
    else if (k === "t") toggle("trails", "#bTrails");
    else if (k === "h") toggle("beats", "#bBeats");
    else if (k === "l") toggle("labels", "#bLabels");
    else if (k === " ") { e.preventDefault(); $("#bPause").click(); }
    else if (k === "escape") select(null);
    else if (k === "/") { e.preventDefault(); search.focus(); }
    else if (k === "+" || k === "=") S.autoFit = false, goal.s = Math.min(24, goal.s * 1.4);
    else if (k === "-") S.autoFit = false, goal.s = Math.max(0.03, goal.s / 1.4);
  });

  // ------------------------------------------------------------ boot + connection
  const bootLines = $("#bootLines");
  const bootStart = performance.now();
  let bootClosed = false;
  function bootLine(text, cls, delay = 0) {
    const d = document.createElement("div");
    d.textContent = "> " + text;
    if (cls) d.className = cls;
    d.style.animationDelay = delay + "ms";
    bootLines.appendChild(d);
  }
  function bootDone(text, cls) {
    bootLine(text, cls);
    $("#bootBar").style.width = "100%";
    const wait = Math.max(500, 1400 - (performance.now() - bootStart));
    setTimeout(closeBoot, wait);
  }
  function closeBoot() { if (bootClosed) return; bootClosed = true; $("#boot").classList.add("gone"); }
  $("#boot").onclick = closeBoot;
  bootLine("OVERSEER // CC: Tweaked network monitor");
  bootLine("calibrating holo-grid", null, 120);
  bootLine("opening link to the overseer server", null, 260);
  requestAnimationFrame(() => ($("#bootBar").style.width = "55%"));

  function startDemo(why) {
    if (S.mode === "demo") return;
    S.delay = 0;
    setMode("demo");
    bootDone(why === "asked" ? "demo world requested" : "no overseer server here · starting the demo world", "warn");
    window.OverseerDemo.start({
      snapshot: applySnapshot,
      nodes: (list) => list.forEach(applyNode),
      packets: (list) => addPackets(list, true),
    });
  }

  function connect() {
    if (params.has("demo") || location.protocol === "file:" || !window.EventSource) { startDemo("asked"); return; }
    let opened = false;
    const es = new EventSource("api/events");
    const giveUp = setTimeout(() => { if (!opened) { es.close(); startDemo("none"); } }, 3500);
    es.onopen = () => {
      if (!opened) bootDone("link established · listening", "ok");
      opened = true;
      clearTimeout(giveUp);
    };
    es.onerror = () => {
      if (!opened) { clearTimeout(giveUp); es.close(); startDemo("none"); return; }
      setMode("down");
    };
    es.addEventListener("snapshot", (e) => applySnapshot(JSON.parse(e.data)));
    es.addEventListener("nodes", (e) => JSON.parse(e.data).forEach(applyNode));
    es.addEventListener("packets", (e) => addPackets(JSON.parse(e.data), true));
    es.addEventListener("bridge", (e) => setBridge(JSON.parse(e.data)));
  }

  // ------------------------------------------------------------ go
  window.__overseer = { S, cam, goal }; // for poking at from the browser console
  window.addEventListener("resize", resize);
  new ResizeObserver(resize).observe(canvas);
  resize();
  setMode("connecting");
  connect();
  requestAnimationFrame(frame);
  setInterval(() => {
    if (S.fleetDirty) renderFleet();
    if (drawerDirty && S.sel != null) renderDrawer();
  }, 250);
  setInterval(() => {
    renderKpis();
    renderProtos();
    drawChart();
    S.fleetDirty = true; // "last seen 12s ago" moves on
    if (S.sel != null) { const n = S.nodes.get(S.sel); if (n) drawSpark(n, stateColor(n)); }
  }, 1000);
  setInterval(() => { if (S.sel != null) drawerDirty = true; }, 5000);
})();
