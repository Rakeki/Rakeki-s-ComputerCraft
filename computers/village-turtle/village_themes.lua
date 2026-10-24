-- Village themes: the look of the buildings (style) and the blocks used for
-- each part (palette). Change any block here to suit what you have; a role
-- set to false is left out (e.g. desert houses have open doorways).
--
-- Palette roles:
--   foundation  floor edge, house footing, chimney     floor     floors inside
--   wallBase    bottom row of the walls                 wall      walls
--   beam        top row of the walls                    pillar    corners and posts
--   window      windows                                 door      doors (2 high)
--   roofStair   roof slopes                             roofBlock roof corners/eaves
--   roofSlab    roof ridge                              masonry   towers, the well
--   stair       tower staircase                         fence     fences and rails
--   light       lanterns                                accent, accent2  stall canopy
--   soil        farm field                              water     water (a bucket each)
--   bed, table, storage, composter, hay                 furniture
--   path        roads and door paths                    edge      road curbs
--   avenue      main roads                              roadStair steps on sloping roads
--   deck        docks and bridges
-- Road blocks shouldn't be ones that fall (sand, gravel).
local T = {}

T.order = { "medieval", "desert", "nordic", "japanese" }

T.medieval = {
  name = "Medieval",
  blurb = "timber frame, cobble, spruce roofs",
  style = { roof = "gable", rise = 1, overhang = 1, posts = true, chimney = true, tower = "crenel" },
  buildings = { "cottage", "townhouse", "tavern", "tower", "farm", "stall", "dock" },
  names = { cottage = "cottage", townhouse = "town house", tavern = "tavern", tower = "watchtower",
    farm = "farm", stall = "market stall", dock = "dock", well = "well" },
  palette = {
    foundation = "minecraft:cobblestone", floor = "minecraft:spruce_planks",
    wallBase = "minecraft:cobblestone", wall = "minecraft:oak_planks", beam = "minecraft:stripped_oak_log",
    pillar = "minecraft:oak_log", window = "minecraft:glass_pane", door = "minecraft:oak_door",
    roofStair = "minecraft:spruce_stairs", roofBlock = "minecraft:spruce_planks", roofSlab = "minecraft:spruce_slab",
    masonry = "minecraft:stone_bricks", stair = "minecraft:stone_brick_stairs",
    fence = "minecraft:oak_fence", light = "minecraft:lantern",
    accent = "minecraft:red_wool", accent2 = "minecraft:white_wool",
    soil = "minecraft:dirt", water = "minecraft:water_bucket",
    bed = "minecraft:red_bed", table = "minecraft:crafting_table", storage = "minecraft:barrel",
    composter = "minecraft:composter", hay = "minecraft:hay_block",
    path = "minecraft:coarse_dirt", edge = "minecraft:cobblestone", avenue = "minecraft:stone_bricks",
    roadStair = "minecraft:cobblestone_stairs", deck = "minecraft:oak_planks",
  },
}

T.desert = {
  name = "Desert",
  blurb = "sandstone, flat roofs, open doorways",
  style = { roof = "flat", overhang = 0, vigas = true, tower = "crenel", towerWall = "masonry" },
  buildings = { "cottage", "townhouse", "tavern", "tower", "farm", "stall", "dock" },
  names = { cottage = "adobe house", townhouse = "courtyard house", tavern = "caravanserai", tower = "lookout",
    farm = "oasis farm", stall = "bazaar stall", dock = "jetty", well = "well" },
  palette = {
    foundation = "minecraft:sandstone", floor = "minecraft:smooth_sandstone",
    wallBase = "minecraft:sandstone", wall = "minecraft:smooth_sandstone", beam = "minecraft:cut_sandstone",
    pillar = "minecraft:cut_sandstone", window = "minecraft:glass_pane", door = false,
    roofStair = "minecraft:sandstone_stairs", roofBlock = "minecraft:smooth_sandstone", roofSlab = "minecraft:smooth_sandstone_slab",
    masonry = "minecraft:cut_sandstone", stair = "minecraft:sandstone_stairs",
    fence = "minecraft:jungle_fence", light = "minecraft:lantern",
    accent = "minecraft:orange_wool", accent2 = "minecraft:yellow_wool",
    soil = "minecraft:dirt", water = "minecraft:water_bucket",
    bed = "minecraft:yellow_bed", table = "minecraft:crafting_table", storage = "minecraft:barrel",
    composter = "minecraft:composter", hay = "minecraft:hay_block",
    path = "minecraft:sandstone", edge = "minecraft:cut_sandstone", avenue = "minecraft:smooth_sandstone",
    roadStair = "minecraft:sandstone_stairs", deck = "minecraft:jungle_planks",
  },
}

T.nordic = {
  name = "Nordic",
  blurb = "spruce longhouses, steep dark roofs",
  style = { roof = "gable", rise = 2, overhang = 1, posts = true, chimney = true, tower = "crenel" },
  buildings = { "cottage", "townhouse", "tavern", "tower", "farm", "stall", "dock" },
  names = { cottage = "hut", townhouse = "longhouse", tavern = "mead hall", tower = "watchtower",
    farm = "farm", stall = "trading post", dock = "boathouse pier", well = "well" },
  palette = {
    foundation = "minecraft:cobblestone", floor = "minecraft:spruce_planks",
    wallBase = "minecraft:cobblestone", wall = "minecraft:spruce_planks", beam = "minecraft:stripped_spruce_log",
    pillar = "minecraft:spruce_log", window = "minecraft:glass_pane", door = "minecraft:spruce_door",
    roofStair = "minecraft:dark_oak_stairs", roofBlock = "minecraft:dark_oak_planks", roofSlab = "minecraft:dark_oak_slab",
    masonry = "minecraft:stone_bricks", stair = "minecraft:spruce_stairs",
    fence = "minecraft:spruce_fence", light = "minecraft:lantern",
    accent = "minecraft:blue_wool", accent2 = "minecraft:white_wool",
    soil = "minecraft:dirt", water = "minecraft:water_bucket",
    bed = "minecraft:blue_bed", table = "minecraft:crafting_table", storage = "minecraft:barrel",
    composter = "minecraft:composter", hay = "minecraft:hay_block",
    path = "minecraft:cobblestone", edge = "minecraft:mossy_cobblestone", avenue = "minecraft:stone_bricks",
    roadStair = "minecraft:cobblestone_stairs", deck = "minecraft:spruce_planks",
  },
}

T.japanese = {
  name = "Japanese",
  blurb = "dark wood, pale walls, tiled hip roofs",
  style = { roof = "hip", overhang = 1, upturn = true, posts = true, tower = "pagoda", towerWall = "wall", towerPillar = true },
  buildings = { "cottage", "townhouse", "tavern", "tower", "farm", "stall", "dock" },
  names = { cottage = "machiya", townhouse = "minka", tavern = "tea house", tower = "pagoda",
    farm = "field", stall = "market stall", dock = "pier", well = "well" },
  palette = {
    foundation = "minecraft:stone_bricks", floor = "minecraft:birch_planks",
    wallBase = "minecraft:dark_oak_planks", wall = "minecraft:birch_planks", beam = "minecraft:dark_oak_planks",
    pillar = "minecraft:dark_oak_log", window = "minecraft:glass_pane", door = "minecraft:birch_door",
    roofStair = "minecraft:deepslate_tile_stairs", roofBlock = "minecraft:deepslate_tiles", roofSlab = "minecraft:deepslate_tile_slab",
    masonry = "minecraft:stone_bricks", stair = "minecraft:dark_oak_stairs",
    fence = "minecraft:dark_oak_fence", light = "minecraft:lantern",
    accent = "minecraft:red_wool", accent2 = "minecraft:white_wool",
    soil = "minecraft:dirt", water = "minecraft:water_bucket",
    bed = "minecraft:white_bed", table = "minecraft:crafting_table", storage = "minecraft:barrel",
    composter = "minecraft:composter", hay = "minecraft:hay_block",
    path = "minecraft:packed_mud", edge = "minecraft:stone_bricks", avenue = "minecraft:polished_andesite",
    roadStair = "minecraft:stone_brick_stairs", deck = "minecraft:dark_oak_planks",
  },
}

return T
