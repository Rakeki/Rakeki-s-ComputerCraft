-- Essence computer settings. 'install update' never replaces this file.
return {
  -- Which ingredients make a recipe show up, as a Lua pattern on item ids.
  -- Every Mystical Agriculture essence (inferium, iron, dirt, ...) by default.
  essence = "^mysticalagriculture:.+_essence$",
  -- Peripherals whose name or type has this in them are the pots to empty.
  pots = "botany_pot",
  -- Items to leave in the pots, as Lua patterns, e.g. { "_seeds$" } to keep
  -- the spare seeds a crop drops. Everything else goes to storage.
  leave = {},
  -- Names on the Pots tab instead of "Pot 1", by peripheral name,
  -- e.g. ["botanypots:terracotta_hopper_botany_pot_0"] = "Iron 1".
  names = {},
}
