// Serves the built website (_site/, from `node site/build.mjs`) to the
// simulated computers' http API, so they install with the real installer.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
export const SITE_DIR = path.join(ROOT, "_site");
export const SITE_URL = "http://localhost:8080";

export function serveSite(world) {
  if (!fs.existsSync(path.join(SITE_DIR, "manifest.json"))) throw new Error("No _site/manifest.json: run node site/build.mjs first");
  const manifest = JSON.parse(fs.readFileSync(path.join(SITE_DIR, "manifest.json"), "utf8"));
  if (manifest.site !== SITE_URL) throw new Error(`_site was built for ${manifest.site}; rebuild it with no SITE_URL for the simulator`);
  world.route(SITE_URL + "/", (req) => {
    const rel = decodeURIComponent(req.path.split("?")[0]);
    const file = path.join(SITE_DIR, rel);
    if (!file.startsWith(SITE_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return { code: 404, body: "Not found" };
    return { code: 200, body: fs.readFileSync(file).toString("latin1") };
  });
  return manifest;
}
