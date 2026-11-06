// No GPS yet: the GPS deployer builds the four hosts, then a computer on
// the ground checks it gets a fix from them.
import { newWorld, addComputer, play, install, run } from "../core/base.mjs";

export function gpsDeployer(w, at = [-30, 64, 30]) {
  const [x, y, z] = at;
  const t = addComputer(w, { pos: at, kind: "turtle", facing: "north", role: "gps-deployer", label: "GPS deployer" });
  for (let i = 0; i < 4; i++) t.inventory.add("computercraft:computer_normal", 1);
  t.inventory.add("computercraft:wireless_modem_normal", 4);
  t.inventory.add("computercraft:disk_drive", 1);
  t.inventory.add("computercraft:disk", 1);
  t.inventory.add("minecraft:coal", 16);
  // the computers it places run `gps host`: mark them for the map
  w.on("placed-computer", ({ turtle, computer }) => { if (turtle === t) { computer.role = "gps"; computer.program = "gps host"; computer.deployed = true; } });
  t.boot();
  play(w, t, [["wait", 5], ...install("gps-deployer"), ...run("refuel all"), ...run("gps-deploy 120"),
    ["until", /X:$/, 20], ["type", `${x}\n`], ["until", /Y:$/, 5], ["type", `${y}\n`], ["until", /Z:$/, 5], ["type", `${z}\n`],
    ["until", /Facing/, 5], ["type", "north\n"], ["until", /Enter to start/, 20], ["type", "\n"]]);
  return t;
}

export function build(w = newWorld()) {
  const deployer = gpsDeployer(w);
  // once it's done, a computer on the ground asks where it is
  const probe = addComputer(w, { pos: [-25, 64, 32], label: "Probe", role: "gps-probe" });
  probe.boot();
  play(w, probe, [["until", /> ?$/, 10], ["wait", 30], ["do", () => {}], ["until", /> ?$/, 10]]);
  w.at(560, () => w.type(probe, "gps locate\n"));
  return { w, deployer, probe };
}

export function check(s) {
  const out = [];
  const hosts = s.w.computers.filter((c) => c.role === "gps");
  if (hosts.length !== 4) out.push(`placed ${hosts.length} GPS computers, want 4`);
  if (!hosts.every((h) => h.on)) out.push("not every GPS computer is on");
  if (!/Position is -25, ?64, ?32/.test(s.probe.term.dump())) out.push("the probe got no GPS fix at -25, 64, 32");
  return out;
}
