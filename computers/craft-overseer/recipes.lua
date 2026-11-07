-- Built-in crafting recipes for the craft overseer's crafting turtles. They
-- cover what the village builder's themes use, plus the usual basics. Teach
-- it more in-game with 'crafter learn' on the crafting turtle; those are
-- saved separately, so updating the programs never loses them.
--
-- Each recipe: make (item made), count (how many one craft makes), rows (the
-- crafting grid from the top left, a space for an empty cell) and keys (what
-- each letter stands for). A key can be an item name, a name with * in it
-- ("minecraft:*_planks" for any planks), or a list of names to choose from.
local R = {}

local function add(make, count, rows, keys)
  R[#R + 1] = { make = "minecraft:" .. make, count = count, rows = rows, keys = keys }
end

local function mc(name) return "minecraft:" .. name end

-- the standard shapes, for a block and the things made from it
local function stairs(make, block) add(make, 4, { "B  ", "BB ", "BBB" }, { B = mc(block) }) end
local function slab(make, block) add(make, 6, { "BBB" }, { B = mc(block) }) end
local function square(make, block, count) add(make, count or 4, { "BB", "BB" }, { B = mc(block) }) end
local function wall(make, block) add(make, 6, { "BBB", "BBB" }, { B = mc(block) }) end

local WOODS = { "oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry" }
local woodSlabs = {}
for _, w in ipairs(WOODS) do woodSlabs[#woodSlabs + 1] = mc(w .. "_slab") end

for _, w in ipairs(WOODS) do
  local planks = w .. "_planks"
  add(planks, 4, { "L" }, { L = mc(w .. "_log") })
  slab(w .. "_slab", planks)
  stairs(w .. "_stairs", planks)
  add(w .. "_fence", 3, { "PSP", "PSP" }, { P = mc(planks), S = mc("stick") })
  add(w .. "_door", 3, { "PP", "PP", "PP" }, { P = mc(planks) })
  add(w .. "_trapdoor", 2, { "PPP", "PPP" }, { P = mc(planks) })
end

local anyPlanks = mc("*_planks")
add("stick", 4, { "P", "P" }, { P = anyPlanks })
add("crafting_table", 1, { "PP", "PP" }, { P = anyPlanks })
add("chest", 1, { "PPP", "P P", "PPP" }, { P = anyPlanks })
add("barrel", 1, { "PSP", "P P", "PSP" }, { P = anyPlanks, S = woodSlabs })
add("composter", 1, { "S S", "S S", "SSS" }, { S = woodSlabs })
add("ladder", 3, { "S S", "SSS", "S S" }, { S = mc("stick") })

-- light
add("torch", 4, { "C", "S" }, { C = { mc("coal"), mc("charcoal") }, S = mc("stick") })
add("iron_nugget", 9, { "I" }, { I = mc("iron_ingot") })
-- nuggets back into ingots (the enricher's Create washing fans make them)
add("iron_ingot", 1, { "NNN", "NNN", "NNN" }, { N = mc("iron_nugget") })
add("gold_ingot", 1, { "NNN", "NNN", "NNN" }, { N = mc("gold_nugget") })
add("copper_ingot", 1, { "NNN", "NNN", "NNN" }, { N = "create:copper_nugget" })
R[#R + 1] = { make = "create:zinc_ingot", count = 1, rows = { "NNN", "NNN", "NNN" }, keys = { N = "create:zinc_nugget" } }
add("lantern", 1, { "NNN", "NTN", "NNN" }, { N = mc("iron_nugget"), T = mc("torch") })

-- stone
add("furnace", 1, { "CCC", "C C", "CCC" }, { C = { mc("cobblestone"), mc("cobbled_deepslate"), mc("blackstone") } })
stairs("cobblestone_stairs", "cobblestone")
slab("cobblestone_slab", "cobblestone")
wall("cobblestone_wall", "cobblestone")
add("mossy_cobblestone", 1, { "CM" }, { C = mc("cobblestone"), M = { mc("vine"), mc("moss_block") } })
square("stone_bricks", "stone")
stairs("stone_brick_stairs", "stone_bricks")
slab("stone_brick_slab", "stone_bricks")
square("polished_andesite", "andesite")
square("polished_deepslate", "cobbled_deepslate")
square("deepslate_bricks", "polished_deepslate")
square("deepslate_tiles", "deepslate_bricks")
stairs("deepslate_tile_stairs", "deepslate_tiles")
slab("deepslate_tile_slab", "deepslate_tiles")
square("bricks", "brick", 1)
stairs("brick_stairs", "bricks")
slab("brick_slab", "bricks")

-- sandstone (smooth sandstone itself is smelted, not crafted)
square("sandstone", "sand", 1)
square("cut_sandstone", "sandstone")
stairs("sandstone_stairs", "sandstone")
slab("sandstone_slab", "sandstone")
slab("cut_sandstone_slab", "cut_sandstone")
stairs("smooth_sandstone_stairs", "smooth_sandstone")
slab("smooth_sandstone_slab", "smooth_sandstone")

-- earth and mud
add("coarse_dirt", 4, { "DG", "GD" }, { D = mc("dirt"), G = mc("gravel") })
add("packed_mud", 1, { "MW" }, { M = mc("mud"), W = mc("wheat") })
square("mud_bricks", "packed_mud")
stairs("mud_brick_stairs", "mud_bricks")
slab("mud_brick_slab", "mud_bricks")

-- more stone: the blocks made from others, then each family's stairs, slab
-- and wall ({ name the pieces start with, block, wall = false for none })
add("mossy_stone_bricks", 1, { "BM" }, { B = mc("stone_bricks"), M = { mc("vine"), mc("moss_block") } })
square("polished_granite", "granite")
square("polished_diorite", "diorite")
square("red_sandstone", "red_sand", 1)
square("nether_bricks", "nether_brick", 1)
square("polished_blackstone", "blackstone")
square("polished_blackstone_bricks", "polished_blackstone")
square("end_stone_bricks", "end_stone")
square("polished_tuff", "tuff")
square("tuff_bricks", "polished_tuff")
local STONES = {
  { "stone", "stone", wall = false },
  { "mossy_cobblestone", "mossy_cobblestone" },
  { "mossy_stone_brick", "mossy_stone_bricks" },
  { "granite", "granite" }, { "diorite", "diorite" }, { "andesite", "andesite" },
  { "polished_granite", "polished_granite", wall = false },
  { "polished_diorite", "polished_diorite", wall = false },
  { "polished_andesite", "polished_andesite", wall = false },
  { "cobbled_deepslate", "cobbled_deepslate" },
  { "polished_deepslate", "polished_deepslate" },
  { "deepslate_brick", "deepslate_bricks" },
  { "red_sandstone", "red_sandstone" },
  { "nether_brick", "nether_bricks" },
  { "blackstone", "blackstone" },
  { "polished_blackstone", "polished_blackstone" },
  { "polished_blackstone_brick", "polished_blackstone_bricks" },
  { "end_stone_brick", "end_stone_bricks" },
  { "prismarine", "prismarine" },
  { "tuff", "tuff" }, { "polished_tuff", "polished_tuff" }, { "tuff_brick", "tuff_bricks" },
}
for _, s in ipairs(STONES) do
  stairs(s[1] .. "_stairs", s[2])
  slab(s[1] .. "_slab", s[2])
  if s.wall ~= false then wall(s[1] .. "_wall", s[2]) end
end
-- walls of families whose stairs and slabs are above
wall("stone_brick_wall", "stone_bricks")
wall("deepslate_tile_wall", "deepslate_tiles")
wall("brick_wall", "bricks")
wall("mud_brick_wall", "mud_bricks")
wall("sandstone_wall", "sandstone")

-- glass, farm and home
add("glass_pane", 16, { "GGG", "GGG" }, { G = mc("glass") })
add("hay_block", 1, { "WWW", "WWW", "WWW" }, { W = mc("wheat") })
for _, colour in ipairs({ "red", "blue", "yellow", "orange", "white", "black", "green", "light_blue", "lime", "pink", "purple", "cyan", "gray", "light_gray", "brown", "magenta" }) do
  if colour ~= "white" then add(colour .. "_wool", 1, { "WD" }, { W = mc("white_wool"), D = mc(colour .. "_dye") }) end
  add(colour .. "_bed", 1, { "WWW", "PPP" }, { W = mc(colour .. "_wool"), P = anyPlanks })
end
add("white_wool", 1, { "SS", "SS" }, { S = mc("string") })

return R
