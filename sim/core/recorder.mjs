// Records a run for the replay viewer (sim/viewer/): the ground and every
// placed block at the start, then every block that changes, every turtle
// move and turn, every rednet message, each computer's status and its screen
// as it changes. replay.mjs saves it as sim/out/replays/<scenario>.json.
import { kind } from "./kinds.mjs";

const HEADING = { north: 0, east: 1, south: 2, west: 3 };
const SAMPLE = 0.5; // seconds between checks of turtles' facing, fuel and status
const SCREENS = 5; // seconds between screen checks (only changed screens are kept)

// box: { x0, x1, z0, z1, y0, y1 }: the part of the world worth drawing
export function record(w, box) {
  const inBox = (x, y, z) => x >= box.x0 && x <= box.x1 && z >= box.z0 && z <= box.z1 && y >= box.y0 && y <= box.y1;
  const ev = [];
  const sent = new Map(); // "x,y,z" -> kind the viewer has (null: air)
  const t = () => Math.round(w.time * 100) / 100;
  const shown = (b) => (!b || b.computer ? null : /water|lava/.test(b.name) ? kind(b.name) : kind(b.name));

  // the start: each column's top block, plus anything placed
  const blocks0 = [];
  const put0 = (x, y, z, b) => { const k = shown(b); if (!k) return; sent.set(`${x},${y},${z}`, k); blocks0.push([x, y, z, k]); };
  for (const [key, b] of w.blocks) {
    if (!b || b.natural || b.computer) continue;
    const [x, y, z] = key.split(",").map(Number);
    if (inBox(x, y, z)) put0(x, y, z, b);
  }
  for (let x = box.x0; x <= box.x1; x++) for (let z = box.z0; z <= box.z1; z++) {
    for (let y = Math.min(box.y1, 80); y >= box.y0; y--) {
      const b = w.block(x, y, z);
      if (!b) continue;
      if (!sent.has(`${x},${y},${z}`)) put0(x, y, z, b);
      if (b.natural) break;
    }
  }

  // a block changed: send it, and any neighbour it uncovered (cave walls,
  // the sides of a hole), so the viewer never shows a see-through hole
  const send = (x, y, z) => {
    if (!inBox(x, y, z)) return;
    const k = `${x},${y},${z}`;
    const now = shown(w.blocks.get(k) ?? w.block(x, y, z));
    if ((sent.get(k) ?? null) === now) return;
    sent.set(k, now);
    ev.push(["b", t(), x, y, z, now]);
  };
  const changed = (x, y, z) => {
    send(x, y, z);
    if ((sent.get(`${x},${y},${z}`) ?? null) === null) {
      for (const [dx, dy, dz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
        const k = `${x + dx},${y + dy},${z + dz}`;
        if (!sent.has(k)) send(x + dx, y + dy, z + dz);
      }
    }
  };
  const setBlock = w.setBlock.bind(w);
  w.setBlock = (x, y, z, name, extra) => { const r = setBlock(x, y, z, name, extra); changed(x, y, z); return r; };
  const settle = w.settle.bind(w);
  w.settle = (x, y, z) => { settle(x, y, z); for (let yy = y; yy <= y + 6; yy++) changed(x, yy, z); };

  // turtles (and every computer, for its screen)
  const starts = new Map(w.computers.map((c) => [c.id, [...c.pos]]));
  const last = new Map();
  const turtleState = (c) => [c.pos[0], c.pos[1], c.pos[2], HEADING[c.facing] ?? 0, c.fuel ?? 0];
  const noteTurtle = (c) => {
    const s = turtleState(c);
    const k = s.join();
    if (last.get(c) === k) return;
    last.set(c, k);
    ev.push(["p", t(), c.id, ...s]);
  };
  w.on("move", ({ turtle }) => noteTurtle(turtle));
  // computers a turtle places (GPS hosts) only appear from then on
  const born = new Map();
  w.on("placed-computer", ({ computer }) => { born.set(computer.id, t()); starts.set(computer.id, [...computer.pos]); });
  const statusSeen = new Map(), screenSeen = new Map();
  let nextScreens = 0;
  const sample = () => {
    for (const c of w.computers) {
      if (c.kind === "turtle") noteTurtle(c);
      const st = w.lastStatus.get(c.id);
      const sk = st ? `${st.state}|${st.detail ?? ""}` : (c.on ? "" : "off");
      if (statusSeen.get(c) !== sk) { statusSeen.set(c, sk); ev.push(["s", t(), c.id, st?.state ?? (c.on ? "" : "off"), st?.detail ?? ""]); }
    }
    if (w.time >= nextScreens) {
      nextScreens = w.time + SCREENS;
      for (const c of w.computers) {
        const text = c.term.dump();
        if (screenSeen.get(c) === text) continue;
        screenSeen.set(c, text);
        ev.push(["t", t(), c.id, text]);
      }
    }
    w.after(SAMPLE, sample);
  };
  w.after(0, sample);

  // rednet: who sent what to whom (and GPS pings)
  const transmit = w.transmit.bind(w);
  w.transmit = (from, ch, reply, msg) => {
    const c = from.owner?.computer;
    if (c && ch !== 65533) {
      if (msg && typeof msg === "object" && msg.sProtocol !== undefined && typeof msg.nRecipient === "number") {
        const proto = msg.sProtocol || "rednet";
        if (proto !== "dns") ev.push(["m", t(), c.id, msg.nRecipient === 65535 || ch === 65535 ? -1 : msg.nRecipient, proto]);
      } else if (ch === 65534 && msg === "PING") ev.push(["m", t(), c.id, -1, "gps"]);
    }
    return transmit(from, ch, reply, msg);
  };

  return {
    data(meta) {
      const computers = w.computers.map((c) => ({ id: c.id, label: c.label || `#${c.id}`, kind: c.kind, role: c.program || c.role || c.kind, start: starts.get(c.id) || [...c.pos], born: born.get(c.id) ?? 0 }));
      ev.sort((a, b) => a[1] - b[1]);
      return { meta: { ...meta, seconds: w.time, box }, computers, blocks0, ev };
    },
  };
}
