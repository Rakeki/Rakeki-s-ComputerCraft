// Runs each scenario on its own and its checks: `npm test` in sim/.
//   node sim/test/all.mjs [scenario ...]
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
// scenario → seconds of game time it needs for its checks
const SCENARIOS = { mining: 1700, storage: 400, machines: 1300, gps: 620, extras: 900, bootstrap: 3200 };
const pick = process.argv.slice(2);
let failed = 0;
for (const [name, secs] of Object.entries(SCENARIOS)) {
  if (pick.length && !pick.includes(name)) continue;
  const mod = await import(pathToFileURL(path.join(HERE, "..", "scenarios", `${name}.mjs`)).href);
  const t0 = Date.now();
  const s = mod.build();
  const errors = [];
  s.w.on("error", ({ computer, msg }) => errors.push(`${computer.label || "#" + computer.id}: ${msg}`));
  s.w.on("script-failed", ({ msg }) => errors.push(`setup: ${msg}`));
  s.w.run(secs);
  const problems = [...(mod.check ? mod.check(s) : []), ...errors];
  const took = ((Date.now() - t0) / 1000).toFixed(0);
  if (problems.length) { failed++; console.log(`FAIL ${name} (${secs}s in ${took}s)\n  ${problems.join("\n  ")}`); }
  else console.log(`ok   ${name} (${secs}s of game time in ${took}s)`);
}
process.exit(failed ? 1 : 0);
