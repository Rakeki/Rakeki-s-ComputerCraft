// The simulated world: blocks, a clock, computers and turtles, wireless and
// wired networks, inventories. Everything runs on simulated time: a computer
// waiting for a timer costs nothing until the clock gets there.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { VM, multi, Multi, LuaError } from "./vm.mjs";
import { Term } from "./term.mjs";
import { FileSystem } from "./fs.mjs";
import * as items from "./items.mjs";
import { turtleApi } from "./turtle.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SIM = path.resolve(HERE, "..");
const ROM = path.join(SIM, "cc-rom");
const PRELUDE = fs.readFileSync(path.join(HERE, "prelude.lua"), "utf8");
const BIOS = fs.readFileSync(path.join(ROM, "bios.lua"), "latin1");
export const TASK = "\u0000task";
const TICK = 0.05;
const START_EPOCH = Date.UTC(2026, 0, 1);

export const DIRS = { north: [0, 0, -1], south: [0, 0, 1], east: [1, 0, 0], west: [-1, 0, 0], up: [0, 1, 0], down: [0, -1, 0] };
const CW = { north: "east", east: "south", south: "west", west: "north" };
const CCW = { north: "west", west: "south", south: "east", east: "north" };
const OPP = { north: "south", south: "north", east: "west", west: "east", up: "down", down: "up" };
export const SIDES = ["bottom", "top", "back", "front", "right", "left"];
export const key = (x, y, z) => `${x},${y},${z}`;
export const add = (p, d) => [p[0] + d[0], p[1] + d[1], p[2] + d[2]];

// the world direction a computer's side faces
export function sideDir(facing, side) {
  switch (side) {
    case "top": return "up";
    case "bottom": return "down";
    case "front": return facing;
    case "back": return OPP[facing];
    case "left": return CCW[facing];
    case "right": return CW[facing];
  }
  return null;
}
export { CW, CCW, OPP };

//---------------------------------------------------------------- heap

class Heap {
  constructor() { this.a = []; }
  get size() { return this.a.length; }
  push(v) { const a = this.a; a.push(v); let i = a.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (lt(a[i], a[p])) { [a[i], a[p]] = [a[p], a[i]]; i = p; } else break; } }
  peek() { return this.a[0]; }
  pop() {
    const a = this.a, top = a[0], last = a.pop();
    if (a.length) { a[0] = last; let i = 0; for (;;) { const l = i * 2 + 1, r = l + 1; let m = i; if (l < a.length && lt(a[l], a[m])) m = l; if (r < a.length && lt(a[r], a[m])) m = r; if (m === i) break; [a[i], a[m]] = [a[m], a[i]]; i = m; } }
    return top;
  }
}
const lt = (x, y) => x.t < y.t || (x.t === y.t && x.seq < y.seq);

//---------------------------------------------------------------- peripherals

// A peripheral: its types and methods. Each method gets (ctx, ...args) where
// ctx = { world, computer, name }. Methods in mainThread take a game tick and
// yield (inventories, Mekanism), the way CC runs them on the server thread.
export class Peripheral {
  constructor(types, methods, opts = {}) {
    this.types = types;
    this.methods = methods;
    this.mainThread = opts.mainThread === true ? new Set(Object.keys(methods)) : new Set(opts.mainThread || []);
    this.label = opts.label;
    this.attachedTo = new Set(); // { computer, name } that see it (for events)
  }
  get type() { return this.types[0]; }
}

// An inventory: chest, barrel, hopper, furnace, ender chest, turtle.
export class Inventory {
  constructor(size, opts = {}) {
    this.size = size;
    this.slots = new Array(size).fill(null);
    this.limit = opts.limit || 64; // per-slot limit multiplier (stack upgrades: 64 * n)
    this.canPlace = opts.canPlace || (() => true);
    this.canTake = opts.canTake || (() => true);
    this.onChange = null;
  }
  slotLimit(slot, name) { return name ? Math.min(this.limit === 64 ? items.maxCount(name) : items.maxCount(name) * this.limit / 64, this.limit) : this.limit; }
  // add up to n of item into slot (or anywhere); returns how many went in
  insert(item, n, slot) {
    let moved = 0;
    const tryOne = (i) => {
      if (n - moved <= 0 || !this.canPlace(i, item)) return;
      const s = this.slots[i];
      const lim = this.slotLimit(i, item.name);
      if (!s) { const k = Math.min(lim, n - moved); if (k > 0) { this.slots[i] = { ...item, count: k }; moved += k; } }
      else if (items.same(s, item)) { const k = Math.min(lim - s.count, n - moved); if (k > 0) { s.count += k; moved += k; } }
    };
    if (slot !== undefined && slot !== null) tryOne(slot);
    else {
      for (let i = 0; i < this.size; i++) if (this.slots[i] && items.same(this.slots[i], item)) tryOne(i);
      for (let i = 0; i < this.size; i++) if (!this.slots[i]) tryOne(i);
    }
    if (moved && this.onChange) this.onChange();
    return moved;
  }
  take(slot, n) {
    const s = this.slots[slot];
    if (!s || !this.canTake(slot, s)) return null;
    const k = Math.min(n, s.count);
    const out = { ...s, count: k };
    s.count -= k;
    if (s.count <= 0) this.slots[slot] = null;
    if (k && this.onChange) this.onChange();
    return out;
  }
  count(name) { return this.slots.reduce((a, s) => a + (s && s.name === name ? s.count : 0), 0); }
  add(name, count, extra = {}) { let left = count; while (left > 0) { const k = this.insert({ name, count: 1, ...extra }, left); if (!k) break; left -= k; } return count - left; }
  // move from this slot to another inventory; returns how many moved
  moveTo(other, fromSlot, limit, toSlot) {
    const s = this.slots[fromSlot];
    if (!s || !this.canTake(fromSlot, s)) return 0;
    const n = Math.min(limit ?? s.count, s.count);
    const k = other.insert({ ...s, count: 1 }, n, toSlot);
    if (k) this.take(fromSlot, k);
    return k;
  }
}

// CC's generic inventory methods for an Inventory
export function inventoryPeripheral(types, inv, extra = {}) {
  const slotArg = (s, n) => {
    if (typeof s !== "number") throw new LuaError(`bad argument #${n} (number expected, got ${s === null ? "nil" : typeof s})`);
    if (s < 1 || s > inv.size) throw new LuaError(`Slot out of range (between 1 and ${inv.size})`);
    return s - 1;
  };
  const target = (ctx, name) => {
    const p = ctx.computer.findPeripheral(name);
    if (!p || !p.inventory) throw new LuaError(`Target '${name}' does not exist`);
    return p.inventory;
  };
  const p = new Peripheral(types, {
    size: () => inv.size,
    list() {
      const m = new Map();
      inv.slots.forEach((s, i) => { if (s) m.set(i + 1, items.detail(s, false)); });
      return m;
    },
    getItemDetail(ctx, slot) { const s = inv.slots[slotArg(slot, 1)]; return s ? items.detail(s) : null; },
    getItemLimit(ctx, slot) { slotArg(slot, 1); return inv.limit; },
    pushItems(ctx, to, fromSlot, limit, toSlot) {
      const dest = target(ctx, to);
      const from = slotArg(fromSlot, 2);
      if (limit !== null && limit !== undefined && limit <= 0) return 0;
      return inv.moveTo(dest, from, limit ?? undefined, toSlot ? toSlot - 1 : undefined);
    },
    pullItems(ctx, from, fromSlot, limit, toSlot) {
      const src = target(ctx, from);
      if (typeof fromSlot !== "number" || fromSlot < 1 || fromSlot > src.size) throw new LuaError(`Slot out of range (between 1 and ${src.size})`);
      if (limit !== null && limit !== undefined && limit <= 0) return 0;
      return src.moveTo(inv, fromSlot - 1, limit ?? undefined, toSlot ? toSlot - 1 : undefined);
    },
    ...extra,
  }, { mainThread: true });
  p.inventory = inv;
  return p;
}

//---------------------------------------------------------------- networks

// A wired network: cables join modems; every peripheral whose modem is on
// gets a name ("minecraft:chest_3") that every computer on it sees.
export class WiredNet {
  constructor(world, name) {
    this.world = world; this.name = name;
    this.members = new Map(); // name → Peripheral
    this.modems = []; // { computer, side, modem } of computers on it
    this.cells = []; // cable cells, for the map
  }
  add(p, name) {
    name = name || this.world.peripheralName(p.type);
    this.members.set(name, p);
    p.netNames = p.netNames || new Map();
    p.netNames.set(this, name);
    for (const m of this.modems) { this.world.queue(m.computer, ["peripheral", name]); }
    return name;
  }
  remove(name) {
    const p = this.members.get(name);
    if (!p) return;
    this.members.delete(name);
    for (const m of this.modems) this.world.queue(m.computer, ["peripheral_detach", name]);
  }
}

class Modem extends Peripheral {
  constructor(world, opts) {
    const methods = {
      open(ctx, ch) { checkChannel(ch); modem.channels.add(ch); },
      close(ctx, ch) { checkChannel(ch); modem.channels.delete(ch); },
      isOpen(ctx, ch) { checkChannel(ch); return modem.channels.has(ch); },
      closeAll() { modem.channels.clear(); },
      transmit(ctx, ch, reply, msg) { checkChannel(ch); checkChannel(reply); world.transmit(modem, ch, reply, msg); },
      isWireless: () => !!opts.wireless,
    };
    if (!opts.wireless) {
      Object.assign(methods, {
        getNamesRemote: () => [...modem.net.members.keys()].filter((n) => n !== modem.localName()),
        isPresentRemote: (ctx, n) => modem.net.members.has(n) && n !== modem.localName(),
        getTypeRemote: (ctx, n) => { const p = modem.net.members.get(n); return p ? multi(...p.types) : null; },
        hasTypeRemote: (ctx, n, t) => { const p = modem.net.members.get(n); return p ? p.types.includes(t) : null; },
        getMethodsRemote: (ctx, n) => { const p = modem.net.members.get(n); return p ? Object.keys(p.methods) : null; },
        callRemote: (ctx, n, method, ...args) => {
          const p = modem.net.members.get(n);
          if (!p) throw new LuaError(`No peripheral attached`);
          return world.callPeripheral(ctx.computer, p, n, method, args);
        },
        getNameLocal: () => modem.localName(),
      });
    }
    super(opts.wireless ? ["modem"] : ["modem", "peripheral_hub"], methods);
    const modem = this;
    this.world = world;
    this.wireless = !!opts.wireless;
    this.ender = !!opts.ender;
    this.net = opts.net || null;
    this.channels = new Set();
    this.owner = null; // { computer, side }
  }
  localName() { const c = this.owner?.computer; return c && this.net ? c.netName(this.net) : null; }
  pos() { return this.owner?.computer.pos || [0, 0, 0]; }
  range() {
    const y = this.pos()[1];
    if (y <= 96) return 64;
    return 64 + Math.min(1, (y - 96) / (256 - 96)) * (384 - 64);
  }
}
function checkChannel(ch) {
  if (typeof ch !== "number" || ch < 0 || ch > 65535) throw new LuaError("Expected number in range 0-65535");
}

//---------------------------------------------------------------- computers

let computerSeq = 0;
let worldSeq = 0;

export class Computer {
  constructor(world, opts) {
    this.world = world;
    this.id = opts.id ?? world.nextComputerId++;
    this.kind = opts.kind || "computer"; // computer | turtle | pocket | command
    this.advanced = opts.advanced !== false;
    this.label = opts.label || null;
    this.pos = opts.pos || [0, 64, 0];
    this.facing = opts.facing || "north";
    this.dir = path.join(world.dir, "computer", String(this.id));
    this.attached = {}; // side → Peripheral (modems, upgrades)
    this.redstoneIn = {}; this.redstoneOut = {}; this.bundledOut = {};
    this.on = false;
    this.events = [];
    this.filter = null;
    this.timers = new Map();
    this.nextTimer = 1;
    this.term = new Term(...this.termSize(), this.advanced);
    this.log = [];
    this.errors = [];
    this.bootAt = 0;
    this.seq = computerSeq++;
    this.role = opts.role || null; // what the map calls it
    this.program = opts.program || null;
    if (this.kind === "turtle") {
      this.inventory = new Inventory(16);
      this.inventory.onChange = () => { this.inventoryChanged = true; };
      this.selected = 1;
      this.fuel = opts.fuel ?? 0;
      this.fuelLimit = this.advanced ? 100000 : 20000;
      this.upgrades = { left: null, right: null };
    }
    fs.mkdirSync(this.dir, { recursive: true });
    if (opts.files) for (const [p, body] of Object.entries(opts.files)) this.writeFile(p, body);
  }

  termSize() {
    if (this.kind === "turtle") return [39, 13];
    if (this.kind === "pocket") return [26, 20];
    return [51, 19];
  }

  writeFile(p, body) { const f = path.join(this.dir, p); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); }
  readFile(p) { const f = path.join(this.dir, p); return fs.existsSync(f) ? fs.readFileSync(f, "utf8") : null; }

  // peripherals by side: upgrades and modems first, then the block next to it
  sidePeripheral(side) {
    if (this.attached[side]) return this.attached[side];
    if (this.kind === "turtle" && (side === "left" || side === "right")) return this.upgrades[side]?.peripheral || null;
    const d = sideDir(this.facing, side);
    if (!d) return null;
    const b = this.world.block(...add(this.pos, DIRS[d]));
    if (b && b.peripheral && b.peripheral !== this.peripheral) return b.peripheral;
    return null;
  }

  // floppies in disk drives next to it: disk, disk2, ...
  diskMounts() {
    const out = [];
    for (const s of SIDES) {
      const p = this.sidePeripheral(s);
      if (p && p.drive && p.drive.disk) out.push({ at: out.length ? `disk${out.length + 1}` : "disk", dir: p.drive.dir(), ro: false, drive: s });
    }
    return out;
  }

  wiredModems() { return SIDES.map((s) => [s, this.sidePeripheral(s)]).filter(([, p]) => p instanceof Modem && !p.wireless); }

  // a peripheral by side or by its name on a wired network
  findPeripheral(name) {
    if (SIDES.includes(name)) return this.sidePeripheral(name);
    for (const [, m] of this.wiredModems()) { const p = m.net.members.get(name); if (p && name !== m.localName()) return p; }
    return null;
  }
  // what this computer is called on a wired network
  netName(net) { return this.peripheral?.netNames?.get(net) || null; }

  attach(side, p) {
    this.attached[side] = p;
    if (p instanceof Modem) {
      p.owner = { computer: this, side };
      if (p.net) {
        p.net.modems.push({ computer: this, side, modem: p });
        // the computer is a peripheral on the cable too
        if (!this.peripheral) this.peripheral = computerPeripheral(this);
        if (!this.netName(p.net)) p.net.add(this.peripheral, this.world.peripheralName(this.kind === "turtle" ? "turtle" : "computer"));
      }
    }
    if (this.on) this.world.queue(this, ["peripheral", side]);
  }
  detach(side) {
    const p = this.attached[side];
    if (!p) return;
    delete this.attached[side];
    if (p instanceof Modem && p.net) p.net.modems = p.net.modems.filter((m) => m.modem !== p);
    if (this.on) this.world.queue(this, ["peripheral_detach", side]);
  }

  //---------------------------------------------------------- lifecycle

  boot() {
    if (this.on) return;
    this.on = true;
    this.bootAt = this.world.time;
    this.events = [];
    this.filter = null;
    this.timers.clear();
    this.term = new Term(...this.termSize(), this.advanced);
    for (const p of Object.values(this.attached)) if (p instanceof Modem) p.channels.clear();
    this.redstoneOut = {}; this.bundledOut = {};
    this.vm = new VM({ __m: this.natives() });
    try {
      this.vm.run(PRELUDE, "prelude.lua");
      this.vm.start("__bios");
    } catch (e) {
      this.fail(`boot: ${e.message}`);
      return;
    }
    this.events.push(null); // first resume: no event
    this.world.wake(this);
  }

  shutdown(reboot = false) {
    if (!this.on) return;
    this.on = false;
    this.vm = null;
    this.events = [];
    this.timers.clear();
    for (const p of Object.values(this.attached)) if (p instanceof Modem) p.channels.clear();
    this.redstoneOut = {};
    if (reboot) this.world.after(TICK, () => this.boot());
  }

  fail(msg) {
    this.errors.push({ t: this.world.time, msg });
    this.world.emit("error", { computer: this, msg });
  }

  // run one event through the computer
  step() {
    if (!this.on || !this.events.length) return false;
    const ev = this.events.shift();
    if (ev && this.filter && ev[0] !== this.filter && ev[0] !== "terminate") return true;
    const r = this.vm.resume(ev);
    if (r.error) this.fail(r.error);
    if (r.done) { this.shutdown(); return true; }
    this.filter = r.filter;
    if (this.pendingPower) { const what = this.pendingPower; this.pendingPower = null; this.shutdown(what === "reboot"); }
    if (this.inventoryChanged) { this.inventoryChanged = false; this.world.queue(this, ["turtle_inventory"]); }
    return true;
  }

  print(line) { this.log.push(line); }

  //---------------------------------------------------------- natives

  natives() {
    const c = this, w = this.world;
    const timerAfter = (secs) => {
      const id = c.nextTimer++;
      const ticks = Math.max(1, Math.ceil((Number(secs) || 0) / TICK - 1e-9));
      const boot = c.bootAt;
      const t = w.time + ticks * TICK;
      c.timers.set(id, t);
      w.at(t, () => { if (c.on && c.bootAt === boot && c.timers.has(id)) { c.timers.delete(id); w.queue(c, ["timer", id]); } });
      return id;
    };
    const os = {
      getComputerID: () => c.id,
      getComputerLabel: () => c.label,
      setComputerLabel: (l) => { c.label = l ?? null; },
      queueEvent: (...ev) => { w.queue(c, ev); },
      startTimer: (s) => timerAfter(s),
      cancelTimer: (id) => { c.timers.delete(id); },
      setAlarm: (t) => {
        const now = w.ingameHours();
        let dt = ((t - now) % 24 + 24) % 24 * 50;
        const id = c.nextTimer++;
        c.timers.set(id, w.time + dt);
        w.at(w.time + Math.max(TICK, dt), () => { if (c.on && c.timers.has(id)) { c.timers.delete(id); w.queue(c, ["alarm", id]); } });
        return id;
      },
      cancelAlarm: (id) => { c.timers.delete(id); },
      shutdown: () => { c.pendingPower = "off"; },
      reboot: () => { c.pendingPower = "reboot"; },
      clock: () => Math.round((w.time - c.bootAt) * 20) / 20,
      time: (kind) => {
        if (kind === "utc" || kind === "local") return Math.floor((START_EPOCH + w.time * 1000) / 1000);
        return w.ingameHours();
      },
      day: (kind) => {
        if (kind === "utc" || kind === "local") return Math.floor((START_EPOCH + w.time * 1000) / 86400000);
        return Math.floor((w.time / 50 + 6) / 24);
      },
      epoch: (kind) => {
        if (kind === "utc" || kind === "local") return START_EPOCH + Math.round(w.time * 1000);
        if (kind === "ingame" || kind === undefined || kind === null) return Math.round((w.time / 50 + 6) * 3600000);
        return Math.round(w.time * 1000);
      },
    };
    const sideNames = () => SIDES.filter((s) => c.sidePeripheral(s));
    const peripheral = {
      isPresent: (s) => !!c.sidePeripheral(s),
      getType: (s) => { const p = c.sidePeripheral(s); return p ? multi(...p.types) : null; },
      hasType: (s, t) => { const p = c.sidePeripheral(s); return p ? p.types.includes(t) : null; },
      getMethods: (s) => { const p = c.sidePeripheral(s); return p ? Object.keys(p.methods) : null; },
      call: (s, method, ...args) => {
        const p = c.sidePeripheral(s);
        if (!p) throw new LuaError("No peripheral attached");
        return w.callPeripheral(c, p, s, method, args);
      },
      getNames: sideNames,
    };
    const redstone = {
      getSides: () => [...SIDES],
      getInput: (s) => (c.redstoneIn[s] || 0) > 0,
      getAnalogInput: (s) => c.redstoneIn[s] || 0,
      getAnalogueInput: (s) => c.redstoneIn[s] || 0,
      setOutput: (s, on) => { c.redstoneOut[s] = on ? 15 : 0; w.emit("redstone", { computer: c, side: s }); },
      getOutput: (s) => (c.redstoneOut[s] || 0) > 0,
      setAnalogOutput: (s, v) => { c.redstoneOut[s] = v; w.emit("redstone", { computer: c, side: s }); },
      setAnalogueOutput: (s, v) => { c.redstoneOut[s] = v; },
      getAnalogOutput: (s) => c.redstoneOut[s] || 0,
      getAnalogueOutput: (s) => c.redstoneOut[s] || 0,
      getBundledInput: () => 0,
      getBundledOutput: (s) => c.bundledOut[s] || 0,
      setBundledOutput: (s, v) => { c.bundledOut[s] = v; },
      testBundledInput: () => false,
    };
    const termApi = c.term.api();
    const natives = {
      TASK,
      os, term: termApi, fs: new FileSystem(c.dir, path.join(ROM, "rom"), () => c.diskMounts()).api(), peripheral, redstone,
      http: w.httpApi(c),
      host: "ComputerCraft 1.121.0 (Minecraft 1.21.1) [cc-sim]",
      defaultSettings: "motd.enable=false",
      bios: BIOS,
    };
    // the term was swapped on boot: keep the native table pointing at it
    if (c.kind === "turtle") natives.turtle = turtleApi(c, w);
    if (c.kind === "pocket") natives.pocket = { equipBack: () => multi(false, "No upgrade"), unequipBack: () => multi(false, "Nothing to unequip") };
    if (c.kind === "command") natives.commands = w.commandsApi(c);
    return natives;
  }
}

function computerPeripheral(c) {
  return new Peripheral([c.kind === "turtle" ? "turtle" : "computer"], {
    turnOn: () => { c.boot(); },
    shutdown: () => { c.shutdown(); },
    reboot: () => { c.shutdown(true); },
    getID: () => c.id,
    isOn: () => c.on,
    getLabel: () => c.label,
  });
}

//---------------------------------------------------------------- the world

export class World {
  constructor(opts = {}) {
    // each run gets a folder of its own (several can run at once); ones
    // from earlier runs go after a day
    const out = path.join(SIM, "out");
    fs.mkdirSync(out, { recursive: true });
    for (const d of fs.readdirSync(out)) {
      const p = path.join(out, d);
      try { if (d.startsWith("run-") && Date.now() - fs.statSync(p).mtimeMs > 86400000) fs.rmSync(p, { recursive: true, force: true }); } catch {}
    }
    this.dir = opts.dir || path.join(out, `run-${process.pid}-${(worldSeq++).toString(36)}`);
    fs.rmSync(this.dir, { recursive: true, force: true });
    fs.mkdirSync(this.dir, { recursive: true });
    this.time = 0;
    this.seq = 0;
    this.heap = new Heap();
    this.blocks = new Map();
    this.computers = [];
    this.nextComputerId = 0;
    this.typeCount = {};
    this.runnable = new Set();
    this.listeners = {};
    this.nets = new Map();
    this.modems = new Set(); // every modem that can transmit
    this.http = { routes: [] };
    this.traffic = new Map(); // "from>to|protocol" → count (rednet, for the map)
    this.broadcasts = new Map(); // "from|protocol" → count
    this.hosts = new Map(); // "id|protocol" → hostname
    this.lastStatus = new Map(); // id → its last cc_status report
    this.gpsPings = new Map(); // id → gps.locate pings
    this.gpsAnswers = new Map(); // "host>channel" → answers
    this.decor = []; // extra map things: { pos, kind, label }
    this.tickers = [];
    this.at(1, () => this.tick());
  }

  on(ev, fn) { (this.listeners[ev] ||= []).push(fn); }
  emit(ev, data) { for (const fn of this.listeners[ev] || []) fn(data); }

  at(t, fn) { this.heap.push({ t, seq: this.seq++, fn }); }
  after(dt, fn) { this.at(this.time + dt, fn); }

  ingameHours() { return ((this.time / 50 + 6) % 24); }

  peripheralName(type) {
    const n = this.typeCount[type] ?? 0;
    this.typeCount[type] = n + 1;
    return `${type}_${n}`;
  }

  //---------------------------------------------------------- blocks

  // A block, or null for air. Cells nothing has touched come from the
  // terrain generator (this.gen), so the ground goes all the way down.
  block(x, y, z) {
    const k = key(x, y, z);
    const b = this.blocks.get(k);
    if (b !== undefined) return b;
    const name = this.gen ? this.gen(x, y, z) : null;
    const nb = name ? { name, natural: true } : null;
    this.blocks.set(k, nb);
    return nb;
  }
  setBlock(x, y, z, name, extra = {}) {
    if (!name) { this.blocks.set(key(x, y, z), null); return null; }
    const b = { name: name.includes(":") ? name : "minecraft:" + name, ...extra };
    this.blocks.set(key(x, y, z), b);
    return b;
  }
  fill(x0, x1, y0, y1, z0, z1, name, fn) {
    for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) {
      const n = fn ? fn(x, y, z) : name;
      if (n) this.setBlock(x, y, z, n); else this.setBlock(x, y, z, null);
    }
  }
  // sand and gravel above an emptied cell fall down
  settle(x, y, z) {
    let yy = y + 1;
    for (;;) {
      const b = this.block(x, yy, z);
      if (!b || !items.FALLS.has(b.name)) break;
      let land = yy;
      while (land - 1 > -64 && !this.block(x, land - 1, z)) land--;
      if (land === yy) break;
      this.blocks.set(key(x, yy, z), null);
      this.blocks.set(key(x, land, z), b);
      yy++;
    }
  }

  // a chest (or any inventory block) at a spot
  addInventory(pos, type = "minecraft:chest", size = 27, opts = {}) {
    const inv = opts.inventory || new Inventory(size, opts);
    const p = inventoryPeripheral([type, ...(opts.types || []), "inventory"], inv, opts.methods);
    this.setBlock(...pos, type, { peripheral: p, inventory: inv });
    if (opts.net) opts.net.add(p, opts.name);
    return { inv, p, pos };
  }

  // a peripheral block (monitor, machine) at one or more spots
  addPeripheral(positions, name, p, net, netName) {
    if (typeof positions[0] === "number") positions = [positions];
    for (const pos of positions) this.setBlock(...pos, name, { peripheral: p });
    if (net) net.add(p, netName);
    return p;
  }

  // every { computer, name } that can see a peripheral (for its events)
  watchers(p) {
    const out = [];
    for (const c of this.computers) {
      if (!c.on) continue;
      for (const s of ["bottom", "top", "back", "front", "right", "left"]) if (c.sidePeripheral(s) === p) out.push({ computer: c, name: s });
      for (const [, m] of c.wiredModems()) { const n = p.netNames?.get(m.net); if (n) out.push({ computer: c, name: n }); }
    }
    return out;
  }

  net(name) {
    if (!this.nets.has(name)) this.nets.set(name, new WiredNet(this, name));
    return this.nets.get(name);
  }
  wiredModem(net) { const m = new Modem(this, { net }); this.modems.add(m); return m; }
  wirelessModem(ender = false) { const m = new Modem(this, { wireless: true, ender }); this.modems.add(m); return m; }

  //---------------------------------------------------------- computers

  addComputer(opts) {
    const c = new Computer(this, opts);
    this.computers.push(c);
    const blockName = c.kind === "turtle" ? (c.advanced ? "computercraft:turtle_advanced" : "computercraft:turtle_normal")
      : c.kind === "pocket" ? null : c.kind === "command" ? "computercraft:computer_command" : c.advanced ? "computercraft:computer_advanced" : "computercraft:computer_normal";
    c.peripheral = computerPeripheral(c);
    if (blockName) this.setBlock(...c.pos, blockName, { peripheral: c.peripheral, computer: c, facing: c.facing });
    return c;
  }

  // type into a computer as the player would (the shell's prompt, read())
  type(c, text) {
    let dt = 0;
    for (const ch of text) {
      dt += 0.05;
      if (ch === "\n") this.after(dt, () => { this.queue(c, ["key", 257, false]); this.queue(c, ["key_up", 257]); });
      else this.after(dt, () => this.queue(c, ["char", ch]));
    }
    return dt;
  }
  key(c, code, hold = false) { this.queue(c, ["key", code, hold]); this.queue(c, ["key_up", code]); }

  queue(c, ev) {
    if (!c.on) return;
    if (c.events.length >= 256) return; // CC drops events past 256
    c.events.push(ev);
    this.runnable.add(c);
  }
  wake(c) { this.runnable.add(c); }

  // call a peripheral method for a computer: main-thread ones take a tick
  callPeripheral(c, p, name, method, args) {
    const fn = p.methods[method];
    if (!fn) throw new LuaError(`No such method ${method}`);
    const ctx = { world: this, computer: c, name };
    if (!p.mainThread.has(method)) return fn(ctx, ...args);
    const id = c.nextTask = (c.nextTask || 0) + 1;
    const boot = c.bootAt;
    this.after(TICK, () => {
      if (!c.on || c.bootAt !== boot) return;
      let r;
      try {
        r = fn(ctx, ...args);
        const vals = r instanceof Multi ? r.values : r === undefined ? [] : [r];
        this.queue(c, ["task_complete", id, true, ...vals]);
      } catch (e) {
        this.queue(c, ["task_complete", id, false, e instanceof LuaError ? e.message : `[sim] ${e.stack}`]);
      }
    });
    return multi(TASK, id);
  }

  //---------------------------------------------------------- rednet

  transmit(from, ch, reply, msg) {
    const sender = from.owner?.computer;
    if (!sender) return;
    const sp = sender.pos;
    // note who talks to whom, for the map
    if (msg && typeof msg === "object" && msg.sProtocol !== undefined && typeof msg.nRecipient === "number" && ch !== 65533) {
      const proto = msg.sProtocol || "(none)";
      if (msg.nRecipient === 65535 || ch === 65535) this.broadcasts.set(`${sender.id}|${proto}`, (this.broadcasts.get(`${sender.id}|${proto}`) || 0) + 1);
      else if (ch === msg.nRecipient) this.traffic.set(`${sender.id}>${msg.nRecipient}|${proto}`, (this.traffic.get(`${sender.id}>${msg.nRecipient}|${proto}`) || 0) + 1);
      if (proto === "dns" && msg.message && msg.message.sType === "lookup response") this.hosts.set(`${sender.id}|${msg.message.sProtocol}`, msg.message.sHostname);
      if (proto === "cc_status" && msg.message && typeof msg.message === "object") this.lastStatus.set(sender.id, { t: this.time, ...msg.message });
    }
    // GPS: a ping on 65534 from a computer, answered by each host in range
    if (ch === 65534 && msg === "PING") this.gpsPings.set(sender.id, (this.gpsPings.get(sender.id) || 0) + 1);
    if (ch === 65534 && Array.isArray(msg)) this.gpsAnswers.set(sender.id, (this.gpsAnswers.get(sender.id) || 0) + 1);
    if (ch === 65534 || ch === 65533) {} // gps and repeat: nothing extra to note
    for (const m of this.modems) {
      if (m === from || !m.owner || !m.channels.has(ch)) continue;
      const rc = m.owner.computer;
      if (!rc.on) continue;
      let dist;
      if (from.wireless !== m.wireless) continue;
      if (from.wireless) {
        if (!(from.ender || m.ender)) {
          const rp = rc.pos;
          dist = Math.hypot(rp[0] - sp[0], rp[1] - sp[1], rp[2] - sp[2]);
          if (dist > Math.max(from.range(), m.range())) continue;
        } else {
          const rp = rc.pos;
          dist = Math.hypot(rp[0] - sp[0], rp[1] - sp[1], rp[2] - sp[2]);
        }
      } else {
        if (m.net !== from.net) continue;
        dist = 0;
      }
      this.queue(rc, ["modem_message", m.owner.side, ch, reply, msg, dist]);
    }
  }

  //---------------------------------------------------------- http

  // routes: { prefix, handle(req) → { code, body, headers } | Promise }
  route(prefix, handle) { this.http.routes.push({ prefix, handle }); }

  httpApi(c) {
    const w = this;
    const respond = (url, res, binary) => {
      const body = String(res.body ?? "");
      let pos = 0, open = true;
      const h = {
        readAll: () => { if (pos >= body.length) return body.length === 0 && pos === 0 ? (pos = 1, "") : null; const s = body.slice(pos); pos = body.length; return s; },
        readLine: (keep) => { if (pos >= body.length) return null; let i = body.indexOf("\n", pos); let s; if (i < 0) { s = body.slice(pos); pos = body.length; } else { s = body.slice(pos, keep ? i + 1 : i); pos = i + 1; } return s; },
        read: (n) => { if (pos >= body.length) return null; if (n === undefined || n === null) return binary ? body.charCodeAt(pos++) : body[pos++]; const s = body.slice(pos, pos + n); pos += s.length; return s; },
        close: () => { open = false; },
        getResponseCode: () => multi(res.code || 200, res.code === 404 ? "Not Found" : "OK"),
        getResponseHeaders: () => res.headers || {},
        seek: () => pos,
      };
      return h;
    };
    const request = (url, body, headers, binary, method) => {
      if (url && typeof url === "object") { ({ url, body, headers, binary, method } = url); }
      url = String(url);
      if (!/^https?:\/\//.test(url)) throw new LuaError("Must specify http or https");
      const boot = c.bootAt;
      const done = (res) => {
        if (!c.on || c.bootAt !== boot) return;
        if (!res || res.error) w.queue(c, ["http_failure", url, res?.error || "Could not connect"]);
        else if (res.code >= 400) w.queue(c, ["http_failure", url, `${res.code}`, respond(url, res, binary)]);
        else w.queue(c, ["http_success", url, respond(url, res, binary)]);
      };
      const route = w.http.routes.find((r) => url.startsWith(r.prefix));
      w.emit("http", { computer: c, url, method: method || (body ? "POST" : "GET") });
      w.after(0.1, () => {
        if (!route) return done({ error: "Could not connect" });
        let res;
        try { res = route.handle({ url, path: url.slice(route.prefix.length), body, headers, method: method || (body !== null && body !== undefined ? "POST" : "GET"), computer: c }); }
        catch (e) { res = { error: String(e.message) }; }
        done(res);
      });
      return true;
    };
    return {
      request,
      checkURL: (url) => { w.after(0.05, () => w.queue(c, ["http_check", url, true])); return true; },
      websocket: () => multi(false, "Websockets are not supported in the simulator"),
    };
  }

  // what a turtle gets for equipping an item (null: not an upgrade)
  upgradeFor(t, name) {
    if (/_pickaxe$|_axe$|_shovel$|_sword$|_hoe$/.test(name)) return { item: name, tool: true };
    if (/^computercraft:wireless_modem_(normal|advanced)$/.test(name)) return { item: name, peripheral: this.wirelessModem(name.endsWith("advanced")) };
    if (name === "minecraft:crafting_table") return { item: name, crafting: true, peripheral: this.workbench(t) };
    if (name === "computercraft:speaker") return { item: name, peripheral: new Peripheral(["speaker"], { playNote: () => true, playSound: () => true, playAudio: () => true, stop: () => {} }) };
    return null;
  }
  workbench(t) {
    return new Peripheral(["workbench"], {
      craft: (ctx, limit = 64) => (this.turtleCraft ? multi(...this.turtleCraft(t, limit)) : multi(false, "No matching recipes")),
    }, { mainThread: ["craft"] });
  }
  // give a new turtle its tools and modems (scenario helper)
  equip(t, side, name) { t.upgrades[side] = this.upgradeFor(t, name); const p = t.upgrades[side]?.peripheral; if (p && "owner" in p) p.owner = { computer: t, side }; }

  commandsApi(c) {
    const w = this;
    return {
      exec: (cmd) => { const r = w.runCommand ? w.runCommand(c, String(cmd)) : { ok: false, out: ["Unknown command"] }; return multi(r.ok, r.out || [], r.n ?? (r.ok ? 1 : 0)); },
      execAsync: (cmd) => { const id = (c.nextTask = (c.nextTask || 0) + 1); w.after(TICK, () => { const r = w.runCommand ? w.runCommand(c, String(cmd)) : { ok: false, out: [] }; w.queue(c, ["task_complete", id, r.ok, r.out || []]); }); return id; },
      list: () => ["setblock", "fill", "data", "item", "say", "tp"],
      getBlockPosition: () => multi(...c.pos),
      getBlockInfo: (x, y, z) => w.blockInfo(x, y, z),
      getBlockInfos: (x0, y0, z0, x1, y1, z1) => {
        const out = [];
        for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) for (let z = Math.min(z0, z1); z <= Math.max(z0, z1); z++) for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) out.push(w.blockInfo(x, y, z));
        return out;
      },
    };
  }
  blockInfo(x, y, z) {
    const b = this.block(x, y, z);
    if (!b) return { name: "minecraft:air", state: {}, tags: {} };
    return { name: b.name, state: b.state || {}, tags: {}, nbt: b.nbt };
  }

  //---------------------------------------------------------- running

  // furnaces, hoppers and anything else that works on its own, every second
  addTicker(fn) { this.tickers.push(fn); }
  tick() {
    for (const fn of this.tickers) { try { fn(1); } catch (e) { console.error("ticker:", e); } }
    this.after(1, () => this.tick());
  }

  // run the queued events, then move the clock on, until `until`
  run(seconds) {
    const end = this.time + seconds;
    for (;;) {
      let guard = 0;
      while (this.runnable.size) {
        const list = [...this.runnable].sort((a, b) => a.seq - b.seq);
        this.runnable.clear();
        const deferred = [];
        for (const c of list) {
          if (c.instantTime !== this.time) { c.instantTime = this.time; c.instantCount = 0; }
          while (c.on && c.events.length && c.instantCount < 5000) { c.step(); c.instantCount++; }
          if (c.on && c.events.length) deferred.push(c);
        }
        for (const c of deferred) {
          // busy (os.queueEvent loops): let the clock move on before more
          this.runnable.delete(c);
          const boot = c.bootAt;
          this.after(TICK, () => { if (c.bootAt === boot) this.wake(c); });
        }
        if (++guard > 100000) throw new Error("event storm");
      }
      const next = this.heap.peek();
      if (!next || next.t > end) { this.time = end; return; }
      this.heap.pop();
      if (next.t > this.time) this.time = next.t;
      next.fn();
    }
  }
}
