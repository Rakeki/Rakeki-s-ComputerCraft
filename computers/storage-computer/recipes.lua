-- Built-in crafting recipes for the storage system's crafting turtle. They
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
add("lantern", 1, { "NNN", "NTN", "NNN" }, { N = mc("iron_nugget"), T = mc("torch") })

-- stone
stairs("cobblestone_stairs", "cobblestone")
slab("cobblestone_slab", "cobblestone")
add("cobblestone_wall", 6, { "CCC", "CCC" }, { C = mc("cobblestone") })
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

-- glass, farm and home
add("glass_pane", 16, { "GGG", "GGG" }, { G = mc("glass") })
add("hay_block", 1, { "WWW", "WWW", "WWW" }, { W = mc("wheat") })
for _, colour in ipairs({ "red", "blue", "yellow", "orange", "white", "black", "green", "light_blue", "lime", "pink", "purple", "cyan", "gray", "light_gray", "brown", "magenta" }) do
  if colour ~= "white" then add(colour .. "_wool", 1, { "WD" }, { W = mc("white_wool"), D = mc(colour .. "_dye") }) end
  add(colour .. "_bed", 1, { "WWW", "PPP" }, { W = mc(colour .. "_wool"), P = anyPlanks })
end
add("white_wool", 1, { "SS", "SS" }, { S = mc("string") })

return R
