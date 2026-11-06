// What happens when a turtle places something that's more than a block:
// computers (they become new computers, off until turned on), modems (they
// attach to the block they're placed against), disk drives (a floppy dropped
// in mounts as disk/ on the computers next to it), chests and furnaces.
// Also the command computer's commands and CC: Spatial Projector.
import fs from "node:fs";
import path from "node:path";
import { Peripheral, Inventory, DIRS, OPP, SIDES, sideDir } from "./world.mjs";
import { multi, LuaError } from "./vm.mjs";
import { addFurnace } from "./machines.mjs";
import * as items from "./items.mjs";

const add = (p, d) => [p[0] + d[0], p[1] + d[1], p[2] + d[2]];

// the side of computer c that faces the cell `pos`
function sideToward(c, pos) {
  for (const s of SIDES) {
    const d = DIRS[sideDir(c.facing, s)];
    if (add(c.pos, d).join() === pos.join()) return s;
  }
  return null;
}

//---------------------------------------------------------------- disk drives

export function diskDrive(w, pos) {
  const inv = new Inventory(1, { canPlace: (slot, item) => /computercraft:(disk|treasure_disk|pocket)/.test(item.name) });
  const drive = {
    get disk() { return inv.slots[0]; },
    // each floppy keeps its files in a folder of its own, by disk id
    dir() {
      const d = inv.slots[0];
      if (!d.diskId) d.diskId = (w.nextDiskId = (w.nextDiskId || 0) + 1) - 1;
      const dir = path.join(w.dir, "disk", String(d.diskId));
      fs.mkdirSync(dir, { recursive: true });
      return dir;
    },
  };
  const p = new Peripheral(["drive"], {
    isDiskPresent: () => !!inv.slots[0],
    hasData: () => !!inv.slots[0] && inv.slots[0].name === "computercraft:disk",
    getMountPath: (ctx) => {
      if (!inv.slots[0]) return null;
      const m = ctx.computer.diskMounts().find((x) => x.drive === ctx.name);
      return m ? m.at : "disk";
    },
    getDiskLabel: () => inv.slots[0]?.label ?? null,
    setDiskLabel: (ctx, l) => { if (inv.slots[0]) inv.slots[0].label = l; },
    getDiskID: () => (inv.slots[0] ? (drive.dir(), inv.slots[0].diskId) : null),
    hasAudio: () => false, getAudioTitle: () => null, playAudio: () => {}, stopAudio: () => {},
    ejectDisk: () => { inv.slots[0] = null; },
  });
  p.drive = drive;
  inv.onChange = () => { for (const { computer, name } of w.watchers(p)) w.queue(computer, [inv.slots[0] ? "disk" : "disk_eject", name]); };
  w.setBlock(...pos, "computercraft:disk_drive", { peripheral: p, inventory: inv });
  return p;
}

//---------------------------------------------------------------- placing

export function placing(w) {
  w.placeItemBlock = (t, p, item, name, dir) => {
    const behind = add(p, DIRS[dir]); // the block it's placed against (beyond the cell)
    if (/^computercraft:computer_(normal|advanced|command)$/.test(name)) {
      const kind = name.endsWith("command") ? "command" : "computer";
      const c = w.addComputer({ pos: p, kind, advanced: !name.endsWith("normal"), label: item.label || null, facing: dir === "up" || dir === "down" ? OPP[t.facing] : OPP[dir], role: null });
      w.emit("placed-computer", { turtle: t, computer: c });
      return true;
    }
    if (/^computercraft:wireless_modem_(normal|advanced)$/.test(name)) {
      // a modem block needs something to sit on: the block it was placed against
      const host = w.block(...behind);
      const m = w.wirelessModem(name.endsWith("advanced"));
      if (host && host.computer) {
        const side = sideToward(host.computer, p);
        host.computer.attach(side, m);
      }
      w.setBlock(...p, name, { modem: m, attachedTo: behind });
      return true;
    }
    if (name === "computercraft:disk_drive") { diskDrive(w, p); return true; }
    if (/chest$|barrel$/.test(name)) { w.addInventory(p, name, 27); return true; }
    if (/^minecraft:(furnace|blast_furnace|smoker)$/.test(name)) { addFurnace(w, p, { type: name }); return true; }
    if (name === "minecraft:hopper") { w.addInventory(p, name, 5); return true; }
    return false;
  };

  // breaking a placed computer gives it back with its id and label
  w.on("dig", ({ turtle, block, pos }) => {
    if (block.modem) { for (const c of w.computers) for (const [side, m] of Object.entries(c.attached)) if (m === block.modem) c.detach(side); }
  });
}

//---------------------------------------------------------------- commands

// /setblock and /fill for command computers (instabuild); anything else fails
export function commands(w) {
  const parseBlock = (s) => {
    const m = s.match(/^([\w:]+)(\[[^\]]*\])?(\{.*\})?$/);
    if (!m) return null;
    const state = {};
    if (m[2]) for (const kv of m[2].slice(1, -1).split(",")) { const [k, v] = kv.split("="); if (k) state[k.trim()] = v?.trim(); }
    return { name: m[1].includes(":") ? m[1] : "minecraft:" + m[1], state, nbt: m[3] };
  };
  const num = (v, base) => (v.startsWith("~") ? base + Number(v.slice(1) || 0) : Number(v));
  w.commandLog = [];
  w.runCommand = (c, cmd) => {
    const parts = cmd.trim().replace(/^\//, "").split(/\s+/);
    w.commandLog.push(cmd);
    const [x, y, z] = c.pos;
    const place = (px, py, pz, b, mode) => {
      const old = w.block(px, py, pz);
      if (mode === "keep" && old) return 0;
      if (old && old.computer) return 0;
      if (b.name === "minecraft:air") { w.setBlock(px, py, pz, null); return old ? 1 : 0; }
      w.setBlock(px, py, pz, b.name, Object.keys(b.state).length ? { state: b.state } : {});
      return 1;
    };
    if (parts[0] === "setblock" && parts.length >= 5) {
      const b = parseBlock(parts[4]);
      if (!b) return { ok: false, out: ["Unknown block type"] };
      const n = place(num(parts[1], x), num(parts[2], y), num(parts[3], z), b, parts[5]);
      return n ? { ok: true, out: ["Changed the block"], n } : { ok: false, out: ["Could not set the block"] };
    }
    if (parts[0] === "fill" && parts.length >= 8) {
      const b = parseBlock(parts[7]);
      if (!b) return { ok: false, out: ["Unknown block type"] };
      const [x0, y0, z0, x1, y1, z1] = parts.slice(1, 7).map((v, i) => num(v, [x, y, z][i % 3]));
      let n = 0;
      if (Math.abs(x1 - x0 + 1) * Math.abs(y1 - y0 + 1) * Math.abs(z1 - z0 + 1) > 32768) return { ok: false, out: ["Too many blocks in the specified area"] };
      for (let px = Math.min(x0, x1); px <= Math.max(x0, x1); px++) for (let py = Math.min(y0, y1); py <= Math.max(y0, y1); py++) for (let pz = Math.min(z0, z1); pz <= Math.max(z0, z1); pz++) n += place(px, py, pz, b, parts[8]);
      return n ? { ok: true, out: [`Successfully filled ${n} block(s)`], n } : { ok: false, out: ["No blocks were filled"] };
    }
    if (parts[0] === "say" || parts[0] === "tellraw") return { ok: true, out: [] };
    return { ok: false, out: [`Unknown or incomplete command: ${parts[0]}`] };
  };
}

//---------------------------------------------------------------- spatial projector

// CC: Spatial Projector: shapes drawn in the world for players with goggles
export function spatialProjector(w, pos, net) {
  const shapes = new Map();
  const p = new Peripheral(["spatial_projector"], {
    stats: () => ({ sourceX: pos[0], sourceY: pos[1], sourceZ: pos[2], objects: shapes.size }),
    getLimits: () => ({ maxObjectsPerProjector: 512, maxRange: 128 }),
    box: (ctx, id, x0, y0, z0, x1, y1, z1, opts) => { shapes.set(id, { kind: "box", box: [x0, y0, z0, x1, y1, z1], opts }); return true; },
    remove: (ctx, id) => shapes.delete(id),
    clear: () => { shapes.clear(); return true; },
  }, { mainThread: true });
  p.shapes = shapes;
  w.addPeripheral(pos, "spatialprojector:spatial_projector", p, net);
  return p;
}
