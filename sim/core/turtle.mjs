// The turtle API: moving, digging, placing, inventory, fuel, upgrades and
// crafting, against the simulated world. Each command that CC runs on the
// server thread hands back a task the prelude waits for.
import { multi, LuaError } from "./vm.mjs";
import * as items from "./items.mjs";

const MOVE = 0.4, ACT = 0.2, QUICK = 0.05; // seconds a command takes

export function turtleApi(t, w) {
  const inv = t.inventory;
  const DIRS = { north: [0, 0, -1], south: [0, 0, 1], east: [1, 0, 0], west: [-1, 0, 0], up: [0, 1, 0], down: [0, -1, 0] };
  const CW = { north: "east", east: "south", south: "west", west: "north" };
  const CCW = { north: "west", west: "south", south: "east", east: "north" };
  const OPP = { north: "south", south: "north", east: "west", west: "east" };
  const dirOf = (where) => (where === "up" ? "up" : where === "down" ? "down" : t.facing);
  const at = (where) => { const d = DIRS[dirOf(where)]; return [t.pos[0] + d[0], t.pos[1] + d[1], t.pos[2] + d[2]]; };
  const blockAt = (where) => w.block(...at(where));
  const solid = (b) => b && !items.FLUIDS.has(b.name) && !items.REPLACEABLE.has(b.name);
  const sel = () => t.selected - 1;
  const unlimited = () => w.unlimitedFuel;

  // run a command as a task: act now, answer after `secs`
  const task = (secs, fn) => (...args) => {
    const id = t.nextTask = (t.nextTask || 0) + 1;
    const boot = t.bootAt;
    let r;
    try { r = fn(...args); } catch (e) { r = e instanceof LuaError ? [false, e.message] : [false, `[sim] ${e.stack}`]; }
    if (!Array.isArray(r)) r = [r];
    w.after(secs, () => { if (t.on && t.bootAt === boot) w.queue(t, ["task_complete", id, true, ...r]); });
    return multi("\u0000task", id);
  };

  const give = (name, count, extra = {}) => {
    // into the selected slot first, then anywhere, then on the ground
    let left = count;
    left -= inv.insert({ name, count: 1, ...extra }, left, sel());
    if (left > 0) left -= inv.insert({ name, count: 1, ...extra }, left);
    if (left > 0) { w.emit("dropped", { turtle: t, name, count: left }); if (w.dropItem) w.dropItem(t.pos, { name, count: left, ...extra }); }
    return count - left;
  };

  const move = (where) => {
    if (!unlimited() && t.fuel <= 0) return [false, "Out of fuel"];
    const to = where === "back" ? (() => { const d = DIRS[OPP[t.facing]]; return [t.pos[0] + d[0], t.pos[1] + d[1], t.pos[2] + d[2]]; })() : at(where);
    if (to[1] < -64 || to[1] > 319) return [false, to[1] < -64 ? "Too low to move" : "Too high to move"];
    const b = w.block(...to);
    if (solid(b)) return [false, "Movement obstructed"];
    const here = w.block(...t.pos);
    w.setBlock(...t.pos, null);
    w.settle(...t.pos);
    t.pos = to;
    w.blocks.set(`${to[0]},${to[1]},${to[2]}`, here || { name: "computercraft:turtle_normal", computer: t, peripheral: t.peripheral });
    if (!unlimited()) t.fuel -= 1;
    w.emit("move", { turtle: t, pos: to });
    return [true];
  };
  const turn = (right) => { t.facing = right ? CW[t.facing] : CCW[t.facing]; const b = w.block(...t.pos); if (b) b.facing = t.facing; return [true]; };

  const dig = (where) => {
    const p = at(where);
    const b = w.block(...p);
    if (!b || items.FLUIDS.has(b.name)) return [false, "Nothing to dig here"];
    if (items.UNBREAKABLE.has(b.name) || b.computer) return [false, "Cannot break unbreakable block"];
    if (!t.upgrades.left?.tool && !t.upgrades.right?.tool) return [false, "No tool to dig with"];
    // an inventory spills its contents
    if (b.inventory) for (const s of b.inventory.slots) if (s) give(s.name, s.count, s.nbt ? { nbt: s.nbt } : {});
    for (const [name, n] of items.drops(b)) give(name, n);
    w.setBlock(...p, null);
    w.settle(...p);
    w.emit("dig", { turtle: t, pos: p, block: b });
    return [true];
  };

  const place = (where, text) => {
    const s = inv.slots[sel()];
    if (!s) return [false, "No items to place"];
    const p = at(where);
    const b = w.block(...p);
    // buckets pick up fluids
    if (s.name === "minecraft:bucket" && b && items.FLUIDS.has(b.name)) {
      inv.take(sel(), 1); give(b.name === "minecraft:lava" ? "minecraft:lava_bucket" : "minecraft:water_bucket", 1);
      w.setBlock(...p, null);
      return [true];
    }
    if (/^minecraft:(lava|water)_bucket$/.test(s.name)) {
      if (solid(b)) return [false, "Cannot place block here"];
      inv.take(sel(), 1); give("minecraft:bucket", 1);
      w.setBlock(...p, s.name.includes("lava") ? "minecraft:lava" : "minecraft:water");
      return [true];
    }
    // bone meal on a sapling or crop
    if (s.name === "minecraft:bone_meal") {
      if (b && /_sapling$|^minecraft:(wheat|carrots|potatoes)$/.test(b.name) && w.boneMeal) { inv.take(sel(), 1); w.boneMeal(p); return [true]; }
      return [false, "Cannot place item here"];
    }
    if (solid(b)) return [false, "Cannot place block here"];
    const kind = items.placesBlock(s.name);
    if (!kind) return [false, "Cannot place item here"];
    if (kind === "crop") {
      const below = w.block(p[0], p[1] - 1, p[2]);
      if (!below || below.name !== "minecraft:farmland") return [false, "Cannot place item here"];
    }
    // nothing to stand on: CC places against any face, needs a neighbour
    const name = items.blockFor(s.name);
    inv.take(sel(), 1);
    const placed = w.placeItemBlock ? w.placeItemBlock(t, p, s, name, dirOf(where), text) : null;
    if (!placed) w.setBlock(...p, name, name.match(/wheat|carrots|potatoes/) ? { state: { age: 0 } } : {});
    w.emit("place", { turtle: t, pos: p, name });
    return [true];
  };

  const inspect = (where) => {
    const b = blockAt(where);
    if (!b) return [false, "No block to inspect"];
    return [true, { name: b.name, state: b.state || (b.facing ? { facing: b.facing } : {}), tags: items.tags(b.name) }];
  };
  const detect = (where) => [solid(blockAt(where))];
  const compare = (where) => { const b = blockAt(where), s = inv.slots[sel()]; if (!b && !s) return [true]; if (!b || !s) return [false]; return [b.name === s.name]; };

  // the inventory in front / above / below, if any (chests, other turtles)
  const invAt = (where) => { const b = blockAt(where); return b ? (b.inventory || (b.computer && b.computer.inventory) || null) : null; };
  const drop = (where, n) => {
    const s = inv.slots[sel()];
    if (!s) return [false, "No items to drop"];
    const count = Math.min(n ?? s.count, s.count);
    const target = invAt(where);
    if (!target) {
      // into the world (lost, for our purposes)
      inv.take(sel(), count);
      w.emit("dropped", { turtle: t, name: s.name, count, pos: at(where) });
      if (w.dropItem) w.dropItem(at(where), { ...s, count });
      return [true];
    }
    const k = inv.moveTo(target, sel(), count);
    if (!k) return [false, "No space for items"];
    return [true];
  };
  const suck = (where, n) => {
    const src = invAt(where);
    // no inventory there: items lying on the ground in that block
    if (!src) {
      const got = w.pickUp ? w.pickUp(at(where), n ?? 64, (item, k) => { let m = inv.insert({ ...item, count: 1 }, k, sel()); if (m < k) m += inv.insert({ ...item, count: 1 }, k - m); return m; }) : 0;
      return got ? [true] : [false, "No items to take"];
    }
    let want = n ?? 64, got = 0;
    for (let i = 0; i < src.size && want > 0; i++) {
      const s = src.slots[i];
      if (!s) continue;
      // takes one kind of item per call, as CC does
      if (got > 0 && !items.same(s, inv.slots[sel()] || s)) continue;
      const k = Math.min(want, s.count);
      const before = { ...s };
      let moved = inv.insert({ ...before, count: 1 }, k, sel());
      if (moved < k) moved += inv.insert({ ...before, count: 1 }, k - moved);
      if (moved) { src.take(i, moved); got += moved; want -= moved; }
      if (got) break;
    }
    return got ? [true] : [false, "No items to take"];
  };

  const refuel = (n) => {
    const s = inv.slots[sel()];
    if (unlimited()) return s && items.turtleFuel(s.name) ? [true] : [false, "Items not combustible"];
    if (!s) return [false, "No items to combust"];
    const per = items.turtleFuel(s.name);
    if (!per) return [false, "Items not combustible"];
    if (n === 0) return [true];
    const count = Math.min(n ?? s.count, s.count, Math.ceil((t.fuelLimit - t.fuel) / per));
    inv.take(sel(), count);
    t.fuel = Math.min(t.fuelLimit, t.fuel + per * count);
    if (s.name === "minecraft:lava_bucket") give("minecraft:bucket", count);
    return [true];
  };

  const equip = (side) => {
    const s = inv.slots[sel()];
    const old = t.upgrades[side];
    if (s) {
      const up = w.upgradeFor ? w.upgradeFor(t, s.name, side) : null;
      if (!up) return [false, "Not a valid upgrade"];
      inv.take(sel(), 1);
      t.upgrades[side] = up;
      if (up.peripheral && "owner" in up.peripheral) up.peripheral.owner = { computer: t, side };
    } else t.upgrades[side] = null;
    if (old) give(old.item, 1);
    w.queue(t, [t.upgrades[side] ? "peripheral" : "peripheral_detach", side]);
    return [true];
  };

  const slotArg = (s) => { if (typeof s !== "number" || s < 1 || s > 16) throw new LuaError(`Slot out of range (between 1 and 16)`); return s - 1; };

  const api = {
    forward: task(MOVE, () => move("forward")),
    back: task(MOVE, () => move("back")),
    up: task(MOVE, () => move("up")),
    down: task(MOVE, () => move("down")),
    turnLeft: task(MOVE, () => turn(false)),
    turnRight: task(MOVE, () => turn(true)),
    dig: task(ACT, () => dig("forward")), digUp: task(ACT, () => dig("up")), digDown: task(ACT, () => dig("down")),
    place: task(ACT, (text) => place("forward", text)), placeUp: task(ACT, (text) => place("up", text)), placeDown: task(ACT, (text) => place("down", text)),
    detect: task(QUICK, () => detect("forward")), detectUp: task(QUICK, () => detect("up")), detectDown: task(QUICK, () => detect("down")),
    inspect: task(QUICK, () => inspect("forward")), inspectUp: task(QUICK, () => inspect("up")), inspectDown: task(QUICK, () => inspect("down")),
    compare: task(QUICK, () => compare("forward")), compareUp: task(QUICK, () => compare("up")), compareDown: task(QUICK, () => compare("down")),
    attack: task(ACT, () => [false, "Nothing to attack here"]), attackUp: task(ACT, () => [false, "Nothing to attack here"]), attackDown: task(ACT, () => [false, "Nothing to attack here"]),
    drop: task(QUICK, (n) => drop("forward", n)), dropUp: task(QUICK, (n) => drop("up", n)), dropDown: task(QUICK, (n) => drop("down", n)),
    suck: task(QUICK, (n) => suck("forward", n)), suckUp: task(QUICK, (n) => suck("up", n)), suckDown: task(QUICK, (n) => suck("down", n)),
    refuel: task(QUICK, (n) => refuel(n)),
    transferTo: task(QUICK, (slot, n) => {
      const to = slotArg(slot);
      const s = inv.slots[sel()];
      if (!s) return [true];
      const k = inv.moveTo(inv, sel(), n ?? s.count, to);
      return [k > 0 || (n === 0)];
    }),
    compareTo: task(QUICK, (slot) => { const a = inv.slots[sel()], b = inv.slots[slotArg(slot)]; return [(!a && !b) || items.same(a, b)]; }),
    equipLeft: task(QUICK, () => equip("left")),
    equipRight: task(QUICK, () => equip("right")),
    getEquippedLeft: () => (t.upgrades.left ? items.detail({ name: t.upgrades.left.item, count: 1 }) : null),
    getEquippedRight: () => (t.upgrades.right ? items.detail({ name: t.upgrades.right.item, count: 1 }) : null),
    select: (s) => { slotArg(s); t.selected = s; return true; },
    getSelectedSlot: () => t.selected,
    getItemCount: (s) => { const i = s === undefined || s === null ? sel() : slotArg(s); return inv.slots[i]?.count || 0; },
    getItemSpace: (s) => { const i = s === undefined || s === null ? sel() : slotArg(s); const it = inv.slots[i]; return it ? items.maxCount(it.name) - it.count : 64; },
    getItemDetail: (s, full) => { const i = s === undefined || s === null ? sel() : slotArg(s); const it = inv.slots[i]; return it ? items.detail(it, !!full) : null; },
    getFuelLevel: () => (unlimited() ? "unlimited" : t.fuel),
    getFuelLimit: () => (unlimited() ? "unlimited" : t.fuelLimit),
  };
  return api;
}
