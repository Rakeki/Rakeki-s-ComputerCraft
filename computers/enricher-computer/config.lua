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
  -- Create crushing lines ('enricher add crusher') crush the ores above
  -- (not fluorite) and these metals' ores too, which no chamber takes.
  crushMetals = { "zinc", "silver", "nickel", "aluminum", "platinum", "quicksilver" },
  -- Chambers are always loaded first (more dust per ore). true: crushers
  -- take the ores the chambers haven't room for, so more gets through.
  -- false: with chambers set up, crushers only take ores no chamber takes.
  share = true,
  -- What Create washing fans ('enricher add washer') take: crushed ores.
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
  -- e.g. ["enrichmentChamber_0"] = "Left". A crusher goes by its feeder's
  -- name, e.g. ["minecraft:barrel_3"] = "Wheels".
  names = {},
}
