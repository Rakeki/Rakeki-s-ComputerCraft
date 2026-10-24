// Serves _site/ on http://localhost:8080 for previewing. Run `node site/build.mjs` first.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "_site");
const PORT = Number(process.env.PORT) || 8080;
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml", ".md": "text/markdown", ".lua": "text/plain", ".zip": "application/zip" };

http.createServer((req, res) => {
  let p = path.join(OUT, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!p.startsWith(OUT)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p = path.join(p, "index.html");
  if (!fs.existsSync(p)) { res.writeHead(404, { "content-type": "text/html" }); fs.createReadStream(path.join(OUT, "404.html")).pipe(res); return; }
  res.writeHead(200, { "content-type": (TYPES[path.extname(p)] || "application/octet-stream") + "; charset=utf-8", "cache-control": "no-cache" });
  fs.createReadStream(p).pipe(res);
}).listen(PORT, () => console.log(`Serving _site on http://localhost:${PORT}`));
