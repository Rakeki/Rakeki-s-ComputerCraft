// Pulls every crafting-table recipe (shaped and shapeless) out of a modpack's
// jars, so the storage system's crafting turtle knows modded recipes too.
// Writes a compact Lua file the storage computer loads as pack_recipes.lua.
//
//   node tools/recipes.mjs <out.lua> <minecraft.jar> <mods folder or jar>...
//
// e.g. node tools/recipes.mjs computers/storage-computer/packs/my-pack.lua \
//        ~/.minecraft/versions/1.21.1/1.21.1.jar ~/.minecraft/mods
//
// Tags (#minecraft:planks) stay tags, and item names are numbered, which
// keeps the file small enough for a computer's 1 MB of disk. No dependencies:
// the jars are read with a tiny ZIP reader.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

//---------------------------------------------------------------- zip

// Every file in a ZIP: name -> () => Buffer.
function readZip(file) {
  const buf = fs.readFileSync(file);
  let eocd = buf.length - 22;
  while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--;
  if (eocd < 0) return new Map();
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = new Map();
  for (let i = 0; i < count; i++) {
    const method = buf.readUInt16LE(p + 10), size = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28), extraLen = buf.readUInt16LE(p + 30), commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nameLen);
    out.set(name, () => {
      const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
      const data = buf.subarray(start, start + size);
      return method === 8 ? zlib.inflateRawSync(data) : data;
    });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

//---------------------------------------------------------------- reading

const [outFile, ...inputs] = process.argv.slice(2);
if (!outFile || !inputs.length) {
  console.error("Usage: node tools/recipes.mjs <out.lua> <minecraft.jar> <mods folder or jar>...");
  process.exit(1);
}
const jars = inputs.flatMap((p) => fs.statSync(p).isDirectory()
  ? fs.readdirSync(p).filter((f) => f.endsWith(".jar")).map((f) => path.join(p, f)) : [p]);

const recipes = new Map(); // recipe id -> json (a later jar replaces an earlier one, like a datapack)
const tagFiles = new Map(); // tag -> list of { replace, values }
const namespaces = new Set(["minecraft", "c", "neoforge", "forge"]);

for (const jar of jars) {
  let files;
  try { files = readZip(jar); } catch { console.error(`skipped ${path.basename(jar)}: not a readable jar`); continue; }
  for (const [name, read] of files) {
    const m = name.match(/^data\/([^/]+)\/(recipes?|tags\/items?)\/(.+)\.json$/);
    if (!m) continue;
    namespaces.add(m[1]);
    let json;
    try { json = JSON.parse(read().toString("utf8")); } catch { continue; }
    if (m[2].startsWith("recipe")) recipes.set(`${m[1]}:${m[3]}`, json);
    else {
      const tag = `${m[1]}:${m[3]}`;
      if (!tagFiles.has(tag)) tagFiles.set(tag, []);
      tagFiles.get(tag).push(json);
    }
  }
}

//---------------------------------------------------------------- conditions

// NeoForge/Forge load conditions: mostly "only if this mod is installed".
function passes(cond) {
  if (!cond || typeof cond !== "object") return true;
  const type = String(cond.type || "").replace(/^(neoforge|forge):/, "");
  switch (type) {
    case "mod_loaded": return namespaces.has(cond.modid);
    case "not": return !passes(cond.value);
    case "and": return (cond.values || []).every(passes);
    case "or": return (cond.values || []).some(passes);
    case "true": return true;
    case "false": return false;
    case "item_exists": return namespaces.has(String(cond.item).split(":")[0]);
    case "tag_empty": return false; // can't tell; assume not empty
    default: return false; // a condition we don't understand: leave the recipe out
  }
}
const conditionsOk = (json) => [json["neoforge:conditions"], json.conditions].every((list) => !list || (Array.isArray(list) ? list : [list]).every(passes));

//---------------------------------------------------------------- tags

const tagCache = new Map();
function tagItems(tag, seen = new Set()) {
  if (tagCache.has(tag)) return tagCache.get(tag);
  if (seen.has(tag)) return new Set();
  seen.add(tag);
  const items = new Set();
  for (const f of tagFiles.get(tag) || []) {
    if (f.replace) items.clear();
    for (const v of f.values || []) {
      const id = typeof v === "string" ? v : v && v.id;
      if (!id) continue;
      if (id.startsWith("#")) for (const i of tagItems(id.slice(1), seen)) items.add(i);
      else items.add(id);
    }
  }
  tagCache.set(tag, items);
  return items;
}

//---------------------------------------------------------------- recipes

const names = [], nameIndex = new Map();
const num = (id) => { if (!nameIndex.has(id)) { nameIndex.set(id, names.length + 1); names.push(id); } return nameIndex.get(id); };
const usedTags = new Set();

// One ingredient -> a key: an item number, "#tag", or a list of those. null
// when it's something the crafter can't match (components, custom types).
function key(ing) {
  if (Array.isArray(ing)) {
    const list = ing.map(key);
    if (list.some((k) => k === null)) return null;
    return list.length === 1 ? list[0] : list;
  }
  if (!ing || typeof ing !== "object") return null;
  if (ing.type && !/^(minecraft:)?(item|tag)$/.test(ing.type)) return null;
  if (typeof ing.item === "string") return num(ing.item);
  if (typeof ing.tag === "string") {
    if (!tagItems(ing.tag).size) return null;
    usedTags.add(ing.tag);
    return `#${ing.tag}`;
  }
  return null;
}

const out = [];
const skipped = { type: 0, ingredient: 0, result: 0, condition: 0 };
for (const [, r] of recipes) {
  const type = String(r.type || "");
  if (type !== "minecraft:crafting_shaped" && type !== "minecraft:crafting_shapeless") { skipped.type++; continue; }
  if (!conditionsOk(r)) { skipped.condition++; continue; }
  const result = r.result || {};
  const make = result.id || result.item;
  // items made with extra data (enchantments, custom names) aren't plain items
  if (typeof make !== "string" || (result.components && Object.keys(result.components).length)) { skipped.result++; continue; }
  const count = result.count || 1;
  let rows, keys = {};
  if (type === "minecraft:crafting_shaped") {
    rows = r.pattern;
    if (!Array.isArray(rows) || rows.length > 3 || rows.some((row) => row.length > 3)) { skipped.type++; continue; }
    let ok = true;
    for (const [ch, ing] of Object.entries(r.key || {})) {
      if (!rows.some((row) => row.includes(ch))) continue;
      const k = key(ing);
      if (k === null) { ok = false; break; }
      keys[ch] = k;
    }
    if (!ok) { skipped.ingredient++; continue; }
  } else {
    const ings = r.ingredients || [];
    if (!ings.length || ings.length > 9) { skipped.type++; continue; }
    const letters = "ABCDEFGHI";
    const cells = [];
    let ok = true;
    ings.forEach((ing, i) => {
      const k = key(ing);
      if (k === null) ok = false;
      keys[letters[i]] = k;
      cells.push(letters[i]);
    });
    if (!ok) { skipped.ingredient++; continue; }
    rows = [];
    for (let i = 0; i < cells.length; i += 3) rows.push(cells.slice(i, i + 3).join(""));
  }
  out.push({ make: num(make), count, rows: rows.join("/"), keys });
}

//---------------------------------------------------------------- writing

const lua = (v) => {
  if (typeof v === "number") return String(v);
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  return `{${Object.entries(v).map(([k, x]) => `${/^[A-Za-z_]\w*$/.test(k) ? k : `[${JSON.stringify(k)}]`}=${lua(x)}`).join(",")}}`;
};
const tags = {};
for (const t of [...usedTags].sort()) tags[t] = [...tagItems(t)].map(num);
const lines = [
  "-- Crafting recipes from a modpack, written by tools/recipes.mjs. The storage",
  "-- computer loads this as pack_recipes.lua, alongside recipes.lua.",
  "-- names: item ids by number. tags: tag -> item numbers. recipes: { make,",
  "-- count, rows (\"/\" between rows), keys (item number, \"#tag\" or a list) }.",
  `return {names=${lua(names)},`,
  `tags=${lua(tags)},`,
  "recipes={",
  ...out.map((r) => `{${r.make},${r.count},${lua(r.rows)},${lua(r.keys)}},`),
  "}}",
  "",
];
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, lines.join("\n"));
const size = fs.statSync(outFile).size;
console.log(`${out.length} crafting recipes, ${names.length} items, ${Object.keys(tags).length} tags from ${jars.length} jars.`);
console.log(`Left out: ${skipped.type} other recipe types, ${skipped.ingredient} with unusual ingredients, ${skipped.result} with special results, ${skipped.condition} for missing mods.`);
console.log(`Wrote ${outFile} (${Math.round(size / 1024)} KB).`);
