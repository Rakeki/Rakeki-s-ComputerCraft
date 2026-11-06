// Downloads CC: Tweaked's own Lua ROM (bios.lua + rom/) at a fixed release
// into sim/cc-rom/ (git-ignored), so the simulated computers run the real
// rednet, parallel, textutils, settings, gps, window, shell and so on.
// Run by `npm install` (postinstall); skips what's already there.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const TAG = "v1.21.1-1.121.0";
const BASE = "projects/core/src/main/resources/data/computercraft/lua/";
const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), "cc-rom");

if (fs.existsSync(path.join(OUT, ".tag")) && fs.readFileSync(path.join(OUT, ".tag"), "utf8") === TAG) {
  console.log(`CC ROM ${TAG} already in cc-rom/`);
  process.exit(0);
}
const tree = await (await fetch(`https://api.github.com/repos/cc-tweaked/CC-Tweaked/git/trees/${TAG}?recursive=1`)).json();
if (!tree.tree) throw new Error(`GitHub said: ${JSON.stringify(tree).slice(0, 200)}`);
// the help pages and games aren't needed
const files = tree.tree.filter((e) => e.type === "blob" && e.path.startsWith(BASE) && !/rom\/(help|programs\/fun)\//.test(e.path));
let n = 0;
async function get(e, tries = 4) {
  const rel = e.path.slice(BASE.length);
  const p = path.join(OUT, rel);
  if (fs.existsSync(p)) { n++; return; }
  try {
    const res = await fetch(`https://raw.githubusercontent.com/cc-tweaked/CC-Tweaked/${TAG}/${e.path}`);
    if (!res.ok) throw new Error(`${rel}: ${res.status}`);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, Buffer.from(await res.arrayBuffer()));
    n++;
  } catch (err) {
    if (tries <= 1) throw err;
    await new Promise((r) => setTimeout(r, 1000));
    return get(e, tries - 1);
  }
}
// a few at a time: hundreds at once time out
const queue = [...files];
await Promise.all(Array.from({ length: 6 }, async () => { while (queue.length) await get(queue.shift()); }));
fs.writeFileSync(path.join(OUT, ".tag"), TAG);
console.log(`CC ROM ${TAG}: ${n} files in cc-rom/`);
