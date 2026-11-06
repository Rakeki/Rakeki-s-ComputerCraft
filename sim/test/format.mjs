import { World } from "../core/world.mjs";
const w = new World();
const c = w.addComputer({ pos: [0, 64, 0], files: { "startup.lua": `
print(("free-%d"):format(os.epoch("utc")))
print(("%5.1f%% %d %3d|%-4d|%x %s"):format(12.345, 2.7, 5, -3.9, 255, "x"))
print(("%d items"):format("7"), ("%05d"):format(42.0), ("%.2f"):format(1/3))
print(string.format("100%%"), ("%c%c"):format(72, 105))
` } });
w.on("error", (e) => console.log("ERR", e.msg));
c.boot(); w.run(2); console.log(c.term.dump());
