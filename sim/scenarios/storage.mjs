// The storage system: a computer on a cable of chests, a monitor, and the
// turtles and computers that work with it.
import { newWorld, addComputer, addChest, addMonitor, addGps, play, install } from "../core/base.mjs";
import { addFurnace, addEnderChest, addCreativeCrate } from "../core/machines.mjs";

export function storageBase(w, at = [10, 64, 0]) {
  const [x, y, z] = at;
  const net = w.net("storage");
  // the computer faces north; its wired modem is on its back (south), the cable runs east
  const pc = addComputer(w, { pos: [x, y, z], label: "Storage", role: "storage-computer", facing: "north", ender: true });
  pc.attach("back", w.wiredModem(net));
  const chests = {};
  chests.input = addChest(w, [x + 2, y, z + 1], { cobblestone: 20, oak_log: 16 }, { net });
  chests.output = addChest(w, [x + 3, y, z + 1], {}, { net });
  chests.fuel = addChest(w, [x + 4, y, z + 1], { coal: 64 }, { net });
  chests.store = [];
  const stock = [
    { oak_log: 64, oak_planks: 32, stick: 32 }, { iron_ingot: 48, gold_ingot: 12, coal: 64 },
    { cobblestone: 256, dirt: 64 }, { raw_iron: 30, sand: 32, redstone: 20 }, { spruce_log: 32, glass: 16 }, {}, {}, {},
  ];
  stock.forEach((s, i) => chests.store.push(addChest(w, [x + 2 + i, y + 1, z + 1], s, { net })));
  // cable along the row, for the map
  for (let i = 0; i <= 10; i++) net.cells.push([x + i, y, z + 2]);
  // a 3x2 monitor on the cable, above the computer
  const mon = addMonitor(w, [[x - 1, y + 2, z], [x, y + 2, z], [x + 1, y + 2, z], [x - 1, y + 1, z], [x, y + 1, z], [x + 1, y + 1, z]], 3, 2, { net });
  // the remote terminal's ender chest, at home on the cable
  chests.ender = addEnderChest(w, [x + 2, y, z + 3], "white-white-blue", { net });
  return { pc, net, chests, mon };
}

// workers on the storage cable: a crafting turtle, a factory with furnaces
export function storageWorkers(w, st, at = [10, 64, 0]) {
  const [x, y, z] = at;
  const out = {};
  // crafty turtle facing east, its chest in front of it on the cable
  out.crafterChest = addChest(w, [x - 1, y, z + 5], {}, { net: st.net });
  out.crafter = addComputer(w, { pos: [x - 2, y, z + 5], kind: "turtle", facing: "east", role: "crafter-turtle", tool: "minecraft:crafting_table" });
  // factory: a computer on the cable, two furnaces on the cable
  out.factory = addComputer(w, { pos: [x - 2, y, z - 3], label: "Factory", role: "factory", facing: "north" });
  out.factory.attach("back", w.wiredModem(st.net));
  out.furnaces = [addFurnace(w, [x + 4, y, z - 2], { net: st.net }), addFurnace(w, [x + 5, y, z - 2], { net: st.net, type: "minecraft:blast_furnace" })];
  for (let i = -2; i <= 6; i++) st.net.cells.push([x + i, y, z - 1]);
  return out;
}

// the whole storage system, set up the way its README says
export function storage(w) {
  const st = storageBase(w);
  st.pc.monitor = st.mon;
  const wk = storageWorkers(w, st);
  st.pc.boot();
  play(w, st.pc, [...install("storage-computer"), ["type", "storage\n"], ["until", /Storage setup/, 20],
    // the setup screen, on the monitor: input, output and fuel chests, then Save
    ["tapText", "Input chest"], ["until", /Pick: Input/, 10], ["tapText", "minecraft:chest_0 "], ["wait", 1],
    ["tapText", "Output chest"], ["until", /Pick: Output/, 10], ["tapText", "minecraft:chest_1 "], ["wait", 1],
    ["tapText", "Fuel chest"], ["until", /Pick: Fuel/, 10], ["tapText", "minecraft:chest_2 "], ["wait", 1],
    ["tapText", "Save"], ["wait", 10]]);
  wk.crafter.boot();
  play(w, wk.crafter, [["wait", 60], ...install("crafter-turtle"), ["reboot"]]);
  wk.factory.boot();
  play(w, wk.factory, [["wait", 70], ...install("factory"), ["reboot"]]);

  // far away: the remote terminal, its ender chest twin on its right
  const remote = addComputer(w, { pos: [600, 64, 600], label: "Remote", role: "remote-terminal", facing: "north", ender: true });
  addEnderChest(w, [601, 64, 600], "white-white-blue");
  remote.boot();
  play(w, remote, [["wait", 80], ...install("remote-terminal"), ["reboot"], ["until", /Iron Ingot/, 120],
    // search, then Enter: a stack of the top match into the ender chest
    ["type", "iron ingot"], ["wait", 1], ["key", 257], ["wait", 30]]);

  // the craft terminal: on the cable (wired modem on its back, no wireless), a chest on its right on the cable
  const crafts = addComputer(w, { pos: [11, 64, -3], label: "Crafts", role: "craft-terminal", facing: "north", modem: false });
  crafts.attach("back", w.wiredModem(st.net));
  const craftsChest = addChest(w, [12, 64, -3], {}, { net: st.net });
  crafts.boot();
  play(w, crafts, [["wait", 90], ...install("craft-terminal"), ["reboot"], ["until", /make \d+/, 180],
    // search, Enter, type how many, Enter: two chests crafted into the chest next to it
    ["type", "chest"], ["wait", 2], ["key", 257], ["until", /How many Chest/, 10], ["type", "2"], ["key", 257],
    ["until", /Crafting 2 Chest/, 30], ["until", /2 Chest: it's in the chest/, 240]]);
  return { ...st, ...wk, remote, crafts, craftsChest };
}

export function build(w = newWorld()) {
  for (const g of addGps(w)) g.boot();
  return { w, ...storage(w) };
}

export function check(s) {
  const out = [];
  // the factory smelted the 30 raw iron, and the ingots got home (others may
  // since have used some: a village orders lanterns, which take iron)
  const smelted = s.furnaces.reduce((a, f) => a + f.furnace.made, 0);
  if (smelted < 30) out.push(`the factory smelted ${smelted} of 30 raw iron`);
  const ingots = s.chests.store.reduce((a, c) => a + c.inv.count("minecraft:iron_ingot"), 0) + s.chests.ender.inv.count("minecraft:iron_ingot");
  if (ingots < 30) out.push(`only ${ingots} iron ingots in storage`);
  // what's pulled waits 10 minutes in the ender chest, then goes home: check the pull itself
  if (!/Sent \d+ Iron Ingot/.test(s.remote.term.dump())) out.push("the remote terminal never got its iron ingots");
  if (!/uses my chest|Crafted \d+/.test(s.crafter.term.dump())) out.push("the crafting turtle never claimed its chest or crafted");
  // the craft terminal's order: 2 chests crafted and sent to its chest (in a long run
  // they go back to storage after 10 minutes, so the terminal saying they arrived counts)
  const made = s.craftsChest.inv.count("minecraft:chest");
  if (made < 2 && !/2 Chest: it's in the chest/.test(s.crafts.term.dump())) out.push(`the craft terminal's chest has ${made} of 2 chests: ${s.crafts.term.dump().split("\n").slice(-3).join(" / ")}`);
  if (!process.env.SHOW) return out;
  const show = (label, inv) => console.log(`${label}: ${inv.slots.filter(Boolean).map((i) => `${i.count} ${i.name.replace("minecraft:", "")}`).join(", ") || "empty"}`);
  console.log();
  for (const f of s.furnaces) show(`${f.furnace.type} (made ${f.furnace.made})`, f.inv);
  show("input", s.chests.input.inv); show("output", s.chests.output.inv); show("fuel", s.chests.fuel.inv);
  show("ender", s.chests.ender.inv); show("crafter chest", s.crafterChest.inv); show("crafter turtle", s.crafter.inventory);
  s.chests.store.forEach((c, i) => show(`store ${i}`, c.inv));
  return out;
}
