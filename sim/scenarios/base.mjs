// The whole base: every program set up the way its README says, in one
// world, all running at once. `node sim/run.mjs base 1800` runs it for half
// an hour of game time; `node sim/map.mjs` turns the result into the map.
import { newWorld, addComputer, addChest, addGps, play, install, run } from "../core/base.mjs";
import { addCreativeCrate } from "../core/machines.mjs";
import { DIRS, OPP, CCW } from "../core/world.mjs";
import { statusServer, autoMine } from "./mining.mjs";
import { storage } from "./storage.mjs";

const back = (pos, facing) => { const d = DIRS[OPP[facing]]; return [pos[0] + d[0], pos[1] + d[1], pos[2] + d[2]]; };
const leftOf = (pos, facing) => { const d = DIRS[CCW[facing]]; return [pos[0] + d[0], pos[1] + d[1], pos[2] + d[2]]; };

// a turtle with its chest directly behind it
function turtleAt(w, pos, facing, chest, opts = {}) {
  const t = addComputer(w, { pos, facing, kind: "turtle", fuel: opts.fuel ?? 0, ...opts });
  t.homeChest = chest === null ? null : addChest(w, back(pos, facing), chest || { coal: 32 }, { net: opts.chestNet });
  for (const [name, n] of Object.entries(opts.carry || { coal: 8 })) t.inventory.add("minecraft:" + name, n);
  return t;
}

export function build(w = newWorld()) {
  const s = { w };
  s.gps = addGps(w);
  for (const g of s.gps) g.boot();
  Object.assign(s, statusServer(w), autoMine(w), storage(w));

  // overseer bridge: ender modem, posts to the overseer server on the PC
  s.posts = [];
  w.route("http://127.0.0.1:8090/", (req) => {
    if (req.path !== "api/ingest" || req.method !== "POST") return { code: 404, body: "" };
    try { s.posts.push(JSON.parse(req.body)); } catch { return { code: 400, body: "" }; }
    return { code: 200, body: '{"ok":true}' };
  });
  s.bridge = addComputer(w, { pos: [-5, 64, -6], label: "Bridge", role: "overseer-bridge", facing: "south", ender: true });
  s.bridge.boot();
  play(w, s.bridge, [["wait", 30], ...install("overseer-bridge"),
    ...run("set overseer.url http://127.0.0.1:8090"), ...run("set overseer.key simkey"), ["wait", 1], ["reboot"]]);

  // craft overseer, on the storage cable
  s.overseer = addComputer(w, { pos: [8, 64, -7], label: "Overseer", role: "craft-overseer", facing: "north" });
  s.overseer.attach("back", w.wiredModem(s.net));
  s.overseer.boot();
  play(w, s.overseer, [["wait", 90], ...install("craft-overseer"), ["reboot"]]);

  // two builder turtles, supply chests on the storage cable, spoil chest on the left
  s.builders = [];
  for (let i = 0; i < 2; i++) {
    const pos = [22 + i * 2, 64, -6];
    const t = turtleAt(w, pos, "north", { coal: 16 }, { role: "builder-turtle", chestNet: s.net, carry: { coal: 16 } });
    t.spoil = addChest(w, leftOf(pos, "north"), {});
    for (let k = 0; k <= 2; k++) s.net.cells.push([22 + i * 2, 64, -4 + k]);
    t.boot();
    play(w, t, [["wait", 100 + i * 5], ...install("builder-turtle"), ...run("refuel all"), ...run("builder"), ["wait", 15], ["reboot"]]);
    s.builders.push(t);
  }
  // build control: sends the cottage to them
  s.control = addComputer(w, { pos: [20, 64, -12], label: "Build control", role: "build-control", facing: "north" });
  s.control.boot();
  play(w, s.control, [["wait", 160], ...install("build-control"), ...run("install plan cottage"), ["until", /Cottage is installed/, 60],
    ...run("build cottage 26 64 -30"), ["until", /\?/, 30], ["type", "y\n"]]);

  // standalone turtles; the excavator digs a room up from where it stands, underground
  w.setBlock(40, 40, 40, null);
  s.excavator = turtleAt(w, [40, 40, 40], "north", { coal: 32 }, { role: "excavate-turtle" });
  s.excavator.boot();
  play(w, s.excavator, [["wait", 40], ...install("excavate-turtle"), ...run("excavate 5 5 3"), ["wait", 5], ["type", "\n"]]);

  // the leveller's area has a dirt mound and a tree on it
  w.fill(42, 43, 64, 65, 15, 16, "minecraft:dirt");
  w.fill(44, 44, 64, 67, 18, 18, "minecraft:oak_log");
  w.fill(43, 45, 68, 68, 17, 19, "minecraft:oak_leaves");
  w.fill(41, 41, 62, 63, 17, 17, null);
  s.leveller = turtleAt(w, [40, 64, 20], "north", { coal: 32 }, { role: "level-turtle" });
  s.leveller.boot();
  play(w, s.leveller, [["wait", 45], ...install("level-turtle"), ["type", "level 6 6\n"], ["wait", 5], ["type", "\n"]]);

  // the strip miner starts underground
  w.setBlock(60, 40, 40, null);
  s.stripper = turtleAt(w, [60, 40, 40], "north", { coal: 32 }, { role: "strip-mine-turtle" });
  s.stripper.boot();
  play(w, s.stripper, [["wait", 50], ...install("strip-mine-turtle"), ["type", "stripmine 10 4 3\n"], ["wait", 5], ["type", "\n"]]);

  // crate turtle: creative crate in front, its chest below
  addCreativeCrate(w, [20, 64, 9], "minecraft:cobblestone");
  s.crateChest = addChest(w, [20, 63, 10], {});
  s.crate = turtleAt(w, [20, 64, 10], "north", null, { role: "crate-turtle", modem: false, carry: {} });
  s.crate.boot();
  play(w, s.crate, [["wait", 55], ...install("crate-turtle"), ["type", "crate keep 64\n"]]);

  // turtle finder, on a pocket computer the player carries
  s.finder = addComputer(w, { pos: [5, 64, 5], kind: "pocket", label: "Finder", role: "turtle-finder" });
  s.finder.boot();
  play(w, s.finder, [["wait", 60], ...install("turtle-finder"), ["type", "finder\n"]]);
  return s;
}

export function check(s) {
  const out = [];
  const seen = (c, re, what) => { if (!re.test(c.term.dump())) out.push(`${c.label || c.role}: ${what}`); };
  if (!s.posts.length) out.push("overseer bridge: posted nothing");
  if (s.crateChest.inv.count("minecraft:cobblestone") < 64) out.push(`crate turtle: its chest has ${s.crateChest.inv.count("minecraft:cobblestone")} cobblestone, want 64`);
  return out;
}
