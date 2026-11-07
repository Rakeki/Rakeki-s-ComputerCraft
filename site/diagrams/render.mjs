// Renders setup diagrams to SVG with the site's own voxel renderer
// (site/src/assets/voxel.js), run in Node with a canvas stand-in that
// records paths, plus numbered markers, a legend, arrows and dashed outlines.
// The scenes are in build.mjs.
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const src = fs.readFileSync(path.join(REPO, "site/src/assets/voxel.js"), "utf8")
  // let a turtle or computer face +x (def.face) as well as +z
  .replace('if (face === "left") {\n          const m = def.tex === "turtle"', 'if (face === (def.face || "left")) {\n          const m = def.tex === "turtle"')
  .replace('face === "right" && v > 0.25', 'face === (def.side || "right") && v > 0.25');
if (!src.includes("def.face ||") || !src.includes("def.side ||")) throw new Error("voxel.js changed: face patch failed");
const sandbox = { window: { devicePixelRatio: 1, addEventListener() {} }, Math, Map, Infinity, Object, Array };
vm.createContext(sandbox);
vm.runInContext(src, sandbox);
export const { render, World, BLOCKS } = sandbox.window.Voxel;

// extra blocks for the setup diagrams (same texture kinds as voxel.js)
const chestBox = [0.06, 0.94, 0, 0.88, 0.06, 0.94];
Object.assign(BLOCKS, {
  gstone: { c: "#6f6f6f", tex: "flat" },
  ggrass: { c: "#86603f", top: "#5f9a42", tex: "grass", amt: 0 },
  gdirt: { c: "#86603f", tex: "flat" },
  gnether: { c: "#6e3533", tex: "flat" },
  gplank: { c: "#9a7847", tex: "flat" },
  gwater: { c: "#3d6fe0", tex: "flat", alpha: 0.75, clear: true },
  ender: { c: "#1f5a52", tex: "chest", amt: 0.04, box: chestBox, clear: true },
  doublechest: { c: "#a2702a", tex: "chest", amt: 0.04, box: [0.06, 0.94, 0, 0.88, 0.06, 0.94], clear: true },
  cannon: { c: "#5c5c64", top: "#7a5c34", tex: "bricks", amt: 0.04 },
  reader: { c: "#5b5b66", tex: "bridge", amt: 0.04 },
  projector: { c: "#3d3d55", top: "#7fd4ff", tex: "me", amt: 0.04 },
  holo: { c: "#7fd4ff", tex: "flat", alpha: 0.22, clear: true },
  ghost: { c: "#f0f0f0", tex: "flat", alpha: 0.13, clear: true },
  chamber: { c: "#a5a9ad", top: "#c2c5c8", tex: "screen", amt: 0.03 },
  esmelter: { c: "#a5a9ad", top: "#c2c5c8", tex: "furnace", amt: 0.03 },
  infuser: { c: "#a5a9ad", top: "#c2c5c8", tex: "bridge", amt: 0.03 },
  fcasing: { c: "#6a7680", tex: "bricks", amt: 0.04 },
  fadapter: { c: "#6a7680", tex: "ore", ore: "#d42a2a", amt: 0.04 },
  fglass: { c: "#9fd4e0", tex: "flat", alpha: 0.4, clear: true },
  mcasing: { c: "#3b4a5c", tex: "bricks", amt: 0.04 },
  mport: { c: "#3b4a5c", tex: "bridge", amt: 0.04 },
  turbine: { c: "#7a8a94", tex: "bridge", amt: 0.04 },
  ecube: { c: "#4c4c4c", top: "#7fcc19", tex: "me", amt: 0.04 },
  zcasing: { c: "#7d6a58", tex: "bricks", amt: 0.04 },
  zadapter: { c: "#7d6a58", tex: "ore", ore: "#d42a2a", amt: 0.04 },
  dminer: { c: "#9aa0a6", top: "#b8bcc2", tex: "noise", amt: 0.04 },
  dport: { c: "#9aa0a6", tex: "ore", ore: "#e66a1c", amt: 0.04 },
  integrator: { c: "#6a5031", tex: "ore", ore: "#f5da3a", amt: 0.06 },
  speaker: { c: "#5a3d26", tex: "noise", amt: 0.12 },
  pasture: { c: "#a6834d", top: "#67a548", tex: "planks", amt: 0.06, box: [0, 1, 0, 0.6, 0, 1], clear: true },
  incubator: { c: "#cfd2da", top: "#9fe0ff", tex: "noise", amt: 0.05, box: [0.1, 0.9, 0, 0.9, 0.1, 0.9], clear: true },
  command: { c: "#c9884a", tex: "computer", amt: 0.03 },
  pocket: { c: "#d6b444", tex: "computer", amt: 0.03, box: [0.25, 0.75, 0, 0.8, 0.42, 0.58], clear: true },
  botany: { c: "#9b5a3a", top: "#4f8f2f", tex: "noise", amt: 0.06, box: [0.15, 0.85, 0, 0.6, 0.15, 0.85], clear: true },
  wheel: { c: "#7a6a4a", top: "#9a8a6a", tex: "barrel", amt: 0.04 },
  fan: { c: "#6e6e6e", tex: "bridge", amt: 0.04 },
  funnel: { c: "#a08a52", tex: "flat", box: [0.15, 0.85, 0, 0.5, 0.15, 0.85], clear: true },
  dust: { c: "#b3261e", tex: "flat", box: [0.1, 0.9, 0, 0.06, 0.1, 0.9], clear: true },
  campfire: { c: "#6a5031", top: "#f2b233", tex: "flat", box: [0, 1, 0, 0.4, 0, 1], clear: true },
  monitorn: { c: "#b9b9b9", tex: "screen", amt: 0.03 },
  rail: { c: "#8a8a8a", tex: "flat", box: [0, 1, 0, 0.08, 0, 1], clear: true },
  station: { c: "#4c4366", tex: "me", amt: 0.05 },
  diskdrive: { c: "#b9b9b9", tex: "furnace", amt: 0.03 },
});
// facing +x
BLOCKS.turtleE = { ...BLOCKS.turtle, face: "right", side: "left" };
BLOCKS.computerE = { ...BLOCKS.computer, face: "right" };
BLOCKS.advancedE = { ...BLOCKS.advanced, face: "right" };
BLOCKS.commandE = { ...BLOCKS.command, face: "right" };

export const COL = { Y: "#dede6c", B: "#99b2f2", G: "#7fcc19", O: "#f2b233", R: "#ff6b6b", P: "#e57fd8", W: "#f0f0f0", C: "#4cc2d6", GR: "#bbbbbb" };

//---------------------------------------------------------------- canvas stand-in

const hex = (s) => {
  const m = /rgb\((\d+),(\d+),(\d+)\)/.exec(s);
  if (!m) return s;
  return "#" + [m[1], m[2], m[3]].map((v) => (+v).toString(16).padStart(2, "0")).join("");
};
const f1 = (v) => (Math.round(v * 10) / 10).toString();

function svgCtx(out) {
  let pathPts = [];
  let base = null; // colour of the whole-face fill: sub-cells the same colour are skipped
  const ctx = {
    fillStyle: "#000", strokeStyle: "#000", lineWidth: 1, globalAlpha: 1, font: "", textAlign: "left", textBaseline: "alphabetic",
    setTransform() {}, clearRect() {}, setLineDash() {},
    beginPath() { pathPts = []; },
    moveTo(x, y) { pathPts.push(["M", x, y]); },
    lineTo(x, y) { pathPts.push(["L", x, y]); },
    closePath() { pathPts.push(["Z"]); },
    fill() {
      const col = hex(ctx.fillStyle);
      if (base === col) return;
      if (base === null) base = col;
      const d = pathPts.map((p) => (p[0] === "Z" ? "Z" : p[0] + f1(p[1]) + "," + f1(p[2]))).join("");
      out.push(`<path d="${d}" fill="${col}"${ctx.globalAlpha < 1 ? ` fill-opacity="${ctx.globalAlpha}"` : ""}/>`);
    },
    stroke() {
      base = null;
      const d = pathPts.map((p) => (p[0] === "Z" ? "Z" : p[0] + f1(p[1]) + "," + f1(p[2]))).join("");
      out.push(`<path d="${d}" fill="none" stroke="#000" stroke-opacity="0.2" stroke-width="0.6"/>`);
    },
    createRadialGradient(x, y, r0, x1, y1, r) { return { glow: true, x, y, r, addColorStop() {} }; },
    fillRect(x, y, w, h) {
      if (ctx.fillStyle && ctx.fillStyle.glow) { const g = ctx.fillStyle; out.push(`<circle cx="${f1(g.x)}" cy="${f1(g.y)}" r="${f1(g.r)}" fill="url(#glow)"/>`); }
    },
    measureText(t) { return { width: t.length * 8 }; },
    fillText() {}, strokeRect() {}, ellipse() {},
  };
  return ctx;
}

//---------------------------------------------------------------- diagram

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const FONT = "ui-monospace, Menlo, Consolas, 'Courier New', monospace";
const CH = 7.25; // px per character at 12px

function wrap(text, max) {
  const words = text.split(" "), lines = [];
  let cur = "";
  for (const w of words) {
    if ((cur + " " + w).trim().length > max) { lines.push(cur); cur = w; } else cur = (cur + " " + w).trim();
  }
  if (cur) lines.push(cur);
  return lines;
}

// scene: { title, world, labels, arrows, outlines, links, headings, notes, width, maxH }
// labels:   { at: [x,y,z], text, col, off: [dx,dy] }  (at = a block; anchors on its middle)
// arrows:   { from: [x,y,z], to: [x,y,z], col, text }  (world points)
// outlines: { box: [x0,x1,y0,y1,z0,z1], col, text, off }  (cells, inclusive)
// links:    { a: [x,y,z], b: [x,y,z], col, text }  dashed line between two points
// headings: { at: [x,y,z], text }  group names on the ground
export function diagram(sc) {
  const W = sc.width || 980;
  const out = [];
  layGround(sc);
  const world = sc.world;
  const bounds = [...world.m.values()].map((v) => v.slice(0, 3));
  for (const o of sc.outlines || []) { const [x0, x1, y0, y1, z0, z1] = o.box; bounds.push([x0, y0, z0], [x1, y1, z1]); }
  for (const a of sc.extraBounds || []) bounds.push(a);
  const canvas = { clientWidth: W, width: 0, height: 0, getContext: () => svgCtx(out) };
  let view;
  view = render(canvas, world, { width: W, maxH: sc.maxH || 560, pad: sc.pad ?? 0.05, detail: 4, bounds, edges: true });
  const { P, T, h } = view;
  const ov = [];
  const marks = []; // numbered markers on the picture, explained in the legend
  const tags = []; // short text drawn on the picture (arrows, links)

  for (const o of sc.outlines || []) {
    const [x0, x1, y0, y1, z0, z1] = o.box;
    const X = [x0, x1 + 1], Y = [y0, y1 + 1], Z = [z0, z1 + 1];
    const e = [];
    for (const y of Y) for (const z of Z) e.push([[X[0], y, z], [X[1], y, z]]);
    for (const x of X) for (const z of Z) e.push([[x, Y[0], z], [x, Y[1], z]]);
    for (const x of X) for (const y of Y) e.push([[x, y, Z[0]], [x, y, Z[1]]]);
    const col = o.col || COL.W;
    if (o.floor !== false) {
      const q = [[X[0], Y[0], Z[0]], [X[1], Y[0], Z[0]], [X[1], Y[0], Z[1]], [X[0], Y[0], Z[1]]].map((p) => P(...p));
      ov.push(`<path d="M${q.map((p) => f1(p[0]) + "," + f1(p[1])).join("L")}Z" fill="${col}" fill-opacity="0.10"/>`);
    }
    for (const [a, b] of e) {
      const [ax, ay] = P(...a), [bx, by] = P(...b);
      ov.push(`<line x1="${f1(ax)}" y1="${f1(ay)}" x2="${f1(bx)}" y2="${f1(by)}" stroke="${col}" stroke-width="1.6" stroke-dasharray="5 4" stroke-opacity="0.85"/>`);
    }
    if (o.text) marks.push({ ax: o.mark ? P(...o.mark) : P((X[0] + X[1]) / 2, Y[1], (Z[0] + Z[1]) / 2), text: o.text, col });
  }
  for (const l of sc.links || []) {
    const [ax, ay] = P(...l.a), [bx, by] = P(...l.b);
    const top = Math.min(ay, by) - (l.bow ?? 50);
    const d = `M${f1(ax)},${f1(ay)}Q${f1((ax + bx) / 2)},${f1(top)} ${f1(bx)},${f1(by)}`;
    ov.push(`<path d="${d}" fill="none" stroke="#000" stroke-width="4.5" stroke-opacity="0.6"/><path d="${d}" fill="none" stroke="${l.col || COL.C}" stroke-width="2.2" stroke-dasharray="7 5"/>`);
    if (l.text) tags.push({ x: (ax + bx) / 2, y: (Math.min(ay, by) + top) / 2 + (l.dy || 0), text: l.text, col: l.col || COL.C });
  }
  for (const a of sc.arrows || []) {
    const [ax, ay] = P(...a.from), [bx, by] = P(...a.to);
    const col = a.col || COL.G;
    const ang = Math.atan2(by - ay, bx - ax), s = 11;
    const h1 = [bx - s * Math.cos(ang - 0.45), by - s * Math.sin(ang - 0.45)], h2 = [bx - s * Math.cos(ang + 0.45), by - s * Math.sin(ang + 0.45)];
    ov.push(`<line x1="${f1(ax)}" y1="${f1(ay)}" x2="${f1(bx)}" y2="${f1(by)}" stroke="#000" stroke-width="6" stroke-linecap="round"/><line x1="${f1(ax)}" y1="${f1(ay)}" x2="${f1(bx)}" y2="${f1(by)}" stroke="${col}" stroke-width="3" stroke-linecap="round"/><path d="M${f1(bx)},${f1(by)}L${f1(h1[0])},${f1(h1[1])}L${f1(h2[0])},${f1(h2[1])}Z" fill="${col}" stroke="#000" stroke-width="1.2"/>`);
    if (a.text) {
      // past the arrowhead, on the side it points to
      const dx = Math.cos(ang), dy = Math.sin(ang);
      tags.push({ x: bx + dx * 14, y: by + dy * 12 + 4, text: a.text, col, anchor: dx < -0.3 ? "end" : dx > 0.3 ? "start" : "middle" });
    }
  }
  for (const l of sc.labels || []) {
    const [x, y, z] = l.at || l.pt;
    marks.push({ ax: l.pt ? P(x, y, z) : P(x + 0.5, y + (l.mid ? 0.5 : 1), z + 0.5), text: l.text, col: l.col || COL.W });
  }

  // markers: on their anchor, pushed apart a little where they'd overlap
  const R0 = 11;
  marks.forEach((m, i) => { m.n = i + 1; m.x = m.ax[0]; m.y = m.ax[1]; });
  for (let it = 0; it < 60; it++) {
    let moved = false;
    for (let i = 0; i < marks.length; i++) for (let j = i + 1; j < marks.length; j++) {
      const a = marks[i], b = marks[j];
      let dx = b.x - a.x, dy = b.y - a.y;
      let d = Math.hypot(dx, dy);
      if (d < 0.01) { dx = 1; dy = 0; d = 1; }
      if (d < R0 * 2 + 3) { moved = true; const push = (R0 * 2 + 3 - d) / 2; dx /= d; dy /= d; a.x -= dx * push; a.y -= dy * push; b.x += dx * push; b.y += dy * push; }
    }
    if (!moved) break;
  }
  const top = [];
  for (const m of marks) {
    if (Math.hypot(m.x - m.ax[0], m.y - m.ax[1]) > 5) ov.push(`<line x1="${f1(m.ax[0])}" y1="${f1(m.ax[1])}" x2="${f1(m.x)}" y2="${f1(m.y)}" stroke="#000" stroke-width="3"/><line x1="${f1(m.ax[0])}" y1="${f1(m.ax[1])}" x2="${f1(m.x)}" y2="${f1(m.y)}" stroke="${m.col}" stroke-width="1.3"/>`);
    top.push(`<circle cx="${f1(m.x)}" cy="${f1(m.y)}" r="${R0}" fill="${m.col}" stroke="#000" stroke-width="2"/><text x="${f1(m.x)}" y="${f1(m.y + 4.5)}" text-anchor="middle" font-size="13" font-weight="bold" fill="#000">${m.n}</text>`);
  }
  for (const t of tags) {
    const wdt = t.text.length * CH + 10, x0 = t.anchor === "end" ? t.x - wdt + 5 : t.anchor === "start" ? t.x - 5 : t.x - wdt / 2;
    top.push(`<rect x="${f1(x0)}" y="${f1(t.y - 13)}" width="${f1(wdt)}" height="18" fill="#000" fill-opacity="0.75"/><text x="${f1(x0 + 5)}" y="${f1(t.y)}" fill="${t.col}">${esc(t.text)}</text>`);
  }
  for (const hd of sc.headings || []) {
    const [hx, hy] = P(...hd.at);
    top.push(`<text x="${f1(hx)}" y="${f1(hy)}" text-anchor="middle" font-size="15" font-weight="bold" fill="${hd.col || COL.W}" stroke="#000" stroke-width="4" paint-order="stroke">${esc(hd.text)}</text>`);
  }

  // the legend: two columns of numbered entries, then the notes
  const HEAD = 44, colW = (W - 54) / 2, maxCh = Math.floor((colW - 34) / CH);
  const entries = marks.map((m) => {
    const parts = Array.isArray(m.text) ? m.text : [m.text];
    const lines = [];
    parts.forEach((p, i) => wrap(p, maxCh).forEach((s) => lines.push([s, i === 0])));
    return { m, lines, h: lines.length * 16 + 8 };
  });
  const half = Math.ceil(entries.length / 2);
  const cols = [entries.slice(0, half), entries.slice(half)];
  const legH = Math.max(0, ...cols.map((c) => c.reduce((s, e) => s + e.h, 0)));
  const leg = [];
  const y0 = HEAD + h + 14;
  cols.forEach((c, ci) => {
    let y = y0;
    const x = 18 + ci * (colW + 18);
    for (const e of c) {
      leg.push(`<circle cx="${f1(x + 10)}" cy="${f1(y + 8)}" r="10" fill="${e.m.col}" stroke="#000" stroke-width="1.5"/><text x="${f1(x + 10)}" y="${f1(y + 12.5)}" text-anchor="middle" font-size="12" font-weight="bold" fill="#000">${e.m.n}</text>`);
      e.lines.forEach(([s, first], i) => leg.push(`<text x="${f1(x + 28)}" y="${f1(y + 12 + i * 16)}" fill="${first ? e.m.col : "#b4b4c0"}">${esc(s)}</text>`));
      y += e.h;
    }
  });
  const noteLines = [];
  for (const n of sc.notes || []) wrap(n, Math.floor((W - 48) / CH) - 3).forEach((s, i) => noteLines.push((i ? "   " : " • ") + s));
  const notesY = y0 + legH + (legH ? 6 : -8);
  const H = Math.round(notesY + (noteLines.length ? noteLines.length * 17 + 16 : 6));
  const svg = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" font-family="${FONT}" font-size="12">`,
    `<defs><radialGradient id="bg" cx="50%" cy="20%" r="80%"><stop offset="0" stop-color="#24242e"/><stop offset="1" stop-color="#0f0f13"/></radialGradient>`,
    `<radialGradient id="glow"><stop offset="0" stop-color="#ffd25a" stop-opacity="0.45"/><stop offset="1" stop-color="#ffd25a" stop-opacity="0"/></radialGradient></defs>`,
    `<rect width="${W}" height="${H}" fill="url(#bg)"/>`,
    `<text x="18" y="29" font-size="18" font-weight="bold" fill="#f0f0f0">${esc(sc.title)}</text>`,
    `<g transform="translate(0,${HEAD})">`, ...out, ...ov, ...top, `</g>`,
    `<line x1="18" y1="${HEAD + h + 4}" x2="${W - 18}" y2="${HEAD + h + 4}" stroke="#33333d" stroke-width="1"/>`,
    ...leg,
    noteLines.length && legH ? `<line x1="18" y1="${notesY}" x2="${W - 18}" y2="${notesY}" stroke="#2a2a33" stroke-width="1"/>` : "",
    ...noteLines.map((s, i) => `<text x="18" y="${f1(notesY + 18 + i * 17)}" fill="#c8c8d0" xml:space="preserve">${esc(s)}</text>`),
    `</svg>`,
  ];
  return svg.join("");
}

export function save(name, file, sc) {
  const dir = path.join(REPO, "computers", name, "preview");
  fs.mkdirSync(dir, { recursive: true });
  const svg = diagram(sc);
  fs.writeFileSync(path.join(dir, file), svg);
  return svg.length;
}

// helpers for scenes
// a ground plate under everything in the scene, 1 block wider all round
// (laid when the scene is saved; the coordinates given are ignored)
export function ground(w, x0, x1, z0, z1, b = "gstone", y = -1) { w.groundKind = b; w.groundY = y; }
function layGround(sc) {
  const w = sc.world;
  if (!w.groundKind) return;
  let a = Infinity, b = -Infinity, c = Infinity, d = -Infinity;
  const add = (x, z) => { a = Math.min(a, x); b = Math.max(b, x); c = Math.min(c, z); d = Math.max(d, z); };
  for (const [x, , z] of w.m.values()) add(x, z);
  for (const o of sc.outlines || []) { add(o.box[0], o.box[4]); add(o.box[1], o.box[5]); }
  const m = sc.margin ?? 1;
  for (let x = a - m; x <= b + m; x++) for (let z = c - m; z <= d + m; z++) if (!w.get(x, w.groundY, z)) w.set(x, w.groundY, z, w.groundKind);
}
