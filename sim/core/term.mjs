// A CC terminal: text, colours, cursor. Used for each computer's screen and
// each monitor. Text is kept as rows of characters plus blit colour rows.
import { multi, LuaError } from "./vm.mjs";

const HEX = "0123456789abcdef";
const toHex = (c) => HEX[Math.max(0, Math.round(Math.log2(c)))] || "0";
const fromHex = (h) => 2 ** HEX.indexOf(h.toLowerCase());

export const DEFAULT_PALETTE = [
  0xf0f0f0, 0xf2b233, 0xe57fd8, 0x99b2f2, 0xdede6c, 0x7fcc19, 0xf2b2cc, 0x4c4c4c,
  0x999999, 0x4c99b2, 0xb266e5, 0x3366cc, 0x7f664c, 0x57a64e, 0xcc4c4c, 0x111111,
];

export class Term {
  constructor(w, h, colour = true) {
    this.colour = colour;
    this.palette = [...DEFAULT_PALETTE];
    this.resize(w, h);
    this.x = 1; this.y = 1; this.fg = "0"; this.bg = "f"; this.blink = false;
    this.changed = 0;
  }

  resize(w, h) {
    this.w = w; this.h = h;
    this.text = Array.from({ length: h }, () => " ".repeat(w));
    this.fgs = Array.from({ length: h }, () => "0".repeat(w));
    this.bgs = Array.from({ length: h }, () => "f".repeat(w));
  }

  put(s, fg, bg) {
    const y = this.y - 1;
    if (y < 0 || y >= this.h) { this.x += s.length; return; }
    let x = this.x - 1;
    let t = this.text[y], f = this.fgs[y], b = this.bgs[y];
    for (let i = 0; i < s.length; i++, x++) {
      if (x < 0 || x >= this.w) continue;
      t = t.slice(0, x) + s[i] + t.slice(x + 1);
      f = f.slice(0, x) + (fg ? fg[i] : this.fg) + f.slice(x + 1);
      b = b.slice(0, x) + (bg ? bg[i] : this.bg) + b.slice(x + 1);
    }
    this.text[y] = t; this.fgs[y] = f; this.bgs[y] = b;
    this.x += s.length;
    this.changed++;
  }

  lines() { return this.text.map((l) => l.replace(/\s+$/, "")); }
  dump() { return this.lines().join("\n").replace(/\n+$/, ""); }

  // The term native table (also a monitor's methods).
  api() {
    const t = this;
    const str = (v) => (typeof v === "number" ? String(v) : String(v ?? ""));
    const colour = (c, n) => {
      if (typeof c !== "number") throw new LuaError(`bad argument #${n} (number expected, got ${c === null ? "nil" : typeof c})`);
      return c;
    };
    const o = {
      write(s) { t.put(str(s).replace(/[\n\r\t]/g, " ")); },
      blit(s, fg, bg) {
        s = str(s); fg = str(fg); bg = str(bg);
        if (fg.length !== s.length || bg.length !== s.length) throw new LuaError("Arguments must be the same length");
        t.put(s, fg.toLowerCase(), bg.toLowerCase());
      },
      clear() { for (let y = 0; y < t.h; y++) { t.text[y] = " ".repeat(t.w); t.fgs[y] = t.fg.repeat(t.w); t.bgs[y] = t.bg.repeat(t.w); } t.changed++; },
      clearLine() { const y = t.y - 1; if (y >= 0 && y < t.h) { t.text[y] = " ".repeat(t.w); t.fgs[y] = t.fg.repeat(t.w); t.bgs[y] = t.bg.repeat(t.w); } t.changed++; },
      getCursorPos: () => multi(t.x, t.y),
      setCursorPos(x, y) { t.x = Math.floor(x); t.y = Math.floor(y); },
      getCursorBlink: () => t.blink,
      setCursorBlink(b) { t.blink = !!b; },
      getSize: () => multi(t.w, t.h),
      scroll(n) {
        n = Math.floor(n);
        const blank = () => [" ".repeat(t.w), t.fg.repeat(t.w), t.bg.repeat(t.w)];
        for (const [arr, i] of [[t.text, 0], [t.fgs, 1], [t.bgs, 2]]) {
          if (n > 0) { arr.splice(0, Math.min(n, t.h)); while (arr.length < t.h) arr.push(blank()[i]); }
          else if (n < 0) { for (let k = 0; k < Math.min(-n, t.h); k++) arr.unshift(blank()[i]); arr.length = t.h; }
        }
        t.changed++;
      },
      isColour: () => t.colour,
      setTextColour(c) { t.fg = toHex(colour(c, 1)); },
      getTextColour: () => fromHex(t.fg),
      setBackgroundColour(c) { t.bg = toHex(colour(c, 1)); },
      getBackgroundColour: () => fromHex(t.bg),
      setPaletteColour(c, r, g, b) {
        const i = Math.round(Math.log2(c));
        if (g === undefined || g === null) t.palette[i] = r;
        else t.palette[i] = (Math.round(r * 255) << 16) | (Math.round(g * 255) << 8) | Math.round(b * 255);
      },
      getPaletteColour(c) { const p = t.palette[Math.round(Math.log2(c))] ?? 0; return multi(((p >> 16) & 255) / 255, ((p >> 8) & 255) / 255, (p & 255) / 255); },
      nativePaletteColour(c) { const p = DEFAULT_PALETTE[Math.round(Math.log2(c))] ?? 0; return multi(((p >> 16) & 255) / 255, ((p >> 8) & 255) / 255, (p & 255) / 255); },
    };
    o.isColor = o.isColour; o.setTextColor = o.setTextColour; o.getTextColor = o.getTextColour;
    o.setBackgroundColor = o.setBackgroundColour; o.getBackgroundColor = o.getBackgroundColour;
    o.setPaletteColor = o.setPaletteColour; o.getPaletteColor = o.getPaletteColour; o.nativePaletteColor = o.nativePaletteColour;
    return o;
  }
}
