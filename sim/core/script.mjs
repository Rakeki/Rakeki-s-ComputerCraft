// The player's hands: type commands into a computer, wait for its screen to
// say something, all on simulated time.
//   play(world, computer, [
//     ["type", "wget run http://localhost:8080/install.lua mine-server\n"],
//     ["until", /installed/i, 60],    // wait (up to 60 s) for the screen to match
//     ["wait", 2],
//     ["do", (c) => ...],             // anything else
//     ["reboot"],
//   ])
export function play(world, c, steps, onDone) {
  let i = 0;
  const log = (c.script = { steps, at: 0, failed: null });
  const next = () => {
    if (i >= steps.length) { log.done = true; onDone && onDone(); return; }
    const [op, a, b] = steps[i++];
    log.at = i;
    switch (op) {
      case "type": world.after(world.type(c, a) + 0.1, next); break;
      case "wait": world.after(a, next); break;
      case "do": a(c, world); world.after(0.05, next); break;
      case "reboot": c.shutdown(true); world.after(1, next); break;
      case "boot": c.boot(); world.after(0.5, next); break;
      case "key": world.key(c, a); world.after(0.1, next); break;
      // click the terminal at (x, y), or on a piece of text it shows
      case "click": case "clickText": {
        let x = a, y = b;
        if (op === "clickText") {
          const lines = c.term.lines();
          y = lines.findIndex((l) => l.includes(a)) + 1;
          if (!y) { log.failed = `no "${a}" on ${c.label || c.id}'s screen`; world.emit("script-failed", { computer: c, msg: log.failed }); return; }
          x = lines[y - 1].indexOf(a) + 1 + (b || 0);
        }
        world.queue(c, ["mouse_click", 1, x, y]);
        world.after(0.05, () => world.queue(c, ["mouse_up", 1, x, y]));
        world.after(0.2, next);
        break;
      }
      // tap a monitor at (x, y), or on a piece of text it shows
      case "tap": case "tapText": {
        const mon = steps[i - 1][3] || c.monitor;
        let x = a, y = b;
        if (op === "tapText") {
          const lines = mon.term.lines();
          y = lines.findIndex((l) => l.includes(a)) + 1;
          if (!y) { log.failed = `no "${a}" on the monitor`; world.emit("script-failed", { computer: c, msg: log.failed }); return; }
          x = lines[y - 1].indexOf(a) + 1;
        }
        for (const wt of world.watchers(mon)) world.queue(wt.computer, ["monitor_touch", wt.name, x, y]);
        world.after(0.2, next);
        break;
      }
      case "until": {
        const deadline = world.time + (b ?? 60);
        const poll = () => {
          const text = c.term.dump();
          if (a.test(text)) return next();
          if (world.time >= deadline) { log.failed = `waited for ${a} on ${c.label || c.id}`; world.emit("script-failed", { computer: c, msg: log.failed }); return; }
          world.after(0.5, poll);
        };
        poll();
        break;
      }
      default: throw new Error(`unknown step ${op}`);
    }
  };
  world.after(0.05, next);
}

// install a program with the website's installer, the way the README says
export const install = (program, url = "http://localhost:8080") => [
  prompt(),
  ["type", `wget run ${url}/install.lua ${program}\n`],
  ["until", /is\s+installed\./, 120],
  prompt(),
];
// wait for the shell's prompt (the last line on screen is "> ")
export function prompt(secs = 120) { return ["until", /(^|\n)> ?$/, secs]; }
// type a shell command once the prompt is back
export const run = (line) => [prompt(), ["type", line + "\n"]];
