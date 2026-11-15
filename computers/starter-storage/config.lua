-- Settings for the stash. 'install update' never overwrites this file.
return {
  -- With this many of an item (or more), it goes into drawers and storage with
  -- stack upgrades, and is moved out of plain chests when there's room.
  bulk = 256,

  -- Burn logs into charcoal whenever there's fuel for fewer than this many
  -- coal's worth (8 smelts each) in storage. 0 = only on request.
  charcoal = 32,

  -- Cook raw meat and fish in the smokers and furnaces by themselves.
  cook = true,

  -- Kept in storage and never smelted by themselves: item id -> how many.
  keep = { ["minecraft:potato"] = 16 },

  -- More things to smelt on request (the Furnaces page): title and the items
  -- it's smelted from, first one there is. kind = "ore" may use blast
  -- furnaces, "food" smokers.
  recipes = {
    -- { title = "Zinc ingot", from = { "create:raw_zinc" }, kind = "ore" },
  },

  -- Keep each kind of item in its own chests (ores, wood, stone, food...,
  -- and each mod's items). false = put things anywhere.
  separate = true,

  -- Your own kinds of item, in place of the built-in ones: name and Lua
  -- patterns on the item id; the first match wins, anything else goes by its
  -- mod ("create") or "misc". Leave out to use the built-in list.
  -- categories = {
  --   { "ores", { ":raw_", "_ore$", "_ingot$", "_nugget$" } },
  --   { "wood", { "_log$", "_planks$", "_sapling$" } },
  -- },

  -- Smelted by themselves as ores (Lua patterns on the item id), unless skip
  -- matches. Leave out to use the built-in lists.
  -- ores = { ":raw_", "_ore$", ":ancient_debris$", ":crushed_raw_" },
  -- skip = { "_block$", "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$", "quartz_ore$" },
}
