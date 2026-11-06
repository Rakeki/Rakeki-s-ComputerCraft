// The mod-block computers: Mekanism power, fission and fusion, Digital
// Miners, and a MineColonies colony, with stand-ins for the blocks.
import { newWorld, addComputer, addMonitor, addGps, play, install, run } from "../core/base.mjs";
import { inductionMatrix, fissionReactor, fusionReactor, digitalMiner, colonyIntegrator } from "../core/mods.mjs";

// a monitor wide x high blocks on the face north of a row starting at (x, y, z)
function wall(w, x, y, z, wide, high, opts) {
  const cells = [];
  for (let dy = high - 1; dy >= 0; dy--) for (let dx = 0; dx < wide; dx++) cells.push([x + dx, y + dy, z]);
  return addMonitor(w, cells, wide, high, opts);
}

export function machines(w, at = [40, 64, -22]) {
  const [x, y, z] = at;
  const s = {};
  // the matrix: one port next to the power dashboard, one on the reactor's cable
  const { matrix, port } = inductionMatrix(w);
  s.matrix = matrix;
  w.fill(x - 4, x - 2, y, y + 2, z - 4, z - 2, "mekanism:induction_casing");
  s.power = addComputer(w, { pos: [x, y, z], label: "Power", role: "power-dashboard", facing: "south", modemSide: "right" });
  w.addPeripheral([x, y, z - 1], "mekanism:induction_port", port()); // behind it
  s.powerMon = wall(w, x - 1, y + 1, z, 3, 2);
  s.power.boot();
  play(w, s.power, [["wait", 20], ...install("power-dashboard"), ["reboot"]]);

  // fission: logic adapter behind the computer, matrix port and monitor on its cable
  const fnet = w.net("fission");
  const { reactor, port: rport } = fissionReactor(w, { coolantRunsOutAt: 900 });
  s.reactor = reactor;
  w.fill(x + 6, x + 10, y, y + 4, z - 6, z - 2, "mekanism:fission_reactor_casing");
  s.fission = addComputer(w, { pos: [x + 8, y, z], label: "Fission", role: "fission-guard", facing: "south", modemSide: "right" });
  w.addPeripheral([x + 8, y, z - 1], "mekanism:fission_reactor_logic_adapter", rport("fissionReactorLogicAdapter"));
  s.fission.attach("left", w.wiredModem(fnet));
  w.addPeripheral([x + 12, y, z], "mekanism:induction_port", port(), fnet);
  for (let i = 9; i <= 12; i++) fnet.cells.push([x + i, y, z + 1]);
  s.fissionMon = wall(w, x + 7, y + 1, z, 3, 2);
  s.fission.boot();
  play(w, s.fission, [["wait", 25], ...install("fission-guard"), ["reboot"], ["wait", 10], ["tapText", "Start", null, s.fissionMon], ["wait", 5]]);

  // fusion: logic adapter behind it
  const { fusion, port: fport } = fusionReactor(w);
  s.fusion = fusion;
  w.fill(x + 15, x + 19, y, y + 4, z - 6, z - 2, "mekanism:fusion_reactor_frame");
  s.fusionPc = addComputer(w, { pos: [x + 17, y, z], label: "Fusion", role: "fusion-control", facing: "south", modemSide: "right" });
  w.addPeripheral([x + 17, y, z - 1], "mekanism:fusion_reactor_logic_adapter", fport("fusionReactorLogicAdapter"));
  s.fusionMon = wall(w, x + 16, y + 1, z, 3, 2);
  s.fusionPc.boot();
  play(w, s.fusionPc, [["wait", 30], ...install("fusion-control"), ["reboot"]]);

  // two digital miners on a cable
  const dnet = w.net("miners");
  s.dminers = [digitalMiner(w, 0), digitalMiner(w, 1)];
  s.dminers.forEach((m, i) => { w.addPeripheral([x + 24 + i * 4, y, z - 3], "mekanism:digital_miner", m, dnet); });
  for (let i = 0; i <= 8; i++) dnet.cells.push([x + 22 + i, y, z - 1]);
  s.dminer = addComputer(w, { pos: [x + 22, y, z], label: "Miners", role: "digital-miner-manager", facing: "south", modemSide: "right" });
  s.dminer.attach("back", w.wiredModem(dnet));
  s.dminerMon = wall(w, x + 21, y + 1, z, 3, 2);
  s.dminer.boot();
  play(w, s.dminer, [["wait", 35], ...install("digital-miner-manager"), ["reboot"], ["wait", 10], ["tapText", "Start all", null, s.dminerMon], ["wait", 5]]);

  // MineColonies: colony integrator behind the computer
  s.colony = addComputer(w, { pos: [x + 32, y, z], label: "Colony", role: "colony-dashboard", facing: "south", modemSide: "right" });
  w.addPeripheral([x + 32, y, z - 1], "advancedperipherals:colony_integrator", colonyIntegrator(w));
  s.colonyMon = wall(w, x + 31, y + 1, z, 3, 2);
  s.colony.boot();
  play(w, s.colony, [["wait", 40], ...install("colony-dashboard"), ["reboot"]]);
  return s;
}

export function build(w = newWorld()) {
  for (const g of addGps(w)) g.boot();
  return { w, ...machines(w) };
}

export function check(s) {
  const out = [];
  if (!s.reactor.starts) out.push("fission: the reactor was never started");
  if (s.w.time > 1000 && !s.reactor.scrams) out.push(`fission: no SCRAM after the coolant ran out (temp ${s.reactor.temp.toFixed(0)} K)`);
  if (s.reactor.temp > 1100) out.push(`fission: reached ${s.reactor.temp.toFixed(0)} K`);
  if (!s.dminers.every((m) => m.state.running || m.state.mined > 0)) out.push("digital miners: not all started");
  return out;
}
