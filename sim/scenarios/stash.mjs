// The starter storage (stash): one computer on a cable of chests and a
// furnace, set up the way its README says, then searched and cleared with
// Delete many times while it works (Delete was being lost now and then).
import { newWorld, addComputer, addChest, play, install } from "../core/base.mjs";
import { addFurnace } from "../core/machines.mjs";

export function stash(w, at = [40, 64, 40]) {
  const [x, y, z] = at;
  const net = w.net("stash");
  const pc = addComputer(w, { pos: [x, y, z], label: "Stash", role: "starter-storage", facing: "north", modem: false });
  pc.attach("back", w.wiredModem(net));
  // on the cable, none touching the computer: input, output, and storage
  const input = addChest(w, [x + 2, y, z + 2], { cobblestone: 64, oak_log: 40, raw_iron: 20, bone: 5, coal: 16 }, { net, type: "minecraft:barrel" });
  const output = addChest(w, [x + 3, y, z + 2], {}, { net, type: "minecraft:barrel" });
  const store = [
    addChest(w, [x + 4, y, z + 2], { dirt: 64, gravel: 30, iron_ingot: 10 }, { net }),
    addChest(w, [x + 5, y, z + 2], { cobblestone: 100, spruce_planks: 12 }, { net }),
    addChest(w, [x + 6, y, z + 2], {}, { net }),
    addChest(w, [x + 7, y, z + 2], {}, { net }),
  ];
  const furnace = addFurnace(w, [x + 8, y, z + 2], { net });
  for (let i = 0; i <= 9; i++) net.cells.push([x + i, y, z + 1]);

  const s = { pc, input, output, store, furnace, tries: { deletes: 0 }, lost: [] };
  // type a search, press Delete, and see whether the Find line is empty again
  const round = (i) => [
    ["type", "cob"], ["wait", 0.05 + (i % 7) * 0.13],
    ["key", 261], ["wait", 0.4],
    ["do", (c, wd) => {
      s.tries.deletes++;
      const find = c.term.lines()[1] || "";
      if (/Find: \S/.test(find)) s.lost.push(`${wd.time.toFixed(1)}s: "${find.trim()}"`);
      // clear it for the next round however it went
      if (/Find: \S/.test(find)) wd.key(c, 261);
    }],
    ["wait", 0.3 + (i % 5) * 0.41],
  ];
  const rounds = [];
  for (let i = 0; i < 40; i++) rounds.push(...round(i));

  pc.boot();
  play(w, pc, [...install("starter-storage"), ["type", "stash\n"], ["until", /Pick the input and output/, 30],
    ["clickText", "Input chest"], ["until", /Pick: Input/, 10], ["clickText", "minecraft:barrel_0"], ["wait", 1],
    ["clickText", "Output chest"], ["until", /Pick: Output/, 10], ["clickText", "minecraft:barrel_1"], ["wait", 1],
    ["clickText", "Save"], ["until", /Del clear/, 60], ["wait", 5],
    ...rounds]);
  return s;
}

export function build(w = newWorld()) {
  return { w, ...stash(w) };
}

export function check(s) {
  const out = [];
  if (s.input.inv.slots.some(Boolean)) out.push(`the input barrel isn't empty: ${s.input.inv.slots.filter(Boolean).map((i) => `${i.count} ${i.name}`).join(", ")}`);
  if (s.tries.deletes < 40) out.push(`only ${s.tries.deletes} of 40 Delete presses were tried`);
  if (s.lost.length) out.push(`Delete didn't clear the search ${s.lost.length} of ${s.tries.deletes} times:\n    ${s.lost.join("\n    ")}`);
  return out;
}
