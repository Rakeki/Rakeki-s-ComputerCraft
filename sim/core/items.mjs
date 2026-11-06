// What the simulator knows about items and blocks: stack sizes, names, tags,
// fuel, smelting, what a block drops and whether an item places a block.

const id = (n) => (n.includes(":") ? n : "minecraft:" + n);

const STACK_1 = /(_pickaxe|_axe|_shovel|_hoe|_sword|_helmet|_chestplate|_leggings|_boots|bucket$|^minecraft:bow$|shears|flint_and_steel|_boat|saddle|minecart|elytra|totem|potion$|turtle_|pocket_computer|disk$)/;
const STACK_16 = /(ender_pearl|snowball|egg$|_sign$|honey_bottle|^minecraft:bucket$|banner$|armor_stand)/;

export function maxCount(name) {
  name = id(name);
  if (name === "minecraft:bucket") return 16;
  if (/lava_bucket|water_bucket|milk_bucket|powder_snow_bucket/.test(name)) return 1;
  if (STACK_16.test(name)) return 16;
  if (STACK_1.test(name)) return 1;
  return 64;
}

export function displayName(name) {
  const base = id(name).split(":")[1];
  return base.split("_").map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
}

const TAG_RULES = [
  [/_log$|_wood$|_stem$/, ["minecraft:logs", "minecraft:logs_that_burn"]],
  [/_planks$/, ["minecraft:planks"]],
  [/_sapling$/, ["minecraft:saplings"]],
  [/_leaves$/, ["minecraft:leaves"]],
  [/_ore$/, ["c:ores"]],
  [/_ingot$/, ["c:ingots"]],
  [/^minecraft:raw_/, ["c:raw_materials"]],
  [/chest$|barrel$/, ["c:chests"]],
  [/^minecraft:(cobblestone|cobbled_deepslate|blackstone)$/, ["minecraft:stone_tool_materials", "minecraft:stone_crafting_materials", "c:cobblestones"]],
  [/^minecraft:coal$|^minecraft:charcoal$/, ["minecraft:coals"]],
  [/^minecraft:(stone|deepslate|granite|diorite|andesite|tuff)$/, ["minecraft:base_stone_overworld"]],
];
export function tags(name) {
  name = id(name);
  const out = {};
  for (const [re, ts] of TAG_RULES) if (re.test(name)) for (const t of ts) out[t] = true;
  const base = name.split(":")[1];
  const m = base.match(/^(iron|gold|copper|diamond|emerald|coal|redstone|lapis|netherite|tin|osmium|lead|uranium|zinc|silver)_(ingot|ore|nugget|block|dust)$/);
  if (m) out[`c:${m[2]}s/${m[1]}`] = true;
  return out;
}

// burn time in items smelted (a furnace takes 10 s an item)
export const FUEL = {
  "minecraft:coal": 8, "minecraft:charcoal": 8, "minecraft:coal_block": 80, "minecraft:lava_bucket": 100,
  "minecraft:blaze_rod": 12, "minecraft:stick": 0.5, "minecraft:dried_kelp_block": 20,
};
export function fuelItems(name) {
  name = id(name);
  if (FUEL[name] !== undefined) return FUEL[name];
  if (/_planks$|_log$|_wood$|_stem$/.test(name)) return 1.5;
  if (/_sapling$/.test(name)) return 0.5;
  return 0;
}
// CC: a turtle gets burn ticks * 5 / 100 fuel, and a furnace takes 200 ticks
// an item, so coal (8 items) is 80 fuel
export const turtleFuel = (name) => Math.floor(fuelItems(name) * 10);

export const SMELT = {
  "minecraft:raw_iron": "minecraft:iron_ingot", "minecraft:raw_gold": "minecraft:gold_ingot", "minecraft:raw_copper": "minecraft:copper_ingot",
  "minecraft:iron_ore": "minecraft:iron_ingot", "minecraft:deepslate_iron_ore": "minecraft:iron_ingot", "minecraft:gold_ore": "minecraft:gold_ingot",
  "minecraft:copper_ore": "minecraft:copper_ingot", "minecraft:cobblestone": "minecraft:stone", "minecraft:sand": "minecraft:glass",
  "minecraft:oak_log": "minecraft:charcoal", "minecraft:birch_log": "minecraft:charcoal", "minecraft:spruce_log": "minecraft:charcoal",
  "minecraft:beef": "minecraft:cooked_beef", "minecraft:porkchop": "minecraft:cooked_porkchop", "minecraft:chicken": "minecraft:cooked_chicken",
  "minecraft:potato": "minecraft:baked_potato", "minecraft:clay_ball": "minecraft:brick", "minecraft:cobbled_deepslate": "minecraft:deepslate",
  "minecraft:stone": "minecraft:smooth_stone", "minecraft:netherrack": "minecraft:nether_brick", "minecraft:kelp": "minecraft:dried_kelp",
  "minecraft:iron_dust": "minecraft:iron_ingot", "mekanism:dust_iron": "minecraft:iron_ingot", "mekanism:dust_gold": "minecraft:gold_ingot",
};

// what breaking a block gives
const DROPS = {
  "minecraft:stone": "minecraft:cobblestone", "minecraft:deepslate": "minecraft:cobbled_deepslate",
  "minecraft:grass_block": "minecraft:dirt", "minecraft:coal_ore": "minecraft:coal", "minecraft:deepslate_coal_ore": "minecraft:coal",
  "minecraft:iron_ore": "minecraft:raw_iron", "minecraft:deepslate_iron_ore": "minecraft:raw_iron",
  "minecraft:gold_ore": "minecraft:raw_gold", "minecraft:deepslate_gold_ore": "minecraft:raw_gold",
  "minecraft:copper_ore": "minecraft:raw_copper", "minecraft:diamond_ore": "minecraft:diamond", "minecraft:deepslate_diamond_ore": "minecraft:diamond",
  "minecraft:redstone_ore": ["minecraft:redstone", 4], "minecraft:deepslate_redstone_ore": ["minecraft:redstone", 4],
  "minecraft:lapis_ore": ["minecraft:lapis_lazuli", 5], "minecraft:emerald_ore": "minecraft:emerald",
  "minecraft:nether_quartz_ore": "minecraft:quartz", "minecraft:nether_gold_ore": ["minecraft:gold_nugget", 3],
  "minecraft:farmland": "minecraft:dirt", "minecraft:glass": null, "minecraft:short_grass": null, "minecraft:tall_grass": null,
  "minecraft:wheat": null, "minecraft:carrots": null, "minecraft:potatoes": null, "minecraft:bedrock": null,
};
export function drops(block) {
  const name = block.name;
  if (name === "minecraft:wheat") return (block.state?.age ?? 0) >= 7 ? [["minecraft:wheat", 1], ["minecraft:wheat_seeds", 2]] : [["minecraft:wheat_seeds", 1]];
  if (name === "minecraft:carrots") return [["minecraft:carrot", (block.state?.age ?? 0) >= 7 ? 3 : 1]];
  if (name === "minecraft:potatoes") return [["minecraft:potato", (block.state?.age ?? 0) >= 7 ? 3 : 1]];
  if (/_leaves$/.test(name)) return random() < 0.1 ? [[name.replace("_leaves", "_sapling"), 1]] : [];
  if (name in DROPS) { const d = DROPS[name]; if (!d) return []; return Array.isArray(d) ? [d] : [[d, 1]]; }
  if (/^computercraft:(computer|turtle)/.test(name)) return [];
  return [[name, 1]];
}

export const UNBREAKABLE = new Set(["minecraft:bedrock", "minecraft:barrier", "minecraft:end_portal_frame"]);
export const FLUIDS = new Set(["minecraft:water", "minecraft:lava"]);
export const FALLS = new Set(["minecraft:sand", "minecraft:gravel", "minecraft:red_sand"]);
// blocks a turtle passes through as if they were air (replaceable plants)
export const REPLACEABLE = new Set(["minecraft:short_grass", "minecraft:tall_grass", "minecraft:fern", "minecraft:snow", "minecraft:dead_bush", "minecraft:vine"]);

// items that aren't blocks (turtle.place does nothing with them unless a special case)
const NOT_BLOCK = /(_ingot|_nugget|^minecraft:raw_(iron|gold|copper)$|^minecraft:(coal|charcoal|diamond|emerald|lapis_lazuli|quartz|stick|flint|string|feather|leather|bone|bone_meal|gunpowder|wheat|wheat_seeds|carrot|potato|beef|porkchop|chicken|cooked_\w+|baked_potato|apple|bread|paper|book|clay_ball|brick|ender_pearl|blaze_rod|glowstone_dust|redstone|slime_ball|sugar|egg|snowball)$|_pickaxe|_axe|_shovel|_hoe|_sword|bucket$|_dust$|^mekanism:(dust|ingot|nugget|clump|shard|crystal|dirty)|essence|_seeds$|^minecraft:arrow$|^computercraft:(disk|treasure_disk|pocket_computer_w+)$)/;
export function placesBlock(name) {
  name = id(name);
  if (/_seeds$|^minecraft:(carrot|potato)$/.test(name)) return "crop";
  return !NOT_BLOCK.test(name);
}
// the block an item places (seeds become crops)
export function blockFor(name) {
  name = id(name);
  return ({ "minecraft:wheat_seeds": "minecraft:wheat", "minecraft:carrot": "minecraft:carrots", "minecraft:potato": "minecraft:potatoes", "minecraft:redstone": "minecraft:redstone_wire" })[name] || name;
}

// Item details as CC's getItemDetail gives them.
export function detail(item, full = true) {
  const d = { name: item.name, count: item.count };
  if (item.nbt) d.nbt = item.nbt;
  if (!full) return d;
  d.displayName = item.displayName || displayName(item.name);
  d.maxCount = maxCount(item.name);
  d.tags = tags(item.name);
  if (item.damage !== undefined) { d.damage = item.damage; d.maxDamage = item.maxDamage; }
  if (item.extra) Object.assign(d, item.extra);
  return d;
}

export const same = (a, b) => a && b && a.name === b.name && (a.nbt || null) === (b.nbt || null);

// The simulator's dice: seeded, so a run goes the same way every time.
let seed = 12345;
export function random() {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
