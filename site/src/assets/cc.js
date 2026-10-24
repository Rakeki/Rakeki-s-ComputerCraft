// CC: Tweaked terminal look-alikes: a character grid with the 16 CC colours,
// a typing terminal, and mock-ups of the AutoMine map, status dashboard,
// blueprint projector panel and storage terminal.
(function () {
  const PALETTE = {
    white: "#f0f0f0", orange: "#f2b233", magenta: "#e57fd8", lightBlue: "#99b2f2",
    yellow: "#dede6c", lime: "#7fcc19", pink: "#f2b2cc", gray: "#4c4c4c",
    lightGray: "#999999", cyan: "#4c99b2", purple: "#b266e5", blue: "#3366cc",
    brown: "#7f664c", green: "#57a64e", red: "#cc4c4c", black: "#111111",
  };

  //---------------------------------------------------------------- screen

  class Screen {
    constructor(w, h, el) {
      this.w = w; this.h = h;
      this.el = el || document.createElement("pre");
      this.el.className = "cc-term";
      this.zones = [];
      this.clear();
      fit(this.el, w);
    }
    clear(bg = "black") {
      this.cells = Array.from({ length: this.h }, () => Array.from({ length: this.w }, () => ({ ch: " ", fg: "white", bg })));
      this.zones = [];
    }
    put(x, y, text, fg = "white", bg = "black") {
      if (y < 1 || y > this.h) return;
      for (let i = 0; i < text.length; i++) {
        const cx = x + i - 1;
        if (cx >= 0 && cx < this.w) this.cells[y - 1][cx] = { ch: text[i], fg, bg };
      }
    }
    fill(y, bg) { this.put(1, y, " ".repeat(this.w), "white", bg); }
    button(x, y, label, fg, bg, action) {
      const text = ` ${label} `;
      this.put(x, y, text, fg, bg);
      this.zones.push({ x1: x, x2: x + text.length - 1, y1: y, y2: y, action });
      return x + text.length + 1;
    }
    render(cursor) {
      let html = "";
      this.cells.forEach((row, y) => {
        let run = null;
        const flush = () => { if (run) html += `<span style="color:${PALETTE[run.fg]};background:${PALETTE[run.bg]}">${esc(run.text)}</span>`; };
        row.forEach((c, x) => {
          if (cursor && cursor.x === x + 1 && cursor.y === y + 1) {
            flush(); run = null;
            html += `<span class="cur" style="color:${PALETTE.white}">_</span>`;
            return;
          }
          if (run && run.fg === c.fg && run.bg === c.bg) run.text += c.ch;
          else { flush(); run = { fg: c.fg, bg: c.bg, text: c.ch }; }
        });
        flush();
        if (y < this.h - 1) html += "\n";
      });
      this.el.innerHTML = html;
    }
    // Cell under a mouse event, 1-based, like CC's mouse_click.
    cellAt(ev) {
      const r = this.el.getBoundingClientRect();
      return { x: Math.floor((ev.clientX - r.left) / r.width * this.w) + 1, y: Math.floor((ev.clientY - r.top) / r.height * this.h) + 1 };
    }
    zoneAt(x, y) { return this.zones.find((z) => x >= z.x1 && x <= z.x2 && y >= z.y1 && y <= z.y2); }
  }
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");

  let charRatio = 0;
  function measure() {
    const probe = document.createElement("pre");
    probe.className = "cc-term";
    probe.style.cssText = "position:absolute;left:0;top:0;width:max-content;visibility:hidden;font-size:100px;padding:0;";
    probe.textContent = "M".repeat(50);
    document.body.append(probe);
    charRatio = probe.getBoundingClientRect().width / 5000;
    probe.remove();
  }
  function fit(el, cols) {
    const apply = () => {
      if (!charRatio) measure();
      const box = el.parentElement.clientWidth - 16;
      if (box > 0) { el.style.fontSize = `${(box / (cols * charRatio)).toFixed(2)}px`; el.style.padding = "8px"; }
    };
    apply();
    if ("ResizeObserver" in window) new ResizeObserver(apply).observe(el.parentElement);
  }

  //---------------------------------------------------------------- typing terminal

  // Plays a scripted session: a prompt with a typed command, then printed lines.
  // lines: [text, typed, colour]; colour "cmd" means `text` is the prompt and `typed` gets typed.
  class Typer {
    constructor(el, w, h, scripts, opts = {}) {
      this.s = new Screen(w, h, el);
      this.scripts = scripts;
      this.opts = opts;
      this.i = 0;
      this.timer = null;
      this.visible = true;
      if ("IntersectionObserver" in window) {
        new IntersectionObserver((es) => { this.visible = es[0].isIntersecting; }).observe(el);
      }
      this.play();
    }
    reset() { this.s.clear(); this.x = 1; this.y = 1; }
    newline() {
      this.x = 1; this.y++;
      if (this.y > this.s.h) { this.s.cells.shift(); this.s.cells.push(Array.from({ length: this.s.w }, () => ({ ch: " ", fg: "white", bg: "black" }))); this.y = this.s.h; }
    }
    print(text, colour) {
      // word wrap like CC's print()
      const words = text.split(/(\s+)/);
      let wrapped = false;
      for (const word of words) {
        if (!word) continue;
        if (this.x + word.length - 1 > this.s.w && this.x > 1 && word.trim()) { this.newline(); wrapped = true; }
        if (!word.trim() && wrapped && this.x === 1) continue;
        for (const ch of word) {
          if (this.x > this.s.w) this.newline();
          this.s.put(this.x, this.y, ch, colour);
          this.x++;
        }
      }
      this.newline();
    }
    wait(ms) { return new Promise((r) => { this.timer = setTimeout(r, ms); }); }
    async play() {
      const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
      for (;;) {
        const script = this.scripts[this.i % this.scripts.length];
        this.reset();
        if (this.opts.header) this.opts.header.forEach(([t, c]) => this.print(t, c));
        for (const [text, typed, colour] of script) {
          while (!this.visible) await this.wait(400);
          if (colour === "cmd") {
            this.s.put(this.x, this.y, text, "yellow"); this.x += text.length;
            for (const ch of typed) {
              if (this.x > this.s.w) this.newline();
              this.s.put(this.x, this.y, ch, "white"); this.x++;
              this.s.render({ x: this.x, y: this.y });
              if (!reduced) await this.wait((typed.length > 30 ? 14 : 45) + Math.random() * (typed.length > 30 ? 30 : 70));
            }
            this.s.render(); if (!reduced) await this.wait(380);
            this.newline();
          } else {
            this.print(text, colour || "white");
            this.s.render({ x: this.x, y: this.y });
            if (!reduced) await this.wait(text.startsWith("  ") ? 140 : 260);
          }
        }
        this.s.put(this.x, this.y, "> ", "yellow"); this.x += 2;
        this.s.render({ x: this.x, y: this.y });
        if (this.scripts.length === 1 && reduced) return;
        await this.wait(this.opts.pause || 4200);
        this.i++;
      }
    }
  }

  //---------------------------------------------------------------- AutoMine map

  function automine(el) {
    const s = new Screen(51, 19, el);
    el.classList.add("clickable");
    const COLS = 15, ROWS = 17, PANEL_X = 32;
    const STYLE = {
      none: ["gray", "black"], queued: ["black", "yellow"], active: ["black", "orange"],
      done: ["black", "green"], player: ["white", "purple"], base: ["white", "blue"],
    };
    const chunks = new Map();
    const key = (x, z) => `${x},${z}`;
    let order = 0;
    const set = (x, z, state, extra) => chunks.set(key(x, z), { state, order: order++, ...extra });
    // a believable plan around HQ at 0,0
    [[-1, 0], [1, 0], [0, -1], [-1, -1], [1, -1], [0, 1]].forEach(([x, z]) => set(x, z, "done"));
    set(-2, 0, "active", { turtle: 7 }); set(2, -1, "active", { turtle: 12 }); set(1, 1, "active", { turtle: 3 });
    [[-2, -1], [-2, 1], [2, 0], [2, 1], [0, -2], [-1, -2], [1, -2], [3, -1], [3, 0]].forEach(([x, z]) => set(x, z, "queued"));
    set(-3, 2, "player"); set(-4, 2, "player");
    const turtles = [
      { id: 3, label: "Miner-3", state: "mining", detail: "layer 31/40", fuel: 4120 },
      { id: 7, label: "Miner-7", state: "mining", detail: "layer 12/40", fuel: 2210 },
      { id: 12, label: "Miner-12", state: "docking", detail: "inventory full", fuel: 860 },
    ];
    let viewX = 0, viewZ = 0, brush = "look", selected = null, paused = false;
    const BRUSHES = [["look", "Look"], ["queued", "Queue"], ["player", "Me"], ["none", "Clear"], ["done", "Done"]];

    function draw() {
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "AutoMine", "yellow", "gray");
      if (paused) s.put(11, 1, "PAUSED", "red", "gray");
      let x = 20;
      x = s.button(x, 1, "<", "white", "lightGray", () => pan(-1, 0));
      x = s.button(x, 1, "^", "white", "lightGray", () => pan(0, -1));
      x = s.button(x, 1, "v", "white", "lightGray", () => pan(0, 1));
      x = s.button(x, 1, ">", "white", "lightGray", () => pan(1, 0));
      s.button(x, 1, "HQ", "white", "blue", () => { viewX = 0; viewZ = 0; });

      const queue = [...chunks.entries()].filter(([, c]) => c.state === "queued").sort((a, b) => a[1].order - b[1].order);
      const rank = new Map(queue.map(([k], i) => [k, i + 1]));
      for (let row = 0; row < ROWS; row++) {
        for (let col = 0; col < COLS; col++) {
          const cx = viewX - Math.floor(COLS / 2) + col, cz = viewZ - Math.floor(ROWS / 2) + row;
          const c = chunks.get(key(cx, cz));
          let st, label;
          if (cx === 0 && cz === 0) { st = STYLE.base; label = "HQ"; }
          else if (!c) { st = STYLE.none; label = " ·"; }
          else if (c.state === "queued") { st = STYLE.queued; label = String(rank.get(key(cx, cz))).padStart(2); }
          else if (c.state === "active") { st = STYLE.active; label = String(c.turtle).padStart(2); }
          else if (c.state === "player") { st = STYLE.player; label = "Me"; }
          else { st = STYLE.done; label = "  "; }
          let [fg, bg] = st;
          if (selected && selected[0] === cx && selected[1] === cz) { fg = "black"; bg = "white"; }
          s.put(col * 2 + 1, row + 2, label, fg, bg);
          s.zones.push({ x1: col * 2 + 1, x2: col * 2 + 2, y1: row + 2, y2: row + 2, action: () => paint(cx, cz) });
        }
      }

      let y = 2;
      const line = (t, c = "white") => { s.put(PANEL_X, y++, (" " + t).slice(0, 20), c); };
      if (selected) {
        const [cx, cz] = selected, c = chunks.get(key(cx, cz));
        line(`Chunk ${cx},${cz}`, "yellow");
        line(`x ${cx * 16}..${cx * 16 + 15}`, "lightGray");
        line(`z ${cz * 16}..${cz * 16 + 15}`, "lightGray");
        line(cx === 0 && cz === 0 ? "Home (never mined)" : !c ? "Not planned" : c.state === "queued" ? `Queued #${rank.get(key(cx, cz))}` : c.state === "active" ? `Mining: #${c.turtle}` : c.state === "player" ? "Reserved for you" : "Mined", c && c.state === "player" ? "purple" : c && c.state === "done" ? "green" : "white");
      } else {
        line("Tap a chunk", "lightGray");
      }
      y++;
      line(`Turtles (${turtles.length})`, "yellow");
      for (const t of turtles) {
        line(`#${t.id} ${t.label}`);
        line(` ${paused ? "paused" : t.state} ${t.detail.replace("layer ", "")}`, "lightGray");
        line(` fuel ${t.fuel}`, "lightGray");
      }
      const mine = [...chunks.entries()].filter(([, c]) => c.state === "player");
      if (mine.length && y < 18) {
        y++;
        line(`Your chunks (${mine.length})`, "purple");
        for (const [k] of mine) { if (y >= 19) break; const [cx, cz] = k.split(",").map(Number); line(` ${cx * 16},${cz * 16}`, "lightGray"); }
      }

      s.fill(19, "gray");
      let bx = 1;
      for (const [id, label] of BRUSHES) {
        const on = brush === id;
        bx = s.button(bx, 19, label, on ? "black" : "white", on ? "white" : "gray", () => { brush = id; });
      }
      const pl = paused ? "Resume" : "Pause";
      s.button(51 - pl.length - 1, 19, pl, "white", paused ? "green" : "red", () => { paused = !paused; });
      s.render();
    }
    function pan(dx, dz) { viewX += dx * 5; viewZ += dz * 5; }
    function paint(cx, cz) {
      if (brush === "look" || (cx === 0 && cz === 0)) { selected = [cx, cz]; return; }
      const k = key(cx, cz);
      if (brush === "none") chunks.delete(k);
      else set(cx, cz, brush);
      selected = [cx, cz];
    }
    el.addEventListener("click", (ev) => {
      const { x, y } = s.cellAt(ev);
      const z = s.zoneAt(x, y);
      if (z) { z.action(); draw(); }
    });
    // turtles slowly progress so the panel feels alive
    setInterval(() => {
      if (paused) return;
      for (const t of turtles) {
        if (t.state === "mining") {
          const m = t.detail.match(/layer (\d+)\/40/);
          const n = m ? +m[1] + 1 : 1;
          t.detail = n > 40 ? "layer 1/40" : `layer ${n}/40`;
          t.fuel = Math.max(200, t.fuel - 7);
        } else if (Math.random() < 0.3) { t.state = "mining"; t.detail = "layer 18/40"; t.fuel = 5000; }
      }
      draw();
    }, 2600);
    draw();
    return s;
  }

  //---------------------------------------------------------------- status dashboard

  function dashboard(el) {
    const W = 57, H = 24, CARD_H = 7;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    let selected = null;
    const now = () => Date.now() / 1000;
    const start = now();
    const comps = [
      { id: 7, label: "Miner-7", role: "auto miner", kind: "turtle", state: "mining", detail: "chunk -2,0 layer 12/40", pos: [-27, 41, 6], from: "tracked", fuel: 2210, limit: 20000 },
      { id: 12, label: "Miner-12", role: "auto miner", kind: "turtle", state: "unloading", detail: "at the dock", pos: [3, 64, 2], from: "tracked", fuel: 860, limit: 20000 },
      { id: 21, label: "Excavator-21", role: "excavator", kind: "turtle", state: "digging", detail: "hall 43% (room 3/24)", pos: [140, -8, -61], from: "gps", fuel: 9840, limit: 20000 },
      { id: 4, label: "AutoMine", role: "mine server", kind: "computer", state: "running", detail: "3 turtles, 9 queued", pos: [0, 65, -3], from: "fixed" },
      { id: 30, label: "Builder-30", role: "village builder", kind: "turtle", state: "waiting", detail: "needs 87 spruce_stairs", pos: [212, 70, 88], from: "gps", fuel: 4100, limit: 20000 },
      { id: 15, label: "GPS-1", role: "gps host", kind: "computer", state: "serving", detail: "GPS at 102, 310, -38", pos: [102, 310, -38], from: "fixed" },
      { id: 33, label: "Stripminer-33", role: "strip miner", kind: "turtle", state: "error", detail: "Out of fuel here.", pos: [-80, 11, 30], from: "gps", fuel: 0, limit: 20000 },
      { id: 9, label: "Farm", role: "wheat farm", kind: "computer", offline: true, detail: "harvesting", pos: [18, 64, 40], from: "fixed", lastSeen: start - 420 },
    ];
    comps.forEach((c) => { if (!c.lastSeen) c.lastSeen = start - Math.random() * 4; });
    const STATE = { mining: "lime", digging: "lime", running: "lime", serving: "lime", building: "lime", unloading: "lightBlue", travelling: "lightBlue", waiting: "yellow", error: "red", idle: "lightGray" };
    const ago = (sec) => sec < 60 ? `${Math.floor(sec)}s` : sec < 3600 ? `${Math.floor(sec / 60)}m` : `${Math.floor(sec / 3600)}h`;
    const fit = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const posText = (c) => `${c.pos.join(", ")}${c.from === "tracked" ? " (tracked)" : ""}`;

    function card(c, x, y, w, t) {
      const bg = c.offline ? "black" : "gray", dim = c.offline ? "gray" : "lightGray";
      for (let r = 0; r < CARD_H - 1; r++) s.put(x, y + r, " ".repeat(w), "white", bg);
      const idText = `#${c.id}`;
      s.put(x + 1, y, fit(c.label, w - idText.length - 3), c.offline ? "gray" : "white", bg);
      s.put(x + w - idText.length - 1, y, idText, dim, bg);
      s.put(x + 1, y + 1, fit(`${c.role} - ${c.kind}`, w - 2), dim, bg);
      s.put(x + 1, y + 2, fit(c.offline ? `offline ${ago(t - c.lastSeen)}` : c.state, w - 2), c.offline ? "gray" : STATE[c.state] || "white", bg);
      s.put(x + 1, y + 3, fit(c.detail, w - 2), c.offline ? "gray" : "white", bg);
      s.put(x + 1, y + 4, fit(posText(c), w - 2), dim, bg);
      if (c.fuel !== undefined) {
        const barW = 8, filled = Math.round(Math.min(1, c.fuel / c.limit) * barW);
        s.put(x + 1, y + 5, " ".repeat(filled), "white", c.fuel < 500 ? "red" : "green");
        s.put(x + 1 + filled, y + 5, " ".repeat(barW - filled), "white", "black");
        s.put(x + 1 + barW, y + 5, fit(` ${c.fuel}`, w - barW - 7), dim, bg);
      }
      if (!c.offline) { const seen = ago(t - c.lastSeen); s.put(x + w - seen.length - 1, y + 5, seen, dim, bg); }
      s.zones.push({ x1: x, x2: x + w - 1, y1: y, y2: y + CARD_H - 2, action: () => { selected = c; } });
    }

    function draw() {
      const t = now();
      s.clear();
      s.fill(1, "gray");
      if (selected) {
        const c = selected;
        const x = s.button(1, 1, "< Back", "white", "lightGray", () => { selected = null; });
        s.put(x, 1, c.label, "yellow", "gray");
        s.button(W - 7, 1, "Forget", "white", "red", () => { selected = null; });
        const rows = [["Role", c.role], ["Type", c.kind], ["State", c.offline ? "offline" : c.state, c.offline ? "gray" : STATE[c.state]], ["Doing", c.detail], ["Position", posText(c)], ["From", { gps: "GPS", tracked: "its own tracking", fixed: "known spot (doesn't move)" }[c.from]], ["Fuel", c.fuel !== undefined ? String(c.fuel) : "-"], ["Last seen", `${ago(t - c.lastSeen)} ago`, c.offline ? "red" : null]];
        rows.forEach(([k, v, col], i) => { s.put(2, 3 + i, fit(k, 10), "lightGray"); s.put(12, 3 + i, fit(v, W - 12), col || "white"); });
        s.put(2, 12, "Recent activity", "yellow");
        const events = c.offline ? [["went offline", 7], ["harvesting", 46]] : [[c.state, 2], [c.detail, 4], ["came online", 31], ["starting", 31]];
        events.forEach(([e, m], i) => {
          const d = new Date(Date.now() - m * 60000);
          s.put(2, 13 + i, `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`, "gray");
          s.put(8, 13 + i, fit(e, W - 8), "lightGray");
        });
      } else {
        s.put(2, 1, "Computers", "yellow", "gray");
        const online = comps.filter((c) => !c.offline).length;
        s.put(12, 1, `${online} online, ${comps.length - online} offline`, "lightGray", "gray");
        const cols = 2, cardW = Math.floor((W - 1) / cols) - 1;
        const sorted = [...comps].sort((a, b) => (a.offline ? 1 : 0) - (b.offline ? 1 : 0));
        sorted.slice(0, 6).forEach((c, i) => card(c, 2 + (i % cols) * (cardW + 1), 3 + Math.floor(i / cols) * CARD_H, cardW, t));
        s.button(W - 11, 1, "<", "white", "lightGray", () => {});
        s.put(W - 7, 1, "1/2", "white", "gray");
        s.button(W - 2 - 1, 1, ">", "white", "lightGray", () => {});
      }
      s.render();
    }
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    setInterval(() => {
      const t = now();
      for (const c of comps) {
        if (c.offline) continue;
        if (c.state !== "error" && c.state !== "waiting") c.lastSeen = t - Math.random() * 3;
        if (c.state === "mining") {
          c.fuel -= 9;
          c.detail = c.detail.replace(/layer (\d+)/, (_, n) => `layer ${(+n % 40) + 1}`);
        }
        if (c.state === "digging") { c.fuel -= 14; c.detail = c.detail.replace(/(\d+)%/, (_, n) => `${Math.min(99, +n + 1)}%`); }
        if (c.label === "Miner-12" && Math.random() < 0.25) {
          c.state = c.state === "unloading" ? "travelling" : c.state === "travelling" ? "mining" : "unloading";
          c.detail = { unloading: "at the dock", travelling: "to chunk 2,-1", mining: "chunk 2,-1 layer 1/40" }[c.state];
          if (c.state === "unloading") c.fuel = 18500;
        }
      }
      draw();
    }, 1500);
    draw();
    return s;
  }

  //---------------------------------------------------------------- blueprint projector

  // The projector's monitor panel with the built-in cottage: same layout as
  // computers/blueprint-projector/ui.lua, and the buttons work.
  function projector(el) {
    const W = 58, H = 24;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const mats = {
      C: ["cobblestone", 0x7a7a7a], P: ["oak_planks", 0xb8945f], L: ["oak_log", 0xb8945f],
      G: ["glass_pane", 0xa8d8ea], D: ["oak_door", 0xb8945f], S: ["spruce_planks", 0x72543a],
    };
    const rgb = (hex) => [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
    for (const m of Object.values(mats)) {
      const r = (m[1] >> 16) & 255, g = (m[1] >> 8) & 255, b = m[1] & 255;
      let best = "white", bestD = Infinity;
      for (const [name, hex] of Object.entries(PALETTE)) {
        const [pr, pg, pb] = rgb(hex), d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2;
        if (d < bestD) { best = name; bestD = d; }
      }
      m.push(best, 0.3 * r + 0.59 * g + 0.11 * b > 140);
    }
    const ring = (a, b, c) => [a, ...Array(5).fill(b), c];
    const full = (ch) => Array(7).fill(ch.repeat(7));
    const layers = [
      full("C"),
      ["LPPDPPL", ...Array(5).fill("P.....P"), "LPPPPPL"],
      ["LPGDGPL", "P.....P", "G.....G", "P.....P", "G.....G", "P.....P", "LPPGPPL"],
      ring("LPPPPPL", "P.....P", "LPPPPPL"),
      full("S"),
      [".......", ...Array(5).fill(".SSSSS."), "......."],
      [".......", ".......", "..SSS..", "..SSS..", "..SSS..", ".......", "......."],
      [".......", ".......", ".......", "...S...", ".......", ".......", "......."],
    ];
    const plans = ["Cottage", "Watchtower", "Pagoda"];
    const st = { plan: 0, x: 100, y: 64, z: -15, turn: 0, view: "whole", layer: 8, step: 1, hidden: false };
    const FACING = ["north", "east", "south", "west"], STEPS = [1, 5, 16], VIEWS = ["whole", "layer", "outline"];
    const LABEL = { whole: "Whole", layer: "Layer", outline: "Outline" };
    let status = ["Showing 39 shapes", "lime"], timer = null;
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    // cell (x, z) of the plan as seen from above after turning, north up
    const cellAt = (layer, col, row) => {
      let x = col, z = row;
      for (let i = 0; i < st.turn; i++) [x, z] = [z, 6 - x];
      const ch = (layers[layer] || [])[z]?.[x];
      return ch && ch !== "." ? ch : null;
    };
    const busy = () => {
      status = ["Moving...", "lightGray"];
      clearTimeout(timer);
      timer = setTimeout(() => {
        const shapes = st.hidden ? 0 : st.view === "outline" ? 1 : st.view === "layer" ? 2 + layers[st.layer - 1].join("").replace(/\./g, "").length : [2, 12, 29, 35, 36, 37, 38, 39][st.layer - 1];
        status = st.hidden ? ["Hidden. Tap Show to project it again.", "lightGray"] : [`Showing ${shapes} shapes`, "lime"];
        draw();
      }, 700);
    };
    const act = {
      north: () => { st.z -= st.step; }, south: () => { st.z += st.step; }, west: () => { st.x -= st.step; }, east: () => { st.x += st.step; },
      up: () => { st.y += st.step; }, down: () => { st.y -= st.step; },
      turnLeft: () => { st.turn = (st.turn + 3) % 4; }, turnRight: () => { st.turn = (st.turn + 1) % 4; },
      step: () => { st.step = STEPS[(STEPS.indexOf(st.step) + 1) % STEPS.length]; },
      layerUp: () => { st.layer = Math.min(8, st.layer + 1); }, layerDown: () => { st.layer = Math.max(1, st.layer - 1); },
      view: () => { st.view = VIEWS[(VIEWS.indexOf(st.view) + 1) % 3]; st.layer = st.view === "layer" ? 1 : st.view === "whole" ? 8 : st.layer; },
      here: () => { st.x = 100; st.y = 64; st.z = -15; }, hide: () => { st.hidden = !st.hidden; },
    };
    const btn = (x, y, label, name, fg = "black", bg = "lightGray") => s.button(x, y, label, fg, bg, () => {
      if (name === "plan") { status = ["This preview only has the cottage.", "orange"]; return; }
      act[name](); busy();
    });
    const label = (x, y, t, fg = "lightGray") => { s.put(x, y, t, fg); return x + t.length; };

    function draw() {
      s.clear();
      s.fill(1, "gray");
      btn(1, 1, "◄", "plan", "white");
      const count = ` 1/${plans.length}`;
      s.put(5, 1, fitT("Cottage", W - 9 - count.length), "yellow", "gray");
      s.put(W - 4 - count.length, 1, count, "lightGray", "gray");
      btn(W - 2, 1, "►", "plan", "white");
      s.put(1, 2, fitT(` X ${st.x}  Y ${st.y}  Z ${st.z}   front faces ${FACING[st.turn]}`, W), "lightGray");
      let x = label(2, 4, "Move ");
      for (const [l, a] of [["N", "north"], ["S", "south"], ["W", "west"], ["E", "east"]]) x = btn(x, 4, l, a);
      x = label(x, 4, "Step ");
      btn(x, 4, String(st.step), "step", "white", "blue");
      x = label(2, 5, "     ");
      x = btn(x, 5, "Up", "up"); x = btn(x, 5, "Down", "down");
      x = label(x, 5, "Turn ");
      x = btn(x, 5, "←", "turnLeft"); btn(x, 5, "→", "turnRight");
      x = label(2, 6, "View ");
      x = btn(x, 6, LABEL[st.view], "view", "white", "cyan");
      x = label(x, 6, "Layer ");
      x = btn(x, 6, "-", "layerDown");
      x = label(x, 6, `${st.layer}/8 `, "white");
      btn(x, 6, "+", "layerUp");
      x = btn(7, 7, "Here", "here", "white", "blue");
      btn(x, 7, st.hidden ? "Show" : "Hide", "hide", "white", st.hidden ? "green" : "red");
      s.put(2, 9, fitT(status[0], W - 2), status[1]);
      s.put(2, 11, `Layer ${st.layer}, north is up`, "yellow");
      const counts = {};
      for (let l = st.view === "whole" ? 1 : st.layer; l <= st.layer; l++) for (const ch of layers[l - 1].join("")) if (ch !== ".") counts[ch] = (counts[ch] || 0) + 1;
      for (let row = 0; row < 7; row++) for (let col = 0; col < 7; col++) {
        const ch = cellAt(st.layer - 1, col, row);
        if (ch) { const m = mats[ch]; s.put(2 + col, 12 + row, ch, m[3] ? "black" : "white", m[2]); }
        else if (cellAt(st.layer - 2, col, row)) s.put(2 + col, 12 + row, "·", "lightGray", "gray");
        else s.put(2 + col, 12 + row, " ", "white", "gray");
      }
      const list = Object.entries(counts).sort((a, b) => b[1] - a[1]);
      const total = list.reduce((n, [, c]) => n + c, 0);
      s.put(11, 12, st.view === "whole" ? `Layers 1-${st.layer}: ${total}` : `Layer ${st.layer}: ${total}`, "yellow");
      list.forEach(([ch, n], i) => {
        const m = mats[ch];
        s.put(11, 13 + i, ch, m[3] ? "black" : "white", m[2]);
        s.put(13, 13 + i, m[0]);
        s.put(W - 1 - String(n).length, 13 + i, String(n), "lightGray");
      });
      s.render();
    }
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    draw();
    return s;
  }

  //---------------------------------------------------------------- storage terminal

  // The storage computer's search screen: same layout as
  // computers/storage-computer/storage.lua. It types a few searches on its own
  // until clicked; then click a row to pick it and click it again for a stack.
  function storage(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const items = [
      ["Cobblestone", 5120], ["Oak Log", 1388], ["Wheat", 912], ["Dirt", 840], ["Carrot", 455],
      ["Iron Ingot", 302], ["Coal", 268], ["Redstone Dust", 197], ["Oak Sapling", 140], ["Iron Ore", 96],
      ["Gold Ingot", 75], ["Potato", 64], ["Diamond", 23], ["Raw Iron", 18], ["Enchanted Book", 3], ["Iron Pickaxe", 1],
    ].map(([name, count]) => ({ name, count }));
    const SLOTS = 27 * 12;
    const st = { query: "", selected: 1, scroll: 0, msg: ["", "lightGray"], auto: true };
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const countText = (n) => n >= 64 ? `${n} (${Math.floor(n / 64)}x64${n % 64 ? `+${n % 64}` : ""})` : String(n);
    const matches = () => items.filter((it) => it.count > 0 && it.name.toLowerCase().includes(st.query.toLowerCase())).sort((a, b) => b.count - a.count);

    function take(n) {
      const it = matches()[st.selected - 1];
      if (!it) return;
      const sent = Math.min(n, it.count);
      it.count -= sent;
      st.msg = [`Sent ${sent} ${it.name} to the output chest.`, "lime"];
    }

    function draw() {
      const list = matches();
      const used = items.reduce((k, it) => k + Math.ceil(it.count / 64), 0);
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "Storage", "yellow", "gray");
      const stat = `12 chests, ${used}/${SLOTS} slots`;
      s.put(W - stat.length, 1, stat, "lightGray", "gray");
      s.put(1, 2, "Search: ", "lightGray");
      s.put(9, 2, st.query, "white");
      const rows = H - 4;
      st.selected = Math.max(1, Math.min(st.selected, list.length));
      if (st.selected <= st.scroll) st.scroll = st.selected - 1;
      if (st.selected > st.scroll + rows) st.scroll = st.selected - rows;
      for (let i = 1; i <= rows; i++) {
        const it = list[st.scroll + i - 1];
        if (!it) continue;
        const sel = st.scroll + i === st.selected, bg = sel ? "blue" : "black", c = countText(it.count);
        s.put(1, 2 + i, fitT(" " + it.name, W - c.length - 1), "white", bg);
        s.put(W - c.length, 2 + i, c + " ", sel ? "white" : "lightGray", bg);
        const idx = st.scroll + i;
        s.zones.push({ x1: 1, x2: W, y1: 2 + i, y2: 2 + i, action: () => { if (st.selected === idx) take(64); else st.selected = idx; } });
      }
      if (!list.length) s.put(2, 4, "No matches.", "lightGray");
      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      s.put(1, H, fitT("Enter: a stack  Right: one  Up/Down: pick", W), "gray");
      s.render({ x: 9 + st.query.length, y: 2 });
    }

    // the demo: search, pick, take, clear, repeat
    const script = [..."iron"].map((ch) => () => { st.query += ch; st.selected = 1; })
      .concat([() => { st.selected = 2; }, () => take(64), () => {}, () => { st.query = ""; st.msg = ["", "lightGray"]; },
        ...[..."log"].map((ch) => () => { st.query += ch; st.selected = 1; }), () => take(64), () => {}, () => { st.query = ""; st.msg = ["", "lightGray"]; }]);
    let step = 0;
    setInterval(() => {
      if (!st.auto) return;
      script[step % script.length]();
      step++;
      if (step % script.length === 0) items.forEach((it) => { it.count = it.base ?? it.count; });
      draw();
    }, 900);
    items.forEach((it) => { it.base = it.count; });

    el.addEventListener("click", (ev) => {
      if (st.auto) { st.auto = false; st.query = ""; st.msg = ["", "lightGray"]; }
      const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y);
      if (z) z.action();
      draw();
    });
    draw();
    return s;
  }

  window.CC = { PALETTE, Screen, Typer, fit, screens: { automine, dashboard, projector, storage } };
})();
