// Serves the replay viewer on http://localhost:8081:
//   /                 sim/viewer/
//   /voxel.js         the site's voxel renderer (site/src/assets/voxel.js)
//   /replays/x.json   recordings from node sim/replay.mjs (sim/out/replays/)
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const PORT = Number(process.env.PORT || 8081);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json" };

http.createServer((req, res) => {
  const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
  let file;
  if (url === "/" || url === "/index.html") file = path.join(HERE, "index.html");
  else if (url === "/voxel.js") file = path.join(ROOT, "site", "src", "assets", "voxel.js");
  else if (url.startsWith("/replays/")) file = path.join(HERE, "..", "out", "replays", path.basename(url));
  else file = path.join(HERE, path.basename(url));
  if (!fs.existsSync(file)) { res.writeHead(404); res.end("Not found"); return; }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
  fs.createReadStream(file).pipe(res);
}).listen(PORT, () => console.log(`Replay viewer on http://localhost:${PORT}/?replay=bootstrap`));
