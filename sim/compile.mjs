// Compiles Lua files with Fengari (no luac needed) and prints any syntax
// errors: a quick check before the simulator or the game.
//
//   node sim/compile.mjs                    every .lua under computers/, lib/, plans/, animations/
//   node sim/compile.mjs <file or folder>... just those
//
// Exits 1 if any file doesn't compile. Needs 'npm install' in sim/ once.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const { lua, lauxlib, to_luastring } = createRequire(import.meta.url)(path.join(here, "node_modules/fengari"));
const root = path.resolve(here, "..");

function luaFiles(p) {
  if (!fs.existsSync(p)) return [];
  if (fs.statSync(p).isFile()) return p.endsWith(".lua") ? [p] : [];
  return fs.readdirSync(p).flatMap((f) => (f === "node_modules" || f.startsWith(".")) ? [] : luaFiles(path.join(p, f)));
}

const args = process.argv.slice(2);
const files = (args.length ? args : ["computers", "lib", "plans", "animations"].map((d) => path.join(root, d)))
  .flatMap((p) => luaFiles(path.resolve(p)));
let bad = 0;
for (const f of files) {
  const L = lauxlib.luaL_newstate();
  if (lauxlib.luaL_loadbuffer(L, to_luastring(fs.readFileSync(f, "utf8")), null, to_luastring("@" + path.relative(root, f))) !== 0) {
    bad++;
    console.log(lua.lua_tojsstring(L, -1));
  }
}
console.log(`${files.length - bad} of ${files.length} files compile.`);
process.exit(bad ? 1 : 0);
