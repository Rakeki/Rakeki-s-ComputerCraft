-- Cooking pot settings. 'install update' never replaces this file.
return {
  -- What a pot can make, by the name 'cooker add' lists. make: the item it
  -- makes (makes = n if one cook gives more than one). Then what goes in:
  -- either different items, one of each per cook (at most 5), or one item
  -- and times = how many of it per cook. A pot recipe that needs two of one
  -- item and one of another can't be done with hoppers.
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
  -- The monitor that shows how much candy there is: pick it on the setup
  -- screen or with 'cooker monitor' instead. A name here is only taken the
  -- first time (it becomes that setting).
  monitor = nil,
  -- What that monitor lists: item, what to call it, and the exp one gives.
  candy = {
    { "cobblemon:exp_candy_xs", "XS", 100 },
    { "cobblemon:exp_candy_s", "S", 800 },
    { "cobblemon:exp_candy_m", "M", 3000 },
    { "cobblemon:exp_candy_l", "L", 10000 },
    { "cobblemon:exp_candy_xl", "XL", 30000 },
    { "cobblemon:rare_candy", "Rare" }, -- its exp depends on the Pokemon
  },
}
