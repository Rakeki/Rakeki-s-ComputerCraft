// Minecraft block names -> the block kinds the site's voxel renderer
// (site/src/assets/voxel.js) draws. Used by map.mjs and the replay recorder.
export function kind(name) {
  const n = name.replace(/^minecraft:/, "");
  if (name.startsWith("computercraft:")) {
    if (n.includes("modem")) return "modem";
    if (n.includes("disk_drive")) return "computer";
    if (n.includes("turtle")) return "turtle";
    if (n.includes("monitor")) return "monitor";
    if (n.includes("command")) return "command";
    if (n.includes("computer_normal")) return "computer";
    return "advanced";
  }
  if (name.startsWith("enderstorage:")) return "enderchest";
  if (name === "create:creative_crate") return "crate";
  if (name.startsWith("advancedperipherals:")) return "port";
  if (name.startsWith("mekanism:")) return /port|adapter/.test(n) ? "port" : n.includes("digital_miner") ? "dminer" : n.includes("fusion") ? "fusion" : n.includes("fission") ? "fission" : "casing";
  if (/chest$/.test(n)) return "chest";
  if (n === "barrel") return "barrel";
  if (/furnace|smoker/.test(n)) return "furnace";
  if (n === "hopper") return "hopper";
  if (n === "grass_block") return "grass";
  if (n === "farmland") return "farmland";
  if (/^(dirt|coarse_dirt|rooted_dirt)$/.test(n)) return "dirt";
  if (/cobble/.test(n)) return "cobble";
  if (/deepslate|tuff/.test(n) && !/ore/.test(n)) return "deepslate";
  if (/coal_ore/.test(n)) return "coal";
  if (/iron_ore|copper_ore/.test(n)) return "iron";
  if (/gold_ore/.test(n)) return "gold";
  if (/diamond_ore/.test(n)) return "diamond";
  if (/redstone_ore/.test(n)) return "redstone";
  if (/_log$|_wood$/.test(n)) return "log";
  if (/_planks$|_door$|_stairs$|_slab$|_fence/.test(n)) return "planks";
  if (/_leaves$/.test(n)) return "leaves";
  if (/glass/.test(n)) return "glass";
  if (/^(sand|gravel|water|lava|bedrock|torch|stone)$/.test(n)) return n === "stone" ? "stone" : n;
  return "stone";
}

