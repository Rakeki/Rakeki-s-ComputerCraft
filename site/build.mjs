// Builds the GitHub Pages site into _site/.
//
//   node site/build.mjs                 build for http://localhost:8080
//   SITE_URL=https://x.y node site/...  build for another address
//
// On GitHub Actions the address comes from GITHUB_REPOSITORY, so the
// installer and every wget command point at the published site.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(ROOT, "site", "src");
const OUT = path.join(ROOT, "_site");
const REPO = process.env.GITHUB_REPOSITORY || "Rakeki/Rakeki-s-ComputerCraft";

function siteUrl() {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/$/, "");
  if (!process.env.GITHUB_REPOSITORY) return "http://localhost:8080";
  const [owner, name] = REPO.split("/");
  const host = `${owner.toLowerCase()}.github.io`;
  return name.toLowerCase() === host ? `https://${host}` : `https://${host}/${name}`;
}
const SITE_URL = siteUrl();

const data = JSON.parse(fs.readFileSync(path.join(ROOT, "site", "programs.json"), "utf8"));

//---------------------------------------------------------------- files

function copyDir(from, to, skip = () => false) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    if (skip(entry.name)) continue;
    const a = path.join(from, entry.name), b = path.join(to, entry.name);
    if (entry.isDirectory()) copyDir(a, b, skip);
    else fs.copyFileSync(a, b);
  }
}

function write(rel, content) {
  const p = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
}

const lineCount = (p) => fs.readFileSync(p, "utf8").replace(/\n$/, "").split("\n").length;

//---------------------------------------------------------------- manifest

// The program itself first, helper files next, startup.lua last.
function programFiles(program) {
  const dir = path.join(ROOT, "computers", program.name);
  const lua = fs.readdirSync(dir).filter((f) => f.endsWith(".lua"));
  const rank = (f) => (f === `${program.command}.lua` ? 0 : f === "startup.lua" ? 2 : 1);
  lua.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  const files = lua.map((f) => ({
    src: `computers/${program.name}/${f}`,
    dest: f,
    lines: lineCount(path.join(dir, f)),
    ...((program.keep || []).includes(f) ? { keep: true } : {}),
  }));
  for (const lib of program.libs) {
    files.push({ src: `lib/${lib}.lua`, dest: `lib/${lib}.lua`, lines: lineCount(path.join(ROOT, "lib", `${lib}.lua`)), lib: true });
  }
  return files;
}

function nextSteps(program) {
  if (program.name === "mine-server") return ["Set the dock in config.lua first: edit config.lua", "Then start it with: reboot"];
  if (program.autostart) return ["Start it with: reboot"];
  return [`Start it with: ${program.command}`];
}

const manifest = { site: SITE_URL, order: [], programs: {} };
for (const program of data.programs) {
  program.files = programFiles(program);
  manifest.order.push(program.name);
  manifest.programs[program.name] = {
    title: program.title,
    device: program.deviceLabel,
    files: program.files.map(({ src, dest, keep }) => ({ src, dest, ...(keep ? { keep } : {}) })),
    next: nextSteps(program),
  };
  if (program.device === "turtle") manifest.programs[program.name].device = "turtle";
}
for (const lib of data.libraries) {
  lib.lines = lineCount(path.join(ROOT, lib.file));
  lib.usedBy = data.programs.filter((p) => p.libs.includes(lib.name)).map((p) => p.name);
}

//---------------------------------------------------------------- zip

// Store-only ZIP writer: enough for a handful of small Lua files.
const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function makeZip(entries) {
  const parts = [], central = [];
  let offset = 0;
  for (const { name, body } of entries) {
    const nameBuf = Buffer.from(name), crc = crc32(body);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(body.length, 18); local.writeUInt32LE(body.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    const dir = Buffer.alloc(46);
    dir.writeUInt32LE(0x02014b50, 0); dir.writeUInt16LE(20, 4); dir.writeUInt16LE(20, 6);
    dir.writeUInt32LE(crc, 16); dir.writeUInt32LE(body.length, 20); dir.writeUInt32LE(body.length, 24);
    dir.writeUInt16LE(nameBuf.length, 28); dir.writeUInt32LE(offset, 42);
    parts.push(local, nameBuf, body);
    central.push(dir, nameBuf);
    offset += 30 + nameBuf.length + body.length;
  }
  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuf.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, centralBuf, end]);
}

//---------------------------------------------------------------- pixel art

// The turtle logo, one character per pixel.
const TURTLE = [
  "................",
  ".kkkkkkkkkkkkkk.",
  ".kGGGGGGGGGGGGk.",
  ".kGggggggggggGk.",
  ".kGgddddddddgGk.",
  ".kGgdllddddgGGk.",
  ".kGgdddddddgGGk.",
  ".kGgddddddddgGk.",
  ".kGggggggggggGk.",
  ".kGGGGGGGGGGGGk.",
  ".kGGsssGGGGGGGk.",
  ".kGGGGGGGGyyGGk.",
  ".kggggggggggggk.",
  ".kkkkkkkkkkkkkk.",
  "................",
  "................",
];
// An advanced computer, a floppy disk (program files) and a book (libraries).
const COMPUTER = [
  "................",
  ".kkkkkkkkkkkkkk.",
  ".kYYYYYYYYYYYYk.",
  ".kYyyyyyyyyyyYk.",
  ".kYydddddddddyk.",
  ".kYydlldddddyYk.",
  ".kYyddddddddyYk.",
  ".kYydddddddddyk.",
  ".kYyddddddddyYk.",
  ".kYyyyyyyyyyyYk.",
  ".kYYYYYYYYYYYYk.",
  ".kYYYYYYYYsssYk.",
  ".kyyyyyyyyyyyyk.",
  ".kkkkkkkkkkkkkk.",
  "................",
  "................",
];
const FLOPPY = [
  "................",
  ".kkkkkkkkkkkkk..",
  ".kBBwwwwwwwBBkk.",
  ".kBBwwwwwgwBBBk.",
  ".kBBwwwwwgwBBBk.",
  ".kBBwwwwwwwBBBk.",
  ".kBBBBBBBBBBBBk.",
  ".kBBBBBBBBBBBBk.",
  ".kBBWWWWWWWWBBk.",
  ".kBBWlllllllWBk.",
  ".kBBWWWWWWWWBBk.",
  ".kBBWlllllWWBBk.",
  ".kBBWWWWWWWWBBk.",
  ".kkkkkkkkkkkkkk.",
  "................",
  "................",
];
const BOOK = [
  "................",
  "...kkkkkkkkkkk..",
  "..kRRRRRRRRRRRk.",
  "..kRrrrrrrrrrRk.",
  "..kRrYYYYYYYrRk.",
  "..kRrrrrrrrrrRk.",
  "..kRrYYYYYrrrRk.",
  "..kRrrrrrrrrrRk.",
  "..kRrrrrrrrrrRk.",
  "..kRrrrrrrrrrRk.",
  "..kRRRRRRRRRRRk.",
  "..kWWWWWWWWWWWk.",
  "..kWwwwwwwwwwWk.",
  "...kkkkkkkkkkk..",
  "................",
  "................",
];
const PIXEL = {
  k: "#1a1a1a", G: "#a8a8a8", g: "#7a7a7a", d: "#111111", l: "#7fcc19", s: "#4c4c4c", y: "#c99a2e",
  Y: "#e8c75a", B: "#3366cc", w: "#d8d8d8", W: "#f0f0f0", R: "#8a3a2a", r: "#a94a35",
};
function pixelSvg(rows) {
  let rects = "";
  rows.forEach((row, y) => [...row].forEach((ch, x) => {
    if (PIXEL[ch]) rects += `<rect x="${x}" y="${y}" width="1.02" height="1.02" fill="${PIXEL[ch]}"/>`;
  }));
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">${rects}</svg>`;
}

//---------------------------------------------------------------- build

fs.rmSync(OUT, { recursive: true, force: true });
copyDir(path.join(SRC, "assets"), path.join(OUT, "assets"));
copyDir(path.join(ROOT, "computers"), path.join(OUT, "computers"), (n) => n === "_template");
copyDir(path.join(ROOT, "lib"), path.join(OUT, "lib"));
copyDir(path.join(ROOT, "tools"), path.join(OUT, "tools"));
write(".nojekyll", "");
write("assets/turtle.svg", pixelSvg(TURTLE).replace(/#c99a2e/g, "#f2b233"));
write("assets/computer.svg", pixelSvg(COMPUTER));
write("assets/floppy.svg", pixelSvg(FLOPPY).replace(/#7fcc19/g, "#4c4c4c"));
write("assets/book.svg", pixelSvg(BOOK).replace(/#c99a2e/g, "#f2b233"));
write("manifest.json", JSON.stringify(manifest, null, 1));
write("install.lua", fs.readFileSync(path.join(ROOT, "site", "install.lua"), "utf8").replace("{{SITE_URL}}", SITE_URL));
write("assets/site-data.js", `window.SITE = ${JSON.stringify({ url: SITE_URL, repo: REPO, ...data })};\n`);

for (const program of data.programs) {
  const entries = program.files.map((f) => ({ name: f.dest, body: fs.readFileSync(path.join(ROOT, f.src)) }));
  write(`zips/${program.name}.zip`, makeZip(entries));
}

function page(template, rel, vars) {
  const depth = rel.split("/").length - 1;
  vars = { ROOT: depth ? "../".repeat(depth) : "./", ...vars };
  const html = fs.readFileSync(path.join(SRC, template), "utf8").replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? "");
  write(rel, html);
}
const esc = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

page("index.html", "index.html", {});
page("404.html", "404.html", { ROOT: `${new URL(SITE_URL).pathname.replace(/\/$/, "")}/` });
for (const p of data.programs) {
  page("page.html", `programs/${p.name}/index.html`, { KIND: "program", NAME: p.name, TITLE: esc(p.title), DESC: esc(p.tagline) });
}
for (const l of data.libraries) {
  page("page.html", `libraries/${l.name}/index.html`, { KIND: "library", NAME: l.name, TITLE: esc(l.title), DESC: esc(l.tagline) });
}

const total = data.programs.reduce((n, p) => n + p.files.length, 0);
console.log(`Built ${data.programs.length} programs (${total} files) for ${SITE_URL} into _site/`);
