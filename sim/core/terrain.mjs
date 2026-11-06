// Flat overworld terrain for the simulated world: grass on dirt on stone on
// deepslate on bedrock, with ores, gravel pockets and the odd lava or water
// pocket, the same every run (hashed from the position).
const SURFACE = 63; // top of the ground (grass); the base stands on y = 64

function hash(x, y, z, salt = 0) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647 + salt * 1274126177) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}
// a blob: true in roughly round pockets about `size` across
function pocket(x, y, z, size, salt, chance) {
  const cx = Math.floor(x / size), cy = Math.floor(y / size), cz = Math.floor(z / size);
  if (hash(cx, cy, cz, salt) > chance) return false;
  const ox = (cx + 0.5) * size, oy = (cy + 0.5) * size, oz = (cz + 0.5) * size;
  return Math.hypot(x - ox, y - oy, z - oz) < size * 0.35;
}

export function overworld(x, y, z) {
  if (y > SURFACE) return null;
  if (y === SURFACE) return "minecraft:grass_block";
  if (y >= SURFACE - 3) return "minecraft:dirt";
  if (y <= -64) return "minecraft:bedrock";
  if (y <= -60 && hash(x, y, z, 1) < (-59 - y) / 5) return "minecraft:bedrock";
  const deep = y < 0;
  if (y < 40 && pocket(x, y, z, 9, 7, 0.04)) return y < -40 ? "minecraft:lava" : "minecraft:water";
  if (pocket(x, y, z, 6, 3, 0.08)) return deep ? "minecraft:tuff" : "minecraft:gravel";
  const r = hash(x, y, z, 2);
  if (r < 0.012) return deep ? "minecraft:deepslate_coal_ore" : "minecraft:coal_ore";
  if (r < 0.02) return deep ? "minecraft:deepslate_iron_ore" : "minecraft:iron_ore";
  if (r < 0.023) return deep ? "minecraft:deepslate_gold_ore" : "minecraft:copper_ore";
  if (deep && r < 0.026) return "minecraft:deepslate_redstone_ore";
  if (deep && r < 0.0275) return "minecraft:deepslate_diamond_ore";
  if (!deep && r < 0.03 && pocket(x, y, z, 5, 9, 0.5)) return "minecraft:andesite";
  return deep ? "minecraft:deepslate" : "minecraft:stone";
}
export { SURFACE };

// The Nether: netherrack from Y 0 to 127 with bedrock at both ends, a lava
// sea below Y 32, some lava pockets, gravel and soul sand, quartz and gold.
export function nether(x, y, z) {
  if (y <= 0 || y >= 127) return "minecraft:bedrock";
  if (y < 32) return "minecraft:lava";
  if (pocket(x, y, z, 7, 11, 0.05)) return "minecraft:lava";
  if (pocket(x, y, z, 6, 12, 0.06)) return y < 50 ? "minecraft:soul_sand" : "minecraft:gravel";
  const r = hash(x, y, z, 13);
  if (r < 0.015) return "minecraft:nether_quartz_ore";
  if (r < 0.02) return "minecraft:nether_gold_ore";
  return "minecraft:netherrack";
}
// x past NETHER_X is "the Nether" (the simulator has one world)
export const NETHER_X = 2500;
export const terrain = (x, y, z) => (x > NETHER_X ? nether(x, y, z) : overworld(x, y, z));
