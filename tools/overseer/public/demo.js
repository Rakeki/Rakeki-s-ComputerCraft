// Demo world for the overseer page: a made-up base running this repo's
// programs (storage, crafting, factory, AutoMine, builders, farms, reactor),
// sending the same status reports and rednet messages they send for real.
// Used when no overseer server answers, or with ?demo in the address.
"use strict";
window.OverseerDemo = (() => {
  const rnd = (a, b) => a + Math.random() * (b - a);
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const chance = (p) => Math.random() < p;

  const ITEMS = ["minecraft:iron_ingot", "minecraft:redstone", "minecraft:oak_planks", "minecraft:coal", "minecraft:glass", "mekanism:osmium_ingot", "minecraft:copper_ingot", "create:andesite_alloy", "minecraft:stone_bricks", "minecraft:torch"];

  let sink, nodes, t0;
  const N = (id, o) => ({ id, kind: "computer", state: "idle", detail: "", events: [], trail: [], sent: 0, recv: 0, bytes: 0, uptime: rnd(300, 90000), lastSeen: Date.now(), offline: false, ...o });

  function world() {
    const list = [
      N(1, { label: "Overseer Bridge", role: "overseer bridge", state: "posting", detail: "posting to the overseer server", pos: { x: 4, y: 72, z: 2 }, isBridge: true, posFrom: "gps" }),
      N(2, { label: "Status Board", role: "status server", state: "serving", detail: "21 computers on the dashboard", pos: { x: 12, y: 72, z: -6 } }),
      N(3, { label: "GPS North", role: "gps host", state: "serving", detail: "gps host", pos: { x: 0, y: 252, z: -24 } }),
      N(4, { label: "GPS East", role: "gps host", state: "serving", detail: "gps host", pos: { x: 24, y: 252, z: 0 } }),
      N(5, { label: "GPS South", role: "gps host", state: "serving", detail: "gps host", pos: { x: 0, y: 248, z: 24 } }),
      N(6, { label: "GPS West", role: "gps host", state: "serving", detail: "gps host", pos: { x: -24, y: 256, z: 0 } }),
      N(10, { label: "Storage", role: "storage computer", state: "serving", detail: "48 chests · 61% full", pos: { x: -46, y: 64, z: 34 } }),
      N(11, { label: "Craft Overseer", role: "craft overseer", state: "crafting", detail: "3 jobs queued", pos: { x: -36, y: 64, z: 44 } }),
      N(12, { label: "Crafter-12", kind: "turtle", role: "crafter", state: "idle", detail: "waiting for a job", pos: { x: -31, y: 64, z: 50 }, fuel: "unlimited", fuelLimit: "unlimited" }),
      N(13, { label: "Crafter-13", kind: "turtle", role: "crafter", state: "idle", detail: "waiting for a job", pos: { x: -28, y: 64, z: 50 }, fuel: "unlimited", fuelLimit: "unlimited" }),
      N(14, { label: "Crafter-14", kind: "turtle", role: "crafter", state: "idle", detail: "waiting for a job", pos: { x: -25, y: 64, z: 50 }, fuel: "unlimited", fuelLimit: "unlimited" }),
      N(15, { label: "Factory", role: "factory", state: "smelting", detail: "12 furnaces · 4 enrichers", pos: { x: -60, y: 64, z: 18 } }),
      N(16, { label: "Factory Annex", role: "factory", state: "working", detail: "infusers · 2 jobs", pos: { x: -72, y: 64, z: 30 } }),
      N(17, { label: "Outpost Terminal", role: "remote terminal", state: "idle", detail: "ender chest linked", pos: { x: 168, y: 88, z: -110 } }),
      N(20, { label: "Mine Control", role: "mine server", state: "serving", detail: "6 miners · 41 chunks done", pos: { x: 70, y: 64, z: 70 } }),
      N(29, { label: "Projector", role: "blueprint projector", state: "building", detail: "Greathall · 4 builders", pos: { x: -128, y: 70, z: -70 } }),
      N(40, { label: "Tree Farm", kind: "turtle", role: "tree farm", state: "farming", detail: "row 2 of 6", pos: { x: 36, y: 64, z: -96 }, fuel: 3800, fuelLimit: 20000 }),
      N(41, { label: "Wheat Farm", kind: "turtle", role: "crop farm", state: "harvesting", detail: "row 5 of 9", pos: { x: 62, y: 64, z: -60 }, fuel: 9120, fuelLimit: 20000 }),
      N(50, { label: "Fission Guard", role: "fission guard", state: "running", detail: "412 K · burn 8.0 mB/t", pos: { x: -70, y: 40, z: -12 } }),
      N(51, { label: "Power Board", role: "power dashboard", state: "running", detail: "71% · +18 kFE/t", pos: { x: -62, y: 40, z: -6 } }),
      N(60, { label: "Excavator-60", kind: "turtle", role: "excavate", state: "digging", detail: "layer 4 of 30", pos: { x: 150, y: 40, z: 150 }, fuel: 14200, fuelLimit: 100000 }),
      N(61, { label: "Tunneler-61", kind: "turtle", role: "nether tunnel", state: "sealing", detail: "312 / 1000 blocks", pos: { x: -200, y: 30, z: 120 }, fuel: 2100, fuelLimit: 20000 }),
      N(70, { label: "Finder", kind: "pocket", role: "turtle finder", state: "listening", detail: "pointing at Miner-23" }),
    ];
    for (let i = 0; i < 6; i++) {
      const cx = 96 + (i % 3) * 32, cz = 96 + Math.floor(i / 3) * 32;
      list.push(N(21 + i, { label: `Miner-${21 + i}`, kind: "turtle", role: "auto miner", state: "mining", detail: `chunk ${cx >> 4},${cz >> 4} · layer ${Math.floor(rnd(2, 9))}`, pos: { x: cx, y: Math.floor(rnd(-40, 20)), z: cz }, fuel: Math.floor(rnd(1500, 60000)), fuelLimit: 100000, chunk: { x: cx, z: cz }, home: { x: 74 + i * 2, y: 64, z: 74 } }));
    }
    for (let i = 0; i < 4; i++) {
      list.push(N(30 + i, { label: `Builder-${30 + i}`, kind: "turtle", role: "builder", state: "building", detail: `strip ${i + 1} · layer 3`, pos: { x: -140 + i * 8, y: 74, z: -80 }, fuel: Math.floor(rnd(8000, 40000)), fuelLimit: 100000, strip: i, done: Math.floor(rnd(100, 400)), total: 1200 }));
    }
    for (const n of list) if (n.pos) n.trail = [{ ...n.pos, t: Date.now() }];
    return new Map(list.map((n) => [n.id, n]));
  }

  // ------------------------------------------------------------ sending
  const queue = [];
  function send(from, to, proto, msg, size, after = 0) {
    queue.push({ at: Date.now() + after, p: { from, to, proto, size: Math.round(size), ...msg } });
  }
  function ask(from, to, proto, type, peek, size, replySize, delay = rnd(80, 260), replyPeek) {
    send(from, to, proto, { type, peek }, size);
    if (replySize != null) send(to, from, proto, { re: type, peek: replyPeek }, replySize, delay);
  }

  function status(n, event) {
    const at = Date.now();
    if (n.pos) {
      const last = n.trail[n.trail.length - 1];
      if (!last || last.x !== n.pos.x || last.y !== n.pos.y || last.z !== n.pos.z) {
        n.trail.push({ ...n.pos, t: at });
        if (n.trail.length > 80) n.trail.shift();
      }
    }
    if (event) { n.events.push({ t: at, text: event }); if (n.events.length > 30) n.events.shift(); }
    n.lastSeen = at;
    n.nextStatus = at + (n.kind === "turtle" ? rnd(2000, 3500) : rnd(8000, 11000));
    send(n.id, -1, "cc_status", { type: "status", peek: { state: n.state } }, 180 + (n.detail || "").length);
    changed.add(n.id);
  }
  function setState(n, state, detail) {
    const ev = state !== n.state ? `${state}${detail ? ": " + detail : ""}` : null;
    n.state = state;
    if (detail != null) n.detail = detail;
    status(n, ev);
  }

  // ------------------------------------------------------------ behaviour
  function step(n, target, dt, speed = 3) {
    if (!n.fx) { n.fx = n.pos.x; n.fy = n.pos.y; n.fz = n.pos.z; }
    let left = speed * dt;
    for (const axis of ["fy", "fx", "fz"]) {
      const want = target[axis.slice(1)];
      const d = want - n[axis];
      const m = Math.sign(d) * Math.min(Math.abs(d), left);
      n[axis] += m; left -= Math.abs(m);
      if (left <= 0) break;
    }
    n.pos = { x: Math.round(n.fx), y: Math.round(n.fy), z: Math.round(n.fz) };
    if (typeof n.fuel === "number" && left < speed * dt) n.fuel = Math.max(0, n.fuel - 1);
    return n.fx === target.x && n.fy === target.y && n.fz === target.z;
  }

  function miner(n, dt) {
    if (!n.target) {
      n.target = n.state === "returning"
        ? n.home
        : { x: n.chunk.x + Math.floor(rnd(0, 16)), y: Math.floor(rnd(-50, 30)), z: n.chunk.z + Math.floor(rnd(0, 16)) };
    }
    if (n.state === "unloading") return;
    if (step(n, n.target, dt, n.state === "returning" ? 5 : 2)) {
      n.target = null;
      if (n.state === "returning") {
        setState(n, "unloading", "emptying into the home chest");
        ask(n.id, 20, "automine", "status", { state: "unloading" }, 220, 90);
        setTimeout(() => {
          n.chunk = { x: 96 + Math.floor(rnd(0, 6)) * 16, z: 96 + Math.floor(rnd(0, 6)) * 16 };
          ask(n.id, 20, "automine", "job", null, 140, 260, 300, { chunk: `${n.chunk.x >> 4},${n.chunk.z >> 4}` });
          setState(n, "mining", `chunk ${n.chunk.x >> 4},${n.chunk.z >> 4} · layer 1`);
        }, rnd(3000, 6000));
      } else if (chance(0.05)) {
        setState(n, "returning", "inventory full, heading home");
      } else {
        n.detail = `chunk ${n.chunk.x >> 4},${n.chunk.z >> 4} · y ${n.pos.y}`;
      }
    }
    if (chance(dt * 0.22)) ask(n.id, 20, "automine", "progress", { mined: Math.floor(rnd(20, 900)) }, 210, 80);
  }

  function builder(n, dt) {
    const x0 = -142 + n.strip * 9, z0 = -86;
    if (n.state === "restocking") return;
    if (!n.target) n.target = { x: x0 + Math.floor(rnd(0, 8)), y: 66 + Math.floor(n.done / 120), z: z0 + Math.floor(rnd(0, 26)) };
    if (step(n, n.target, dt, 4)) {
      n.target = null;
      n.done = Math.min(n.total, n.done + Math.floor(rnd(4, 14)));
      n.detail = `strip ${n.strip + 1} · ${n.done} / ${n.total} blocks`;
      if (n.done >= n.total) { n.done = 0; setState(n, "done", "strip finished"); setTimeout(() => setState(n, "building", "next strip"), 6000); }
    }
    if (chance(dt * 0.3)) send(n.id, 29, "projector_build", { type: "progress", peek: { stage: "build", done: n.done, total: n.total } }, 160);
    if (chance(dt * 0.02)) {
      const item = pick(ITEMS);
      setState(n, "restocking", `fetching ${item.split(":")[1]}`);
      ask(n.id, 10, "storage", "deliver", { item, count: 64 }, 260, 120, 400, { sent: 64 });
      setTimeout(() => setState(n, "building", `strip ${n.strip + 1} · layer ${Math.floor(n.done / 120) + 1}`), rnd(4000, 7000));
    }
  }

  function farmer(n, dt, x0, z0, w, d) {
    if (!n.target) { n.row = ((n.row || 0) + 1) % d; n.target = { x: x0 + (n.row % 2 ? w : 0), y: 64, z: z0 + n.row * 2 }; n.detail = `row ${n.row + 1} of ${d}`; }
    if (step(n, n.target, dt, 2.5)) n.target = null;
  }

  // background traffic of the computers that sit still
  function chatter(dt) {
    for (const id of [12, 13, 14]) {
      const c = nodes.get(id);
      if (c.state === "idle" && chance(dt * 0.18)) {
        const item = pick(ITEMS);
        send(11, id, "storage_crafter", { type: "craft", peek: { make: item.split(":")[1], count: 16 } }, 380);
        setState(c, "crafting", `16 × ${item.split(":")[1]}`);
        setTimeout(() => { send(id, 11, "storage_crafter", { re: "craft", peek: { made: 16 } }, 140); setState(c, "idle", "waiting for a job"); }, rnd(1800, 4200));
      }
    }
    if (chance(dt * 0.4)) ask(11, 10, "storage", pick(["load", "clear", "stock", "crafters"]), { job: Math.floor(rnd(100, 999)) }, 300, rnd(200, 1600));
    if (chance(dt * 0.25)) ask(15, 10, "storage", "fill", { furnaces: 12 }, 900, 420, 320);
    if (chance(dt * 0.12)) ask(16, 10, "storage", "stock", null, 120, rnd(3000, 9000));
    if (chance(dt * 0.06)) ask(15, 16, "factory", "hello", null, 160, 640);
    if (chance(dt * 0.05)) ask(10, 11, "craft_overseer", "jobs", { jobs: Math.floor(rnd(1, 5)) }, rnd(900, 4000), 60);
    if (chance(dt * 0.1)) ask(17, 10, "storage", "list", null, 90, rnd(18000, 42000), 500, { items: Math.floor(rnd(800, 1400)) });
    if (chance(dt * 0.07)) ask(17, 10, "storage", "deliver", { item: pick(ITEMS), count: 64 }, 220, 110);
    if (chance(dt * 0.05)) ask(29, 30 + Math.floor(rnd(0, 4)), "projector_build", "status", null, 80, 200);
    if (chance(dt * 0.04)) {
      const from = pick([...nodes.keys()].filter((id) => id !== 1));
      send(from, -1, "dns", { type: "lookup", peek: { protocol: pick(["storage", "automine", "craft_overseer", "factory"]) } }, 90);
    }
  }

  // the odd drama: a reactor scare, a stuck turtle, a computer dropping off and coming back
  function drama(dt) {
    const t = nodes.get(61);
    if (t.state === "sealing" && chance(dt * 0.02)) {
      setState(t, "stuck", "lava ahead and no bucket left");
      setTimeout(() => setState(t, "sealing", "bucket refilled, carrying on"), rnd(12000, 20000));
    }
    const f = nodes.get(50);
    if (f.state === "running" && chance(dt * 0.006)) {
      setState(f, "alert", "SCRAM: heat 1180 K");
      setTimeout(() => setState(f, "running", "reset · 398 K"), 14000);
    }
    const ex = nodes.get(60);
    if (!ex.offline && chance(dt * 0.004)) {
      ex.offline = true; ex.events.push({ t: Date.now(), text: "went offline" }); changed.add(60);
      setTimeout(() => { ex.offline = false; status(ex, "back online"); }, 15000);
    }
  }

  // ------------------------------------------------------------ loop
  const changed = new Set();
  let lastTick;
  function tick() {
    const now = Date.now();
    const dt = Math.min(0.5, (now - lastTick) / 1000);
    lastTick = now;
    for (const n of nodes.values()) {
      if (n.offline) continue;
      if (n.role === "auto miner") miner(n, dt);
      else if (n.role === "builder") builder(n, dt);
      else if (n.id === 40) farmer(n, dt, 30, -104, 16, 6);
      else if (n.id === 41) farmer(n, dt, 54, -70, 18, 9);
      else if (n.id === 60) { if (!n.target) n.target = { x: 140 + Math.floor(rnd(0, 20)), y: Math.max(-58, n.pos.y - (chance(0.2) ? 1 : 0)), z: 140 + Math.floor(rnd(0, 20)) }; if (step(n, n.target, dt, 2)) n.target = null; n.detail = `layer ${64 - n.pos.y} · y ${n.pos.y}`; }
      else if (n.id === 61 && n.state === "sealing") { if (!n.target) n.target = { x: n.pos.x - 6, y: 30, z: 120 }; if (step(n, n.target, dt, 1)) n.target = null; }
      if (now >= n.nextStatus && n.id !== 1) status(n);
    }
    chatter(dt);
    drama(dt);
    const due = [];
    for (let i = queue.length - 1; i >= 0; i--) if (queue[i].at <= now) due.push(queue.splice(i, 1)[0]);
    due.sort((a, b) => a.at - b.at);
    const packets = due.map((q) => {
      const p = { t: q.at, dist: null, ...q.p };
      const a = nodes.get(p.from), b = p.to >= 0 ? nodes.get(p.to) : null;
      if (a) { a.sent++; a.bytes += p.size; changed.add(a.id); }
      if (b) { b.recv++; changed.add(b.id); }
      return p;
    });
    // the bridge reports itself
    const br = nodes.get(1);
    br.lastSeen = now; br.uptime = (now - t0) / 1000 + 4000; changed.add(1);
    if (changed.size) { sink.nodes([...changed].map((id) => ({ ...nodes.get(id) }))); changed.clear(); }
    if (packets.length) sink.packets(packets);
  }

  function start(s) {
    sink = s;
    nodes = world();
    t0 = Date.now();
    lastTick = t0;
    for (const n of nodes.values()) n.nextStatus = t0 + rnd(0, 9000);
    // a minute of made-up history so the chart isn't empty
    const history = [];
    for (let i = 120; i > 0; i--) history.push({ t: Math.floor(t0 / 1000) - i, c: { cc_status: Math.floor(rnd(2, 5)), storage: Math.floor(rnd(1, 4)), storage_crafter: Math.floor(rnd(0, 2)), automine: Math.floor(rnd(0, 3)), projector_build: Math.floor(rnd(0, 2)) } });
    sink.snapshot({ nodes: [...nodes.values()].map((n) => ({ ...n })), packets: [], history, bridge: { id: 1, online: true, posts: 1 } });
    setInterval(tick, 100);
  }

  return { start };
})();
