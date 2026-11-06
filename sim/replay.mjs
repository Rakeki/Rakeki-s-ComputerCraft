// Runs a scenario with the recorder on and saves the replay for the viewer.
//   node sim/replay.mjs [scenario] [seconds]     (default: bootstrap 3200)
// Then `node sim/viewer/serve.mjs` and open http://localhost:8081.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { newWorld } from "./core/base.mjs";
import { record } from "./core/recorder.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const name = process.argv[2] || "bootstrap";
const seconds = Number(process.argv[3] || 3200);
const OUT = path.join(HERE, "out", "replays");

const mod = await import(pathToFileURL(path.join(HERE, "scenarios", `${name}.mjs`)).href);
// the recorder needs the world before the scenario fills it in, so start
// recording right after build: every block it placed is in the start
const w = newWorld();
const s = mod.build(w);
// with no VIEW, a box round where the computers are
let box = mod.VIEW;
if (!box) {
  const cs = w.computers.filter((c) => Math.abs(c.pos[0]) < 300 && Math.abs(c.pos[2]) < 300);
  const xs = cs.map((c) => c.pos[0]), zs = cs.map((c) => c.pos[2]);
  box = { x0: Math.min(...xs) - 24, x1: Math.max(...xs) + 24, z0: Math.min(...zs) - 24, z1: Math.max(...zs) + 24, y0: 40, y1: 130 };
}
const rec = record(w, box);
const t0 = Date.now();
for (let t = 0; t < seconds; t += 30) {
  w.run(Math.min(30, seconds - t));
  process.stdout.write(`\r${w.time.toFixed(0)}s of ${seconds}s simulated (${((Date.now() - t0) / 1000).toFixed(0)}s)   `);
}
console.log();
const problems = mod.check ? mod.check(s) : [];
fs.mkdirSync(OUT, { recursive: true });
const file = path.join(OUT, `${name}.json`);
const data = rec.data({ scenario: name, made: new Date().toISOString().slice(0, 10), problems });
fs.writeFileSync(file, JSON.stringify(data));
const kinds = {};
for (const e of data.ev) kinds[e[0]] = (kinds[e[0]] || 0) + 1;
console.log(`${data.blocks0.length} blocks at the start, events ${JSON.stringify(kinds)} -> ${path.relative(process.cwd(), file)} (${(fs.statSync(file).size / 1024).toFixed(0)} KB)`);
console.log("View it: node sim/viewer/serve.mjs, then http://localhost:8081/?replay=" + name);
