// Pulls the essence recipes (Mystical Agriculture's) out of a modpack's
// pack_recipes.lua (from tools/recipes.mjs) into a small file of their own,
// for the factory's Essence part: it loads essence_recipes.lua instead of
// asking the craft overseer, so the farm needs no 700 KB pack on its disk
// and no overseer that has one.
//
//   node tools/essence-recipes.mjs <pack_recipes.lua> <out.lua> [pattern]
//
// e.g. node tools/essence-recipes.mjs computers/craft-overseer/packs/trekt-mons.lua \
//        computers/factory/packs/trekt-mons-essence.lua
//
// pattern: a JavaScript regex for the ingredient ids to look for (default
// Mystical Agriculture's essences). Tags are written out as their items, as
// the craft overseer's 'recipes' answer does. No dependencies.
import fs from "node:fs";
import path from "node:path";

const [inFile, outFile, patternText] = process.argv.slice(2);
if (!inFile || !outFile) {
  console.log("Usage: node tools/essence-recipes.mjs <pack_recipes.lua> <out.lua> [pattern]");
  process.exit(1);
}
const pattern = new RegExp(patternText || "^mysticalagriculture:.+_essence$");

//---------------------------------------------------------------- reading the pack

// A Lua table literal as recipes.mjs writes them: numbers, JSON-style
// strings, and tables of items or of name=value / ["name"]=value.
function parseLua(src) {
  let i = src.indexOf("return") + 6;
  const ws = () => {
    for (;;) {
      while (/\s/.test(src[i])) i++;
      if (src.startsWith("--", i)) { while (i < src.length && src[i] !== "\n") i++; } else return;
    }
  };
  const string = () => {
    const start = i++;
    while (src[i] !== '"') i += src[i] === "\\" ? 2 : 1;
    i++;
    return JSON.parse(src.slice(start, i));
  };
  const value = () => {
    ws();
    if (src[i] === '"') return string();
    if (src[i] === "{") return table();
    const m = /^-?[\d.]+(e[-+]?\d+)?/i.exec(src.slice(i, i + 40));
    if (!m) throw new Error(`can't read the pack at character ${i}`);
    i += m[0].length;
    return Number(m[0]);
  };
  const table = () => {
    i++; // {
    const list = [], named = {};
    let isNamed = false;
    for (;;) {
      ws();
      if (src[i] === "}") { i++; break; }
      let key;
      if (src[i] === "[") {
        i++; ws(); key = string(); ws(); i++; // ]
        ws(); i++; // =
      } else {
        const m = /^([A-Za-z_]\w*)\s*=(?!=)/.exec(src.slice(i, i + 200));
        if (m) { key = m[1]; i += m[0].length; }
      }
      const v = value();
      if (key !== undefined) { named[key] = v; isNamed = true; } else list.push(v);
      ws();
      if (src[i] === ",") i++;
    }
    return isNamed ? named : list;
  };
  return value();
}

const pack = parseLua(fs.readFileSync(inFile, "utf8"));
const names = pack.names || [];
const tags = pack.tags || {};

// A key: an item number, "#tag" or a list of them -> an item id, or a sorted list of ids.
function expand(k) {
  if (typeof k === "number") return names[k - 1];
  if (typeof k === "string" && !k.startsWith("#")) return k;
  const out = new Set();
  for (const x of Array.isArray(k) ? k : [k]) {
    if (typeof x === "number") { if (names[x - 1]) out.add(names[x - 1]); } else if (x.startsWith("#")) {
      for (const n of tags[x.slice(1)] || []) if (names[n - 1]) out.add(names[n - 1]);
    } else out.add(x);
  }
  return [...out].sort();
}

//---------------------------------------------------------------- picking

const out = [];
for (const [make, count, rowText, keys] of pack.recipes || []) {
  if (!names[make - 1]) continue;
  const rows = String(rowText).split("/");
  const grid = {};
  let hit = false, ok = true;
  for (let row = 0; row < 3; row++) {
    for (let col = 0; col < 3; col++) {
      const ch = (rows[row] || "")[col];
      if (!ch || ch === " " || ch === ".") continue;
      if (keys[ch] === undefined) { ok = false; continue; }
      const item = expand(keys[ch]);
      grid[row * 3 + col + 1] = item;
      if ((Array.isArray(item) ? item : [item]).some((n) => n && pattern.test(n))) hit = true;
    }
  }
  if (ok && hit) out.push({ make: names[make - 1], count, grid });
}
out.sort((a, b) => (a.make < b.make ? -1 : a.make > b.make ? 1 : 0));

//---------------------------------------------------------------- writing

const lua = (v) => {
  if (typeof v === "number") return String(v);
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  return `{${Object.entries(v).map(([k, x]) => `${/^\d+$/.test(k) ? `[${k}]` : k}=${lua(x)}`).join(",")}}`;
};
const lines = [
  "-- Essence recipes from a modpack, written by tools/essence-recipes.mjs. The",
  "-- factory's Essence part loads this as essence_recipes.lua instead of asking",
  "-- the craft overseer. Each: { make, count, grid = { [cell 1-9] = item or a",
  "-- list of items to choose from } }.",
  "return {",
  ...out.map((r) => `${lua(r)},`),
  "}",
  "",
];
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, lines.join("\n"));
console.log(`${out.length} essence recipes. Wrote ${outFile} (${Math.round(fs.statSync(outFile).size / 1024)} KB).`);
