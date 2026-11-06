// Building blocks for scenarios: computers with their modems and monitors,
// GPS hosts, chests with things in them, installed programs.
import { World, Peripheral, Inventory, inventoryPeripheral } from "./world.mjs";
import { Term } from "./term.mjs";
import { terrain } from "./terrain.mjs";
import { serveSite, SITE_URL } from "./site.mjs";
import { play, install, prompt, run } from "./script.mjs";
import { multi, LuaError } from "./vm.mjs";
import { turtleCraft, addGrowth, addGround } from "./machines.mjs";
import { placing, commands } from "./placing.mjs";

export { play, install, prompt, run, SITE_URL };

export function newWorld(opts = {}) {
  const w = new World(opts);
  w.gen = opts.flat === false ? null : terrain;
  w.manifest = serveSite(w);
  w.monitors = [];
  w.turtleCraft = (t, limit) => turtleCraft(w, t, limit);
  placing(w); commands(w); addGrowth(w); addGround(w);
  return w;
}

// characters a monitor of this many blocks shows at a text scale
export function monitorSize(bw, bh, scale) {
  return [Math.round((bw * 16 - 5) / (1.5 * scale)), Math.round((bh * 16 - 5) / (16 / 7) / scale)];
}

// A monitor bw x bh blocks; positions[0] is its top-left as seen from the front.
export function addMonitor(w, positions, bw, bh, opts = {}) {
  let scale = 1;
  const term = new Term(...monitorSize(bw, bh, scale), opts.advanced !== false);
  const api = term.api();
  const p = new Peripheral(["monitor"], {});
  const methods = {};
  for (const [k, fn] of Object.entries(api)) methods[k] = (ctx, ...a) => fn(...a);
  methods.setTextScale = (ctx, s) => {
    if (typeof s !== "number" || s < 0.5 || s > 5) throw new LuaError("Expected number in range 0.5-5");
    scale = s;
    const [cw, ch] = monitorSize(bw, bh, s);
    if (cw !== term.w || ch !== term.h) {
      term.resize(cw, ch);
      for (const { computer, name } of w.watchers(p)) w.queue(computer, ["monitor_resize", name]);
    }
  };
  methods.getTextScale = () => scale;
  p.methods = methods;
  p.term = term;
  p.blocks = [bw, bh];
  w.addPeripheral(positions, opts.advanced === false ? "computercraft:monitor_normal" : "computercraft:monitor_advanced", p, opts.net, opts.name);
  w.monitors.push(p);
  return p;
}

// tap a monitor at (x, y): every computer that sees it gets monitor_touch
export function touch(w, mon, x, y) {
  for (const { computer, name } of w.watchers(mon)) w.queue(computer, ["monitor_touch", name, x, y]);
}

export function addChest(w, pos, contents = {}, opts = {}) {
  const c = w.addInventory(pos, opts.type || "minecraft:chest", opts.size || 27, opts);
  for (const [name, n] of Object.entries(contents)) c.inv.add(name.includes(":") ? name : "minecraft:" + name, n);
  return c;
}

// A computer (or turtle) with a wireless modem on `modemSide`.
export function addComputer(w, opts) {
  const c = w.addComputer(opts);
  if (opts.modem !== false && c.kind !== "turtle") c.attach(opts.modemSide || "top", w.wirelessModem(!!opts.ender));
  if (c.kind === "turtle") {
    w.equip(c, "left", opts.tool || "minecraft:diamond_pickaxe");
    if (opts.modem !== false) w.equip(c, "right", opts.ender ? "computercraft:wireless_modem_advanced" : "computercraft:wireless_modem_normal");
  }
  if (c.kind === "pocket" && opts.modem !== false) c.attach("back", w.wirelessModem(!!opts.ender));
  return c;
}

// Four GPS hosts high up, wide apart: `gps host` on each, as gps-deployer sets them up.
export function addGps(w, at = [0, 180, 0], spread = 6) {
  const [x, y, z] = at;
  const spots = [[x + spread, y, z], [x - spread, y, z], [x, y, z + spread], [x, y + spread, z - spread]];
  return spots.map((p, i) => {
    const c = addComputer(w, { pos: p, label: `GPS-${i + 1}`, role: "gps", advanced: false, files: {
      "startup.lua": `shell.run("gps", "host", ${p[0]}, ${p[1]}, ${p[2]})\n`,
    } });
    c.program = "gps host";
    return c;
  });
}

// An oak tree on the ground at (x, z): a trunk and a canopy, like a grown sapling.
export function tree(w, x, z, h = 5) {
  const y = 64;
  for (let dy = 0; dy < h; dy++) w.setBlock(x, y + dy, z, "minecraft:oak_log");
  for (let dx = -2; dx <= 2; dx++) for (let dz = -2; dz <= 2; dz++) for (let dy = h - 2; dy <= h + 1; dy++) {
    const r = dy >= h ? 1 : 2;
    if (Math.abs(dx) > r || Math.abs(dz) > r || (dx === 0 && dz === 0 && dy < h) || (Math.abs(dx) === 2 && Math.abs(dz) === 2)) continue;
    if (!w.block(x + dx, y + dy, z + dz)) w.setBlock(x + dx, y + dy, z + dz, "minecraft:oak_leaves");
  }
}
