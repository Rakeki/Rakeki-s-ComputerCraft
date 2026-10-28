-- Enricher settings. 'install update' never replaces this file.
return {
  -- Metals whose ores, raw ores and raw ore blocks go into the chambers:
  -- 1 ore -> 2 dust, 3 raw -> 4 dust, 1 raw block -> 12 dust. The smelter
  -- turns the dust into ingots.
  metals = { "iron", "gold", "copper", "osmium", "tin", "lead", "uranium" },
  -- Other ores enriched straight into what they drop: 2 coal, diamonds,
  -- emeralds or quartz, 12 redstone or lapis, 6 fluorite. Remove one to keep
  -- those ores for a Fortune pickaxe instead.
  gems = { "coal", "diamond", "emerald", "lapis", "redstone", "quartz", "fluorite" },
  -- How many of an item to leave in storage, e.g. ["minecraft:iron_ore"] = 16.
  keep = {},
  -- Set each chamber's bottom to Output and turn Auto-eject on (needs its
  -- security set to Public). false: you set the sides yourself.
  setSides = true,
  -- Names on the screen instead of "Chamber 1", by peripheral name,
  -- e.g. ["enrichmentChamber_0"] = "Left".
  names = {},
}
