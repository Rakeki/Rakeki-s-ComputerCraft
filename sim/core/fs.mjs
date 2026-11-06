// The fs API for one computer: its own folder on disk as the root, /rom from
// CC's ROM (read only), and any extra mounts (disk drives).
import fs from "node:fs";
import path from "node:path";
import { multi, LuaError } from "./vm.mjs";

// fs.combine's rules: split on / and \, drop ".", resolve "..".
export function normalise(p) {
  const out = [];
  for (const part of String(p).split(/[\\/]+/)) {
    if (part === "" || part === ".") continue;
    if (part === "..") { if (out.length && out[out.length - 1] !== "..") out.pop(); else out.push(".."); continue; }
    out.push(part);
  }
  return out.join("/");
}

export class FileSystem {
  // dynamic: () => more mounts right now (disk drives next to the computer)
  constructor(root, romDir, dynamic) {
    this.mounts = [{ at: "", dir: root, ro: false, drive: "hdd" }, { at: "rom", dir: romDir, ro: true, drive: "rom" }];
    this.dynamic = dynamic || (() => []);
    fs.mkdirSync(root, { recursive: true });
    this.openCount = 0;
  }

  mount(at, dir, ro = false, drive = at) { this.unmount(at); this.mounts.push({ at, dir, ro, drive }); fs.mkdirSync(dir, { recursive: true }); }
  unmount(at) { this.mounts = this.mounts.filter((m) => m.at !== at); }

  resolve(p) {
    const n = normalise(p);
    if (n === ".." || n.startsWith("../")) throw new LuaError(`/${n}: Invalid Path`);
    const all = this.allMounts();
    let best = all[0];
    for (const m of all) if (m.at && (n === m.at || n.startsWith(m.at + "/")) && m.at.length > best.at.length) best = m;
    const rel = best.at ? n.slice(best.at.length).replace(/^\//, "") : n;
    return { n, mount: best, real: path.join(best.dir, rel), isRoot: rel === "" };
  }

  // the mounts directly inside a folder (rom, disk)
  allMounts() { return [...this.mounts, ...this.dynamic()]; }
  childMounts(n) { return this.allMounts().filter((m) => m.at && path.posix.dirname(m.at) === (n || ".")).map((m) => m.at.split("/").pop()); }

  api() {
    const self = this;
    const r = (p) => self.resolve(p);
    const exists = (p) => { const x = r(p); return x.isRoot || fs.existsSync(x.real); };
    const isDir = (p) => { const x = r(p); return x.isRoot || (fs.existsSync(x.real) && fs.statSync(x.real).isDirectory()); };
    const ro = (p) => { const x = r(p); if (x.mount.ro) throw new LuaError(`/${x.n}: Access denied`); return x; };
    const o = {
      combine(...parts) { return normalise(parts.join("/")); },
      getName(p) { const n = normalise(p); return n === "" ? "root" : n.split("/").pop(); },
      getDir(p) { const n = normalise(p); if (n === "") return ".."; const i = n.lastIndexOf("/"); return i < 0 ? "" : n.slice(0, i); },
      exists,
      isDir,
      isReadOnly(p) { return r(p).mount.ro; },
      getDrive(p) { if (!exists(p)) return null; return r(p).mount.drive; },
      getSize(p) { const x = r(p); if (!fs.existsSync(x.real)) throw new LuaError(`/${x.n}: No such file`); const s = fs.statSync(x.real); return s.isDirectory() ? 0 : s.size; },
      getFreeSpace() { return 1000000; },
      getCapacity() { return 1000000; },
      list(p) {
        const x = r(p);
        if (!isDir(p)) throw new LuaError(`/${x.n}: Not a directory`);
        const names = fs.existsSync(x.real) ? fs.readdirSync(x.real) : [];
        return [...new Set([...names, ...self.childMounts(x.n)])].sort();
      },
      makeDir(p) { const x = ro(p); if (fs.existsSync(x.real) && !fs.statSync(x.real).isDirectory()) throw new LuaError(`/${x.n}: File exists`); fs.mkdirSync(x.real, { recursive: true }); },
      delete(p) { const x = ro(p); if (x.isRoot) throw new LuaError(`/${x.n}: Access denied`); fs.rmSync(x.real, { recursive: true, force: true }); },
      move(a, b) {
        const x = ro(a), y = ro(b);
        if (!fs.existsSync(x.real)) throw new LuaError("No such file");
        if (fs.existsSync(y.real)) throw new LuaError("File exists");
        if ((y.n + "/").startsWith(x.n + "/")) throw new LuaError("Can't move a directory inside itself");
        fs.mkdirSync(path.dirname(y.real), { recursive: true });
        fs.renameSync(x.real, y.real);
      },
      copy(a, b) {
        const x = r(a), y = ro(b);
        if (!fs.existsSync(x.real)) throw new LuaError("No such file");
        if (fs.existsSync(y.real)) throw new LuaError("File exists");
        fs.mkdirSync(path.dirname(y.real), { recursive: true });
        fs.cpSync(x.real, y.real, { recursive: true });
      },
      attributes(p) {
        const x = r(p);
        if (!x.isRoot && !fs.existsSync(x.real)) throw new LuaError(`/${x.n}: No such file`);
        const s = fs.statSync(x.isRoot ? x.mount.dir : x.real);
        return { size: s.isDirectory() ? 0 : s.size, isDir: s.isDirectory(), isReadOnly: x.mount.ro, created: s.birthtimeMs, modified: s.mtimeMs, modification: s.mtimeMs };
      },
      find(pattern) {
        const parts = normalise(pattern).split("/").filter(Boolean);
        const re = (g) => new RegExp("^" + g.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$");
        let found = [""];
        for (const part of parts) {
          const next = [];
          for (const base of found) {
            if (!isDir(base)) continue;
            for (const name of o.list(base)) if (re(part).test(name)) next.push(base ? base + "/" + name : name);
          }
          found = next;
        }
        return found.sort();
      },
      open(p, mode) {
        mode = String(mode || "r");
        const x = r(p);
        const binary = mode.includes("b");
        if (mode.startsWith("r")) {
          if (!fs.existsSync(x.real)) return multi(null, `/${x.n}: No such file`);
          if (fs.statSync(x.real).isDirectory()) return multi(null, `/${x.n}: No such file`);
          return handle(fs.readFileSync(x.real).toString("latin1"), null, binary, mode.includes("+"), x);
        }
        if (x.mount.ro) return multi(null, `/${x.n}: Access denied`);
        if (fs.existsSync(x.real) && fs.statSync(x.real).isDirectory()) return multi(null, `/${x.n}: Cannot write to directory`);
        fs.mkdirSync(path.dirname(x.real), { recursive: true });
        const start = mode.startsWith("a") && fs.existsSync(x.real) ? fs.readFileSync(x.real).toString("latin1") : "";
        fs.writeFileSync(x.real, Buffer.from(start, "latin1"));
        return handle(start, x.real, binary, true, x, mode.startsWith("a"));
      },
    };
    o.isDriveRoot = (p) => { const x = r(p); return x.isRoot; };
    return o;

    function handle(data, file, binary, writable, x, append) {
      let pos = append ? data.length : 0, open = true;
      self.openCount++;
      const check = () => { if (!open) throw new LuaError("attempt to use a closed file"); };
      const flush = () => { if (file) fs.writeFileSync(file, Buffer.from(data, "latin1")); };
      const h = {
        close() { check(); flush(); open = false; self.openCount--; },
        seek(whence = "cur", off = 0) {
          check();
          const base = whence === "set" ? 0 : whence === "end" ? data.length : pos;
          pos = Math.max(0, base + off);
          return pos;
        },
      };
      if (!file || writable) {
        h.read = (n) => {
          check();
          if (pos >= data.length) return null;
          if (n === undefined || n === null) { if (binary) return data.charCodeAt(pos++); n = 1; }
          const s = data.slice(pos, pos + n); pos += s.length; return s;
        };
        h.readAll = () => { check(); if (pos >= data.length && data.length > 0) return null; const s = data.slice(pos); pos = data.length; return s; };
        h.readLine = (keep) => {
          check();
          if (pos >= data.length) return null;
          let i = data.indexOf("\n", pos);
          let s;
          if (i < 0) { s = data.slice(pos); pos = data.length; }
          else { s = data.slice(pos, keep ? i + 1 : i); pos = i + 1; }
          if (!keep) s = s.replace(/\r$/, "");
          return s;
        };
      }
      if (file) {
        h.write = (s) => {
          check();
          s = typeof s === "number" && binary ? String.fromCharCode(s & 255) : typeof s === "number" ? String(s) : String(s ?? "");
          data = data.slice(0, pos) + s + data.slice(pos + s.length); pos += s.length;
        };
        h.writeLine = (s) => { h.write(String(s ?? "") + "\n"); };
        h.flush = () => { check(); flush(); };
      }
      return h;
    }
  }
}
