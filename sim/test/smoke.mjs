// Smallest check: two computers boot CraftOS, one sends a rednet message,
// the other prints it.
import { World } from "../core/world.mjs";

const w = new World();
const a = w.addComputer({ pos: [0, 64, 0], label: "A", files: { "startup.lua": `
  print("A up", os.getComputerID(), _HOST)
  rednet.open("top")
  sleep(1)
  rednet.broadcast({ hello = "there", n = 1.5, list = { 1, 2, 3 } }, "test")
  print("sent")
  print(("%d items, %s"):format(2.0, tostring(3.0)))
` } });
a.attach("top", w.wirelessModem());
const b = w.addComputer({ pos: [10, 64, 0], label: "B", files: { "startup.lua": `
  rednet.open("top")
  local id, msg, proto = rednet.receive("test", 5)
  print("B got", id, proto, msg and msg.hello, msg and msg.n, msg and #msg.list)
  print(textutils.serialise({ a = 1, b = { true } }, { compact = true }))
` } });
b.attach("top", w.wirelessModem());
w.on("error", ({ computer, msg }) => console.log(`ERR ${computer.label}: ${msg}`));
a.boot(); b.boot();
const t0 = Date.now();
w.run(10);
console.log(`--- A (${Date.now() - t0} ms)\n` + a.term.dump());
console.log("--- B\n" + b.term.dump());
