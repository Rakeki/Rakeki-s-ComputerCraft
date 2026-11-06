// The update watcher: a power dashboard (report.loop), the AutoMine server
// (its own event loop: report.handle) and a dashboard set to say no
// (install.remote false), all installed from the site. Then a new version of
// the power dashboard and the mine server "goes up" on the website, and the
// watcher has them update and reboot, one at a time.
import fs from "node:fs";
import { newWorld, addComputer, addMonitor, play, install, run, SITE_URL } from "../core/base.mjs";

const PUSH_AT = 240 // seconds in: the new versions go up
const NEW = { "power-dashboard": "simnewpower1", "mine-server": "simnewmines1" };

// Count boots, to tell a computer really rebooted after the push.
function counted(c) {
  const boot = c.boot.bind(c);
  c.boots = [];
  c.boot = () => { c.boots.push(c.world.time); boot(); };
  return c;
}

export function build(w = newWorld()) {
  const s = { w };

  s.watcher = counted(addComputer(w, { pos: [0, 64, 0], label: "Updates", role: "update-watcher", facing: "south" }));
  s.watcherMon = addMonitor(w, [[-1, 65, -1], [0, 65, -1], [1, 65, -1], [-1, 64, -1], [0, 64, -1], [1, 64, -1]], 3, 2);
  s.watcher.boot();
  play(w, s.watcher, [["wait", 30], ...install("update-watcher"), ...run("updates every 1"), ["reboot"]]);

  s.power = counted(addComputer(w, { pos: [6, 64, 0], label: "Power", role: "power-dashboard", facing: "south" }));
  s.power.boot();
  play(w, s.power, [["wait", 5], ...install("power-dashboard"), ["reboot"]]);

  const server = counted(addComputer(w, { pos: [-8, 64, 4], label: "AutoMine", role: "mine-server", facing: "south" }));
  s.server = server;
  server.boot();
  play(w, server, [["wait", 10], ...install("mine-server"), ["reboot"]]);

  s.stubborn = counted(addComputer(w, { pos: [4, 64, 8], label: "Stubborn", role: "power-dashboard", facing: "south" }));
  s.stubborn.boot();
  play(w, s.stubborn, [["wait", 15], ...install("power-dashboard"), ...run("set install.remote false"), ["reboot"]]);

  // the push: the same files, a new version for two programs
  w.at(PUSH_AT, () => {
    const manifest = JSON.parse(JSON.stringify(w.manifest));
    for (const [name, v] of Object.entries(NEW)) manifest.programs[name].version = v;
    const body = JSON.stringify(manifest);
    w.http.routes.unshift({ prefix: SITE_URL + "/manifest.json", handle: () => ({ code: 200, body }) });
    s.pushedAt = w.time;
  });
  return s;
}

function versions(c) {
  const body = c.readFile(".installed_versions");
  return body || "";
}

export function check(s) {
  const out = [];
  for (const [c, name] of [[s.power, "power-dashboard"], [s.server, "mine-server"]]) {
    if (!versions(c).includes(NEW[name])) out.push(`${c.label} didn't get the new ${name} version`);
    if (!c.boots.some((t) => t > s.pushedAt)) out.push(`${c.label} didn't reboot after the push`);
  }
  if (versions(s.stubborn).includes(NEW["power-dashboard"])) out.push("Stubborn updated though install.remote is false");
  if (s.stubborn.boots.some((t) => t > s.pushedAt)) out.push("Stubborn rebooted though install.remote is false");
  const screen = s.watcher.term.dump();
  if (!/Stubborn.*says no/.test(screen)) out.push("the watcher doesn't show Stubborn saying no");
  if (!/Power .*up to date/.test(screen)) out.push("the watcher doesn't show Power up to date");
  if (!s.watcherMon.term.dump().includes("Update watcher")) out.push("nothing on the watcher's monitor");
  return out;
}
