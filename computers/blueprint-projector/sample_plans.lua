-- Built-in plans for the blueprint projector, and examples of the plan format.
-- Your own plans go in /plans/<name>.lua and look just like one of these:
--
--   return {
--     name = "My house",                       -- shown on the monitor
--     legend = {                               -- one character per block
--       C = "minecraft:cobblestone",
--       G = { "minecraft:glass", 0x99ddff },   -- block + projection colour
--     },
--     layers = {                               -- bottom layer first
--       { "CCC",                               -- first row: the front (north
--         "CGC",                               -- at turn 0), across = east
--         "CCC" },
--       ...
--     },
--   }
--
-- "." and " " are air. Instead of layers, a plan can list its blocks:
-- blocks = { { x, y, z, "minecraft:stone" }, ... }, which is handy when a
-- loop makes the plan (see the watchtower).
local plans = {}

---------------------------------------------------------------- cottage

plans[#plans + 1] = {
  id = "cottage",
  name = "Cottage",
  legend = {
    C = "minecraft:cobblestone",
    P = "minecraft:oak_planks",
    L = "minecraft:oak_log",
    G = "minecraft:glass_pane",
    D = "minecraft:oak_door",
    S = "minecraft:spruce_planks",
  },
  layers = {
    { "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC" },
    { "LPPDPPL",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "LPPPPPL" },
    { "LPGDGPL",
      "P.....P",
      "G.....G",
      "P.....P",
      "G.....G",
      "P.....P",
      "LPPGPPL" },
    { "LPPPPPL",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "LPPPPPL" },
    { "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS" },
    { ".......",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      "......." },
    { ".......",
      ".......",
      "..SSS..",
      "..SSS..",
      "..SSS..",
      ".......",
      "......." },
    { ".......",
      ".......",
      ".......",
      "...S...",
      ".......",
      ".......",
      "......." },
  },
}

---------------------------------------------------------------- watchtower

-- 5x5 stone tower with a door, windows, and a wider lookout on top.
local tower = { id = "watchtower", name = "Watchtower", blocks = {} }
local function add(x, y, z, block) tower.blocks[#tower.blocks + 1] = { x, y, z, block } end

for y = 0, 7 do
  for z = 0, 4 do
    for x = 0, 4 do
      local edge = x == 0 or x == 4 or z == 0 or z == 4
      local middle = x == 2 or z == 2
      if y == 0 then
        add(x, y, z, "minecraft:stone_bricks")
      elseif edge then
        if z == 0 and x == 2 and y <= 2 then
          add(x, y, z, "minecraft:spruce_door")
        elseif middle and (y == 4 or y == 5) then
          add(x, y, z, "minecraft:glass_pane")
        else
          add(x, y, z, "minecraft:stone_bricks")
        end
      end
    end
  end
end
-- lookout floor hangs one block out on every side, with gaps in the parapet
for z = -1, 5 do
  for x = -1, 5 do
    local edge = x == -1 or x == 5 or z == -1 or z == 5
    add(x, 8, z, edge and "minecraft:stone_bricks" or "minecraft:spruce_planks")
    if edge then
      add(x, 9, z, "minecraft:stone_brick_wall")
      if (x + z) % 2 == 0 then add(x, 10, z, "minecraft:stone_brick_wall") end
    end
  end
end
plans[#plans + 1] = tower

return plans
