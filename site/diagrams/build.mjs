// Setup diagrams for every program in computers/: writes
// computers/<name>/preview/setup.svg (and setup-far.svg for some).
//   node site/diagrams/build.mjs            every program
//   node site/diagrams/build.mjs factory    just one
// Each scene follows the program's README Setup / Use section; when that
// changes (where a chest goes, a new peripheral), change the scene and rerun.
// Coordinates: y up; a turtle drawn as "turtle" faces +z (towards the bottom
// left), so behind it is -z, its left +x and its right -x. "turtleE" faces
// +x: behind -x, left -z, right +z.
import { World, save, ground, COL } from "./render.mjs";
const { Y, B, G, O, R, P, W, C, GR } = COL;
const only = process.argv[2];
const S = {};

// a storage system in miniature: chests and full-block modems in a row at z,
// cable along z + 1 from x0 to x1, the storage computer at the end
function storage(w, x0, z, x1, opts = {}) {
  for (let i = 0; i < 5; i++) {
    const b = i % 3 === 1 ? "fullmodem" : "chest";
    w.set(x0 + i, 0, z, b); w.set(x0 + i, 1, z, b);
  }
  w.box(x0 + 1, x1, 0, 0, z + 1, z + 1, "cable");
  if (opts.computer !== false) {
    w.set(x1 + 1, 0, z + 1, opts.computer || "advancedE");
    w.set(x1 + 1, 1, z + 1, "modem");
  }
}
const facing = (x, z, dx, dz, text = "facing", col = G) => ({ from: [x + 0.5 + dx * 0.5, 0.05, z + 0.5 + dz * 0.5], to: [x + 0.5 + dx * 2.6, 0.05, z + 0.5 + dz * 2.6], col, text });

//---------------------------------------------------------------- mining

S["excavate-turtle"] = () => {
  const w = new World();
  ground(w, -6, 2, -3, 7);
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest");
  return {
    title: "Excavator: where to put it",
    world: w,
    outlines: [{ box: [-4, 0, 0, 3, 0, 5], col: Y, text: ["the hole, forward and to the turtle's right", "default 21 wide x 21 long x 16 high, from the turtle's block up"], off: [-30, -60] }],
    arrows: [facing(0, 0, 0, 1, "facing: along one edge"), { from: [0, 0.05, 0.5], to: [-2.4, 0.05, 0.5], col: B, text: "turtle's right" }],
    labels: [
      { at: [0, 0, 0], text: ["mining turtle", "at floor level in one corner", "wireless or ender modem (GPS)"], col: G, off: [150, 40] },
      { at: [0, 0, -1], text: ["chest directly behind it", "coal for fuel; loot goes in here"], col: O, off: [150, -40] },
    ],
    notes: [
      "Needs GPS: a GPS constellation in range (gps-deployer) and a modem on the turtle.",
      "excavate 30 40 12 = 30 to the right, 40 forward, 12 up. 'excavate 21 21 16 down' digs downwards: put the turtle at the top corner instead.",
      "Junk (cobblestone, dirt...) is dropped on the ground in front of the start; everything else goes in the chest.",
    ],
  };
};

S["strip-mine-turtle"] = () => {
  const w = new World();
  ground(w, -7, 7, -3, 14);
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest");
  return {
    title: "Strip miner: where to put it",
    world: w,
    outlines: [
      { box: [-1, 1, 0, 2, 0, 13], col: Y, text: ["main tunnel: 3 wide (centred on the turtle) x 3 high", "64 long by default"], off: [60, 110] },
      { box: [2, 6, 0, 2, 5, 7], col: O, text: "branch, 32 long (left)", off: [30, -40] },
      { box: [-6, -2, 0, 2, 5, 7], col: O, text: "branch (right)", off: [-30, -40] },
      { box: [2, 6, 0, 2, 11, 13], col: O, floor: true },
      { box: [-6, -2, 0, 2, 11, 13], col: O, text: "next pair: 6 blocks on (3 solid between)", off: [-40, 30] },
    ],
    arrows: [facing(0, 0, 0, 1, "facing: the way to dig")],
    labels: [
      { at: [0, 0, 0], text: ["mining turtle", "on the tunnel floor"], col: G, off: [-150, 20] },
      { at: [0, 0, -1], text: ["chest directly behind it", "coal; it unloads here"], col: O, off: [130, -50] },
    ],
    notes: ["Torches anywhere in the turtle: one every 8 blocks along the floor.", "Needs GPS (a modem on the turtle) to start or resume."],
  };
};

S["nether-tunnel-turtle"] = () => {
  const w = new World();
  ground(w, -3, 3, -3, 10, "gnether");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest");
  w.box(2, 3, -1, -1, 5, 8, "lava");
  return {
    title: "Nether tunnel: where to put it",
    world: w,
    outlines: [{ box: [-1, 1, 0, 2, 0, 9], col: Y, text: ["the sealed tunnel: 3 wide (centred) x 3 high", "128 long by default"], off: [110, -40] }],
    arrows: [facing(0, 0, 0, 1, "facing: the way to dig")],
    labels: [
      { at: [0, 0, 0], text: ["mining turtle on the floor", "optional: empty bucket (lava fuel), torches"], col: G, off: [-170, 20] },
      { at: [0, 0, -1], text: ["chest directly behind it", "coal; a few stacks of cobblestone"], col: O, off: [130, -60] },
    ],
    notes: ["The start end stays open as the way in. It patches holes and walls off lava along the way.", "Needs GPS in the Nether too: build a constellation there (gps-deployer), or use an ender modem."],
  };
};

S["level-turtle"] = () => {
  const w = new World();
  ground(w, -8, 2, -3, 8, "ggrass");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest");
  w.box(-6, -4, 0, 1, 4, 6, "ggrass"); w.set(-5, 2, 5, "ggrass");
  w.box(-2, -1, -1, -1, 5, 6, "gwater");
  return {
    title: "Leveller: where to put it",
    world: w,
    outlines: [{ box: [-6, 0, 0, 2, 0, 6], col: Y, text: ["the platform area: x to the turtle's right, z forward", "everything above the block under the turtle is cleared"], off: [-60, -70] }],
    arrows: [facing(0, 0, 0, 1, "facing: along one edge (z)"), { from: [0, 0.05, 0.5], to: [-2.4, 0.05, 0.5], col: B, text: "x: turtle's right" }],
    labels: [
      { at: [0, 0, 0], text: ["mining turtle standing on the ground", "the block under it = platform top"], col: G, off: [170, 40] },
      { at: [0, 0, -1], text: ["chest directly behind it", "coal; wood and loot go here"], col: O, off: [150, -40] },
      { at: [-2, -1, 5], text: "holes and ponds get filled", col: B, off: [-60, 50] },
    ],
    notes: ["level 32 32 = 32 to the right, 32 forward. A third number is how high to clear (default: up to open sky).", "Needs GPS (a modem on the turtle)."],
  };
};

//---------------------------------------------------------------- farming

S["tree-farm-turtle"] = () => {
  const w = new World();
  ground(w, -12, 2, -3, 11, "ggrass");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest");
  for (let c = 0; c < 4; c++) for (let r = 0; r < 3; r++) w.set(-(c * 3 + 1), 0, 1 + r * 3, "sapling");
  return {
    title: "Tree farm: where to put it",
    world: w,
    outlines: [{ box: [-11, 0, 0, 0, 0, 10], col: Y, floor: true, text: ["the farm: forward and to the turtle's right", "4 columns of 6 trees, 3 apart (11 x 18)"], off: [-40, -80] }],
    arrows: [facing(0, 0, 0, 1, "facing: along the farm")],
    labels: [
      { at: [0, 0, 0], text: ["turtle at the near left corner", "saplings, coal, bone meal in it"], col: G, off: [160, 40] },
      { at: [0, 0, -1], text: "chest directly behind it", col: O, off: [130, -40] },
      { at: [-1, 0, 1], text: ["first tree: 1 right, 1 forward", "lanes on the left of each column"], col: Y, off: [-40, 70] },
    ],
    notes: ["Flat dirt or grass, cleared. Torches between trees (not in the lanes) keep saplings growing at night.", "Needs GPS (a modem on the turtle)."],
  };
};

S["crop-farm-turtle"] = () => {
  const w = new World();
  ground(w, -6, 2, -3, 6, "ggrass", -2);
  for (let x = -4; x <= 0; x++) for (let z = 0; z <= 4; z++) {
    if (x === -2 && z === 2) { w.set(x, -2, z, "gwater"); continue; }
    w.set(x, -2, z, "farmland"); w.set(x, -1, z, (x + z) % 3 ? "wheat" : "carrots");
  }
  w.set(0, -1, -1, "gstone"); w.set(0, 0, -1, "chest"); w.set(0, 0, 0, "turtle");
  return {
    title: "Crop farm: where to put it",
    world: w,
    outlines: [{ box: [-4, 0, -1, -1, 0, 4], col: Y, floor: false, text: ["the field: forward and to the right of the crop under the turtle", "9 x 9 by default"], off: [-60, -70] }],
    arrows: [{ from: [0.5, 0.05, 1], to: [0.5, 0.05, 3.4], col: G, text: "facing: along one edge" }],
    labels: [
      { at: [0, 0, 0], text: ["turtle flying one block above the crops", "over a corner crop; coal and seeds in it"], col: G, off: [170, 40] },
      { at: [0, 0, -1], text: ["chest directly behind it, same height", "(stood on a block)"], col: O, off: [150, -40] },
    ],
    notes: ["Keep the layer just above the crops clear: that's where the turtle flies.", "Needs GPS (a modem on the turtle)."],
  };
};

S["mob-farm-turtle"] = () => {
  const w = new World();
  ground(w, -5, 4, -3, 6, "ggrass");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest"); w.set(0, -1, 0, "chest");
  return {
    title: "Mob farm: where to put it",
    world: w,
        outlines: [
      { box: [-1, 0, 0, 6, 2, 3], col: B, text: ["the 2x2 drop shaft comes down here:", "1 block in front, in front and front-right"], off: [-170, 10] },
      { box: [-4, 3, 7, 8, -1, 6], col: Y, floor: false, text: ["spawning room, 32 up by default (18 x 18 inside), centred on the shaft (drawn smaller)"] },
    ],
    arrows: [facing(0, 0, 0, 1, "facing: the way the farm goes")],
    labels: [
      { at: [0, 0, 0], text: ["turtle on the ground, where you'll stand", "slot 1: a stack of the block to build with"], col: G, off: [190, 40] },
      { at: [0, 0, -1], text: ["supply chest directly behind it", "'mobfarm list' says what goes in"], col: O, off: [170, -30] },
      { at: [0, -1, 0], text: ["optional buffer chest", "directly under the start block"], col: O, off: [120, 80] },
    ],
    notes: ["Open sky above. Over an ocean or far from caves is best (fewer mobs elsewhere using up the mob cap).", "The buffer chest is needed with Sophisticated Storage barrels as the supply chest."],
  };
};

S["crate-turtle"] = () => {
  const w = new World();
  ground(w, -2, 13, -2, 3);
  w.set(0, 0, 0, "chest"); w.set(0, 1, 0, "turtle"); w.set(0, 2, 0, "crate");
  w.set(4, 0, 0, "gstone"); w.set(4, 1, 0, "turtle"); w.set(4, 1, 1, "crate"); w.set(4, 2, 0, "chest");
  storage(w, 8, -1, 11, { computer: false });
  w.set(12, 0, 0, "advancedE"); w.set(12, 1, 0, "modem");
  w.set(8, 0, 1, "chest"); w.set(9, 0, 1, "fullmodem"); w.set(8, 1, 1, "turtle"); w.set(8, 2, 1, "crate");
  return {
    title: "Crate turtle: where to put it",
    world: w,
    headings: [{ at: [0.5, 0, 2.6], text: "crate above, chest below" }, { at: [4.5, 0, 2.6], text: "crate in front, chest above" }, { at: [9.5, 0, 3.2], text: "crate stock" }],
    labels: [
      { at: [0, 2, 0], text: ["Creative Crate", "filter slot set to the item"], col: P, off: [-60, -50] },
      { at: [0, 1, 0], text: "turtle (no fuel needed)", col: G, off: [-110, 0] },
      { at: [0, 0, 0], text: ["chest touching it", "below, above or in front"], col: O, off: [-90, 50] },
      { at: [8, 0, 1], text: ["the storage input chest", "under the turtle"], col: G, off: [-30, 70] },
      { at: [8, 1, 1], text: ["wireless or ender modem", "on its left or right"], col: B, off: [-100, -30] },
      { at: [9, 0, 1], text: "full-block wired modem", col: W, off: [90, 50] },
      { at: [12, 0, 0], text: "storage computer", col: B, off: [60, -40] },
    ],
    notes: ["The crate and the chest go on the turtle's front, top or bottom: a turtle can't reach a chest behind it or beside it, or through a full-block modem.", "Below is checked first for the chest, then above, then in front."],
  };
};

S["mine-turtle"] = () => {
  const w = new World();
  ground(w, -3, 9, -3, 4, "ggrass");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "chest"); w.set(1, 0, 0, "chest");
  w.set(3, 0, 0, "turtle"); w.set(3, 0, -1, "chest");
  w.set(7, 0, -1, "advanced"); w.set(7, 1, -1, "modem"); w.set(8, 0, -1, "monitor"); w.set(8, 1, -1, "monitor");
  return {
    title: "AutoMine miner: its home",
    world: w,
    outlines: [{ box: [0, 0, 1, 5, 0, 0], col: B, floor: false, text: "open sky above", off: [-60, -10] }],
    arrows: [facing(0, 0, 0, 1, "facing (room to step forward)"), facing(3, 0, 0, 1, "")],
    labels: [
      { at: [0, 0, 0], text: ["mining turtle + ender modem", "its home: where you place it"], col: G, off: [-150, 30] },
      { at: [0, 0, -1], text: ["home chest directly behind", "it unloads here"], col: O, off: [-60, -70] },
      { at: [1, 0, 0], text: ["optional fuel chest", "on its left or right"], col: R, off: [60, 70] },
      { at: [3, 0, 0], text: "another miner: its own spot and chest", col: G, off: [90, 50] },
      { at: [7, 0, -1], text: ["mine-server", "anywhere, with a modem"], col: B, off: [60, -50] },
    ],
    notes: ["Needs GPS (gps-deployer). The server never mines a chunk with a home in it.", "Put a little coal in the chest and in the turtle (refuel all) before the first start."],
  };
};

S["mine-server"] = () => {
  const w = new World();
  ground(w, -4, 9, -2, 7, "ggrass");
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem");
  w.box(1, 3, 0, 1, 0, 0, "monitor");
  w.box(-3, -1, 0, 1, 0, 0, "monitor");
  for (const x of [4, 6]) { w.set(x, 0, 5, "turtle"); w.set(x, 0, 4, "chest"); }
  return {
    title: "AutoMine server: what to place",
    world: w,
    links: [{ a: [0.5, 1.2, 0.5], b: [4.5, 1, 5.5], col: C, text: "automine over rednet", bow: 60 }],
    labels: [
      { at: [0, 0, 0], text: ["computer + wireless or ender modem", "runs mine-server"], col: B, off: [-60, 80] },
      { at: [2, 1, 0], text: ["optional status board", "(any monitor; statusMonitor)"], col: Y, off: [60, -60] },
      { at: [-2, 1, 0], text: ["optional touch map", "(advanced monitor; mapMonitor)"], col: Y, off: [-60, -60] },
      { at: [6, 0, 5], text: ["miners at their homes,", "each with its own chest behind"], col: G, off: [120, 30] },
    ],
    notes: ["Without a mapMonitor the touch map shows on the computer's screen. Monitors can come and go while it runs."],
  };
};

//---------------------------------------------------------------- network

S["status-server"] = () => {
  const w = new World();
  ground(w, -2, 9, -2, 7);
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem");
  w.box(1, 3, 0, 1, 0, 0, "monitor");
  w.set(6, 0, 5, "turtle"); w.set(2, 0, 5, "computer"); w.set(2, 1, 5, "modem");
  return {
    title: "Status server: what to place",
    world: w,
    links: [{ a: [0.5, 1.2, 0.5], b: [6.5, 1, 5.5], col: C, text: "cc_status", bow: 40 }, { a: [0.5, 1.2, 0.5], b: [2.5, 1.2, 5.5], col: C, bow: 20 }],
    labels: [
      { at: [0, 0, 0], text: ["advanced computer", "+ wireless or ender modem"], col: B, off: [-110, 50] },
      { at: [2, 1, 0], text: ["advanced monitor, 3 x 2 or bigger", "touching the computer"], col: Y, off: [60, -60] },
      { at: [6, 0, 5], text: ["every program that reports", "needs a modem too"], col: G, off: [90, 30] },
    ],
    notes: ["Without a monitor the dashboard shows on the computer's own screen."],
  };
};

S["update-watcher"] = () => {
  const w = new World();
  ground(w, -2, 10, -2, 8);
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem");
  w.box(1, 3, 0, 1, 0, 0, "monitor");
  w.set(7, 0, 5, "turtle"); w.set(3, 0, 6, "computer"); w.set(3, 1, 6, "modem");
  return {
    title: "Update watcher: what to place",
    world: w,
    links: [
      { a: [7.5, 1, 5.5], b: [0.5, 1.2, 0.5], col: C, text: "cc_status: installed versions", bow: 40 },
      { a: [0.5, 1.2, 0.5], b: [3.5, 1.2, 6.5], col: O, text: "cc_update: update", bow: 25 },
    ],
    labels: [
      { at: [0, 0, 0], text: ["computer (advanced for colour)", "+ wireless or ender modem"], col: B, off: [-110, 50] },
      { at: [2, 1, 0], text: ["optional monitor, 3 x 2 or bigger", "touching it or on its cable"], col: Y, off: [60, -60] },
      { at: [7, 0, 5], text: ["every computer and turtle running a program", "(they need a modem too)"], col: G, off: [90, 30] },
    ],
    notes: ["An ender modem on the watcher and the computers reaches them anywhere; a wireless modem only those in range.", "Each asked computer fetches the new files, reboots and carries on."],
  };
};

S["turtle-finder"] = () => {
  const w = new World();
  ground(w, -4, 9, -2, 8, "ggrass");
  w.set(0, 0, 0, "pocket");
  w.set(6, 0, 1, "turtle"); w.set(-2, 0, 6, "turtle");
  for (const [x, y, z] of [[2, 7, 3], [6, 8, 6]]) { w.set(x, y, z, "computer"); w.set(x, y + 1, z, "modem"); }
  return {
    title: "Turtle finder: what you need",
    world: w,
    links: [{ a: [6.5, 1, 1.5], b: [0.5, 0.9, 0.5], col: C, text: "cc_status", bow: 30 }, { a: [-1.5, 1, 6.5], b: [0.5, 0.9, 0.5], col: C, bow: 20 }],
    labels: [
      { at: [0, 0, 0], text: ["pocket computer + wireless or ender modem", "(advanced: colour arrow)"], col: Y, off: [-60, 70] },
      { at: [6, 0, 1], text: ["turtles that report", "(status on cc_status)"], col: G, off: [90, 30] },
      { at: [2, 7, 3], text: ["GPS hosts in range", "so it knows where you are"], col: B, off: [-70, -30] },
    ],
    notes: ["An ender modem hears turtles at any distance; a wireless one a few hundred blocks."],
  };
};

S["gps-deployer"] = () => {
  const w = new World();
  ground(w, -3, 3, -3, 3, "ggrass");
  w.set(0, 0, 0, "turtle");
  for (const [x, y, z] of [[-3, 12, 0], [3, 12, 0], [0, 12, -3], [0, 18, 3]]) { w.set(x, y, z, "computer"); w.set(x, y + 1, z, "modem"); }
  return {
    title: "GPS deployer: where to put it",
    world: w,
    outlines: [{ box: [0, 0, 1, 11, 0, 0], col: B, floor: false, text: ["open sky above: it flies straight up", "and digs anything in the way"], off: [150, 0] }],
    arrows: [facing(0, 0, 0, 1, "facing: type it in from F3")],
    labels: [
      { at: [0, 0, 0], text: ["turtle on the ground", "4 computers, 4 wireless or ender modems,", "1 disk drive + 1 floppy, ~750 fuel"], col: G, off: [-180, 40] },
      { at: [0, 18, 3], text: ["four GPS hosts at the top", "one raised so they're not in one plane"], col: B, off: [140, -10] },
    ],
    notes: ["It asks for the turtle's X, Y, Z and facing (F3): there's no GPS yet to find them.", "Satellites (gps-deploy satellite) need the extra hull, solar, bar, slab, light and rod blocks listed in the README."],
  };
};

//---------------------------------------------------------------- building

function builderHome(w, x, z, opts = {}) {
  w.set(x, 0, z, "turtle"); w.set(x, 0, z - 1, opts.supply || "chest"); w.set(x + 1, 0, z, "chest");
  if (opts.buffer) w.set(x, -1, z, "chest");
}

S["builder-turtle"] = () => {
  const w = new World();
  ground(w, -5, 13, -6, 3);
  storage(w, -4, -6, 1, { computer: false });
  w.set(2, 0, -5, "advancedE"); w.set(2, 1, -5, "modem");
  builderHome(w, 0, 0, { buffer: true });
  w.set(0, 0, -2, "fullmodem"); w.set(0, 0, -3, "cable"); w.set(0, 0, -4, "cable");
  w.set(-4, 0, -5, "fullmodem"); w.set(-4, 0, -4, "ender");
  builderHome(w, 6, 0, { supply: "ender" });
  return {
    title: "Builder turtle: its home",
    world: w,
    headings: [{ at: [0.5, 0, 2.6], text: "next to the storage system" }, { at: [6.5, 0, 2.6], text: "far away: an ender chest" }],
    links: [{ a: [-3.5, 1, -3.5], b: [6.5, 1, -0.5], col: C, text: "same colours (one pair per builder)", bow: 70 }],
    arrows: [facing(0, 0, 0, 1, ""), facing(6, 0, 0, 1, "")],
    labels: [
      { at: [0, 0, 0], text: ["builder turtle on its home block", "wireless or ender modem, some coal"], col: G, off: [-170, 20] },
      { at: [0, 0, -1], text: "supply chest directly behind", col: O, off: [-150, -50] },
      { at: [1, 0, 0], text: "spoil chest on its left", col: O, off: [90, 50] },
      { at: [0, -1, 0], text: ["optional buffer chest", "under the home block"], col: O, off: [-40, 80] },
      { at: [0, 0, -2], text: ["full-block wired modem on the supply chest", "(optional: blocks from storage)"], col: W, off: [130, -20] },
      { at: [-4, 0, -4], text: ["ender chest at home,", "wired modem on the storage cable"], col: C, off: [-110, -20] },
      { at: [1, 1, -6], text: "storage system", col: B, off: [0, -40] },
      { at: [6, 0, -1], text: ["its twin as the supply chest", "builder needs an ender modem"], col: C, off: [100, -30] },
    ],
    notes: ["Then tap Build on the projector (or use build-control). The building can be up to 256 blocks away.", "Needs GPS: it steps forward once to find its facing, so leave room in front.", "Use the linkable kind of ender chest (EnderStorage): a vanilla one belongs to a player and CC can't see into it."],
  };
};

S["blueprint-projector"] = () => {
  const w = new World();
  ground(w, -4, 10, -2, 9, "ggrass");
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem"); w.set(1, 0, 0, "projector");
  w.box(-3, -1, 0, 1, 0, 0, "monitor");
  builderHome(w, 8, 1);
  return {
    title: "Blueprint projector: what to place",
    world: w,
    outlines: [{ box: [-1, 4, 0, 3, 3, 8], col: C, text: ["the projection (here the cottage)", "appears south of the projector"], off: [-140, 0] }],
    arrows: [{ from: [7, 0.05, 4], to: [7, 0.05, 6.5], col: W, text: "south" }],
    labels: [
      { at: [0, 0, 0], text: ["advanced computer", "+ wireless or ender modem"], col: B, off: [-20, -70] },
      { at: [1, 0, 0], text: ["Spatial Projector", "next to it (or on a wired modem)"], col: C, off: [110, -50] },
      { at: [-2, 1, 0], text: ["advanced monitor touching", "the computer: the control panel"], col: Y, off: [-80, -50] },
      { at: [8, 0, 1], text: ["builder turtle at its home", "(optional): builds it on Build"], col: G, off: [70, 60] },
    ],
    notes: ["Bind Spatial Goggles to the projector (right-click it with them) and wear them to see the projection.", "Without a monitor the panel shows on the computer's screen."],
  };
};

S["build-control"] = () => {
  const w = new World();
  ground(w, -3, 12, -4, 9, "ggrass");
  w.set(-1, 0, -2, "pocket");
  builderHome(w, 3, -2); builderHome(w, 6, -2);
  return {
    title: "Build control: placing a building",
    world: w,
    outlines: [{ box: [1, 9, 0, 3, 2, 8], col: Y, text: ["the building grows south and east", "from the corner you type"], off: [-120, 60] }],
    arrows: [
      { from: [1, 0.05, 2], to: [1, 0.05, 0], col: W, text: "north" },
      { from: [1, 0.05, 2], to: [3, 0.05, 2], col: W, text: "east" },
    ],
    labels: [
      { pt: [1, 0, 2], text: ["the north-west bottom corner:", "smallest X and Z, bottom layer's Y", "build <plan> <x> <y> <z>"], col: Y, off: [-170, -20] },
      { at: [-1, 0, -2], text: ["computer or pocket computer", "+ wireless or ender modem"], col: B, off: [-80, -60] },
      { at: [6, 0, -2], text: ["builder turtles at their homes", "supply chest behind, spoil chest left"], col: G, off: [140, -40] },
    ],
    notes: ["Read the corner with F3, looking at the block. A facing word (north, east...) turns the plan; the corner stays where you said."],
  };
};

S["instabuild"] = () => {
  const w = new World();
  ground(w, -3, 14, -3, 9, "ggrass");
  w.set(-1, 0, -1, "command"); w.set(-1, 1, -1, "modem");
  w.set(11, 0, -1, "advanced"); w.set(11, 1, -1, "modem"); w.set(12, 0, -1, "projector"); w.box(9, 10, 0, 1, -1, -1, "monitor");
  return {
    title: "Instabuild: placing a building",
    world: w,
    outlines: [{ box: [2, 8, 0, 3, 2, 7], col: Y, text: ["placed in one go, only into air", "south and east of the corner"], off: [-120, 70] }],
    arrows: [{ from: [2, 0.05, 2], to: [2, 0.05, 0], col: W, text: "north" }, { from: [2, 0.05, 2], to: [4, 0.05, 2], col: W, text: "east" }],
    links: [{ a: [11.5, 1.2, -0.5], b: [-0.5, 1.2, -0.5], col: C, text: "instabuild serve: Build on the projector", bow: 70 }],
    labels: [
      { pt: [2, 0, 2], text: ["north-west bottom corner", "instabuild <plan> <x> <y> <z>"], col: Y, off: [-150, 0] },
      { at: [-1, 0, -1], text: ["command computer (creative)", "anywhere loaded"], col: O, off: [-60, -70] },
      { at: [11, 0, -1], text: ["optional: blueprint projector", "both need a modem (or one cable)"], col: B, off: [60, -70] },
    ],
    notes: ["/give @s computercraft:computer_command. Install the plans you want with 'install plan <name>'.", "'instabuild undo' removes what the last build placed."],
  };
};

S["village-turtle"] = () => {
  const w = new World();
  ground(w, -6, 6, -7, 7, "ggrass");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, -1, "doublechest"); w.set(-1, 0, -1, "doublechest"); w.set(1, 0, 0, "chest"); w.set(0, -1, 0, "chest");
  w.set(0, 0, -2, "fullmodem"); w.box(0, 0, 0, 0, -6, -3, "cable");
  return {
    title: "Village turtle: the village centre",
    world: w,
        arrows: [facing(0, 0, 0, 1, "facing: the village's 'forward'")],
    labels: [
      { at: [0, 0, 0], text: ["village turtle on fairly flat ground", "wireless modem (for storage or a crew)"], col: G, off: [-190, 40] },
      { at: [-1, 0, -1], text: ["supply chest directly behind", "(a double chest is best)"], col: O, off: [-150, -40] },
      { at: [1, 0, 0], text: "spoil chest on its left", col: O, off: [110, 30] },
      { at: [0, -1, 0], text: ["optional buffer chest", "under its home block"], col: O, off: [40, 80] },
      { at: [0, 0, -4], text: ["optional: full-block wired modem on the", "supply chest, cable back to the storage system"], col: W, off: [150, -30] },
    ],
    notes: ["The village spreads out round this spot (radius 48 by default).", "Fill the supply chest with the theme's blocks and coal ('village list medieval'), or let the storage system send them.", "Needs GPS (a modem on the turtle)."],
  };
};

//---------------------------------------------------------------- storage

S["storage-computer"] = () => {
  const w = new World();
  ground(w, -1, 14, -1, 6);
  for (let i = 0; i < 9; i++) { const b = i % 3 === 1 ? "fullmodem" : "chest"; w.set(i, 0, 0, b); w.set(i, 1, 0, b); }
  w.box(1, 11, 0, 0, 1, 1, "cable");
  w.set(12, 0, 1, "advancedE"); w.set(12, 1, 1, "modem"); w.set(13, 0, 1, "monitor"); w.set(13, 1, 1, "monitor");
  const tap = (x, b = "chest") => { w.set(x, 0, 2, "fullmodem"); w.set(x, 0, 3, b); };
  tap(2); tap(5); tap(8); tap(11);
  return {
    title: "Storage system: what to place",
    world: w,
    labels: [
      { at: [3, 1, 0], text: ["storage chests (double chests and barrels work)", "one full-block wired modem between two chests joins both"], col: Y, off: [0, -70] },
      { at: [7, 1, 0], text: "full-block wired modem", col: W, off: [120, -50] },
      { at: [6, 0, 1], text: ["networking cable joining every modem", "right-click each modem: it turns red"], col: W, off: [140, -10] },
      { at: [2, 0, 3], text: ["input chest", "(put things in here)"], col: G, off: [-90, 40] },
      { at: [5, 0, 3], text: ["output chest", "(what you take out)"], col: O, off: [-40, 70] },
      { at: [8, 0, 3], text: ["optional fuel chest", "(coal for furnaces, turtles)"], col: R, off: [40, 80] },
      { at: [11, 0, 3], text: ["optional transfer chest", "(ME / RS, crafting)"], col: P, off: [110, 60] },
      { at: [12, 0, 1], text: ["the computer: small wired modem", "+ wireless (or ender) modem on top"], col: B, off: [80, -80] },
      { at: [13, 1, 1], text: "optional monitor", col: Y, off: [110, -20] },
    ],
    notes: ["A small wired modem only goes on a full block: chests need a full-block modem touching them; barrels take a small one directly.", "Turtles' chests (builders, crafters, remote terminals) find themselves: don't pick them in 'storage setup'.", "ME or RS: an ME Bridge / RS Bridge touching the system, with a wired modem on the cable (see Example layouts)."],
  };
};

S["remote-terminal"] = () => {
  const w = new World();
  ground(w, -1, 14, -2, 3);
  storage(w, 0, -1, 5, { computer: false });
  w.set(6, 0, 0, "advancedE"); w.set(6, 1, 0, "modem");
  w.set(3, 0, 1, "fullmodem"); w.set(3, 0, 2, "ender");
  w.set(12, 0, 1, "advancedE"); w.set(12, 1, 1, "modem"); w.set(13, 0, 1, "ender");
  return {
    title: "Remote terminal: home and away",
    world: w,
    headings: [{ at: [3, 0, 3.6], text: "at home" }, { at: [12.5, 0, 3.2], text: "far away" }],
    links: [{ a: [3.5, 1, 2.5], b: [13.5, 1, 1.5], col: C, text: "an ender chest pair: same three colours", bow: 80 }],
    labels: [
      { at: [6, 0, 0], text: ["storage computer", "+ an ender modem"], col: B, off: [20, -70] },
      { at: [3, 0, 2], text: ["ender chest next to the storage,", "wired modem on the storage cable"], col: C, off: [-100, 60] },
      { at: [12, 0, 1], text: ["this computer", "+ an ender modem"], col: B, off: [-80, -60] },
      { at: [13, 0, 1], text: ["its twin, next to this computer", "(or on its wired network)"], col: C, off: [80, 60] },
    ],
    notes: ["Don't pick the home ender chest in 'storage setup': the storage computer finds it the first time you pull something.", "The linkable kind (EnderStorage): a vanilla ender chest can't be seen by computers. One pair per terminal or builder."],
  };
};

S["craft-terminal"] = () => {
  const w = new World();
  ground(w, -2, 11, -5, 3);
  storage(w, 2, -4, 8, { computer: false });
  w.set(9, 0, -3, "advancedE"); w.set(9, 1, -3, "modem");
  // the craft terminal with a wired modem on its back, its chest on its left with a full-block modem
  w.set(0, 0, 0, "advancedE"); w.set(0, 0, -1, "fullmodem");
  w.set(1, 0, 0, "chest"); w.set(1, 0, -1, "fullmodem");
  w.box(0, 1, 0, 0, -2, -2, "cable"); w.box(1, 2, 0, 0, -3, -3, "cable");
  return {
    title: "Craft terminal: where to put it",
    world: w,
    labels: [
      { at: [0, 0, 0], text: ["the craft terminal (advanced computer)", "wired modem on the storage cable"], col: B, off: [-150, 40] },
      { at: [1, 0, 0], text: ["optional chest touching it: crafts come here", "full-block wired modem on the same cable"], col: O, off: [150, 60] },
      { at: [9, 0, -3], text: "storage computer", col: B, off: [60, -40] },
      { at: [5, 1, -4], text: "storage system", col: B, off: [0, -50] },
    ],
    notes: ["Right-click every modem so it turns red. The storage computer finds the chest itself the first time you order something.", "Without a chest, crafts go into storage. Far away: an ender modem on both computers, and an ender chest whose twin is on the storage cable."],
  };
};

S["cannon-feeder"] = () => {
  const w = new World();
  ground(w, -3, 13, -5, 3);
  storage(w, -3, -5, 6, { computer: false });
  w.set(7, 0, -4, "advancedE"); w.set(7, 1, -4, "modem");
  // near: chest on the cable
  w.set(0, 0, 0, "cannon"); w.set(1, 0, 0, "chest"); w.set(0, 0, 1, "reader"); w.set(1, 0, 1, "computer"); w.set(1, 1, 1, "modem");
  w.set(1, 0, -1, "fullmodem"); w.box(1, 1, 0, 0, -3, -2, "cable");
  // far: an ender chest
  w.set(9, 0, 0, "cannon"); w.set(10, 0, 0, "ender"); w.set(9, 0, 1, "reader"); w.set(10, 0, 1, "computer"); w.set(10, 1, 1, "modem");
  w.set(5, 0, -3, "fullmodem"); w.set(5, 0, -2, "ender");
  return {
    title: "Cannon feeder: where everything goes",
    world: w,
    headings: [{ at: [1, 0, 3], text: "near the storage" }, { at: [10, 0, 3], text: "far away: ender chest" }],
    links: [{ a: [5.5, 1, -1.5], b: [10.5, 1, 0.5], col: C, text: "same colours, used by nothing else", bow: 60 }],
    labels: [
      { at: [0, 0, 0], text: "Schematicannon", col: Y, off: [-110, -40] },
      { at: [1, 0, 0], text: ["chest against the cannon", "(the cannon's own chest)"], col: O, off: [-40, -90] },
      { at: [0, 0, 1], text: ["Block Reader (optional): against", "the cannon, facing it, touching the computer"], col: C, off: [-150, 50] },
      { at: [1, 0, 1], text: ["this computer, against the chest", "+ wired modem on the cable (or wireless)"], col: B, off: [60, 70] },
      { at: [1, 0, -1], text: "full-block wired modem on the chest", col: W, off: [-170, -20] },
      { at: [5, 0, -2], text: ["ender chest's home twin:", "wired modem on the storage cable"], col: C, off: [-60, 70] },
      { at: [10, 0, 0], text: ["ender chest against the cannon", "touching this computer (or on its wired modem)"], col: C, off: [110, -40] },
      { at: [10, 0, 1], text: ["computer + ender modem", "(the storage computer needs one too)"], col: B, off: [90, 50] },
      { at: [7, 0, -4], text: "storage computer", col: B, off: [70, -40] },
    ],
    notes: ["Don't pick the chest in 'storage setup': the storage computer finds it by itself.", "Use the linkable kind of ender chest (EnderStorage): a vanilla ender chest can't be seen by computers.", "With several ender chests on its network, pick the right one with 'cannon chest'."],
  };
};

S["crafter-turtle"] = () => {
  const w = new World();
  ground(w, -2, 11, -5, 3);
  storage(w, 2, -4, 8, { computer: false });
  w.set(9, 0, -3, "advancedE"); w.set(9, 1, -3, "modem");
  w.set(0, 0, 0, "turtle"); w.set(0, 0, 1, "chest"); w.set(1, 0, 1, "fullmodem");
  w.box(1, 1, 0, 0, -2, 0, "cable"); w.set(1, 0, -3, "cable");
  w.set(0, 0, -1, "fullmodem"); w.set(0, 0, -2, "cable"); w.set(0, 0, -3, "cable");
  return {
    title: "Crafting turtle: where to put it",
    world: w,
    arrows: [{ from: [-0.2, 0.05, 0.5], to: [-0.2, 0.05, 2.5], col: G, text: "facing the chest" }],
    labels: [
      { at: [0, 0, 0], text: ["crafty turtle", "+ wireless or ender modem on its other side"], col: G, off: [-170, -20] },
      { at: [0, 0, 1], text: ["the crafter chest: directly in front", "(a barrel works)"], col: O, off: [-120, 60] },
      { at: [1, 0, 1], text: ["full-block wired modem touching the chest", "(not between the chest and the turtle)"], col: W, off: [140, 60] },
      { at: [0, 0, -1], text: ["or: a full-block wired modem against its back", "on the storage cable, instead of wireless"], col: W, off: [-130, -60] },
      { at: [6, 1, -4], text: "storage system", col: B, off: [0, -40] },
    ],
    notes: ["It finds its own chest: nothing to pick in 'storage setup'.", "Far away, with a craft overseer hub: its barrel goes on the overseer's cable instead, and the turtle needs an ender modem."],
  };
};

S["craft-overseer"] = () => {
  const w = new World();
  ground(w, -1, 13, -5, 3);
  storage(w, 0, -4, 10, { computer: false });
  w.set(0, 0, -3, "advancedE"); w.set(0, 1, -3, "modem");
  w.set(11, 0, -3, "advancedE"); w.set(11, 1, -3, "modem"); w.set(12, 0, -3, "monitor"); w.set(12, 1, -3, "monitor");
  for (const x of [3, 6, 9]) { w.set(x, 0, -1, "turtle"); w.set(x, 0, 0, "chest"); w.set(x + 1, 0, 0, "fullmodem"); w.set(x + 1, 0, -1, "cable"); }
  return {
    title: "Craft overseer: next to the storage",
    world: w,
    labels: [
      { at: [11, 0, -3], text: ["the overseer: advanced computer", "wired modem on the storage cable", "+ wireless or ender modem"], col: B, off: [60, -80] },
      { at: [12, 1, -3], text: "optional monitor", col: Y, off: [110, 0] },
      { at: [6, 0, -1], text: ["crafting turtles, each with", "its own chest directly in front"], col: G, off: [-60, -110] },
      { at: [3, 0, 0], text: ["full-block wired modem on each chest", "joined to the storage cable"], col: O, off: [-120, 70] },
      { at: [0, 0, -3], text: "storage computer", col: B, off: [-80, -40] },
    ],
    notes: ["Set up the storage computer and the crafting turtles first. Far from the storage system: see the hub diagram."],
  };
};

function craftOverseerFar() {
  const w = new World();
  ground(w, -1, 15, -5, 3);
  storage(w, 0, -4, 4, { computer: false });
  w.set(0, 0, -3, "advancedE"); w.set(0, 1, -3, "modem");
  w.set(3, 0, -2, "fullmodem"); w.set(3, 0, -1, "ender");
  w.box(8, 14, 0, 0, -3, -3, "cable");
  w.set(8, 0, -4, "advanced"); w.set(8, 1, -4, "modem");
  w.set(9, 0, -2, "fullmodem"); w.set(9, 0, -1, "ender");
  for (const x of [11, 13]) { w.set(x, 0, -2, "barrel"); w.set(x, 1, -2, "modem"); w.set(x, 0, -1, "turtle"); }
  return {
    title: "Craft overseer: far away, one ender chest pair",
    world: w,
    headings: [{ at: [2.5, 0, 2], text: "at the storage system" }, { at: [11.5, 0, 2], text: "at the crafting site" }],
    links: [{ a: [3.5, 1, -0.5], b: [9.5, 1, -0.5], col: C, text: "an ender chest pair, its own colours", bow: 60 }],
    labels: [
      { at: [3, 0, -1], text: ["ender chest, full-block wired", "modem on the storage cable"], col: C, off: [-90, 70] },
      { at: [8, 0, -4], text: ["the overseer: ender modem", "+ wired modem on its own cable", "overseer hub"], col: B, off: [-40, -90] },
      { at: [9, 0, -1], text: ["the twin, wired modem", "on the site's cable"], col: C, off: [-20, 80] },
      { at: [13, 0, -2], text: ["each turtle's barrel, directly in front of it", "with a wired modem on the site's cable"], col: O, off: [80, -70] },
      { at: [13, 0, -1], text: ["crafting turtles", "+ ender or wireless modem"], col: G, off: [100, 50] },
    ],
    notes: ["Keep the crafting site loaded (a chunk loader), or its turtles stop answering.", "Use the linkable kind of ender chest (EnderStorage): a vanilla one can't be seen by computers."],
  };
}

S["factory"] = () => {
  const w = new World();
  ground(w, -2, 19, -3, 4);
  for (let i = 0; i < 4; i++) { const b = i === 1 ? "fullmodem" : "chest"; w.set(i, 0, -1, b); w.set(i, 1, -1, b); }
  w.box(1, 17, 0, 0, 0, 0, "cable");
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem");
  // furnaces
  w.set(2, 0, 1, "furnace"); w.set(2, 1, 1, "modem"); w.set(3, 0, 1, "furnace"); w.set(3, 1, 1, "modem");
  // enrichment chamber: hopper on top, output chest under
  w.set(5, 0, 1, "chest"); w.set(5, 1, 1, "chamber"); w.set(5, 2, 1, "hopper");
  // infuser: feeder on top, infusion feeder on a side, output under
  w.set(8, 0, 1, "chest"); w.set(8, 1, 1, "infuser"); w.set(8, 2, 1, "hopper"); w.set(9, 1, 1, "hopper");
  // work chest
  w.set(7, 0, -1, "chest"); w.set(7, 0, 0, "fullmodem");
  // create crushing line
  w.set(11, 2, 1, "chest"); w.set(11, 1, 1, "wheel"); w.set(12, 1, 1, "wheel"); w.set(11, 0, 1, "chest");
  // botany pots on full-block modems
  w.set(14, 0, 1, "fullmodem"); w.set(14, 1, 1, "botany"); w.set(15, 0, 1, "fullmodem"); w.set(15, 1, 1, "botany");
  // the factory computer
  w.set(18, 0, 0, "advancedE"); w.set(18, 1, 0, "modem"); w.set(18, 0, -1, "monitor"); w.set(18, 1, -1, "monitor");
  return {
    title: "Factory: machines on the storage cable",
    world: w,
    labels: [
      { at: [1, 1, -1], text: "storage system", col: B, off: [-30, -50] },
      { at: [2, 0, 1], text: ["furnaces, blast furnaces, smokers", "a small wired modem on each"], col: GR, off: [-90, 70] },
      { at: [5, 2, 1], text: ["feeder: hopper on top, pointing down", "(or an empty barrel + a pipe)"], col: GR, off: [-80, -80] },
      { at: [5, 1, 1], text: ["Enrichment Chamber / Energized Smelter", "security Public, wired modem on it"], col: W, off: [-180, 20] },
      { at: [5, 0, 1], text: "output chest under it", col: O, off: [-60, 90] },
      { at: [8, 1, 1], text: ["Metallurgic Infuser: feeder on top,", "infusion feeder on a side, output chest under"], col: W, off: [60, 100] },
      { at: [7, 0, -1], text: ["optional work chest", "(empty chest on the cable)"], col: G, off: [20, -80] },
      { at: [11, 1, 1], text: ["Create crushing line: feeder chest", "(funnel onto the wheels), output chest"], col: Y, off: [40, -90] },
      { at: [14, 1, 1], text: ["Hopper Botany Pots, each on", "a full-block wired modem"], col: G, off: [40, 80] },
      { at: [18, 0, 0], text: ["factory computer: wired modem", "on the cable, monitor optional"], col: B, off: [60, -80] },
    ],
    notes: ["Every machine, feeder and output chest gets a wired modem joined to the storage cable: right-click each so it turns red.", "Add Mekanism machines and Create lines on the setup screen (factory setup / F1); furnaces and botany pots are found by themselves.", "Cooking pots: see Example layouts (feed hopper into the side, output hopper under, comparator and redstone relay)."],
  };
};

function factoryFar() {
  const w = new World();
  ground(w, -1, 17, -4, 3);
  storage(w, 0, -3, 4, { computer: false });
  w.set(0, 0, -2, "advancedE"); w.set(0, 1, -2, "modem");
  w.set(3, 0, -1, "fullmodem"); w.set(3, 0, 0, "ender");
  w.box(9, 16, 0, 0, -2, -2, "cable");
  w.set(9, 0, -3, "advanced"); w.set(9, 1, -3, "modem");
  w.set(10, 0, -1, "fullmodem"); w.set(10, 0, 0, "ender");
  w.set(13, 0, -1, "chest"); w.set(13, 1, -1, "chamber"); w.set(13, 2, -1, "hopper");
  w.set(15, 0, -1, "furnace"); w.set(15, 1, -1, "modem"); w.set(16, 0, -1, "furnace"); w.set(16, 1, -1, "modem");
  return {
    title: "Factory: far from the storage system",
    world: w,
    headings: [{ at: [2.5, 0, 2.4], text: "at home" }, { at: [12.5, 0, 2.4], text: "at the far base" }],
    links: [{ a: [3.5, 1, 0.5], b: [10.5, 1, 0.5], col: C, text: "ender chest pair: the work chest", bow: 60 }],
    labels: [
      { at: [0, 0, -2], text: ["storage computer", "+ ender modem"], col: B, off: [-50, -60] },
      { at: [3, 0, 0], text: ["ender chest, wired modem on the storage", "cable; not picked in storage setup"], col: C, off: [-60, 70] },
      { at: [9, 0, -3], text: ["factory computer: ender modem", "+ wired modem on its own cable"], col: B, off: [-60, -80] },
      { at: [10, 0, 0], text: ["the twin: a wired modem on it,", "joined to the factory's cable"], col: C, off: [20, 80] },
      { at: [13, 1, -1], text: ["machines on the far cable", "output chest under each Mekanism machine"], col: W, off: [80, -70] },
    ],
    notes: ["Pick Work chest, Far away on the factory's setup screen (or 'factory chest remote'). Both bases must stay loaded.", "Botany pots can't be far away: they go through the storage input chest."],
  };
}

S["cobble-breeder"] = () => {
  const w = new World();
  ground(w, -2, 9, -3, 6, "ggrass");
  w.set(0, 0, 0, "hopper"); w.set(0, 1, 0, "pasture"); w.set(1, 0, 0, "chest");
  w.set(7, 0, 0, "incubator"); w.set(7, 1, 0, "hopper");
  w.set(4, 0, -2, "chest");
  w.set(3, 0, 3, "command"); w.set(4, 0, 3, "monitor"); w.set(4, 1, 3, "monitor"); w.set(5, 0, 3, "monitor"); w.set(5, 1, 3, "monitor");
  return {
    title: "Cobble breeder: what to place",
    world: w,
    outlines: [{ box: [-1, 8, 0, 0, -3, 5], col: B, floor: true, text: "everything within 8 blocks of the command computer", off: [0, -150] }],
    labels: [
      { at: [0, 1, 0], text: ["pasture with your two breeders", "breeding on"], col: G, off: [-90, -60] },
      { at: [0, 0, 0], text: "hopper under the pasture", col: GR, off: [-120, 40] },
      { at: [1, 0, 0], text: ["egg chest", "(the hopper leads into it)"], col: O, off: [-60, 90] },
      { at: [7, 0, 0], text: ["Cobblemon Incubator, away from the pasture", "(PC Upgrade optional)"], col: C, off: [110, 60] },
      { at: [7, 1, 0], text: "hopper on top, pointing down into it", col: GR, off: [60, -60] },
      { at: [4, 0, -2], text: "optional reject chest", col: R, off: [60, -50] },
      { at: [3, 0, 3], text: ["command computer (creative / op)", "+ advanced monitor next to it"], col: O, off: [-120, 60] },
    ],
    notes: ["Turn egg encryption off first: \"eggEncryptionEnabled\": false in config/cobbreeding/main.json, then /cobbreeding reload.", "'breed setup' finds the pasture and lists the chests and hoppers round it. To teach it a breeder, send it out next to the computer and tap Scan."],
  };
};

//---------------------------------------------------------------- mekanism and mods

S["colony-dashboard"] = () => {
  const w = new World();
  ground(w, -5, 5, -3, 4, "ggrass");
  w.set(0, 0, 0, "advanced"); w.set(0, 1, 0, "modem"); w.set(1, 0, 0, "integrator"); w.set(-1, 0, 0, "speaker");
  w.box(-2, 2, 1, 2, 0, 0, "monitor"); w.set(-2, 0, 0, "gplank"); w.set(2, 0, 0, "gplank");
  return {
    title: "Colony dashboard: what to place",
    world: w,
        labels: [
      { at: [0, 0, 0], text: ["advanced computer", "optional wireless modem (status server)"], col: B, off: [-40, 80] },
      { at: [1, 0, 0], text: ["Colony Integrator touching it", "(Advanced Peripherals)"], col: Y, off: [120, 50] },
      { at: [-1, 0, 0], text: ["optional speaker", "(attack alarm)"], col: GR, off: [-130, 40] },
      { at: [0, 2, 0], text: "advanced monitor next to it, 3 x 2 or bigger", col: Y, off: [0, -70] },
    ],
    notes: ["Place the computer inside your colony's borders. You need Advanced Peripherals alongside MineColonies."],
  };
};

S["fission-guard"] = () => {
  const w = new World();
  ground(w, -1, 12, -1, 7);
  w.box(0, 4, 0, 4, 0, 3, "fcasing"); w.box(1, 3, 1, 3, 3, 3, "fglass"); w.set(2, 0, 3, "fadapter");
  w.set(2, 0, 4, "advanced"); w.set(2, 1, 4, "modem"); w.set(1, 0, 4, "speaker");
  w.box(3, 5, 0, 1, 4, 4, "monitor");
  w.box(8, 10, 0, 2, 0, 2, "mcasing"); w.set(9, 0, 2, "mport"); w.set(9, 0, 3, "fullmodem");
  w.box(2, 2, 0, 0, 5, 5, "cable"); w.box(3, 9, 0, 0, 5, 5, "cable"); w.set(9, 0, 4, "cable");
  return {
    title: "Fission guard: what to place",
    world: w,
    labels: [
      { at: [2, 3, 0], text: "fission reactor", col: GR, off: [-60, -60] },
      { at: [2, 0, 3], text: ["Fission Reactor Logic Adapter in the casing", "(redstone mode: Disabled)"], col: R, off: [-190, -20] },
      { at: [2, 0, 4], text: ["advanced computer touching the adapter", "(or wired modems + cable)"], col: B, off: [-150, 60] },
      { at: [4, 1, 4], text: "advanced monitor, 3 x 2 or bigger", col: Y, off: [100, -60] },
      { at: [1, 0, 4], text: "optional speaker (alarm)", col: GR, off: [-150, 90] },
      { at: [9, 1, 1], text: ["optional: an Induction Port of your matrix", "on the same wired network (pause when full)"], col: C, off: [60, -70] },
      { at: [6, 0, 5], text: "wired modem on the computer, cable", col: W, off: [60, 50] },
    ],
    notes: ["Check the limits in config.lua before the first start. Optional wireless modem for the status server."],
  };
};

S["power-dashboard"] = () => {
  const w = new World();
  ground(w, -6, 6, -1, 8);
  w.box(0, 3, 0, 3, 0, 2, "mcasing"); w.set(1, 0, 2, "mport");
  w.set(1, 0, 3, "advanced"); w.box(2, 4, 0, 1, 3, 3, "monitor");
  w.box(-2, 0, 0, 0, 3, 3, "cable"); w.set(-3, 0, 3, "turbine"); w.set(-3, 1, 3, "turbine"); w.set(-2, 0, 4, "ecube");
  w.box(1, 1, 0, 0, 4, 6, "dust"); w.set(1, 0, 7, "fcasing");
  return {
    title: "Power dashboard: what to place",
    world: w,
    labels: [
      { at: [2, 3, 1], text: "Induction Matrix", col: GR, off: [0, -60] },
      { at: [1, 0, 2], text: "Induction Port", col: C, off: [-120, -30] },
      { at: [1, 0, 3], text: ["advanced computer touching the port", "(or wired modems + cable)"], col: B, off: [-160, 30] },
      { at: [3, 1, 3], text: "advanced monitor, 3 x 2 or bigger", col: Y, off: [110, -40] },
      { at: [-3, 1, 3], text: ["optional: turbine valves and energy cubes", "on the same cable (wired modem on each)"], col: W, off: [-60, -80] },
      { at: [1, 0, 6], text: ["optional: redstone from signalSide", "to your generators (low-power signal)"], col: R, off: [-150, 30] },
      { at: [1, 0, 7], text: "generators", col: GR, off: [90, 30] },
    ],
  };
};

S["fusion-control"] = () => {
  const w = new World();
  ground(w, -1, 8, -1, 7);
  w.box(0, 4, 0, 4, 0, 4, "zcasing"); w.box(1, 3, 1, 3, 4, 4, "fglass"); w.set(2, 0, 4, "zadapter");
  w.set(2, 0, 5, "advanced"); w.set(2, 1, 5, "modem"); w.set(1, 0, 5, "speaker"); w.box(3, 5, 0, 1, 5, 5, "monitor");
  return {
    title: "Fusion control: what to place",
    world: w,
    labels: [
      { at: [2, 3, 0], text: "fusion reactor", col: GR, off: [0, -50] },
      { at: [2, 0, 4], text: ["Fusion Reactor Logic Adapter", "in the casing (or a Reactor Port)"], col: R, off: [-170, -30] },
      { at: [2, 0, 5], text: ["advanced computer touching it", "(or wired modems + cable)"], col: B, off: [-140, 60] },
      { at: [4, 1, 5], text: "advanced monitor, 3 x 2 or bigger", col: Y, off: [110, -40] },
      { at: [1, 0, 5], text: "optional speaker", col: GR, off: [-110, 90] },
    ],
    notes: ["Optional wireless modem (on top here) for the status server."],
  };
};

S["overseer-bridge"] = () => {
  const w = new World();
  ground(w, 0, 0, 0, 0);
  storage(w, 0, -3, 4, { computer: false });
  w.set(5, 0, -2, "advancedE"); w.set(5, 1, -2, "modem");
  w.set(2, 0, 0, "computer"); w.set(2, 1, 0, "modem"); w.box(2, 2, 0, 0, -1, -1, "cable");
  w.set(8, 0, 2, "turtle"); w.set(6, 0, 4, "computer"); w.set(6, 1, 4, "modem");
  return {
    title: "Overseer bridge: what to place",
    world: w,
    links: [{ a: [8.5, 1, 2.5], b: [2.5, 1.2, 0.5], col: C, text: "every rednet message in range", bow: 50 }, { a: [6.5, 1.2, 4.5], b: [2.5, 1.2, 0.5], col: C, bow: 25 }],
    labels: [
      { at: [2, 0, 0], text: ["the bridge: a computer with an ender modem", "(a wireless one only hears what's in range)"], col: B },
      { at: [2, 0, -1], text: ["optional: a wired modem on a cable", "to hear that cable's traffic (e.g. the storage network)"], col: W },
      { at: [8, 0, 2], text: ["the computers and turtles it hears", "(anything with a modem sending on rednet)"], col: G },
      { at: [1, 1, -3], text: "a storage network (optional)", col: Y },
    ],
    notes: ["It posts what it hears with http.post to tools/overseer/server.mjs on your PC, which shows it in the browser: allow the PC's address and port in computercraft-server.toml first (see Setup).", "Set overseer.url and overseer.key to the lines the server prints, run 'overseer test', then reboot."],
  };
};

S["digital-miner-manager"] = () => {
  const w = new World();
  ground(w, -1, 13, -1, 7);
  for (const x0 of [0, 4]) {
    w.box(x0, x0 + 2, 0, 1, 0, 2, "dminer"); w.set(x0 + 1, 1, 2, "dport"); w.set(x0 + 1, 2, 1, "modem");
  }
  w.box(2, 4, 2, 2, 1, 1, "cable"); w.box(6, 7, 2, 2, 1, 1, "cable"); w.box(8, 8, 0, 2, 1, 1, "cable");
  w.set(9, 0, 1, "advancedE"); w.box(10, 12, 0, 1, 1, 1, "monitor");
  w.set(1, 0, 3, "fullmodem"); w.set(1, 1, 3, "chest"); w.box(1, 1, 0, 0, 4, 6, "cable");
  return {
    title: "Digital miner manager: what to place",
    world: w,
    labels: [
      { at: [5, 1, 1], text: ["Digital Miners, security set to Public", "a wired modem on each"], col: W, off: [0, -80] },
      { at: [1, 1, 2], text: ["eject port: middle of its back,", "top row"], col: O, off: [-140, -30] },
      { at: [1, 1, 3], text: ["storage input chest right behind that port", "(or a pipe from it)"], col: G, off: [-150, 50] },
      { at: [1, 0, 6], text: "to the storage cable", col: W, off: [-80, 30] },
      { at: [8, 1, 1], text: "networking cable to the computer", col: W, off: [70, -60] },
      { at: [9, 0, 1], text: ["advanced computer", "wired modem on the cable"], col: B, off: [-20, 80] },
      { at: [11, 1, 1], text: "advanced monitor, 3 x 2 or bigger", col: Y, off: [80, -40] },
    ],
    notes: ["Right-click each modem so it turns red. Without Public security the buttons fail with a security message."],
  };
};

//---------------------------------------------------------------- run

const extra = { "craft-overseer": [["setup-far.svg", craftOverseerFar]], factory: [["setup-far.svg", factoryFar]] };
for (const [name, fn] of Object.entries(S)) {
  if (only && only !== name) continue;
  console.log(name, save(name, "setup.svg", fn()));
  for (const [file, f] of extra[name] || []) console.log(name, file, save(name, file, f()));
}
