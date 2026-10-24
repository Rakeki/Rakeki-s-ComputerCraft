// Tiny isometric voxel renderer, plus the block scenes for each program.
// Scenes are built from the same numbers the programs use (hall size, room
// spacing, branch gaps), scaled down where the real thing is too big to see.
(function () {
  //---------------------------------------------------------------- blocks

  // c: base colour, tex: how the face is speckled, box: [x0, x1, y0, y1, z0, z1] inside the cell
  const BLOCKS = {
    stone: { c: "#7d7d7d", tex: "noise", amt: 0.07 },
    deepslate: { c: "#4f4f57", tex: "noise", amt: 0.09 },
    cobble: { c: "#727272", tex: "noise", amt: 0.16 },
    bedrock: { c: "#3c3c3c", tex: "noise", amt: 0.28 },
    dirt: { c: "#86603f", tex: "noise", amt: 0.12 },
    grass: { c: "#86603f", top: "#67a548", tex: "grass", amt: 0.1 },
    sand: { c: "#d9cc93", tex: "noise", amt: 0.06 },
    bricks: { c: "#7b7b7b", tex: "bricks", amt: 0.05 },
    planks: { c: "#a6834d", tex: "planks", amt: 0.06 },
    log: { c: "#6a5031", top: "#a6834d", tex: "noise", amt: 0.1 },
    coal: { c: "#7d7d7d", tex: "ore", ore: "#262626", amt: 0.07 },
    iron: { c: "#7d7d7d", tex: "ore", ore: "#d8a985", amt: 0.07 },
    gold: { c: "#7d7d7d", tex: "ore", ore: "#f5da3a", amt: 0.07 },
    diamond: { c: "#4f4f57", tex: "ore", ore: "#5de8f0", amt: 0.07 },
    redstone: { c: "#4f4f57", tex: "ore", ore: "#d42a2a", amt: 0.07 },
    water: { c: "#3d6fe0", tex: "noise", amt: 0.05, alpha: 0.72, clear: true },
    lava: { c: "#e66a1c", tex: "noise", amt: 0.12 },
    chest: { c: "#a2702a", tex: "chest", amt: 0.04, box: [0.06, 0.94, 0, 0.88, 0.06, 0.94], clear: true },
    computer: { c: "#b9b9b9", tex: "computer", amt: 0.03 },
    advanced: { c: "#d6b444", tex: "computer", amt: 0.03 },
    turtle: { c: "#a0a0a0", tex: "turtle", amt: 0.03, box: [0.08, 0.92, 0, 0.84, 0.08, 0.92], clear: true },
    modem: { c: "#d4d4d4", top: "#e8e8e8", tex: "noise", amt: 0.03, box: [0.3, 0.7, 0, 0.18, 0.3, 0.7], clear: true },
    torch: { c: "#6b5232", top: "#ffd75e", tex: "flat", box: [0.43, 0.57, 0, 0.62, 0.43, 0.57], clear: true, glow: true },
    hopper: { c: "#454549", tex: "noise", amt: 0.05 },
    cloud: { c: "#f4f4f4", tex: "flat", alpha: 0.85, clear: true, box: [0, 1, 0.3, 0.7, 0, 1] },
    flag: { c: "#dede6c", tex: "flat", box: [0.44, 0.56, 0, 1, 0.44, 0.56], clear: true },
    leaves: { c: "#3f7a2a", tex: "noise", amt: 0.22 },
    sapling: { c: "#4f8f2f", top: "#5fa83a", tex: "flat", box: [0.28, 0.72, 0, 0.66, 0.28, 0.72], clear: true },
    farmland: { c: "#6b4a2c", top: "#4a321c", tex: "noise", amt: 0.12 },
    wheat: { c: "#c9a83e", top: "#dcbf55", tex: "noise", amt: 0.18, box: [0.08, 0.92, 0, 0.82, 0.08, 0.92], clear: true },
    carrots: { c: "#4f9a2f", top: "#e0862a", tex: "noise", amt: 0.16, box: [0.1, 0.9, 0, 0.55, 0.1, 0.9], clear: true },
    potatoes: { c: "#4f9a2f", top: "#cfae62", tex: "noise", amt: 0.16, box: [0.1, 0.9, 0, 0.55, 0.1, 0.9], clear: true },
    sprout: { c: "#6fb33f", tex: "noise", amt: 0.15, box: [0.18, 0.82, 0, 0.26, 0.18, 0.82], clear: true },
  };
  const LIGHT = { top: 1, left: 0.8, right: 0.62 };

  function hexToRgb(h) { return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]; }
  const rgbCache = {};
  const rgb = (h) => rgbCache[h] || (rgbCache[h] = hexToRgb(h));

  // deterministic hash → 0..1
  function hash(a, b, c, d) {
    let h = (a * 374761393 + b * 668265263 + c * 2147483647 + d * 1274126177) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  }
  function rand(seed) {
    let s = seed >>> 0;
    return () => { s = (s + 0x6d2b79f5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }

  //---------------------------------------------------------------- world

  class World {
    constructor() { this.m = new Map(); }
    static k(x, y, z) { return ((x + 512) * 1024 + (y + 512)) * 1024 + (z + 512); }
    set(x, y, z, b) { if (b) this.m.set(World.k(x, y, z), [x, y, z, b]); else this.m.delete(World.k(x, y, z)); }
    get(x, y, z) { const v = this.m.get(World.k(x, y, z)); return v && v[3]; }
    box(x0, x1, y0, y1, z0, z1, b) {
      for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) this.set(x, y, z, typeof b === "function" ? b(x, y, z) : b);
    }
    clone() { const w = new World(); w.m = new Map(this.m); return w; }
    rotated(r) {
      if (!r) return this;
      const w = new World();
      for (const [x, y, z, b] of this.m.values()) {
        let nx = x, nz = z;
        for (let i = 0; i < r; i++) { const t = nx; nx = -nz; nz = t; }
        w.set(nx, y, nz, b);
      }
      return w;
    }
  }

  //---------------------------------------------------------------- render

  const C30 = Math.cos(Math.PI / 6);
  const proj = (x, y, z) => [(x - z) * C30, (x + z) * 0.5 - y];

  function faceColour(b, face, i, j, n, x, y, z, light) {
    const def = BLOCKS[b];
    let col = face === "top" && def.top ? def.top : def.c;
    const h = hash(x * 7 + i, y * 13 + j, z * 3 + n, face.length);
    let shade = 1 + (h - 0.5) * 2 * (def.amt || 0);
    const u = i / n, v = j / n; // u across, v down from the top edge
    switch (def.tex) {
      case "grass":
        if (face !== "top" && v < 0.26) col = "#67a548";
        break;
      case "ore":
        if (h > 0.72 && n > 1) { col = def.ore; shade = 1 + (h - 0.86) * 1.2; }
        break;
      case "planks":
        if (face !== "top" && j % 2 === 1 && n > 2) shade *= 0.88;
        break;
      case "bricks":
        if (n > 2 && (j % 2 === 1 || i === (j % 4 < 2 ? 0 : 2))) shade *= 0.86;
        break;
      case "chest":
        if (face !== "top" && v > 0.3 && v < 0.45) col = "#3c2a11";
        if (face === "left" && v > 0.3 && v < 0.6 && u > 0.38 && u < 0.62) col = "#c9c9c9";
        break;
      case "computer":
      case "turtle":
        if (face === "left") {
          const m = def.tex === "turtle" ? 0.2 : 0.14;
          if (u > m && u < 1 - m && v > m && v < (def.tex === "turtle" ? 0.62 : 0.72)) { col = "#111111"; shade = 1; if (n > 3 && i === 1 && j === 1) col = "#7fcc19"; }
        }
        if (def.tex === "turtle" && face === "right" && v > 0.25 && v < 0.65 && u > 0.2 && u < 0.8) col = "#5a5a5a";
        break;
    }
    const [r, g, bl] = rgb(col);
    const k = shade * light;
    return `rgb(${Math.min(255, r * k) | 0},${Math.min(255, g * k) | 0},${Math.min(255, bl * k) | 0})`;
  }

  // Draws world into canvas, scaled to fit. Returns a projector for overlays.
  function render(canvas, world, opts = {}) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const cssW = opts.width || canvas.clientWidth || 800;
    const blocks = [...world.m.values()];
    if (!blocks.length) return null;

    // bounds in unit projection
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    const fitIn = opts.bounds || blocks;
    for (const [x, y, z] of fitIn) {
      for (const [dx, dy, dz] of [[0, 1, 0], [1, 0, 1], [0, 0, 1], [1, 0, 0], [1, 1, 0], [0, 1, 1]]) {
        const [px, py] = proj(x + dx, y + dy, z + dz);
        if (px < minX) minX = px; if (px > maxX) maxX = px;
        if (py < minY) minY = py; if (py > maxY) maxY = py;
      }
    }
    const pad = opts.pad ?? 0.06;
    const aspect = opts.aspect;
    let T = (cssW * (1 - pad * 2)) / (maxX - minX);
    let cssH = (maxY - minY) * T / (1 - pad * 2);
    if (aspect) {
      cssH = cssW / aspect;
      T = Math.min(T, (cssH * (1 - pad * 2)) / (maxY - minY));
    }
    if (opts.maxH && cssH > opts.maxH) { T *= opts.maxH / cssH; cssH = opts.maxH; }
    canvas.width = Math.round(cssW * dpr);
    canvas.height = Math.round(cssH * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);
    const ox = cssW / 2 - ((minX + maxX) / 2) * T;
    const oy = cssH / 2 - ((minY + maxY) / 2) * T;
    const P = (x, y, z) => { const [px, py] = proj(x, y, z); return [ox + px * T, oy + py * T]; };

    const detail = opts.detail ?? (T >= 13 ? 4 : T >= 7 ? 2 : 1);
    const opaque = (x, y, z) => { const b = world.get(x, y, z); return b && !BLOCKS[b].clear; };
    blocks.sort((a, b) => (a[0] + a[1] + a[2]) - (b[0] + b[1] + b[2]) || a[1] - b[1]);

    if (opts.background) opts.background(ctx, P, T, cssW, cssH);

    for (const [x, y, z, b] of blocks) {
      const def = BLOCKS[b];
      const [bx0, bx1, by0, by1, bz0, bz1] = def.box || [0, 1, 0, 1, 0, 1];
      const X0 = x + bx0, X1 = x + bx1, Y0 = y + by0, Y1 = y + by1, Z0 = z + bz0, Z1 = z + bz1;
      const full = !def.box;
      const faces = [];
      if (!full || !opaque(x, y + 1, z)) faces.push(["top", (u, v) => [X0 + (X1 - X0) * u, Y1, Z0 + (Z1 - Z0) * v]]);
      if (!full || !opaque(x, y, z + 1)) faces.push(["left", (u, v) => [X0 + (X1 - X0) * u, Y1 - (Y1 - Y0) * v, Z1]]);
      if (!full || !opaque(x + 1, y, z)) faces.push(["right", (u, v) => [X1, Y1 - (Y1 - Y0) * v, Z1 - (Z1 - Z0) * u]]);
      if (!faces.length) continue;
      ctx.globalAlpha = def.alpha || 1;
      for (const [face, at] of faces) {
        const n = def.tex === "flat" ? 1 : face === "top" && (def.tex === "computer" || def.tex === "turtle") ? 1 : Math.max(detail, def.tex === "chest" || def.tex === "computer" || def.tex === "turtle" ? Math.min(detail * 2, 8) : detail);
        // whole face first so sub-cell seams never show through
        ctx.fillStyle = faceColour(b, face, 0, 0, 1, x, y, z, LIGHT[face]);
        quad(ctx, P, at, 0, 0, 1, 1);
        if (n > 1) {
          for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
            ctx.fillStyle = faceColour(b, face, i, j, n, x, y, z, LIGHT[face]);
            quad(ctx, P, at, i / n, j / n, (i + 1) / n, (j + 1) / n);
          }
        }
        if (opts.edges !== false && T > 5) {
          ctx.strokeStyle = "rgba(0,0,0,0.18)"; ctx.lineWidth = 0.6;
          quad(ctx, P, at, 0, 0, 1, 1, true);
        }
      }
      if (def.glow) {
        const [gx, gy] = P(x + 0.5, y + 0.7, z + 0.5);
        const g = ctx.createRadialGradient(gx, gy, 0, gx, gy, T * 1.6);
        g.addColorStop(0, "rgba(255,210,90,0.45)"); g.addColorStop(1, "rgba(255,210,90,0)");
        ctx.fillStyle = g; ctx.globalAlpha = 1;
        ctx.fillRect(gx - T * 2, gy - T * 2, T * 4, T * 4);
      }
    }
    ctx.globalAlpha = 1;
    if (opts.overlay) opts.overlay(ctx, P, T, cssW, cssH);
    return { P, T, w: cssW, h: cssH };
  }

  function quad(ctx, P, at, u0, v0, u1, v1, stroke) {
    const a = P(...at(u0, v0)), b = P(...at(u1, v0)), c = P(...at(u1, v1)), d = P(...at(u0, v1));
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.lineTo(d[0], d[1]); ctx.closePath();
    if (stroke) ctx.stroke(); else ctx.fill();
  }

  function label(ctx, x, y, text, colour = "#f0f0f0", bg = "rgba(0,0,0,0.75)") {
    ctx.font = "15px 'Pixelify Sans', monospace";
    const w = ctx.measureText(text).width + 14;
    ctx.fillStyle = bg; ctx.fillRect(x - w / 2, y - 12, w, 22);
    ctx.strokeStyle = "#000"; ctx.lineWidth = 2; ctx.strokeRect(x - w / 2, y - 12, w, 22);
    ctx.fillStyle = colour; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(text, x, y);
  }

  //---------------------------------------------------------------- scenes

  function rock(r, y, deep) {
    const v = r();
    const base = deep ? "deepslate" : "stone";
    if (v < 0.025) return "coal";
    if (v < 0.038) return "iron";
    if (deep && v < 0.046) return "diamond";
    if (deep && v < 0.054) return "redstone";
    if (!deep && v < 0.042) return "gold";
    return base;
  }

  // Excavator: the default 21x21x16 hall, rooms 5 wide x 10 deep x 6 high,
  // 3 per wall on two floors, a 3-wide ledge at the upper floor and split stairs.
  function excavate() {
    const W = 21, H = 16, ROOM_D = 10, UPPER = 7, LEDGE = 3;
    const w = new World(), r = rand(21);
    const lo = -ROOM_D - 2, hi = W + ROOM_D + 1;
    w.box(lo, hi, -1, H - 1, lo, hi, (x, y, z) => y === H - 1 ? "grass" : y >= H - 3 ? "dirt" : rock(r, y, y < 3));
    const air = (x0, x1, y0, y1, z0, z1) => w.box(x0, x1, y0, y1, z0, z1, null);
    air(0, W - 1, 0, H - 1, 0, W - 1);
    // rooms: along each wall at 2..6, 8..12, 14..18; doorway in the middle
    for (const floor of [0, UPPER]) {
      for (const a of [2, 8, 14]) {
        const mid = a + 2;
        air(a, a + 4, floor, floor + 5, -ROOM_D - 1, -2); air(mid, mid, floor, floor + 2, -1, -1);
        air(a, a + 4, floor, floor + 5, W + 1, W + ROOM_D); air(mid, mid, floor, floor + 2, W, W);
        air(-ROOM_D - 1, -2, floor, floor + 5, a, a + 4); air(-1, -1, floor, floor + 2, mid, mid);
        air(W + 1, W + ROOM_D, floor, floor + 5, a, a + 4); air(W, W, floor, floor + 2, mid, mid);
      }
    }
    // ledge
    for (let x = 0; x < W; x++) for (let z = 0; z < W; z++) {
      if (Math.min(x, z, W - 1 - x, W - 1 - z) < LEDGE) w.set(x, UPPER - 1, z, "bricks");
    }
    // split stairs, 2 wide just inside the ledge, 7 steps from the middle to each corner
    const mid = (W - 1) / 2;
    for (let k = 1; k <= 7; k++) {
      for (const along of [mid + 1 + k, mid - 1 - k]) {
        for (const d of [LEDGE, LEDGE + 1]) {
          for (let y = 0; y < k; y++) {
            const m = y === k - 1 ? "planks" : "bricks";
            w.set(along, y, d, m); w.set(along, y, W - 1 - d, m);
            w.set(d, y, along, m); w.set(W - 1 - d, y, along, m);
          }
        }
      }
    }
    // the turtle and its chest at the start corner
    w.set(0, 0, 0, "turtle"); w.set(-1, 0, 0, "chest"); air(-1, -1, 1, 1, 0, 0);
    [[3, 3], [17, 3], [3, 17], [17, 17]].forEach(([x, z]) => w.set(x, UPPER, z, "torch"));
    // the quarter nearest the viewer is cut away (see mount) so you can see in
    return { world: w, cut: Math.floor(W / 2) };
  }

  // Strip miner, scaled down: main tunnel 40 long, branches 12 long, 3 apart.
  function stripmine() {
    const LEN = 40, BR = 12, GAP = 3;
    const w = new World(), r = rand(64);
    w.box(-2, LEN + 1, -1, 2, -BR - 3, BR + 3, (x, y) => (y === -1 ? (r() < 0.5 ? "deepslate" : "stone") : rock(r, y, y < 1)));
    w.set(-1, 0, 0, "chest");
    const steps = [];
    const slice = (cells, tx, tz, torch) => steps.push({ cells, turtle: [tx, 0, tz], torch });
    const branchX = [];
    for (let x = 3; x + 2 < LEN; x += 3 + GAP) branchX.push(x);
    let next = 0;
    for (let x = 0; x < LEN; x++) {
      const cells = [];
      for (let z = -1; z <= 1; z++) for (let y = 0; y <= 2; y++) cells.push([x, y, z]);
      slice(cells, x, 0, x % 8 === 0 && x > 0 ? [x - 1, 0, 0] : null);
      if (next < branchX.length && x === branchX[next] + 3) {
        const bx = branchX[next++];
        for (const dir of [1, -1]) {
          for (let d = 2; d <= BR + 1; d++) {
            const bc = [];
            for (let xx = bx; xx <= bx + 2; xx++) for (let y = 0; y <= 2; y++) bc.push([xx, y, d * dir]);
            slice(bc, bx + 1, d * dir, (d - 1) % 8 === 0 ? [bx + 1, 0, (d - 1) * dir] : null);
          }
        }
      }
    }
    return { world: w, steps };
  }

  // GPS: four hosts high above the start (start +2/+10/+6), the fourth 6 higher.
  function gps() {
    const H = 12;
    const w = new World(), r = rand(5);
    w.box(-3, 15, -3, -1, -3, 15, (x, y) => (y === -1 ? "grass" : y === -2 ? "dirt" : rock(r, y, false)));
    w.set(0, 0, 0, "turtle");
    const hosts = [[2, H, 2, "GPS-1"], [10, H, 2, "GPS-2"], [2, H, 10, "GPS-3"], [6, H + 6, 6, "GPS-4"]];
    for (const [x, y, z] of hosts) { w.set(x, y, z, "computer"); w.set(x, y + 1, z, "modem"); }
    [[13, H + 9, -2], [14, H + 9, -2], [13, H + 9, -1], [-2, H + 3, 13], [-1, H + 3, 13], [-1, H + 3, 14], [0, H + 3, 13]].forEach(([x, y, z]) => w.set(x, y, z, "cloud"));
    return { world: w, hosts, animate: true };
  }

  // AutoMine: three chunks, queued / being mined / mined out, plus a miner in transit.
  function automineScene() {
    const D = 13, w = new World(), r = rand(16);
    const ground = (x, y, z) => (y === 0 ? "bedrock" : y === D ? "grass" : y >= D - 2 ? "dirt" : rock(r, y, y < 5));
    w.box(0, 47, 0, D, -3, 15, ground);
    // chunk 3 (nearest): mined out down to bedrock
    w.box(32, 47, 1, D, 0, 15, null);
    // chunk 2: top layers done, the current layer half way
    w.box(16, 31, 8, D, 0, 15, null);
    w.box(16, 31, 6, 7, 0, 7, null);
    w.set(24, 6, 8, "turtle");
    w.set(8, D + 1, 8, "flag"); w.set(8, D + 2, 8, "flag");
    w.set(30, D + 5, 12, "turtle");
    return {
      world: w,
      labels: [[8, D + 3.4, 8, "queued", "#dede6c"], [24, D + 1.5, 8, "mining", "#f2b233"], [40, D + 1.5, 8, "mined out", "#57a64e"]],
    };
  }

  // Tree farm: the default 4 columns of 6 trees, 3 apart. Lanes run down the
  // left of each column; the turtle is half way up a tree in the third column,
  // with the trees it has visited replanted and some ahead still growing.
  function treefarm() {
    const COLS = 4, ROWS = 6, S = 3, FAR = (ROWS - 1) * S + 2;
    const w = new World(), r = rand(9);
    w.box(-2, (COLS - 1) * S + 3, -2, -1, -3, FAR + 2, (x, y) => (y === -1 ? "grass" : "dirt"));
    w.set(0, 0, -1, "chest");
    // canopies are drawn a little smaller than in game so the lanes show
    const tree = (x, z, trunk) => {
      for (let y = 0; y < trunk; y++) w.set(x, y, z, "log");
      for (let y = trunk - 2; y <= trunk + 1; y++) {
        for (let dx = -2; dx <= 2; dx++) for (let dz = -2; dz <= 2; dz++) {
          const far = Math.abs(dx) + Math.abs(dz);
          const keep = y === trunk + 1 ? far <= 1 : y === trunk ? far <= 1 || (far === 2 && dx && dz && r() < 0.5) : far <= 2 && Math.max(Math.abs(dx), Math.abs(dz)) <= 1 || (far === 2 && r() < 0.3);
          if (keep && (dx || dz || y >= trunk) && !w.get(x + dx, y, z + dz)) w.set(x + dx, y, z + dz, "leaves");
        }
      }
    };
    const visited = 2 * ROWS + 3; // trees done this round, in the order the turtle visits them
    for (let i = 0; i < COLS * ROWS; i++) {
      const c = Math.floor(i / ROWS), j = i % ROWS, row = c % 2 === 0 ? j : ROWS - 1 - j;
      const x = c * S + 1, z = 1 + row * S;
      if (i < visited) w.set(x, 0, z, "sapling");
      else if (i === visited) {
        // being chopped: the bottom of the trunk is gone, the turtle is in it
        tree(x, z, 7);
        w.set(x, 0, z, null); w.set(x, 1, z, null); w.set(x, 2, z, "turtle");
      } else if (r() < 0.7) tree(x, z, 4 + Math.floor(r() * 3));
      else w.set(x, 0, z, "sapling");
    }
    return { world: w.rotated(2) };
  }

  // Crop farm: a 9x9 field with water in the middle, wheat, carrots and
  // potatoes in bands. Behind the turtle it's harvested and replanted.
  function cropfarm() {
    const N = 9, w = new World();
    w.box(-1, N, -1, -1, -2, N, "dirt");
    w.box(-1, N, 0, 0, -2, N, "grass");
    w.box(0, N - 1, 0, 0, 0, N - 1, "farmland");
    const mid = (N - 1) / 2;
    w.set(mid, 0, mid, "water");
    w.set(0, 1, -1, "log"); w.set(0, 2, -1, "chest");
    const at = 3 * N + 4; // the cell the turtle is over, in its snaking order
    for (let i = 0; i < N * N; i++) {
      const z = Math.floor(i / N), x = z % 2 === 0 ? i % N : N - 1 - (i % N);
      if (x === mid && z === mid) continue;
      w.set(x, 1, z, i < at ? "sprout" : z < 3 ? "wheat" : z < 6 ? "carrots" : "potatoes");
      if (i === at) w.set(x, 2, z, "turtle");
    }
    return { world: w.rotated(2) };
  }

  const SCENES = { excavate, stripmine, gps, automine: automineScene, treefarm, cropfarm };

  //---------------------------------------------------------------- mounting

  // Renders a scene into a canvas; returns controls for rotate/replay.
  function mount(canvas, sceneName, opts = {}) {
    const scene = SCENES[sceneName]();
    let rot = opts.rotation || 0;
    let world = scene.world;
    let bounds = null;
    let anim = null;
    let playing = false;
    const turn = (x, z) => { for (let i = 0; i < rot; i++) { const t2 = x; x = -z; z = t2; } return [x, z]; };
    const draw = (t = 0) => {
      let rw = world.rotated(rot);
      if (scene.cut !== undefined) {
        // the hall centre after rotation; the near quarter is +x, +z of it
        const [a, b] = turn(scene.cut, scene.cut), [c, d] = turn(scene.cut + 1, scene.cut + 1);
        const cx = Math.min(a, c), cz = Math.min(b, d);
        if (rw === world) rw = rw.clone();
        for (const [x, y, z] of [...rw.m.values()]) if (x > cx && z > cz && y >= 0) rw.set(x, y, z, null);
      }
      if (!bounds || bounds.rot !== rot) bounds = { rot, list: [...scene.world.rotated(rot).m.values()] };
      const view = render(canvas, rw, {
        width: opts.width || canvas.parentElement.clientWidth,
        aspect: opts.aspect, maxH: opts.maxH, detail: playing ? 2 : opts.detail, pad: opts.pad,
        bounds: bounds.list,
        overlay: (ctx, P, T) => {
          if (opts.labels === false) return;
          if (scene.hosts) {
            for (const [x, y, z, name] of scene.hosts) {
              const [rx, rz] = turn(x, z);
              const [cx, cy] = P(rx + 0.5, y + 0.6, rz + 0.5);
              for (let k = 0; k < 3; k++) {
                const ph = ((t / 2600 + k / 3) % 1);
                ctx.strokeStyle = `rgba(153,178,242,${(1 - ph) * 0.55})`; ctx.lineWidth = 2;
                ctx.beginPath(); ctx.ellipse(cx, cy, ph * T * 9 * 1.22, ph * T * 9 * 0.7, 0, 0, Math.PI * 2); ctx.stroke();
              }
              if (T > 9) label(ctx, cx, name === "GPS-1" ? cy + T * 1.6 : cy - T * 1.9, name, "#99b2f2");
            }
            const [sx, sy] = P(...(() => { const [a, b] = turn(0, 0); return [a + 0.5, 1, b + 0.5]; })());
            const [ex, ey] = P(...(() => { const [a, b] = turn(0, 0); return [a + 0.5, 12, b + 0.5]; })());
            ctx.setLineDash([5, 6]); ctx.strokeStyle = "rgba(240,240,240,0.5)"; ctx.lineWidth = 2;
            ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke(); ctx.setLineDash([]);
          }
          if (scene.labels && T > 6) {
            for (const [x, y, z, text, col] of scene.labels) { const [rx, rz] = turn(x, z); const [lx, ly] = P(rx + 0.5, y, rz + 0.5); label(ctx, lx, ly, text, col); }
          }
        },
      });
      return view;
    };

    function replay() {
      if (!scene.steps) return;
      cancelAnimationFrame(anim);
      clearTimeout(anim);
      world = scene.world.clone();
      playing = true;
      let i = 0, last = 0;
      const turtle = { at: null };
      const perFrame = Math.max(1, Math.ceil(scene.steps.length / 90));
      const tick = (t) => {
        if (t - last > 70) {
          last = t;
          for (let n = 0; n < perFrame && i < scene.steps.length; n++, i++) {
            const st = scene.steps[i];
            for (const [x, y, z] of st.cells) world.set(x, y, z, null);
            if (st.torch) world.set(...st.torch, "torch");
            if (turtle.at) world.set(...turtle.at, null);
            turtle.at = st.turtle; world.set(...st.turtle, "turtle");
          }
          draw();
          if (i >= scene.steps.length) {
            if (turtle.at) world.set(...turtle.at, null);
            world.set(0, 0, 0, "turtle"); playing = false; draw();
            anim = setTimeout(() => replay(), 3500);
            return;
          }
        }
        anim = requestAnimationFrame(tick);
      };
      anim = requestAnimationFrame(tick);
    }

    if (scene.steps) {
      if (opts.animate) replay();
      else {
        world = scene.world.clone();
        for (const st of scene.steps) { for (const [x, y, z] of st.cells) world.set(x, y, z, null); if (st.torch) world.set(...st.torch, "torch"); }
        world.set(0, 0, 0, "turtle");
        draw();
      }
    } else if (scene.animate && opts.animate !== false) {
      const loop = (t) => { draw(t); anim = requestAnimationFrame(loop); };
      // only spend frames while it's on screen
      const io = new IntersectionObserver(([e]) => {
        cancelAnimationFrame(anim);
        if (e.isIntersecting) anim = requestAnimationFrame(loop);
      });
      draw(0); io.observe(canvas);
    } else {
      draw();
    }

    let resizeT;
    window.addEventListener("resize", () => { clearTimeout(resizeT); resizeT = setTimeout(() => draw(), 200); });
    return {
      rotate() { rot = (rot + 1) % 4; bounds = null; draw(); },
      replay,
      hasReplay: !!scene.steps,
    };
  }

  window.Voxel = { mount, render, World, BLOCKS };
})();
