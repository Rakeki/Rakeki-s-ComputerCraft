// CC: Tweaked terminal look-alikes: a character grid with the 16 CC colours,
// a typing terminal, and mock-ups of the AutoMine map and status dashboard.
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

  window.CC = { PALETTE, Screen, Typer, fit, screens: { automine, dashboard } };
})();
