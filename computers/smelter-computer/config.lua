-- Smelter settings. 'install update' never replaces this file.
return {
  -- Items smelted whenever there are any in storage: Lua patterns matched
  -- against the item's id, like "minecraft:raw_iron". Add more to smelt
  -- other things, e.g. "^minecraft:sand$" to turn all sand into glass
  -- (for a set amount, use a glass order: G on the screen).
  smelt = {
    ":raw_", -- raw iron, gold and copper, and raw ores from mods
    "_ore$", -- ore blocks (silk-touched, or from mods)
    ":ancient_debris$", -- into netherite scrap
    ":crushed_raw_", -- Create's crushed ores
  },
  -- Raw food cooked whenever there's any in storage, in smokers and plain
  -- furnaces (blast furnaces can't). Same kind of patterns as above; add
  -- mod foods here, e.g. "^farmersdelight:minced_beef$".
  cook = {
    "^minecraft:beef$", "^minecraft:porkchop$", "^minecraft:chicken$", "^minecraft:mutton$",
    "^minecraft:rabbit$", "^minecraft:cod$", "^minecraft:salmon$",
    "^minecraft:potato$", -- into baked potatoes
    "^minecraft:kelp$", -- into dried kelp
  },
  -- Mekanism dust from the enricher (computers/enricher-computer), smelted
  -- into ingots. While the enricher runs, the ores it takes are left to it.
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
  -- Mekanism smelters ('smelter add'): set each one's bottom to Output and
  -- turn Auto-eject on (needs its security set to Public). false: you set
  -- the sides yourself.
  setSides = true,
  -- Names on the screen instead of "Smelter 1", by peripheral name,
  -- e.g. ["energizedSmelter_0"] = "Left".
  names = {},
}
