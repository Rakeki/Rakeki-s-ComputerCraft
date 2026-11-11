-- Factory settings, a table per part. 'install update' never replaces this
-- file. (A config.lua from the smelter, enricher, cooker or essence computer
-- before the factory, with its settings at the top instead, still works.)
return {
  -- Furnaces, blast furnaces, smokers, Mekanism smelters and Create fans.
  smelter = {
    -- Items smelted whenever there are any in storage: Lua patterns matched
    -- against the item's id, like "minecraft:raw_iron". Add more to smelt
    -- other things, e.g. "^minecraft:sand$" to turn all sand into glass
    -- (for a set amount, request it: G on the Smelter page, or 'factory smelt').
    smelt = {
      ":raw_", -- raw iron, gold and copper, and raw ores from mods
      "_ore$", -- ore blocks (silk-touched, or from mods)
      ":ancient_debris$", -- into netherite scrap
      ":crushed_raw_", -- Create's crushed ores
    },
    -- Raw food cooked whenever there's any in storage, in smokers, plain
    -- furnaces and smoking fans (blast furnaces can't). Add mod foods here,
    -- e.g. "^farmersdelight:minced_beef$".
    cook = {
      "^minecraft:beef$", "^minecraft:porkchop$", "^minecraft:chicken$", "^minecraft:mutton$",
      "^minecraft:rabbit$", "^minecraft:cod$", "^minecraft:salmon$",
      "^minecraft:potato$", -- into baked potatoes
      "^minecraft:kelp$", -- into dried kelp
    },
    -- Mekanism dust from the enrichment chambers, smelted into ingots. Ores
    -- an enricher (on any factory computer) takes are left to it.
    dusts = {
      "^mekanism:dust_iron$", "^mekanism:dust_gold$", "^mekanism:dust_copper$", "^mekanism:dust_osmium$",
      "^mekanism:dust_tin$", "^mekanism:dust_lead$", "^mekanism:dust_uranium$",
    },
    -- How many of an item to leave in storage uncooked or unsmelted.
    keep = {
      ["minecraft:potato"] = 64, -- for planting
    },
    -- Never smelted or cooked, even when they match the lists above.
    skip = {
      "_block$", -- blocks of raw iron etc. don't smelt
      -- ores that give more mined with Fortune than smelted: keep them for that
      "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$", "quartz_ore$",
    },
    -- Mekanism smelters: set each one's bottom to Output and turn Auto-eject
    -- on (needs its security set to Public). false: you set the sides yourself.
    setSides = true,
    -- Names on the screen instead of "Smelter 1", by peripheral name,
    -- e.g. ["energizedSmelter_0"] = "Left". A Create fan goes by its feeder's
    -- name, e.g. ["minecraft:barrel_3"] = "Lava fan".
    names = {},
    -- Tell the craft overseer what the furnaces can smelt (stone, glass,
    -- charcoal, ...), so a crafting plan or a builder short of stone has it
    -- smelted here. false: only your own requests.
    offer = true,
    -- More smelting recipes to request, e.g. a mod's (kind = "ore": blast
    -- furnaces take it too; kind = "food": smokers):
    -- { make = "create:zinc_ingot", from = { "create:raw_zinc" }, kind = "ore" }
    recipes = {},
    -- Recipes not to offer or take requests for, by what they make, e.g. "minecraft:sponge".
    hide = {},
  },

  -- Mekanism enrichment chambers, Create crushing wheels and washing fans.
  enricher = {
    -- Metals whose ores, raw ores and raw ore blocks go into the chambers:
    -- 1 ore -> 2 dust, 3 raw -> 4 dust, 1 raw block -> 12 dust. The smelter
    -- turns the dust into ingots.
    metals = { "iron", "gold", "copper", "osmium", "tin", "lead", "uranium" },
    -- Other ores enriched straight into what they drop: 2 coal, diamonds,
    -- emeralds or quartz, 12 redstone or lapis, 6 fluorite. Remove one to keep
    -- those ores for a Fortune pickaxe instead.
    gems = { "coal", "diamond", "emerald", "lapis", "redstone", "quartz", "fluorite" },
    -- Create crushing lines crush the ores above (not fluorite) and these
    -- metals' ores too, which no chamber takes.
    crushMetals = { "zinc", "silver", "nickel", "aluminum", "platinum", "quicksilver" },
    -- Chambers are always loaded first (more dust per ore). true: crushers
    -- take the ores the chambers haven't room for, so more gets through.
    -- false: with chambers set up, crushers only take ores no chamber takes.
    share = true,
    -- What Create washing fans take: crushed ores.
    washes = { "^create:crushed_raw_" },
    -- With a washer, have the storage computer craft every 9 nuggets into an
    -- ingot (needs its crafting turtle, or ME / RS patterns). false: leave them.
    compact = true,
    -- Nuggets -> the ingot they craft into. Add a mod's, e.g.
    -- ["mekanism:nugget_osmium"] = "mekanism:ingot_osmium" (it needs that recipe too).
    nuggets = {
      ["minecraft:iron_nugget"] = "minecraft:iron_ingot",
      ["minecraft:gold_nugget"] = "minecraft:gold_ingot",
      ["create:copper_nugget"] = "minecraft:copper_ingot",
      ["create:zinc_nugget"] = "create:zinc_ingot",
    },
    -- How many of an item to leave in storage, e.g. ["minecraft:iron_ore"] = 16
    -- (or nuggets kept back from crafting, ["minecraft:iron_nugget"] = 18).
    keep = {},
    -- Set each chamber's bottom to Output and turn Auto-eject on (needs its
    -- security set to Public). false: you set the sides yourself.
    setSides = true,
    -- Names on the screen instead of "Chamber 1", by peripheral name,
    -- e.g. ["enrichmentChamber_0"] = "Left". A crusher or washer goes by its
    -- feeder's name, e.g. ["minecraft:barrel_3"] = "Wheels".
    names = {},
  },

  -- Mekanism metallurgic infusers: nothing is infused until it's requested.
  infuser = {
    -- More recipes, e.g. a mod's: make (count of it) from per of one of
    -- from, with amount of an infusion type (carbon, redstone, diamond,
    -- refined_obsidian, tin, gold, bio, fungi).
    -- { title = "Bronze block", make = "mod:bronze_block", from = { "minecraft:copper_block" }, per = 1,
    --   infuse = "tin", amount = 90 },
    recipes = {},
    -- Recipes not to offer (on the screen or to the storage computer), by what they make.
    hide = {},
    -- How many of an item to leave in storage, never infused or used to infuse.
    keep = {},
    -- Tell the storage computer what can be infused here, so its crafting
    -- plans can have steel dust, alloys and circuits made. false: requests only.
    offer = true,
    -- Set each infuser's sides: Top to Input, Bottom to Output, the rest to
    -- Extra, Auto-eject on (needs its security set to Public). false: you do.
    setSides = true,
    -- Names on the screen instead of "Infuser 1", by peripheral name.
    names = {},
  },

  -- Create mechanical saws: logs, planks and stone cut on request. The
  -- recipes come from saw_pack.lua (your modpack's: tools/saw-recipes.mjs)
  -- or the saw_recipes.lua that comes with the factory (vanilla and Create).
  saw = {
    -- More recipes, if your pack's file misses one: make (count of it) from one from, e.g.
    -- { make = "mod:stripped_palm_trunk", from = "mod:palm_trunk", title = "Stripped palm" }.
    recipes = {},
    -- Recipes never made (on the screen or for the craft overseer), by what they make.
    hide = {},
    -- How many of an item to leave in storage, never cut.
    keep = {},
    -- Tell the craft overseer what the saws can make, so its crafting plans
    -- can have stripped logs and the like cut. false: requests only.
    offer = true,
    -- Names on the screen instead of "Saw 1", by feeder name.
    names = {},
  },

  -- Cobblemon cooking pots.
  cooker = {
    -- What a pot can make, by the name 'factory add pot' lists. make: the item
    -- it makes. Then what goes in: either different items, one of each per
    -- cook (at most 5), or one item and times = how many of it per cook. A pot
    -- recipe that needs two of one item and one of another can't be done
    -- with hoppers.
    recipes = {
      exp_candy_xs = { make = "cobblemon:exp_candy_xs", "minecraft:sculk", "minecraft:honeycomb" },
      exp_candy_s = { make = "cobblemon:exp_candy_s", "cobblemon:exp_candy_xs", times = 6 },
      exp_candy_m = { make = "cobblemon:exp_candy_m", "cobblemon:exp_candy_s", times = 3 },
      exp_candy_l = { make = "cobblemon:exp_candy_l", "cobblemon:exp_candy_m", times = 3 },
      exp_candy_xl = { make = "cobblemon:exp_candy_xl", "cobblemon:exp_candy_l", times = 3 },
      -- with Create installed, experience nuggets work instead of sculk:
      -- exp_candy_xs_create = { make = "cobblemon:exp_candy_xs", "create:experience_nugget", "minecraft:honeycomb" },
    },
    -- How many of an item to leave in storage, never put in a pot. Without
    -- this, every candy that has a pot to go into gets compressed.
    keep = {
      -- ["cobblemon:exp_candy_s"] = 64,
      -- ["minecraft:honeycomb"] = 16,
    },
    -- How many of each raw item (what a pot without 'times' takes: sculk,
    -- honeycomb) to keep in storage by having the storage computer craft
    -- more, when it has a recipe for it; on top of 'keep'. A number for all
    -- of them, by item, e.g. { ["minecraft:honeycomb"] = 256 }, or false for none.
    craft = 128,
    -- What the monitor's Candy page lists: item, what to call it, and the exp one gives.
    candy = {
      { "cobblemon:exp_candy_xs", "XS", 100 },
      { "cobblemon:exp_candy_s", "S", 800 },
      { "cobblemon:exp_candy_m", "M", 3000 },
      { "cobblemon:exp_candy_l", "L", 10000 },
      { "cobblemon:exp_candy_xl", "XL", 30000 },
      { "cobblemon:rare_candy", "Rare" }, -- its exp depends on the Pokemon
    },
  },

  -- Hopper Botany Pots growing Mystical Agriculture essence.
  essence = {
    -- Which ingredients make a recipe show up, as a Lua pattern on item ids.
    -- Every Mystical Agriculture essence (inferium, iron, dirt, ...) by default.
    essence = "^mysticalagriculture:.+_essence$",
    -- Peripherals whose name or type has this in them are the pots to empty.
    pots = "botany_pot",
    -- Items to leave in the pots, as Lua patterns, e.g. { "_seeds$" } to keep
    -- the spare seeds a crop drops. Everything else goes to storage.
    leave = {},
    -- Names on the Pots view instead of "Pot 1", by peripheral name,
    -- e.g. ["botanypots:terracotta_hopper_botany_pot_0"] = "Iron 1".
    names = {},
  },
}
