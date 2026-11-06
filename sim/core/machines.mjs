// Blocks that do things on their own: furnaces, hoppers, ender chests,
// Create's creative crate, and the crafting table a crafty turtle uses.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Inventory, inventoryPeripheral, Peripheral } from "./world.mjs";
import { VM, lua, get, toLuaBytes } from "./vm.mjs";
import * as items from "./items.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

//---------------------------------------------------------------- furnaces

const SPEED = { "minecraft:furnace": 10, "minecraft:blast_furnace": 5, "minecraft:smoker": 5 };
const BLAST = /raw_|_ore$|_dust$|^mekanism:dust/;
const SMOKE = /beef|porkchop|chicken|potato|mutton|rabbit|cod|salmon|kelp/;

// a furnace on a cable (or next to a computer); slot 1 input, 2 fuel, 3 output
export function addFurnace(w, pos, opts = {}) {
  const type = opts.type || "minecraft:furnace";
  const inv = new Inventory(3, {
    canPlace: (slot, item) => slot === 0 || (slot === 1 && items.fuelItems(item.name) > 0),
  });
  // vanilla's faces, for turtles touching it: the top takes the input, the
  // sides the fuel, the bottom fuel in and the results out
  inv.faces = (face) => face === "up" ? { put: [0], take: [0] } : face === "down" ? { put: [1], take: [2] } : { put: [1], take: [1] };
  const f = { inv, burn: 0, progress: 0, made: 0, type };
  const c = w.addInventory(pos, type, 3, { inventory: inv, net: opts.net, name: opts.name });
  w.addTicker((dt) => {
    const input = inv.slots[0];
    const out = SPEED[type] && input && items.SMELT[input.name];
    const fits = out && (type === "minecraft:furnace" || (type === "minecraft:blast_furnace" ? BLAST.test(input.name) : SMOKE.test(input.name)));
    const room = fits && (!inv.slots[2] || (inv.slots[2].name === out && inv.slots[2].count < 64));
    if (!room) { f.progress = 0; if (f.burn > 0) f.burn = Math.max(0, f.burn - dt); return; }
    if (f.burn <= 0) {
      const fuel = inv.slots[1];
      if (!fuel) { f.progress = 0; return; }
      f.burn = items.fuelItems(fuel.name) * SPEED[type];
      inv.take(1, 1);
      if (fuel.name === "minecraft:lava_bucket" && !inv.slots[1]) inv.slots[1] = { name: "minecraft:bucket", count: 1 };
    }
    f.burn -= dt;
    f.progress += dt;
    if (f.progress >= SPEED[type]) {
      f.progress = 0;
      inv.take(0, 1);
      // straight into the output slot (nothing else may put items there)
      if (inv.slots[2]) inv.slots[2].count++; else inv.slots[2] = { name: out, count: 1 };
      f.made++;
    }
  });
  return { ...c, furnace: f };
}

// A hopper: every 0.4 s it moves one item down (or `into`), and pulls one
// from the inventory above it.
export function addHopper(w, pos, opts = {}) {
  const c = w.addInventory(pos, "minecraft:hopper", 5, { net: opts.net });
  const into = opts.into || [pos[0], pos[1] - 1, pos[2]];
  w.addTicker((dt) => {
    for (let k = 0; k < Math.round(dt / 0.4); k++) {
      const dest = w.block(...into)?.inventory;
      if (dest) for (let i = 0; i < 5; i++) if (c.inv.slots[i] && c.inv.moveTo(dest, i, 1, opts.slot)) break;
      const above = w.block(pos[0], pos[1] + 1, pos[2])?.inventory;
      if (above) for (let i = 0; i < above.size; i++) if (above.slots[i] && above.moveTo(c.inv, i, 1)) break;
    }
  });
  return c;
}

// Two ender chests with the same colours share one inventory.
export function addEnderChest(w, pos, frequency, opts = {}) {
  w.enderInvs ||= new Map();
  if (!w.enderInvs.has(frequency)) w.enderInvs.set(frequency, new Inventory(27));
  return w.addInventory(pos, opts.type || "enderstorage:ender_chest", 27, { inventory: w.enderInvs.get(frequency), net: opts.net, name: opts.name });
}

// Create's Creative Crate: whatever's taken out of it comes back.
export function addCreativeCrate(w, pos, item, opts = {}) {
  const inv = new Inventory(1);
  inv.slots[0] = { name: item, count: items.maxCount(item) };
  const take = inv.take.bind(inv);
  inv.take = (slot, n) => { const out = take(slot, n); inv.slots[0] = { name: item, count: items.maxCount(item) }; return out; };
  inv.canPlace = () => false;
  return w.addInventory(pos, "create:creative_crate", 1, { inventory: inv, net: opts.net, name: opts.name });
}

//---------------------------------------------------------------- crafting

// The storage computer's own recipe list (computers/storage-computer/recipes.lua).
let RECIPES = null;
export function recipes() {
  if (RECIPES) return RECIPES;
  const vm = new VM({});
  const src = fs.readFileSync(path.join(ROOT, "computers", "storage-computer", "recipes.lua"), "utf8");
  vm.run(`__R = (function() ${src}\nend)()`, "recipes.lua");
  lua.lua_getglobal(vm.L, toLuaBytes("__R"));
  RECIPES = get(vm.L, -1, null);
  return RECIPES;
}

const matchKey = (want, name) => {
  if (Array.isArray(want)) return want.some((x) => matchKey(x, name));
  if (want.includes("*")) return new RegExp("^" + want.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$").test(name);
  return want === name;
};

// what's in a turtle's 4x4 inventory, as the grid the items span (CC lets
// the recipe sit anywhere, so long as everything fits in 3x3)
function turtleGrid(t) {
  const cells = [];
  for (let i = 0; i < 16; i++) if (t.inventory.slots[i]) cells.push([i % 4, Math.floor(i / 4), t.inventory.slots[i]]);
  if (!cells.length) return null;
  const x0 = Math.min(...cells.map((c) => c[0])), x1 = Math.max(...cells.map((c) => c[0]));
  const y0 = Math.min(...cells.map((c) => c[1])), y1 = Math.max(...cells.map((c) => c[1]));
  if (x1 - x0 > 2 || y1 - y0 > 2) return null;
  const grid = [];
  for (let y = y0; y <= y1; y++) { const row = []; for (let x = x0; x <= x1; x++) row.push(t.inventory.slots[y * 4 + x]); grid.push(row); }
  return { grid, slots: cells.map((c) => c[1] * 4 + c[0]) };
}

// a recipe's rows without empty rows and columns round the edge
function trim(rows) {
  const wd = Math.max(...rows.map((r) => r.length));
  let r = rows.map((x) => x.padEnd(wd, " ")).filter((x) => x.trim());
  let lo = wd, hi = -1;
  for (const x of r) for (let i = 0; i < wd; i++) if (x[i] !== " ") { lo = Math.min(lo, i); hi = Math.max(hi, i); }
  return r.map((x) => x.slice(lo, hi + 1));
}

function matches(recipe, grid, mirror) {
  let rows = (recipe.trimmed ||= trim(recipe.rows));
  if (mirror) rows = rows.map((r) => [...r].reverse().join(""));
  const h = rows.length, wd = Math.max(...rows.map((r) => r.length));
  // trim the recipe's own empty edges
  if (grid.length !== h) return false;
  for (let y = 0; y < h; y++) {
    if (grid[y].length !== wd) return false;
    for (let x = 0; x < wd; x++) {
      const ch = rows[y][x] || " ";
      const it = grid[y][x];
      if (ch === " ") { if (it) return false; continue; }
      if (!it || !matchKey(recipe.keys[ch], it.name)) return false;
    }
  }
  return true;
}

export function turtleCraft(w, t, limit = 64) {
  const g = turtleGrid(t);
  if (!g) return [false, "No matching recipes"];
  const extra = w.extraRecipes || [];
  const recipe = [...extra, ...recipes()].find((r) => matches(r, g.grid) || matches(r, g.grid, true));
  if (!recipe) return [false, "No matching recipes"];
  if (limit === 0) return [true];
  const steps = Math.min(limit, ...g.slots.map((s) => t.inventory.slots[s].count));
  for (const s of g.slots) t.inventory.take(s, steps);
  let left = steps * recipe.count;
  left -= t.inventory.insert({ name: recipe.make, count: 1 }, left, t.selected - 1);
  if (left > 0) left -= t.inventory.insert({ name: recipe.make, count: 1 }, left);
  // a bucket recipe would give the bucket back; none of ours do
  w.emit("craft", { turtle: t, make: recipe.make, count: steps * recipe.count });
  return [true];
}

//---------------------------------------------------------------- growing

// Saplings grow into trees and crops ripen, on their own: a sapling after
// 2-5 minutes (bone meal: at once), wheat, carrots and potatoes one age step
// every 20-40 s. Anything planted by a turtle or a scenario counts.
export function addGrowth(w) {
  const plants = new Map(); // "x,y,z" → when it next grows
  const watch = (pos, name) => {
    if (/_sapling$/.test(name)) plants.set(pos.join(), w.time + 120 + items.random() * 180);
    else if (/^minecraft:(wheat|carrots|potatoes)$/.test(name)) plants.set(pos.join(), w.time + 20 + items.random() * 20);
  };
  w.on("place", ({ pos, name }) => watch(pos, name));
  w.plant = (pos, name, state) => { w.setBlock(...pos, name, state ? { state } : {}); watch(pos, name.includes(":") ? name : "minecraft:" + name); };
  // bone meal on a sapling or crop grows it now
  w.boneMeal = (pos) => { if (plants.has(pos.join())) plants.set(pos.join(), w.time); };
  w.addTicker(() => {
    for (const [k, t] of plants) {
      if (t > w.time) continue;
      const [x, y, z] = k.split(",").map(Number);
      const b = w.block(x, y, z);
      if (!b) { plants.delete(k); continue; }
      if (/_sapling$/.test(b.name)) {
        const wood = b.name.replace("_sapling", "");
        const h = 4 + Math.floor(items.random() * 3);
        // room to grow?
        let room = true;
        for (let dy = 1; dy <= h + 1; dy++) if (w.block(x, y + dy, z)) room = false;
        if (!room) { plants.set(k, w.time + 60); continue; }
        for (let dy = 0; dy < h; dy++) w.setBlock(x, y + dy, z, `${wood}_log`);
        for (let dx = -2; dx <= 2; dx++) for (let dz = -2; dz <= 2; dz++) for (let dy = h - 2; dy <= h + 1; dy++) {
          const r = dy >= h ? 1 : 2;
          if (Math.abs(dx) > r || Math.abs(dz) > r || (dx === 0 && dz === 0 && dy < h) || (Math.abs(dx) === 2 && Math.abs(dz) === 2)) continue;
          if (!w.block(x + dx, y + dy, z + dz)) w.setBlock(x + dx, y + dy, z + dz, `${wood}_leaves`);
        }
        plants.delete(k);
        w.emit("grew", { pos: [x, y, z], name: b.name });
      } else {
        const age = (b.state?.age ?? 0) + 1;
        b.state = { ...(b.state || {}), age: Math.min(7, age) };
        if (age >= 7) plants.delete(k); else plants.set(k, w.time + 20 + items.random() * 20);
      }
    }
  });
}

//---------------------------------------------------------------- on the ground

// Items lying in the world: dropped by turtles or by decaying leaves. They
// fall to the ground, a turtle sucks them up from the block they're in, and
// they despawn after 5 minutes. Leaves with no log within 4 blocks decay over
// half a minute or so, and 5% drop a sapling (the tree farm's replanting).
export function addGround(w) {
  const ground = new Map(); // "x,y,z" → [{ item, until }]
  w.ground = ground;
  w.dropItem = (pos, item) => {
    let [x, y, z] = pos;
    while (y > -64 && !w.block(x, y - 1, z)) y--;
    const k = `${x},${y},${z}`;
    if (!ground.has(k)) ground.set(k, []);
    ground.get(k).push({ item: { ...item }, until: w.time + 300 });
  };
  w.pickUp = (pos, n, take) => {
    let got = 0;
    for (const k of [pos.join(), `${pos[0]},${pos[1] - 1},${pos[2]}`]) {
      const list = ground.get(k);
      if (!list) continue;
      for (const e of list) {
        if (got >= n) break;
        if (got > 0 && e.item.name !== list.find((x) => x.item.count > 0)?.item.name) continue;
        const m = take(e.item, Math.min(n - got, e.item.count));
        e.item.count -= m; got += m;
      }
      const left = list.filter((e) => e.item.count > 0);
      if (left.length) ground.set(k, left); else ground.delete(k);
      if (got) break;
    }
    return got;
  };
  const decay = new Map(); // leaf "x,y,z" → when it goes
  const nearLog = (x, y, z) => {
    for (let dx = -4; dx <= 4; dx++) for (let dy = -4; dy <= 4; dy++) for (let dz = -4; dz <= 4; dz++) {
      if (Math.abs(dx) + Math.abs(dy) + Math.abs(dz) > 6) continue;
      const b = w.blocks.get(`${x + dx},${y + dy},${z + dz}`);
      if (b && /_log$/.test(b.name)) return true;
    }
    return false;
  };
  w.on("dig", ({ pos, block }) => {
    if (!/_log$/.test(block.name)) return;
    const [x, y, z] = pos;
    for (let dx = -4; dx <= 4; dx++) for (let dy = -4; dy <= 4; dy++) for (let dz = -4; dz <= 4; dz++) {
      const k = `${x + dx},${y + dy},${z + dz}`;
      const b = w.blocks.get(k);
      if (b && /_leaves$/.test(b.name) && !decay.has(k)) decay.set(k, w.time + 10 + items.random() * 40);
    }
  });
  w.addTicker(() => {
    for (const [k, t] of decay) {
      if (t > w.time) continue;
      decay.delete(k);
      const [x, y, z] = k.split(",").map(Number);
      const b = w.block(x, y, z);
      if (!b || !/_leaves$/.test(b.name) || nearLog(x, y, z)) continue;
      w.setBlock(x, y, z, null);
      if (items.random() < 0.05) w.dropItem([x, y, z], { name: b.name.replace("_leaves", "_sapling"), count: 1 });
      else if (items.random() < 0.02) w.dropItem([x, y, z], { name: "minecraft:stick", count: 1 });
    }
    for (const [k, list] of ground) {
      const left = list.filter((e) => e.until > w.time);
      if (left.length) ground.set(k, left); else ground.delete(k);
    }
  });
}
