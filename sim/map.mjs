// Runs the whole base in the simulator, checks it, and writes what happened
// as site/network.json: where every computer is, its cables and modems, who
// talked to whom (and how much), and each one's screen at the end. The
// website's network map (site/src/assets/netmap.js) draws it.
//
//   node sim/map.mjs [seconds]      (default 1800: half an hour of game time)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build, check } from "./scenarios/base.mjs";
import { machines } from "./scenarios/machines.mjs";
import { extras, check as checkExtras } from "./scenarios/extras.mjs";
import { gpsDeployer } from "./scenarios/gps.mjs";
import { check as checkMachines } from "./scenarios/machines.mjs";
import { check as checkMining } from "./scenarios/mining.mjs";
import { check as checkStorage } from "./scenarios/storage.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, "..", "site", "network.json");
const seconds = Number(process.argv[2] || 1800);

const s = build();
Object.assign(s, machines(s.w), extras(s.w, s.net));
s.deployer = gpsDeployer(s.w);
const w = s.w;
const errors = [];
w.on("error", ({ computer, msg }) => errors.push({ t: w.time, id: computer.id, msg }));
w.on("script-failed", ({ computer, msg }) => errors.push({ t: w.time, id: computer.id, msg: `setup step: ${msg}` }));

const t0 = Date.now();
for (let t = 0; t < seconds; t += 30) {
  w.run(Math.min(30, seconds - t));
  process.stdout.write(`\r${w.time.toFixed(0)}s of ${seconds}s simulated (${((Date.now() - t0) / 1000).toFixed(0)}s)   `);
}
console.log();

const problems = [...check(s), ...checkMining(s), ...checkStorage(s), ...checkMachines(s), ...checkExtras(s)];
if (w.computers.filter((c) => c.deployed).length < 4) problems.push("gps deployer: fewer than 4 GPS hosts built");

//---------------------------------------------------------------- export

// the block kinds the site's voxel renderer has
function kind(name) {
  const n = name.replace(/^minecraft:/, "");
  if (name.startsWith("computercraft:")) {
    if (n.includes("turtle")) return "turtle";
    if (n.includes("monitor")) return "monitor";
    if (n.includes("command")) return "command";
    if (n.includes("computer_normal")) return "computer";
    return "advanced";
  }
  if (name.startsWith("enderstorage:")) return "enderchest";
  if (name === "create:creative_crate") return "crate";
  if (name.startsWith("advancedperipherals:")) return "port";
  if (name.startsWith("mekanism:")) return /port|adapter/.test(n) ? "port" : n.includes("digital_miner") ? "dminer" : n.includes("fusion") ? "fusion" : n.includes("fission") ? "fission" : "casing";
  if (/chest$/.test(n)) return "chest";
  if (n === "barrel") return "barrel";
  if (/furnace|smoker/.test(n)) return "furnace";
  if (n === "hopper") return "hopper";
  if (n === "grass_block") return "grass";
  if (n === "farmland") return "farmland";
  if (/^(dirt|coarse_dirt|rooted_dirt)$/.test(n)) return "dirt";
  if (/cobble/.test(n)) return "cobble";
  if (/deepslate|tuff/.test(n) && !/ore/.test(n)) return "deepslate";
  if (/coal_ore/.test(n)) return "coal";
  if (/iron_ore|copper_ore/.test(n)) return "iron";
  if (/gold_ore/.test(n)) return "gold";
  if (/diamond_ore/.test(n)) return "diamond";
  if (/redstone_ore/.test(n)) return "redstone";
  if (/_log$|_wood$/.test(n)) return "log";
  if (/_planks$|_door$|_stairs$|_slab$|_fence/.test(n)) return "planks";
  if (/_leaves$/.test(n)) return "leaves";
  if (/glass/.test(n)) return "glass";
  if (/^(sand|gravel|water|lava|bedrock|torch|stone)$/.test(n)) return n === "stone" ? "stone" : n;
  return "stone";
}

const far = (c) => Math.abs(c.pos[0]) > 300 || Math.abs(c.pos[2]) > 300;
const inBase = w.computers.filter((c) => !far(c) && c.pos[1] < 120);
const xs = inBase.map((c) => c.pos[0]), zs = inBase.map((c) => c.pos[2]);
const box = { x0: Math.min(...xs) - 4, x1: Math.max(...xs) + 4, z0: Math.min(...zs) - 8, z1: Math.max(...zs) + 6 };

// every block anything placed (above y 55), plus the ground's top block in each column
const blocks = [];
const placed = new Set();
for (const [k, b] of w.blocks) {
  if (!b || b.natural) continue;
  const [x, y, z] = k.split(",").map(Number);
  if (y < 55 || y > 110 || x < box.x0 || x > box.x1 || z < box.z0 || z > box.z1) continue;
  if (b.computer && b.computer.kind !== "turtle" && b.computer.pos.join() !== `${x},${y},${z}`) continue;
  blocks.push([x, y, z, kind(b.name)]);
  placed.add(k);
}
for (let x = box.x0; x <= box.x1; x++) for (let z = box.z0; z <= box.z1; z++) {
  for (let y = 75; y > 40; y--) {
    const b = w.block(x, y, z);
    if (!b || /water|lava/.test(b.name) && y > 63) continue;
    if (b.natural) blocks.push([x, y, z, kind(b.name)]);
    break;
  }
}
for (const net of w.nets.values()) for (const [x, y, z] of net.cells) if (!placed.has(`${x},${y},${z}`) && !w.block(x, y, z)) blocks.push([x, y, z, "cable"]);

const modemsOf = (c) => {
  const out = [];
  for (const [side, p] of Object.entries(c.attached)) if (p.channels) out.push({ side, type: p.wireless ? (p.ender ? "ender" : "wireless") : "wired", net: p.net?.name });
  if (c.kind === "turtle") for (const [side, u] of Object.entries(c.upgrades)) if (u?.peripheral?.channels) out.push({ side, type: u.peripheral.ender ? "ender" : "wireless" });
  return out;
};
const programOf = (c) => c.program || c.role;
const computers = w.computers.map((c) => {
  const st = w.lastStatus.get(c.id);
  return {
    id: c.id, label: c.label, program: programOf(c), kind: c.kind === "computer" ? (c.advanced ? "advanced" : "computer") : c.kind,
    pos: c.pos, facing: c.facing, on: c.on, far: far(c) || undefined,
    modems: modemsOf(c),
    fuel: c.kind === "turtle" ? c.fuel : undefined,
    state: st?.state, detail: st?.detail,
    screen: c.term.lines().slice(0, c.term.h),
    monitor: undefined,
  };
});
// the screens of monitors next to (or cabled to) a computer
for (const m of w.monitors) {
  const owner = w.computers.find((c) => w.watchers(m).some((x) => x.computer === c));
  const entry = owner && computers.find((c) => c.id === owner.id);
  if (entry && !entry.monitor) entry.monitor = m.term.lines();
}

const nets = [...w.nets.values()].map((n) => ({
  name: n.name,
  computers: n.modems.map((m) => m.computer.id),
  members: [...n.members.entries()].filter(([, p]) => !(p.types[0] === "computer" || p.types[0] === "turtle")).map(([name, p]) => {
    let pos = null;
    for (const [k, b] of w.blocks) if (b && b.peripheral === p) { pos = k.split(",").map(Number); break; }
    return { name, type: p.types[0], pos };
  }),
}));

const links = [...w.traffic.entries()].map(([k, count]) => {
  const [pair, protocol] = k.split("|");
  const [from, to] = pair.split(">").map(Number);
  return { from, to, protocol, count };
}).filter((l) => l.protocol !== "dns");
const broadcasts = [...w.broadcasts.entries()].map(([k, count]) => { const [from, protocol] = k.split("|"); return { from: Number(from), protocol, count }; }).filter((b) => b.protocol !== "dns");
// broadcasts are heard by the programs that listen for them
const LISTENERS = { cc_status: ["status-server", "storage-computer", "turtle-finder"] };
for (const b of broadcasts) {
  b.heardBy = w.computers.filter((c) => (LISTENERS[b.protocol] || []).includes(c.role) && c.id !== b.from).map((c) => c.id);
}
const hosts = [...w.hosts.entries()].map(([k, name]) => { const [id, protocol] = k.split("|"); return { id: Number(id), protocol, name }; });
const gps = { hosts: s.gps.map((g) => g.id), askers: [...w.gpsPings.entries()].map(([id, count]) => ({ id, count })) };
const http = { posts: s.posts.length, packets: s.posts.reduce((n, p) => n + (p.packets?.length || 0), 0) };

const data = {
  made: new Date().toISOString().slice(0, 10),
  simulated: seconds,
  box,
  computers, nets, links, broadcasts, hosts, gps, http,
  blocks,
  problems,
  errors: errors.map((e) => ({ ...e, t: Math.round(e.t) })),
};
fs.writeFileSync(OUT, JSON.stringify(data));
console.log(`${computers.length} computers, ${nets.length} cables, ${links.length} links, ${blocks.length} blocks -> ${path.relative(process.cwd(), OUT)} (${(fs.statSync(OUT).size / 1024).toFixed(0)} KB)`);
console.log(problems.length ? `Problems:\n  ${problems.join("\n  ")}` : "All checks passed");
if (errors.length) console.log(`Errors:\n  ${errors.map((e) => `${e.t.toFixed(0)}s #${e.id}: ${e.msg}`).join("\n  ")}`);
