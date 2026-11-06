// GPS, the status server and AutoMine (server + two miners).
import fs from "node:fs";
import { newWorld, addComputer, addChest, addMonitor, addGps, play, install } from "../core/base.mjs";

// the status server: an advanced computer with a 4x3 monitor behind it
export function statusServer(w, at = [0, 64, -8]) {
  const [x, y, z] = at;
  const status = addComputer(w, { pos: at, label: "Status", role: "status-server", facing: "south" });
  const cells = [];
  for (let dy = 2; dy >= 0; dy--) for (let dx = -2; dx <= 1; dx++) cells.push([x + dx, y + dy, z - 1]);
  const mon = addMonitor(w, cells, 4, 3);
  status.boot();
  play(w, status, [...install("status-server"), ["reboot"]]);
  return { status, statusMon: mon };
}

export function autoMine(w, at = [-10, 64, 0]) {
  const [x, y, z] = at;
  const server = addComputer(w, { pos: at, label: "AutoMine", role: "mine-server", facing: "south" });
  // a shallow band so a chunk is done in minutes, not hours
  const cfg = fs.readFileSync(new URL("../../computers/mine-server/config.lua", import.meta.url), "utf8");
  server.writeFile("config.lua", cfg.replace("yTop = 60", "yTop = 40").replace("yBottom = -59", "yBottom = 34"));
  server.boot();
  play(w, server, [...install("mine-server"), ["reboot"], ["until", /·HQ/, 120],
    // Queue, then tap two chunks east of HQ
    ["clickText", "Queue"], ["clickText", "·HQ", 5], ["clickText", "·HQ", 7]]);

  // two miners side by side, each with a chest of coal behind it (south)
  const miners = [];
  for (let i = 0; i < 2; i++) {
    const mx = x - 4 - i;
    const chest = addChest(w, [mx, y, z + 11], { coal: 32 });
    const m = addComputer(w, { pos: [mx, y, z + 10], kind: "turtle", facing: "north", role: "mine-turtle", fuel: 0 });
    m.inventory.add("minecraft:coal", 16);
    m.boot();
    m.homeChest = chest;
    play(w, m, [["wait", 20 + i * 3], ...install("mine-turtle"), ["type", "refuel all\n"], ["wait", 2], ["reboot"]]);
    miners.push(m);
  }
  return { server, miners };
}

export function build(w = newWorld()) {
  const gps = addGps(w);
  for (const g of gps) g.boot();
  return { w, gps, ...statusServer(w), ...autoMine(w) };
}

export function check(s) {
  const out = [];
  if (!/fuel/.test(s.server.term.dump())) out.push("AutoMine shows no turtles");
  for (const m of s.miners) {
    const mined = m.homeChest.inv.slots.filter((x) => x && x.name !== "minecraft:coal").length;
    if (!mined) out.push(`${m.label}: nothing mined into its chest`);
  }
  return out;
}
