// Runs a scenario and prints what each computer shows.
//   node sim/run.mjs [scenario] [seconds] [--screens] [--watch <label>]
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flags = new Set(args.filter((a) => a.startsWith("--")));
const plain = args.filter((a) => !a.startsWith("--"));
const name = plain[0] || "base";
const seconds = Number(plain[1] || 600);

const mod = await import(pathToFileURL(path.join(HERE, "scenarios", `${name}.mjs`)).href);
const s = mod.build();
const w = s.w;
const errors = [];
w.on("error", ({ computer, msg }) => { errors.push(`${w.time.toFixed(1)}s ${computer.label || "#" + computer.id}: ${msg}`); console.log(`  ! ${w.time.toFixed(1)}s ${computer.label || "#" + computer.id}: ${msg}`); });
w.on("script-failed", ({ computer, msg }) => { errors.push(`${w.time.toFixed(1)}s script: ${msg}`); console.log(`  ! script: ${msg}\n${computer.term.dump()}`); });

const t0 = Date.now();
const STEP = 30;
for (let t = 0; t < seconds; t += STEP) {
  w.run(Math.min(STEP, seconds - t));
  process.stdout.write(`\r${w.time.toFixed(0)}s simulated in ${((Date.now() - t0) / 1000).toFixed(1)}s   `);
}
console.log();
for (const c of w.computers) {
  if (!flags.has("--screens") && c.role === "gps") continue;
  console.log(`\n=== #${c.id} ${c.label || ""} (${c.role || c.kind}) ${c.on ? "on" : "OFF"} at ${c.pos.join(",")}${c.kind === "turtle" ? ` fuel ${c.fuel}` : ""}`);
  console.log(c.term.dump());
}
if (flags.has("--monitors")) for (const m of w.monitors) { console.log(`\n=== monitor ${[...(m.netNames?.values() || [])].join(",")}`); console.log(m.term.dump()); }
if (mod.check) {
  const problems = mod.check(s);
  console.log(problems.length ? `\nFAILED:\n  ${problems.join("\n  ")}` : "\nAll checks passed");
}
if (errors.length) console.log(`\n${errors.length} error(s)`);
