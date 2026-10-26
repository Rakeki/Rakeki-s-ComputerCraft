// CC: Tweaked terminal look-alikes: a character grid with the 16 CC colours,
// a typing terminal, and mock-ups of the AutoMine map, status dashboard,
// blueprint projector panel, storage terminal, smelter, craft overseer and colony dashboard.
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
  // computers/storage-computer/storage.lua, with its Stored and Craftable tabs.
  // It types a few searches on its own until clicked; then click a tab or a
  // row to pick it, and a row again for a stack.
  function storage(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const items = [
      ["Cobblestone", 5120], ["Oak Log", 1388], ["Wheat", 912], ["Dirt", 840], ["Carrot", 455],
      ["Iron Ingot", 302], ["Coal", 268], ["Redstone Dust", 197], ["Oak Sapling", 140], ["Iron Ore", 96],
      ["Gold Ingot", 75], ["Potato", 64], ["Diamond", 23], ["Raw Iron", 18], ["Enchanted Book", 3], ["Iron Pickaxe", 1],
    ].map(([name, count]) => ({ name, count }));
    // not stored, but the crafting turtle could make them: listed in light blue
    const crafts = [["Oak Planks", 4096], ["Stick", 2776], ["Oak Fence", 1041], ["Torch", 536], ["Chest", 173]]
      .map(([name, count]) => ({ name, count, craft: true }));
    const SLOTS = 27 * 12;
    const st = { query: "", selected: 1, scroll: 0, msg: ["", "lightGray"], auto: true, tab: "stored" };
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const countText = (n) => n >= 64 ? `${n} (${Math.floor(n / 64)}x64${n % 64 ? `+${n % 64}` : ""})` : String(n);
    const fits = (it) => it.count > 0 && it.name.toLowerCase().includes(st.query.toLowerCase());
    const stored = () => items.filter(fits).sort((a, b) => b.count - a.count);
    const matches = () => (st.tab === "craft" ? crafts.filter(fits) : stored());
    const setTab = (t) => { st.tab = t; st.selected = 1; st.scroll = 0; };

    function take(n) {
      const it = matches()[st.selected - 1];
      if (!it) return;
      const sent = Math.min(n, it.count);
      if (it.craft) {
        st.msg = [`Crafting ${sent} ${it.name} for the output chest...`, "lightBlue"];
        setTimeout(() => { st.msg = [`Crafted ${sent} ${it.name}: it's in the output chest.`, "lime"]; draw(); }, 1800);
        return;
      }
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
      // tabs: what's stored, and (light blue) what could be crafted
      let tx = 1;
      for (const [t, label, on] of [["stored", `Stored ${stored().length}`, "white"], ["craft", `Craftable ${crafts.filter(fits).length}`, "lightBlue"]]) {
        const text = ` ${label} `, sel = st.tab === t;
        s.put(tx, 2, text, sel ? "black" : "white", sel ? on : "gray");
        s.zones.push({ x1: tx, x2: tx + text.length - 1, y1: 2, y2: 2, action: () => setTab(t) });
        tx += text.length + 1;
      }
      s.put(1, 3, "Search: ", "lightGray");
      s.put(9, 3, st.query, "white");
      const rows = H - 5;
      st.selected = Math.max(1, Math.min(st.selected, list.length));
      if (st.selected <= st.scroll) st.scroll = st.selected - 1;
      if (st.selected > st.scroll + rows) st.scroll = st.selected - rows;
      for (let i = 1; i <= rows; i++) {
        const it = list[st.scroll + i - 1];
        if (!it) continue;
        const sel = st.scroll + i === st.selected, bg = sel ? "blue" : "black";
        const c = it.craft ? `can make ${it.count}` : countText(it.count);
        s.put(1, 3 + i, fitT(" " + it.name, W - c.length - 1), it.craft && !sel ? "lightBlue" : "white", bg);
        s.put(W - c.length, 3 + i, c + " ", sel ? "white" : it.craft ? "lightBlue" : "lightGray", bg);
        const idx = st.scroll + i;
        s.zones.push({ x1: 1, x2: W, y1: 3 + i, y2: 3 + i, action: () => { if (st.selected === idx) take(64); else st.selected = idx; } });
      }
      if (!list.length) s.put(2, 5, "No matches.", "lightGray");
      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      s.put(1, H, fitT(st.tab === "craft" ? "Enter: craft a stack  Right: craft one  Tab: stored" : "Enter: a stack  Right: one  Tab: craftable", W), "gray");
      s.render({ x: 9 + st.query.length, y: 3 });
    }

    // the demo: search, pick, take, clear, repeat
    const script = [..."iron"].map((ch) => () => { st.query += ch; st.selected = 1; })
      .concat([() => { st.selected = 2; }, () => take(64), () => {}, () => { st.query = ""; st.msg = ["", "lightGray"]; },
        ...[..."log"].map((ch) => () => { st.query += ch; st.selected = 1; }), () => take(64), () => {}, () => { st.query = ""; st.msg = ["", "lightGray"]; },
        // a village builder asks for blocks, then the delivery chest gets tidied
        () => { items[0].count -= 192; st.msg = ["Sent 192 items to turtle #14.", "lightBlue"]; }, () => {}, () => {},
        () => { items[0].count += 12; st.msg = ["Put away 12 items from the delivery chests.", "lightGray"]; }, () => {},
        // and something it hasn't got, made by the crafting turtle
        () => { st.msg = ["Crafting 24 Smooth Sandstone Slab...", "lightBlue"]; }, () => {},
        () => { st.msg = ["Crafted 24 Smooth Sandstone Slab.", "lime"]; }, () => {}, () => { st.msg = ["", "lightGray"]; },
        // and one asked for on the Craftable tab
        () => setTab("craft"), () => {}, () => { st.selected = 3; }, () => take(64), () => {}, () => {},
        () => {}, () => { setTab("stored"); st.msg = ["", "lightGray"]; }]);
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

  //---------------------------------------------------------------- smelter

  // The smelter's screen: same layout as computers/smelter-computer/smelter.lua.
  // Furnaces smelt down on their own and get reloaded from a pile of ores
  // (the smoker from a pile of raw food);
  // click the footer (or the order line) to place a charcoal order.
  function smelter(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const furnaces = [
      { name: "blast furnace 0", blast: true, input: ["raw iron", 64], fuel: ["charcoal", 8] },
      { name: "blast furnace 1", blast: true, input: ["raw gold", 23], fuel: ["charcoal", 3] },
      { name: "furnace 0", input: ["raw copper", 40], fuel: ["coal", 5] },
      { name: "furnace 1", input: ["raw copper", 40], fuel: ["coal", 5] },
      { name: "smoker 0", smoker: true, input: ["beef", 24], fuel: ["charcoal", 3] },
      { name: "furnace 2", input: null, fuel: null },
    ];
    const ores = { "raw iron": 410, "raw copper": 96, "raw gold": 0 };
    const food = { beef: 40, porkchop: 18, cod: 12 };
    const st = { fuel: 2384, order: null, msg: ["Loaded 80 items into 2 furnaces.", "lightGray"], tick: 0 };

    function load(f) {
      if (f.smoker) {
        const name = Object.keys(food).sort((a, b) => food[b] - food[a])[0];
        if (!food[name]) return;
        const n = Math.min(64, food[name]);
        food[name] -= n;
        f.input = [name, n];
      } else if (!f.blast && st.order && st.order.loaded < st.order.count) {
        const n = Math.min(64, st.order.count - st.order.loaded);
        st.order.loaded += n;
        f.input = ["spruce log", n];
      } else {
        const name = Object.keys(ores).sort((a, b) => ores[b] - ores[a])[0];
        if (!ores[name]) return;
        const n = Math.min(64, ores[name]);
        ores[name] -= n;
        f.input = [name, n];
      }
      const want = Math.ceil(f.input[1] / 8);
      f.fuel = [f.fuel ? f.fuel[0] : "charcoal", Math.max(f.fuel ? f.fuel[1] : 0, want)];
      st.msg = [`Loaded ${f.input[1]} ${f.input[0]} into ${f.name}.`, "lightGray"];
    }

    function step() {
      st.tick++;
      for (const f of furnaces) {
        if (!f.input) { load(f); continue; }
        const n = Math.min(f.input[1], f.blast || f.smoker ? 2 : 1);
        f.input[1] -= n;
        if (f.input[0] === "spruce log" && st.order) st.order.made += n;
        if (st.tick % 8 === 0 && f.fuel) { f.fuel[1]--; st.fuel = Math.max(0, st.fuel - 8); }
        if (f.fuel && f.fuel[1] <= 0) f.fuel = null;
        if (f.input[1] <= 0) f.input = null;
      }
      if (st.order && st.order.made >= st.order.count) {
        st.fuel += st.order.made * 8;
        st.msg = [`Made ${st.order.made} charcoal. It's in the fuel chest.`, "lime"];
        st.order = null;
      }
      if (!Object.values(ores).some((n) => n > 0) && !furnaces.some((f) => f.input)) Object.assign(ores, { "raw iron": 410, "raw copper": 96, "raw gold": 64 });
      if (!Object.values(food).some((n) => n > 0) && !furnaces.some((f) => f.smoker && f.input)) Object.assign(food, { beef: 40, porkchop: 18, cod: 12 });
    }

    function draw() {
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "Smelter", "yellow", "gray");
      const stat = `fuel for ${st.fuel} items`;
      s.put(W - stat.length, 1, stat, "lightGray", "gray");
      const fuelX = W - 12;
      s.put(2, 3, "Furnace", "yellow"); s.put(20, 3, "Smelting", "yellow"); s.put(fuelX, 3, "Fuel", "yellow");
      furnaces.forEach((f, i) => {
        const y = 4 + i;
        s.put(2, y, fitT(f.name, 17), f.blast ? "orange" : f.smoker ? "pink" : "white");
        s.put(20, y, fitT(f.input ? `${f.input[1]} ${f.input[0]}` : "idle", fuelX - 21), f.input ? "white" : "gray");
        s.put(fuelX, y, fitT(f.fuel ? `${f.fuel[1]} ${f.fuel[0]}` : "-", 12), "lightGray");
      });
      const o = st.order;
      s.put(1, H - 2, fitT(" " + (o ? `Charcoal: ${o.made} of ${o.count} made from spruce log` : "No charcoal order."), W), o ? "lightBlue" : "gray");
      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      s.put(1, H, fitT("C: make charcoal  X: cancel charcoal", W), "gray");
      const order = () => {
        st.order = st.order ? null : { count: 128, loaded: 0, made: 0 };
        st.msg = st.order ? ["Making 128 charcoal from spruce log.", "lightBlue"] : ["Charcoal order cancelled. Logs already in furnaces still burn.", "lightGray"];
      };
      s.zones.push({ x1: 1, x2: W, y1: H - 2, y2: H, action: order });
      s.render();
    }

    setInterval(() => { step(); draw(); }, 900);
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    draw();
    return s;
  }

  //---------------------------------------------------------------- craft overseer

  // The crafting overseer's monitor: same layout as
  // computers/craft-overseer/overseer.lua. Three turtles work through a queue
  // where one order is short of iron until it "arrives"; click to add an order.
  function overseer(el) {
    const W = 39, H = 19;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const orders = [
      [{ name: "oak planks", left: 4, count: 4 }, { name: "stick", left: 8, count: 4 }, { name: "oak fence", left: 10, count: 3 }],
      [{ name: "spruce planks", left: 6, count: 4 }, { name: "spruce slab", left: 8, count: 6 }],
      [{ name: "lantern", left: 6, count: 1, needs: "6 iron nugget" }],
    ];
    let plan = 0;
    const queue = [];
    const add = (o) => { plan++; for (const j of o) queue.push({ ...j, plan, state: "queued" }); };
    orders.forEach(add);
    const turtles = [{ id: 12, job: null }, { id: 13, job: null }, { id: 14, job: null }];
    const st = { msg: ["The storage computer sent 6 crafts.", "lightBlue"], tick: 0, last: null };

    function next() {
      const busy = new Set();
      for (const j of queue) {
        if (!busy.has(j.plan) && j.state === "queued" && !j.needs) return j;
        busy.add(j.plan);
      }
    }

    function step() {
      st.tick++;
      if (st.tick % 12 === 0) for (const j of queue) if (j.needs) { j.needs = null; st.msg = ["Iron nuggets came in: lantern can start.", "lightGray"]; }
      for (const t of turtles) {
        if (!t.job) {
          const j = next();
          if (j) { j.state = "working"; j.on = t.id; t.job = j; }
          continue;
        }
        const j = t.job;
        j.left = Math.max(0, j.left - 2);
        if (j.left === 0) {
          queue.splice(queue.indexOf(j), 1);
          st.msg = [`Crafted ${j.count * 8} ${j.name} on turtle #${t.id}.`, "lime"];
          st.last = j;
          t.job = null;
        }
      }
      if (!queue.length && st.tick % 6 === 0) orders.forEach(add);
    }

    function draw() {
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "Crafting", "yellow", "gray");
      const head = `${queue.length} jobs`;
      s.put(W - head.length, 1, head, "lightGray", "gray");
      s.put(2, 3, "Turtles", "yellow");
      turtles.forEach((t, i) => {
        const text = t.job ? `crafting ${t.job.left * t.job.count} ${t.job.name}` : "idle";
        s.put(2, 4 + i, fitT(`#${t.id} ${text}`, W - 2), t.job ? "lightBlue" : "gray");
      });
      let y = 4 + turtles.length + 1;
      s.put(2, y++, "Queue", "yellow");
      for (const j of queue) {
        if (y > H - 2) break;
        const [state, colour] = j.state === "working" ? [`on #${j.on}`, "lightBlue"] : j.needs ? ["missing", "orange"] : ["queued", "white"];
        s.put(2, y, fitT(`${j.left * j.count} ${j.name}`, W - state.length - 3), "white");
        s.put(W - state.length, y, state, colour);
        y++;
        if (j.needs && y <= H - 2) s.put(4, y++, fitT(`needs ${j.needs}`, W - 4), "orange");
      }
      if (!queue.length) s.put(2, y, "Nothing queued.", "gray");
      s.put(1, H, fitT(st.msg[0], W), st.msg[1]);
      s.zones.push({ x1: 1, x2: W, y1: 1, y2: H, action: () => { add(orders[0]); st.msg = ["The storage computer sent 3 crafts.", "lightBlue"]; } });
      s.render();
    }

    setInterval(() => { step(); draw(); }, 900);
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    draw();
    return s;
  }

  //---------------------------------------------------------------- colony dashboard

  // The MineColonies dashboard on a monitor: same pages and layout as
  // computers/colony-dashboard/colony.lua, with a made-up colony. Tabs work.
  function colony(el) {
    const W = 57, H = 24;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const TABS = ["Overview", "Citizens", "Buildings", "Requests", "Builds"];
    const st = { tab: 0, scroll: 0, attack: false };
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const citizens = [
      ["Alice Brook", "Builder", "Working"], ["Ben Carter", "Farmer", "Working"], ["Cara Dune", "Miner", "Working"],
      ["Dale Ember", "Courier", "Delivering"], ["Eve Frost", "Unemployed", "Idle", "idle"], ["Finn Gale", "Knight", "Patrolling"],
      ["Gus Hale", "Cook", "Working"], ["Hana Iver", "Lumberjack", "Sleeping", "asleep"], ["Ivo Jett", "Fisher", "Working"],
      ["Jo Kent", "Builder", "Hungry - Working", "hungry"], ["Kai Lune", "Archer", "Patrolling", "hurt"], ["Lia Moss", "Smelter", "Working"],
      ["Max Noor", "Researcher", "Working"], ["Nia Oak", "Deliveryman", "Delivering"], ["Oli Pike", "Unemployed", "Idle", "idle"],
      ["Pia Quill", "Shepherd", "Sleeping", "asleep"], ["Rex Stone", "Baker", "Working"], ["Sue Tide", "Sawmill", "Working"],
      ["Tom Vale", "Guard", "Patrolling"], ["Uma West", "Farmer", "Working"], ["Vic Yew", "Miner", "Working"],
    ];
    const buildings = [
      ["Town hall", 3, 5, "", true], ["Builder", 2, 5, "Alice Brook", true], ["Builder", 1, 5, "Jo Kent", true],
      ["Farmer", 3, 5, "Ben Carter, Uma West", true], ["Miner", 2, 5, "Cara Dune, Vic Yew", true], ["Residence", 5, 5, "", true],
      ["Residence", 2, 5, "", true], ["Restaurant", 1, 5, "Gus Hale", true], ["Guard tower", 2, 5, "Finn Gale", true],
      ["Library", 0, 5, "being built", false], ["Warehouse", 3, 5, "", true], ["Barracks", 1, 5, "Tom Vale", true],
    ];
    const requests = [["Oak Planks", 64, "Builder"], ["Cobblestone", 128, "Builder"], ["Iron Ingot", 12, "Blacksmith"], ["Bread", 16, "Restaurant"], ["Glass Pane", 24, "Builder"]];
    const orders = [["Library -> 1", "build", "at 104,64,-31"], ["Residence -> 3", "upgrade", "at 98,63,-22"], ["Farmer -> 4", "upgrade", ""], ["Road", "decoration", ""]];
    const col = (c) => c === "idle" ? "yellow" : c === "asleep" ? "lightGray" : c === "hurt" ? "red" : "white";

    function bar(x, y, w, frac, colour) {
      const f = Math.round(Math.max(0, Math.min(1, frac)) * w);
      s.put(x, y, " ".repeat(f), "white", colour); s.put(x + f, y, " ".repeat(w - f), "white", "gray");
    }
    function list(items, y0, row) {
      const rows = H - y0 + 1, max = Math.max(0, items.length - rows);
      st.scroll = Math.max(0, Math.min(st.scroll, max));
      items.slice(st.scroll, st.scroll + rows).forEach((it, i) => row(it, y0 + i));
      if (max > 0) {
        const range = `${st.scroll + 1}-${Math.min(items.length, st.scroll + rows)} of ${items.length}`;
        s.put(W - 8 - range.length, 3, range, "lightGray");
        s.button(W - 7, 3, "v", "white", "lightGray", () => { st.scroll += rows - 1; });
        s.button(W - 3, 3, "^", "white", "lightGray", () => { st.scroll -= rows - 1; });
      }
    }
    function draw() {
      s.clear();
      const bg = st.attack ? "red" : "gray";
      s.fill(1, bg);
      s.put(2, 1, "Riverside" + (st.attack ? "  UNDER ATTACK!" : ""), st.attack ? "white" : "yellow", bg);
      let x = 1;
      TABS.forEach((t, i) => { x = s.button(x, 2, t, i === st.tab ? "black" : "white", i === st.tab ? "white" : "gray", () => { st.tab = i; st.scroll = 0; }); });
      if (st.tab === 0) {
        s.put(2, 4, "Citizens", "lightGray"); s.put(14, 4, "21 / 26"); bar(26, 4, W - 27, 21 / 26, "lime");
        s.put(2, 5, "Happiness", "lightGray"); s.put(14, 5, "7.4 / 10"); bar(26, 5, W - 27, 0.74, "lime");
        const facts = [["Idle", 2, "yellow"], ["Asleep", 2], ["Hungry", 1, "orange"], ["Hurt", 1, "red"], ["Graves", 0], ["Buildings", 12], ["Building sites", 1], ["Work orders", 4], ["Open requests", 5, "yellow"]];
        const cw = Math.floor((W - 2) / 2);
        facts.forEach(([k, v, c], i) => { const xx = 2 + (i % 2) * cw, yy = 7 + Math.floor(i / 2); s.put(xx, yy, fitT(k, cw - 6), "lightGray"); s.put(xx + cw - 6, yy, String(v), c || "white"); });
        s.put(2, 13, "Waiting for", "yellow");
        requests.forEach(([n, c, t], i) => { const cnt = `${c}x`; s.put(2, 14 + i, cnt, "lightGray"); s.put(3 + cnt.length, 14 + i, fitT(n, W - cnt.length - 20)); s.put(W - 15, 14 + i, fitT(t, 15), "lightGray"); });
        s.button(2, H, st.attack ? "End the raid" : "Simulate a raid", "white", st.attack ? "green" : "red", () => { st.attack = !st.attack; });
      } else if (st.tab === 1) {
        s.put(2, 4, fitT("Name", 20), "yellow"); s.put(23, 4, fitT("Job", 14), "yellow"); s.put(38, 4, "Doing", "yellow");
        list(citizens, 5, ([n, j, d, c], y) => { s.put(2, y, fitT(n, 20), col(c)); s.put(23, y, fitT(j, 14), "lightGray"); s.put(38, y, fitT(d, W - 38), col(c)); });
      } else if (st.tab === 2) {
        s.put(2, 4, fitT("Building", 24), "yellow"); s.put(27, 4, fitT("Level", 7), "yellow"); s.put(35, 4, "Workers", "yellow");
        list(buildings, 5, ([n, l, m, who, built], y) => { const c = !built ? "lightGray" : l >= m ? "lime" : "white"; s.put(2, y, fitT(n, 24), c); s.put(27, y, `${l}/${m}`, c); s.put(35, y, fitT(who, W - 35), built ? "lightGray" : "orange"); });
      } else if (st.tab === 3) {
        s.put(2, 4, fitT("Item", 30), "yellow"); s.put(33, 4, fitT("Count", 6), "yellow"); s.put(40, 4, "For", "yellow");
        list(requests, 5, ([n, c, t], y) => { s.put(2, y, fitT(n, 30)); s.put(33, y, String(c), "lightGray"); s.put(40, y, t, "lightGray"); });
      } else {
        s.put(2, 4, fitT("Work order", 24), "yellow"); s.put(27, 4, fitT("Type", 10), "yellow"); s.put(38, 4, "Builder", "yellow");
        list(orders, 5, ([n, t, b], y) => { s.put(2, y, fitT(n, 24)); s.put(27, y, fitT(t, 10), "lightGray"); s.put(38, y, b || "waiting for a builder", b ? "lime" : "yellow"); });
      }
      s.render();
    }
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    draw();
    return s;
  }

  window.CC = { PALETTE, Screen, Typer, fit, screens: { automine, dashboard, projector, storage, smelter, overseer, colony } };
})();
