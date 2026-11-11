// Pulls every recipe a Create Mechanical Saw runs out of a modpack's jars,
// for the factory's Saw part:
//   - Create's own cutting recipes (create:cutting: andesite alloy into
//     shafts, mod woods, Immersive Engineering wires, ...),
//   - every stonecutter recipe (the saw runs them too, unless the pack
//     turned allowStonecuttingOnSaw off), and woodcutter ones (*:woodcutting),
//   - the wood recipes Create makes for itself when the game starts (they're
//     in no jar: its RuntimeDataGenerator), for every wood whose items exist:
//     a log, wood, stem, hyphae or block into its stripped kind, a stripped
//     one into 6 planks (3 for a block: bamboo), and planks into stairs,
//     2 slabs, a fence, fence gate, door, trapdoor, pressure plate, button
//     and sign.
//
//   node tools/saw-recipes.mjs <out.lua> <minecraft.jar> <mods folder or jar>...
//
// e.g. node tools/saw-recipes.mjs computers/factory/packs/my-pack-saw.lua \
//        ~/.minecraft/versions/1.21.1/1.21.1.jar ~/.minecraft/mods
//
// Put the file on the factory computer as /saw_pack.lua: it's used instead
// of the saw_recipes.lua that comes with the factory (vanilla and Create
// only, made with this tool). No dependencies: the jars are read with a
// tiny ZIP reader.
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
  console.error("Usage: node tools/saw-recipes.mjs <out.lua> <minecraft.jar> <mods folder or jar>...");
  process.exit(1);
}
const jars = inputs.flatMap((p) => fs.statSync(p).isDirectory()
  ? fs.readdirSync(p).filter((f) => f.endsWith(".jar")).map((f) => path.join(p, f)) : [p]);

const recipes = new Map(); // recipe id -> json (a later jar replaces an earlier one, like a datapack)
const tagFiles = new Map(); // tag -> list of { replace, values }
const items = new Set(); // every item id seen: item models, tags, recipes (the wood rules check these exist)
const namespaces = new Set(["minecraft", "c", "neoforge", "forge"]);

for (const jar of jars) {
  let files;
  try { files = readZip(jar); } catch { console.error(`skipped ${path.basename(jar)}: not a readable jar`); continue; }
  for (const [name, read] of files) {
    const model = name.match(/^assets\/([^/]+)\/(?:models\/item|items)\/([\w/.-]+)\.json$/);
    if (model) { items.add(`${model[1]}:${model[2]}`); continue; }
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
  const out = new Set();
  for (const f of tagFiles.get(tag) || []) {
    if (f.replace) out.clear();
    for (const v of f.values || []) {
      const id = typeof v === "string" ? v : v && v.id;
      if (!id) continue;
      if (id.startsWith("#")) for (const i of tagItems(id.slice(1), seen)) out.add(i);
      else out.add(id);
    }
  }
  tagCache.set(tag, out);
  return out;
}
for (const tag of tagFiles.keys()) for (const id of tagItems(tag)) items.add(id);

// An ingredient -> every item it takes ([] for one we can't read: components, custom types).
function ingredientItems(ing) {
  if (Array.isArray(ing)) return ing.flatMap(ingredientItems);
  if (!ing || typeof ing !== "object") return [];
  if (ing.type === "neoforge:compound" || ing.type === "forge:compound") return ingredientItems(ing.ingredients || ing.children);
  if (ing.type && !/^(minecraft:)?(item|tag)$/.test(ing.type)) return [];
  if (typeof ing.item === "string") return [ing.item];
  if (typeof ing.tag === "string") return [...tagItems(ing.tag)];
  return [];
}

//---------------------------------------------------------------- recipes

const out = new Map(); // "make<from" -> { make, count, from, kind }
const add = (from, make, count, kind) => {
  if (from === make) return;
  const key = `${make}<${from}`;
  if (!out.has(key)) out.set(key, { make, count, from, kind });
};
const skipped = { condition: 0, ingredient: 0, result: 0 };
const kinds = { cut: 0, stone: 0, wood: 0 };

for (const [, r] of recipes) {
  let type = String(r.type || "");
  if (!type.includes(":")) type = `minecraft:${type}`;
  let kind;
  if (type === "create:cutting") kind = "cut";
  else if (type === "minecraft:stonecutting") kind = "stone";
  else if (/:woodcutting$/.test(type)) kind = "stone"; // a woodcutter works like a stonecutter
  else continue;
  if (!conditionsOk(r)) { skipped.condition++; continue; }
  let make, count;
  if (kind === "cut") {
    // the first sure result; chance ones (bark, sawdust) just go to storage
    const res = (r.results || []).find((x) => x && !(x.chance < 1)) || {};
    const it = typeof res.item === "object" ? res.item : res;
    make = it.id || (typeof it.item === "string" ? it.item : undefined);
    count = it.count || res.count || 1;
  } else {
    const res = typeof r.result === "string" ? { id: r.result } : r.result || {};
    make = res.id || res.item;
    count = res.count || r.count || 1;
  }
  if (typeof make !== "string") { skipped.result++; continue; }
  const from = ingredientItems(kind === "cut" ? (r.ingredients || [])[0] : r.ingredient);
  if (!from.length) { skipped.ingredient++; continue; }
  for (const f of from) { add(f, make, count, kind); kinds[kind]++; }
}

// Create's own wood recipes, as RuntimeDataGenerator makes them.
const STRIPPED_PREFIX = /^(\w*?)stripped_(\w*)(_log|_wood|_stem|_hyphae|_block|(?<!_)wood)$/;
const STRIPPED_SUFFIX = /^(\w*)(_log|_wood|_stem|_hyphae|_block|(?<!_)wood)(\w*)_stripped(\w*)$/;
const NON_STRIPPED = /^(?!stripped_)([a-z_]+)(_log|_wood|_stem|_hyphae|(?<!bioshroom)_block)(([a-z_]+)(?<!_stripped))?$/;
// woods whose planks have another name (Create's MISMATCHED_WOOD_NAMES)
const MISMATCHED = { "ars_nouveau:blue_archwood": "ars_nouveau:archwood", "deeperdarker:blooming": "deeperdarker:bloom" };
const PIECES = [["_stairs", 1], ["_slab", 2], ["_fence", 1], ["_fence_gate", 1], ["_door", 1], ["_trapdoor", 1],
  ["_pressure_plate", 1], ["_button", 1], ["_sign", 1]];
const has = (id) => items.has(id);
for (const id of [...items].sort()) {
  const [ns, p] = id.split(":");
  if (!p || p.includes("/")) continue;
  const pre = p.match(STRIPPED_PREFIX), suf = p.match(STRIPPED_SUFFIX);
  if (pre || suf) {
    // a stripped one: into planks, and the planks into their pieces
    let base = `${ns}:${pre ? pre[1] + pre[2] : suf[1]}`;
    base = MISMATCHED[base] || base;
    const planks = `${base}_planks`;
    if (!has(planks)) continue;
    add(id, planks, p.includes("block") ? 3 : 6, "wood"); kinds.wood++;
    for (const [end, n] of PIECES) {
      // Biomes O' Plenty-style names first ("fir_planks_stairs"), then vanilla's ("oak_stairs")
      const piece = [`${planks}${end}`, `${base}${end}`].find(has);
      if (piece) { add(planks, piece, n, "wood"); kinds.wood++; }
    }
  } else if (NON_STRIPPED.test(p)) {
    const stripped = [`${ns}:stripped_${p}`, `${ns}:${p}_stripped`].find(has);
    if (stripped) { add(id, stripped, 1, "wood"); kinds.wood++; }
  }
}

//---------------------------------------------------------------- writing

const list = [...out.values()].sort((a, b) => a.make < b.make ? -1 : a.make > b.make ? 1 : a.from < b.from ? -1 : 1);
const names = [], index = new Map();
const num = (id) => { if (!index.has(id)) { index.set(id, names.length + 1); names.push(id); } return index.get(id); };
const KIND = { cut: 1, stone: 2, wood: 3 };
const rows = list.map((r) => `{${num(r.make)},${r.count},${num(r.from)},${KIND[r.kind]}},`);
const lines = [
  "-- What a Create Mechanical Saw makes, written by tools/saw-recipes.mjs for",
  "-- the factory's Saw part. names: item ids by number. recipes: { make,",
  "-- count, from (one goes in), kind (1 Create cutting, 2 stonecutter, 3 Create's wood) }.",
  `return {names={${names.map((n) => JSON.stringify(n)).join(",")}},`,
  "recipes={",
  ...rows,
  "}}",
  "",
];
fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true });
fs.writeFileSync(outFile, lines.join("\n"));
const size = fs.statSync(outFile).size;
console.log(`${list.length} saw recipes (${kinds.cut} Create cutting, ${kinds.stone} stonecutter, ${kinds.wood} wood), ${names.length} items, from ${jars.length} jars.`);
console.log(`Left out: ${skipped.condition} for missing mods, ${skipped.ingredient} with unusual ingredients, ${skipped.result} with special results.`);
console.log(`Wrote ${outFile} (${Math.round(size / 1024)} KB).`);
