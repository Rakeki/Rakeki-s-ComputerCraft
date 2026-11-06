// The rest of the base: farms, the mob farm, a village, a Nether tunnel,
// and the projector with instabuild (command computer) building what it shows.
import { newWorld, addComputer, addChest, addMonitor, addGps, play, install, run } from "../core/base.mjs";
import { spatialProjector } from "../core/placing.mjs";
import { schematicannon } from "../core/mods.mjs";
import { DIRS, OPP, CCW } from "../core/world.mjs";

const back = (p, f) => { const d = DIRS[OPP[f]]; return [p[0] + d[0], p[1] + d[1], p[2] + d[2]]; };
const leftOf = (p, f) => { const d = DIRS[CCW[f]]; return [p[0] + d[0], p[1] + d[1], p[2] + d[2]]; };

function turtleAt(w, pos, facing, chest, opts = {}) {
  const t = addComputer(w, { pos, facing, kind: "turtle", fuel: 0, ...opts });
  t.homeChest = addChest(w, back(pos, facing), chest, { size: opts.chestSize || 27 });
  for (const [name, n] of Object.entries(opts.carry || {})) t.inventory.add(name.includes(":") ? name : "minecraft:" + name, n);
  return t;
}

export function extras(w, net) {
  const s = {};

  // cannon feeder: the chest against the Schematicannon is on the storage
  // cable, the computer against the chest, the Block Reader in front of it
  if (net) {
    s.cannonChest = addChest(w, [15, 64, 7], {}, { net });
    const { cannon, reader } = schematicannon(w, [15, 64, 6], s.cannonChest.inv, { cobblestone: 49, oak_log: 12 });
    s.cannon = cannon;
    w.addPeripheral([16, 64, 6], "advancedperipherals:block_reader", reader);
    s.cannonPc = addComputer(w, { pos: [16, 64, 7], label: "Cannon", role: "cannon-feeder", facing: "north" });
    s.cannonPc.boot();
    play(w, s.cannonPc, [["wait", 120], ...install("cannon-feeder"), ...run("cannon add cobblestone 49"), ...run("cannon add oak log 12"), ["wait", 1], ["reboot"]]);
  }

  // cobble breeder: a command computer and monitor; with no Cobblemon here
  // it has no pasture to find, so this only shows it starts and says so
  s.breeder = addComputer(w, { pos: [-20, 64, -36], label: "Breeder", role: "cobble-breeder", kind: "command", facing: "north", modemSide: "right" });
  addMonitor(w, [[-21, 66, -36], [-20, 66, -36], [-19, 66, -36], [-21, 65, -36], [-20, 65, -36], [-19, 65, -36]], 3, 2);
  s.breeder.boot();
  play(w, s.breeder, [["wait", 110], ...install("cobble-breeder"), ...run("breed setup")]);

  // tree farm: 2 columns of 3 trees, saplings and bone meal in the turtle
  s.treefarm = turtleAt(w, [-30, 64, -20], "north", { coal: 16 }, { role: "tree-farm-turtle", tool: "minecraft:diamond_axe", carry: { oak_sapling: 8, bone_meal: 16, coal: 8 } });
  s.treefarm.boot();
  play(w, s.treefarm, [["wait", 60], ...install("tree-farm-turtle"), ...run("treefarm 2 3"), ["wait", 5], ["type", "\n"]]);

  // crop farm: a 5x5 wheat field, the turtle flying one above the crops
  for (let x = -42; x <= -38; x++) for (let z = -24; z <= -20; z++) {
    w.setBlock(x, 63, z, "minecraft:farmland");
    w.plant([x, 64, z], "minecraft:wheat", { age: (x + z) % 3 === 0 ? 7 : 3 });
  }
  w.setBlock(-42, 64, -19, "minecraft:dirt"); // the chest stands on it
  s.cropfarm = turtleAt(w, [-42, 65, -20], "north", { coal: 16 }, { role: "crop-farm-turtle", carry: { coal: 8, wheat_seeds: 8 } });
  s.cropfarm.boot();
  play(w, s.cropfarm, [["wait", 65], ...install("crop-farm-turtle"), ...run("cropfarm 5 5"), ["wait", 5], ["type", "\n"]]);

  // mob farm: a double chest of what 'mobfarm list' asks for
  s.mobfarm = turtleAt(w, [-45, 64, 40], "north", { cobblestone: 1300, hopper: 4, chest: 2, oak_slab: 2, water_bucket: 8, coal: 64 }, { role: "mob-farm-turtle", chestSize: 54 });
  s.mobfarm.boot();
  play(w, s.mobfarm, [["wait", 70], ...install("mob-farm-turtle"), ...run("mobfarm"), ["wait", 5], ["type", "\n"]]);

  // the village: supply chest behind, spoil chest on the left
  const palette = {
    cobblestone: 512, spruce_planks: 384, oak_planks: 384, stripped_oak_log: 64, oak_log: 128, glass_pane: 64, oak_door: 8,
    spruce_stairs: 192, spruce_slab: 64, stone_bricks: 640, stone_brick_stairs: 64, oak_fence: 64, lantern: 32,
    red_wool: 16, white_wool: 16, dirt: 128, water_bucket: 4, red_bed: 4, crafting_table: 4, barrel: 4, composter: 2,
    hay_block: 8, coarse_dirt: 128, cobblestone_stairs: 64, coal: 128,
  };
  s.village = turtleAt(w, [-60, 64, -5], "north", palette, { role: "village-turtle", chestSize: 108, carry: { coal: 16 } });
  s.village.spoil = addChest(w, leftOf([-60, 64, -5], "north"), {}, { size: 54 });
  s.village.boot();
  play(w, s.village, [["wait", 75], ...install("village-turtle"), ...run("refuel all"), ...run("village"),
    ["until", /Pick a theme \(1-4\):$/, 20], ["type", "1\n"], ["until", /in blocks\?\s+\[\d+\]:$/, 10], ["type", "16\n"],
    ["until", /Press Enter to start/, 20], ["type", "\n"]]);

  // the Nether: its own GPS, and the tunnel turtle in a pocket it starts from
  const NX = 3000;
  s.netherGps = addGps(w, [NX, 110, 0], 5);
  for (const g of s.netherGps) { g.label = g.label.replace("GPS", "Nether GPS"); g.boot(); }
  w.fill(NX - 1, NX + 1, 64, 66, -1, 2, null);
  s.tunnel = turtleAt(w, [NX, 64, 0], "north", { coal: 32, cobblestone: 128 }, { role: "nether-tunnel-turtle", carry: { bucket: 1, torch: 8 } });
  s.tunnel.boot();
  play(w, s.tunnel, [["wait", 80], ...install("nether-tunnel-turtle"), ...run("nethertunnel 24"), ["wait", 5], ["type", "\n"]]);

  // instabuild: a command computer, builds the watchtower, then serves the projector
  s.insta = addComputer(w, { pos: [-20, 64, -30], label: "Instabuild", role: "instabuild", kind: "command", facing: "north" });
  s.insta.boot();
  play(w, s.insta, [["wait", 90], ...install("instabuild"), ...run("install plan watchtower"), ["until", /Watchtower is installed/, 60],
    ...run("instabuild watchtower -28 64 -44"), ["until", /\?/, 30], ["type", "y\n"], ...run("instabuild serve")]);

  // the projector: spatial projector on its left, monitor above it
  s.projector = addComputer(w, { pos: [-12, 64, -30], label: "Projector", role: "blueprint-projector", facing: "north", modemSide: "right" });
  s.spatial = spatialProjector(w, [-13, 64, -30]);
  s.projMon = addMonitor(w, [[-13, 66, -30], [-12, 66, -30], [-11, 66, -30], [-13, 65, -30], [-12, 65, -30], [-11, 65, -30]], 3, 2);
  s.projector.boot();
  play(w, s.projector, [["wait", 100], ...install("blueprint-projector"), ...run("install plan cottage"), ["until", /Cottage is installed/, 60], ["reboot"],
    ["wait", 30], ["tapText", "Build", null, s.projMon], ["wait", 10]]);
  return s;
}

export function build(w = newWorld()) {
  for (const g of addGps(w)) g.boot();
  return { w, ...extras(w) };
}

export function check(s) {
  const out = [];
  const w = s.w;
  const count = (x0, x1, y0, y1, z0, z1, re) => { let n = 0; for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) { const b = w.block(x, y, z); if (b && !b.natural && re.test(b.name)) n++; } return n; };
  if (s.cannon && s.cannon.placed < s.cannon.total) out.push(`cannon feeder: the cannon placed ${s.cannon.placed} of ${s.cannon.total}`);
  if (!w.commandLog.some((c) => /^(setblock|fill)/.test(c))) out.push("instabuild placed nothing");
  if (!s.spatial.shapes.size) out.push("the projector showed nothing on the Spatial Projector");
  // the farm harvested (it burns some of its logs, so go by its own count)
  const logs = Math.max(0, ...[...s.treefarm.term.dump().matchAll(/(\d+) logs so far/g)].map((m) => Number(m[1])));
  if (!logs) out.push("tree farm: no logs harvested");
  if (s.cropfarm.homeChest.inv.count("minecraft:wheat") === 0) out.push("crop farm: no wheat in its chest");
  // the village built something: its blocks round where it started
  const built = count(-76, -44, 63, 72, -21, 11, /stone_brick|spruce_|oak_planks|cobblestone|lantern|oak_fence/);
  if (built < 50) out.push(`village: only ${built} blocks built`);
  return out;
}
