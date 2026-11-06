// Five turtles and nothing else, placed together in one chunk: how far
// towards a whole base do today's programs get on their own? Each keeps
// within nav.range of where it started (lib/nav.lua; 256 blocks unless set).
//
// The player places four turtles in the middle chunk, each with an ender
// modem, a tool and a chest behind it with a starter kit, then types a few
// commands into each (what a foreman program would have to do for them).
// Each faces outwards, so its job goes into a quarter of its own. A fifth,
// a crafty turtle (no modem), sits on the far side of the strip miner's
// chest and smelts what it brings home in furnaces it crafts itself.
// check() prints every step of a full base: done, or what's missing for it.
import { newWorld, addComputer, addChest, play, install, run, tree } from "../core/base.mjs";
import { DIRS, OPP } from "../core/world.mjs";

const MID = [64, 64]; // the middle chunk (4, 4) runs from x 64, z 64 to x 79, z 79
// the pathfinder's range: its 100-block tunnel north has to stop 64 blocks out
const PATHFINDER_RANGE = "set nav.range 64";

const back = (p, f) => { const d = DIRS[OPP[f]]; return [p[0] + d[0], p[1] + d[1], p[2] + d[2]]; };

// a turtle with an ender modem on its right, a tool on its left, and its chest behind it
function worker(w, label, pos, facing, tool, chest, carry = {}) {
  const t = addComputer(w, { pos, facing, kind: "turtle", label, role: null, tool, ender: true, fuel: 0 });
  t.homeChest = addChest(w, back(pos, facing), chest);
  for (const [name, n] of Object.entries(carry)) t.inventory.add(name.includes(":") ? name : "minecraft:" + name, n);
  return t;
}

// where each turtle goes in the middle chunk (x, z from its north-west corner) and which way it faces
export const PLACES = {
  pathfinder: { at: [0, 0], facing: "north", job: "GPS overhead, then a strip mine north" },
  digger: { at: [15, 0], facing: "north", job: "the storage cellar's hole, north-east" },
  leveller: { at: [0, 15], facing: "south", job: "a 24x24 plaza for the village, south-west" },
  forester: { at: [15, 15], facing: "east", job: "a 3x3 tree farm, south-east" },
  smelter: { at: [0, 2], facing: "south", job: "furnaces behind the strip miner's chest, smelting its ore" },
};
// what the replay viewer draws: the four quarters the jobs go into, and the GPS overhead
export const VIEW = { x0: 34, x1: 100, z0: -4, z1: 108, y0: -60, y1: 130 };
const spot = (name) => [MID[0] + PLACES[name].at[0], 64, MID[1] + PLACES[name].at[1]];

export function build(w = newWorld()) {
  // trees scattered about, as on real land (the same every run), none in the middle chunk
  for (let i = 0; i < 40; i++) {
    const x = 6 + ((i * 37) % 132), z = 6 + ((i * 61 + 17) % 132);
    if (x < MID[0] - 3 || x > MID[0] + 18 || z < MID[1] - 3 || z > MID[1] + 18) tree(w, x, z, 4 + (i % 3));
  }
  const s = { w };

  // 1. The pathfinder: builds GPS (there's none yet), then mines for ore.
  const pf = spot("pathfinder");
  s.pathfinder = worker(w, "Pathfinder", pf, PLACES.pathfinder.facing, "minecraft:diamond_pickaxe", { coal: 64 }, {
    "computercraft:computer_normal": 4, "computercraft:wireless_modem_advanced": 4,
    "computercraft:disk_drive": 1, "computercraft:disk": 1, coal: 24,
  });
  s.pathfinder.role = "gps-deployer";
  w.on("placed-computer", ({ turtle, computer }) => { if (turtle === s.pathfinder) { computer.role = "gps"; computer.program = "gps host"; computer.deployed = true; } });
  s.pathfinder.boot();
  play(w, s.pathfinder, [...run(PATHFINDER_RANGE), ...install("gps-deployer"), ...run("refuel all"), ...run("gps-deploy 120"),
    ["until", /X:$/, 20], ["type", `${pf[0]}\n`], ["until", /Y:$/, 5], ["type", "64\n"], ["until", /Z:$/, 5], ["type", `${pf[2]}\n`],
    ["until", /Facing/, 5], ["type", "north\n"], ["until", /Enter to start/, 20], ["type", "\n"],
    // a second job on the same turtle: the installer replaces startup.lua
    ["until", /GPS hosts are running/, 900], ...run("wget run http://localhost:8080/install.lua strip-mine-turtle"),
    ["until", /Carry on\?|is\s+installed\./, 60], ["do", (c, w2) => { if (/Carry on\?/.test(c.term.dump())) w2.type(c, "y\n"); }],
    ["until", /is\s+installed\./, 60], ...run("stripmine 100 12 3 at -54"), ["wait", 5], ["type", "\n"],
    ["do", (c) => { c.role = "strip-mine-turtle"; }]]);

  // 2. The digger: the hole for the storage cellar.
  s.digger = worker(w, "Digger", spot("digger"), PLACES.digger.facing, "minecraft:diamond_pickaxe", { coal: 64, cobblestone: 128 }, { coal: 8 });
  s.digger.role = "excavate-turtle";
  s.digger.boot();
  play(w, s.digger, [["wait", 200], ...install("excavate-turtle"), ...run("install plan cellar"), ["until", /Cellar is installed/, 60],
    ...run("excavate cellar down"), ["wait", 5], ["type", "\n"]]);

  // 3. The leveller: flattens the plaza where the village would go.
  s.leveller = worker(w, "Leveller", spot("leveller"), PLACES.leveller.facing, "minecraft:diamond_pickaxe", { coal: 64 }, { coal: 8 });
  s.leveller.role = "level-turtle";
  s.leveller.boot();
  play(w, s.leveller, [["wait", 200], ...install("level-turtle"), ...run("level 24 24"), ["wait", 5], ["type", "\n"]]);

  // 4. The forester: an axe instead of a pickaxe, saplings and bone meal on board.
  s.forester = worker(w, "Forester", spot("forester"), PLACES.forester.facing, "minecraft:diamond_axe", {}, { oak_sapling: 8, bone_meal: 16, coal: 16 });
  s.forester.role = "tree-farm-turtle";
  s.forester.boot();
  play(w, s.forester, [["wait", 200], ...install("tree-farm-turtle"), ...run("treefarm 3 3"), ["wait", 5], ["type", "\n"]]);
  // 5. The smelter: a crafty turtle (pickaxe and crafting table, so no modem
  // and no GPS) with the pathfinder's chest behind it, an output chest on its
  // left, and cobblestone for its furnaces.
  s.smelter = addComputer(w, { pos: spot("smelter"), facing: PLACES.smelter.facing, kind: "turtle", label: "Smelter", role: "furnace-turtle", modem: false, fuel: 0 });
  w.equip(s.smelter, "right", "minecraft:crafting_table");
  s.smelter.inventory.add("minecraft:cobblestone", 40);
  s.smelter.inventory.add("minecraft:coal", 4);
  s.smelter.homeChest = s.pathfinder.homeChest;
  const sp = spot("smelter");
  s.smelter.outChest = addChest(w, [sp[0] + 1, sp[1], sp[2]], {}); // facing south, its left is east
  s.smelter.furnaceAt = [1, 2, 3, 4].map((i) => [sp[0], sp[1], sp[2] + i]);
  s.smelter.boot();
  play(w, s.smelter, [["wait", 200], ...install("furnace-turtle"), ...run("furnace 4"), ["until", /Enter to start/, 30], ["type", "\n"]]);

  // how far each turtle got from where it was placed (along X or Z)
  s.farthest = new Map();
  const starts = new Map([s.pathfinder, s.digger, s.leveller, s.forester, s.smelter].map((t) => [t, [...t.pos]]));
  w.on("move", ({ turtle, pos }) => {
    const st = starts.get(turtle);
    if (st) s.farthest.set(turtle, Math.max(s.farthest.get(turtle) || 0, Math.abs(pos[0] - st[0]), Math.abs(pos[2] - st[2])));
  });
  return s;
}

// what's in a turtle's chest and inventory, by item
function haul(t) {
  const out = {};
  for (const x of [...t.homeChest.inv.slots, ...t.inventory.slots]) if (x) out[x.name.replace("minecraft:", "")] = (out[x.name.replace("minecraft:", "")] || 0) + x.count;
  return out;
}

export function check(s) {
  const w = s.w;
  const said = (t, re) => re.test(t.term.dump());
  const hosts = w.computers.filter((c) => c.deployed && c.on).length;
  // the miner's chest, plus what the smelter took out of it (raw, in its furnaces or smelted)
  const ore = haul(s.pathfinder);
  const sm = s.smelter;
  const smelted = {};
  for (const x of [...sm.outChest.inv.slots, ...sm.inventory.slots, ...sm.furnaceAt.flatMap((p) => w.block(...p)?.inventory?.slots || [])]) {
    if (!x) continue;
    const k = x.name.replace("minecraft:", "");
    if (/_ingot$/.test(k)) smelted[k] = (smelted[k] || 0) + x.count;
    ore[k] = (ore[k] || 0) + x.count;
  }
  ore.raw_iron = (ore.raw_iron || 0) + (ore.iron_ingot || 0);
  ore.raw_gold = (ore.raw_gold || 0) + (ore.gold_ingot || 0);
  ore.raw_copper = (ore.raw_copper || 0) + (ore.copper_ingot || 0);
  const furnaces = sm.furnaceAt.filter((p) => w.block(...p)?.name === "minecraft:furnace").length;
  const ingots = Object.values(smelted).reduce((a, b) => a + b, 0);
  const ores = ["raw_iron", "raw_copper", "raw_gold", "diamond", "redstone", "lapis_lazuli"].reduce((n, k) => n + (ore[k] || 0), 0);
  const logs = Math.max(0, ...[...s.forester.term.dump().matchAll(/(\d+) logs so far/g)].map((m) => Number(m[1])));
  const out = [];

  // every step of a whole base: [step, done?, what got done / what's missing]
  const steps = [
    ["GPS over the base", hosts >= 4, `${hosts} of 4 hosts up`],
    ["Plaza levelled for the village", said(s.leveller, /Levelling complete/), "level 24 24"],
    ["Storage cellar dug", said(s.digger, /Excavation complete/), "excavate cellar down"],
    ["Wood coming in", logs > 0, `${logs} logs`],
    ["Ore coming in", ores > 0, ores ? `${ores} ores from Y -54: ${["raw_iron", "raw_copper", "raw_gold", "diamond", "redstone", "lapis_lazuli"].filter((k) => ore[k]).map((k) => `${ore[k]} ${k}`).join(", ")}` : "none: the strip miner's shaft didn't reach its tunnels"],
    ["One turtle, two jobs (GPS, then mining)", said(s.pathfinder, /Strip mine complete|overall|too\s+far\s+from/), "reinstalled by hand"],
    ["The strip miner finished at its range", /Strip mine complete/.test(s.pathfinder.term.dump()) && s.farthest.get(s.pathfinder) === 64, "nav.range 64, a 100-block tunnel at Y -54: dug to 64, skipped the rest, came back up"],
    ["Furnaces crafted and placed", furnaces === 4, `${furnaces} of 4, crafted from cobblestone by the crafty smelter`],
    ["Ore smelted", ingots > 0, ingots ? Object.entries(smelted).map(([k, n]) => `${n} ${k}`).join(", ") : "no ingots: nothing reached the smelter's furnaces"],
    ["Every turtle stayed within its range", (s.farthest.get(s.pathfinder) || 0) <= 64 && [s.digger, s.leveller, s.forester, s.smelter].every((t) => (s.farthest.get(t) || 0) <= 256),
      [...s.farthest].map(([t, n]) => `${t.label} ${n}`).join(", ") + " blocks out at most"],
    // nothing in the repo does these yet
    ["Storage hall built (chests, cable, modems, computer, monitor)", false, "missing: no program places them and installs the storage computer"],
    ["Storage set up with nobody there", false, "missing: the first 'storage' run needs its setup screen"],
    ["Computers, turtles and modems crafted", false, "missing: recipes.lua has no CC recipes, and there's no storage yet"],
    ["Crop field made", false, "missing: the crop farm needs farmland already there (no tilling or water)"],
    ["Village supplied and started", false, "missing: needs the storage system, or a chest of its blocks"],
    ["Jobs handed out, turtles re-tasked", false, "missing: a foreman program; here the script typed every command"],
  ];
  console.log("\nTowards a whole base:");
  for (const [step, done, note] of steps) console.log(`  ${done ? "done   " : "not yet"}  ${step}: ${note}`);
  // the steps today's programs can do must pass
  for (const [step, done, note] of steps.slice(0, 10)) if (!done) out.push(`${step}: ${note}`);
  return out;
}
