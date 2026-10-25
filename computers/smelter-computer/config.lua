-- Smelter settings. 'install update' never replaces this file.
return {
  -- Items smelted whenever there are any in storage: Lua patterns matched
  -- against the item's id, like "minecraft:raw_iron". Add more to smelt
  -- other things, e.g. "^minecraft:sand$" for glass or
  -- "^minecraft:cobblestone$" for stone.
  smelt = {
    ":raw_", -- raw iron, gold and copper, and raw ores from mods
    "_ore$", -- ore blocks (silk-touched, or from mods)
    ":ancient_debris$", -- into netherite scrap
    ":crushed_raw_", -- Create's crushed ores
  },
  -- Never smelted, even when they match the list above.
  skip = {
    "_block$", -- blocks of raw iron etc. don't smelt
    -- ores that give more mined with Fortune than smelted: keep them for that
    "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$", "quartz_ore$",
  },
}
