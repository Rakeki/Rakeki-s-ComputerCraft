// CC: Tweaked terminal look-alikes: a character grid with the 16 CC colours,
// a typing terminal, and mock-ups of the AutoMine map, status dashboard,
// blueprint projector panel, storage terminal and monitor, smelter, cooker, craft overseer, colony dashboard
// and the Mekanism fission guard, power dashboard, fusion control, digital miner manager and enricher,
// the essence computer, build control on a pocket computer, and instabuild.
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
      { id: 12, label: "Miner-12", state: "unloading", detail: "at home", fuel: 860 },
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
      { id: 12, label: "Miner-12", role: "auto miner", kind: "turtle", state: "unloading", detail: "at home", pos: [3, 64, 2], from: "tracked", fuel: 860, limit: 20000 },
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
          c.detail = { unloading: "at home", travelling: "to chunk 2,-1", mining: "chunk 2,-1 layer 1/40" }[c.state];
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
    const plans = ["Cottage", "Watchtower", "Pagoda", "Sky Station"];
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
      s.put(1, H, fitT((st.tab === "craft" ? "Enter: craft a stack  Right: craft one" : "Enter: a stack  Right: one") + (st.query ? "  Del: clear" : st.tab === "craft" ? "  Tab: stored" : "  Tab: craftable"), W), "gray");
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

  //---------------------------------------------------------------- storage monitor

  // The storage computer's touch monitor: same layout as drawMonitor in
  // computers/storage-computer/storage.lua. Sort, search on the on-screen
  // keyboard, page, tap an item, then how many to send.
  function storageMonitor(el) {
    const W = 57, H = 19, AMOUNTS = [1, 16, 64], COLUMN = 26;
    const s = new Screen(W, H, el);
    el.classList.add("clickable");
    const fitT = (t, w) => (w <= 0 ? "" : t.length > w ? t.slice(0, w) : t.padEnd(w));
    const short = (n) => (n < 10000 ? String(n) : n < 1e6 ? `${(n / 1000).toFixed(1)}k` : `${(n / 1e6).toFixed(1)}M`);
    const items = [
      ["Cobblestone", 51200], ["Cobbled Deepslate", 23110], ["Dirt", 8400], ["Oak Log", 1388], ["Wheat", 912], ["Andesite", 870],
      ["Granite", 655], ["Carrot", 455], ["Oak Planks", 410], ["Iron Ingot", 302], ["Coal", 268], ["Sand", 250], ["Gravel", 233],
      ["Redstone Dust", 197], ["Bone Meal", 160], ["Oak Sapling", 140], ["Copper Ingot", 128], ["Iron Ore", 96], ["String", 88],
      ["Gold Ingot", 75], ["Potato", 64], ["Glass", 60], ["Torch", 52], ["Lapis Lazuli", 41], ["Bread", 30], ["Diamond", 23],
      ["Raw Iron", 18], ["Emerald", 12], ["Iron Pickaxe", 1], ["Enchanted Book", 3], ["Ender Pearl", 7], ["Iron Block", 9],
      ["Raw Gold", 33], ["Feather", 21], ["Leather", 17], ["Bow", 2],
    ].map(([name, count]) => ({ name, count }));
    const SLOTS = 27 * 80;
    const st = { sort: "count", query: "", typing: false, page: 1, pick: null, msg: ["", "lightGray"], auto: true };

    function take(it, n) {
      const sent = Math.min(n, it.count);
      it.count -= sent;
      st.msg = sent > 0 ? [`Sent ${sent} ${it.name} to the output chest.`, "lime"] : ["Couldn't send it: is the output chest full?", "red"];
      if (!it.count) st.pick = null;
    }

    function draw() {
      s.clear();
      const btn = (x, y, label, fg, bg, action) => { s.put(x, y, label, fg, bg); s.zones.push({ x1: x, x2: x + label.length - 1, y1: y, y2: y, action }); };
      let list = items.filter((it) => it.count > 0 && it.name.toLowerCase().includes(st.query));
      list = st.sort === "name" ? list.sort((a, b) => a.name.localeCompare(b.name)) : list.sort((a, b) => b.count - a.count);
      const picked = items.find((it) => it.name === st.pick && it.count > 0);

      const used = items.reduce((k, it) => k + Math.ceil(it.count / 64), 0);
      s.fill(1, "gray");
      s.put(2, 1, "Storage", "yellow", "gray");
      const stat = `80 chests, ${used}/${SLOTS} slots`;
      s.put(W - stat.length, 1, stat, "lightGray", "gray");
      const frac = Math.min(1, used / SLOTS), filled = Math.round(frac * W);
      const bar = fitT(` ${Math.round(frac * 100)}% full`, W);
      s.put(1, 2, bar.slice(0, filled), "white", frac > 0.9 ? "red" : frac > 0.7 ? "orange" : "green");
      s.put(filled + 1, 2, bar.slice(filled), "white", "gray");

      const top = 4, rows = (st.typing ? H - 5 : H - 2) - top + 1;
      const cols = Math.max(1, Math.floor(W / COLUMN)), colW = Math.floor(W / cols);
      const per = rows * cols, pages = Math.max(1, Math.ceil(list.length / per));
      st.page = Math.max(1, Math.min(st.page, pages));
      const first = (st.page - 1) * per;
      for (let c = 1; c <= cols; c++) {
        const x0 = (c - 1) * colW + 1, cw = c === cols ? W - x0 + 1 : colW - 1;
        for (let r = 1; r <= rows; r++) {
          const it = list[first + (c - 1) * rows + r - 1];
          if (!it) continue;
          const y = top + r - 1, count = short(it.count), on = it.name === st.pick, bg = on ? "blue" : "black";
          s.put(x0, y, fitT(" " + it.name, cw - count.length - 1), "white", bg);
          s.put(x0 + cw - count.length - 1, y, count + " ", on ? "white" : "lightGray", bg);
          s.zones.push({ x1: x0, x2: x0 + cw - 1, y1: y, y2: y, action: () => { st.pick = st.pick === it.name ? null : it.name; } });
        }
      }
      if (!list.length) s.put(2, top, st.query ? "No matches." : "Nothing stored yet.", "lightGray");

      const pageText = `${st.page}/${pages}`;
      let px = W - pageText.length - 5;
      if (pages > 1) {
        btn(px, 3, " < ", "white", st.page > 1 ? "gray" : "black", () => { st.page--; });
        s.put(px + 3, 3, pageText, "lightGray");
        btn(px + 3 + pageText.length, 3, " > ", "white", st.page < pages ? "gray" : "black", () => { st.page++; });
      } else px = W + 1;
      const sortLabel = st.sort === "count" ? " Most " : " A-Z ";
      btn(1, 3, sortLabel, "black", "lightGray", () => { st.sort = st.sort === "count" ? "name" : "count"; st.page = 1; });
      let find = st.typing ? ` ${st.query}_ ` : st.query ? ` ${st.query} ` : " Find ";
      const room = px - sortLabel.length - 3;
      if (find.length > room) find = room > 0 ? find.slice(-room) : "";
      if (find) btn(sortLabel.length + 2, 3, find, "black", st.typing || st.query ? "yellow" : "lightGray", () => { st.typing = !st.typing; });

      if (st.typing) {
        const kw = Math.max(1, Math.min(4, Math.floor(W / 10))), kx = Math.floor((W - kw * 10) / 2) + 1;
        const key = (i, y, label, width, action) => {
          const cell = kw > 1 ? width * kw - 1 : width, pad = Math.floor((cell - label.length) / 2);
          btn(kx + (i - 1) * kw, y, fitT(" ".repeat(pad) + label, cell), "white", "gray", action);
        };
        const typeCh = (ch) => () => { st.query += ch; st.page = 1; };
        ["abcdefghij", "klmnopqrst", "uvwxyz"].forEach((chars, r) => [...chars].forEach((ch, i) => key(i + 1, H - 4 + r, ch, 1, typeCh(ch))));
        key(7, H - 2, "_", 1, typeCh(" "));
        key(8, H - 2, "<", 1, () => { st.query = st.query.slice(0, -1); st.page = 1; });
        key(9, H - 2, "Clear", 2, () => { st.query = ""; st.page = 1; });
      }

      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      if (picked) {
        const labels = AMOUNTS.map((n) => ` ${n} `);
        let bx = W - (3 + labels.reduce((k, l) => k + l.length + 1, 0)) + 1;
        s.put(1, H, fitT(` ${picked.name} ${picked.count}`, bx - 5), "white");
        s.put(bx - 4, H, "Get", "lightGray");
        labels.forEach((l, i) => { btn(bx, H, l, "black", "lime", () => take(picked, AMOUNTS[i])); bx += l.length + 1; });
        btn(bx, H, " x ", "white", "red", () => { st.pick = null; });
      } else s.put(1, H, fitT(" Tap an item to send some to the output chest.", W), "gray");
      s.render();
    }

    // the demo: open the keyboard, type "iron", pick one, send 16, then sort A-Z and page
    const script = [() => { st.typing = true; }, ...[..."iron"].map((ch) => () => { st.query += ch; }),
      () => { st.typing = false; }, () => { st.pick = "Iron Ingot"; }, () => take(items.find((it) => it.name === "Iron Ingot"), 16), () => {},
      () => { st.pick = null; st.query = ""; st.msg = ["", "lightGray"]; }, () => { st.sort = "name"; }, () => {}, () => { st.page = 2; }, () => {},
      () => { st.page = 1; st.sort = "count"; }, () => {}];
    items.forEach((it) => { it.base = it.count; });
    let step = 0;
    setInterval(() => {
      if (!st.auto) return;
      script[step % script.length]();
      step++;
      if (step % script.length === 0) items.forEach((it) => { it.count = it.base; });
      draw();
    }, 900);

    el.addEventListener("click", (ev) => {
      if (st.auto) { st.auto = false; st.typing = false; st.query = ""; st.pick = null; st.msg = ["", "lightGray"]; }
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
  // click the footer (or the order lines) to place a charcoal order, then a
  // stone order as well, then cancel both.
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
    const st = { fuel: 2384, orders: [], msg: ["Loaded 80 items into 2 furnaces.", "lightGray"], tick: 0 };

    function load(f) {
      if (f.smoker) {
        const name = Object.keys(food).sort((a, b) => food[b] - food[a])[0];
        if (!food[name]) return;
        const n = Math.min(64, food[name]);
        food[name] -= n;
        f.input = [name, n];
      } else if (!f.blast && st.orders.some((o) => o.loaded < o.count)) {
        const o = st.orders.find((o) => o.loaded < o.count);
        const n = Math.min(64, o.count - o.loaded);
        o.loaded += n;
        f.input = [o.from, n];
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
        for (const o of st.orders) if (f.input[0] === o.from) o.made += n;
        if (st.tick % 8 === 0 && f.fuel) { f.fuel[1]--; st.fuel = Math.max(0, st.fuel - 8); }
        if (f.fuel && f.fuel[1] <= 0) f.fuel = null;
        if (f.input[1] <= 0) f.input = null;
      }
      for (const o of st.orders.filter((o) => o.made >= o.count)) {
        const charcoal = o.kind === "Charcoal";
        if (charcoal) st.fuel += o.made * 8;
        st.msg = [`Made ${o.made} ${o.kind.toLowerCase()}. It's in ${charcoal ? "the fuel chest" : "storage"}.`, "lime"];
        st.orders = st.orders.filter((x) => x !== o);
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
      const lines = st.orders.map((o) => `${o.kind}: ${o.made} of ${o.count} made from ${o.from}`);
      if (!lines.length) s.put(1, H - 2, fitT(" No orders.", W), "gray");
      lines.forEach((l, i) => s.put(1, H - 1 - lines.length + i, fitT(" " + l, W), "lightBlue"));
      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      s.put(1, H, fitT("C: charcoal  S: stone  X: cancel an order", W), "gray");
      const order = () => {
        if (!st.orders.length) {
          st.orders.push({ kind: "Charcoal", from: "spruce log", count: 128, loaded: 0, made: 0 });
          st.msg = ["Making 128 charcoal from spruce log.", "lightBlue"];
        } else if (st.orders.length === 1) {
          st.orders.push({ kind: "Stone", from: "cobblestone", count: 256, loaded: 0, made: 0 });
          st.msg = ["Making 256 stone from cobblestone.", "lightBlue"];
        } else {
          st.orders = [];
          st.msg = ["Orders cancelled. What's in the furnaces still smelts.", "lightGray"];
        }
      };
      s.zones.push({ x1: 1, x2: W, y1: H - 3, y2: H, action: order });
      s.render();
    }

    setInterval(() => { step(); draw(); }, 900);
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
    draw();
    return s;
  }

  //---------------------------------------------------------------- cooker

  // The cooker's screen: same layout as computers/cooker-computer/cooker.lua.
  // The XS pot cooks steadily, the S pot fills to 321 XS candy and then
  // cooks, and the M and L pots wait for smaller candy.
  function cooker(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const pots = [
      { makes: "exp candy xs", made: 412, state: "cooking", colour: "lime" },
      { makes: "exp candy s", made: 0, fill: 180, need: 321 },
      { makes: "exp candy m", made: 0, fill: 0, need: 129 },
      { makes: "exp candy l", made: 6, state: "needs exp candy m", colour: "orange" },
    ];
    const st = { msg: ["Sent 64 items to the pots.", "lightGray"], tick: 0 };

    function step() {
      st.tick++;
      pots[0].made++;
      const p = pots[1];
      if (p.fill < p.need) {
        p.fill = Math.min(p.need, p.fill + 25);
        p.state = `filling ~${p.fill}/${p.need}`; p.colour = "lightBlue";
        st.msg = ["Sent 64 items to the pots.", "lightGray"];
      } else {
        p.made++; p.state = "cooking"; p.colour = "lime";
        st.msg = ["Cooking in 2 pots.", "lightGray"];
      }
      pots[2].state = "needs exp candy s"; pots[2].colour = "orange";
      if (p.made > 40) { p.made = 0; p.fill = 180; pots[0].made = 412; }
    }

    function draw() {
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "Cooking pots", "yellow", "gray");
      s.put(2, 3, "#", "yellow"); s.put(5, 3, "Makes", "yellow"); s.put(21, 3, "Made", "yellow"); s.put(29, 3, "Doing", "yellow");
      pots.forEach((p, i) => {
        const y = 4 + i;
        s.put(2, y, String(i + 1), "lightGray");
        s.put(5, y, fitT(p.makes, 15), "white");
        s.put(21, y, fitT(String(p.made), 7), "white");
        s.put(29, y, fitT(p.state, W - 29), p.colour);
      });
      s.put(1, H - 1, fitT(st.msg[0], W), st.msg[1]);
      s.put(1, H, fitT("cooker add / relay / remove in another tab", W), "gray");
      s.render();
    }

    step();
    setInterval(() => { step(); draw(); }, 900);
    draw();
    return s;
  }

  //---------------------------------------------------------------- cooker monitor

  // The cooker's candy monitor: same layout as drawMonitor in
  // computers/cooker-computer/cooker.lua. XS candy comes out of its pot and
  // gets compressed into S now and then.
  function cookerMonitor(el) {
    const W = 39, H = 12;
    const s = new Screen(W, H, el);
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const commas = (n) => Math.floor(n).toLocaleString("en-US");
    const candy = [["XS", 1654, 100, 352], ["S", 213, 800, 171], ["M", 58, 3000, 0], ["L", 9, 10000, 0], ["XL", 2, 30000, 0], ["Rare", 12, null, 0]];
    const st = { sculk: 412, honeycomb: 96, tick: 0 };

    function step() {
      st.tick++;
      candy[0][1]++; st.sculk--; st.honeycomb--;
      if (st.tick % 5 === 0) { candy[0][1] -= 6; candy[1][1]++; }
      if (st.honeycomb <= 0) { st.honeycomb = 96; st.sculk = 412; }
    }

    function draw() {
      s.clear();
      const right = (x, y, t, c) => s.put(x - t.length + 1, y, t, c);
      const expR = W - 1, potsR = expR - 11, storedR = potsR - 8;
      s.fill(1, "gray");
      s.put(2, 1, "Exp candy", "yellow", "gray");
      s.put(2, 3, "Candy", "yellow"); right(storedR, 3, "Stored", "yellow"); right(potsR, 3, "In pots", "yellow"); right(expR, 3, "Exp", "yellow");
      let total = 0;
      candy.forEach(([name, n, exp, pots], i) => {
        const y = 4 + i;
        total += n * (exp || 0);
        s.put(2, y, name, "white"); right(storedR, y, commas(n), "white");
        right(potsR, y, pots ? "~" + commas(pots) : "", "lightBlue"); right(expR, y, exp ? commas(n * exp) : "-", "lightGray");
      });
      s.put(2, 10, "Exp stored", "white"); right(expR, 10, commas(total), "lime");
      s.put(2, 11, fitT(`For more: honeycomb ${st.honeycomb}, sculk ${st.sculk}`, W - 2), "lightGray");
      s.put(1, H, fitT("Cooking in 2 pots.", W), "lightGray");
      s.render();
    }

    setInterval(() => { step(); draw(); }, 900);
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

  //---------------------------------------------------------------- Mekanism helpers

  const fitM = (t, w) => (w <= 0 ? "" : t.length > w ? t.slice(0, w) : t.padEnd(w));
  const pctM = (f) => `${Math.round(f * 100)}%`;
  // 1234567 -> "1.23 M", like the programs' scaled()/energy()
  function scaledM(n) {
    const units = ["", "k", "M", "G", "T", "P"];
    let i = 0;
    while (Math.abs(n) >= 1000 && i < units.length - 1) { n /= 1000; i++; }
    return i === 0 ? `${Math.round(n)} ` : `${n.toFixed(2)} ${units[i]}`;
  }
  function barM(s, x, y, w, frac, colour) {
    const f = Math.round(Math.max(0, Math.min(1, frac)) * w);
    s.put(x, y, " ".repeat(f), "white", colour); s.put(x + f, y, " ".repeat(Math.max(0, w - f)), "white", "gray");
  }
  function clickable(s, el, draw) {
    el.classList.add("clickable");
    el.addEventListener("click", (ev) => { const { x, y } = s.cellAt(ev); const z = s.zoneAt(x, y); if (z) { z.action(); draw(); } });
  }

  //---------------------------------------------------------------- fission guard

  // computers/fission-guard/fission.lua on a monitor, with a made-up reactor
  // that warms, burns and fills with waste. The buttons work, and a coolant
  // leak shows the guard SCRAM and latch.
  function fission(el) {
    const W = 57, H = 24;
    const s = new Screen(W, H, el);
    const LIM = { temp: 1000, coolant: 0.1, heated: 0.9, waste: 0.8 };
    const r = { on: true, temp: 640, damage: 0, coolant: 1, heated: 0.06, fuel: 0.84, waste: 0.31, burn: 12, max: 20, power: 0.46, leak: false };
    const st = { latch: null, msg: null, msgC: "white" };
    const say = (t, c = "white") => { st.msg = t; st.msgC = c; };
    const problems = () => {
      const p = [];
      if (r.damage >= 1) p.push(`damage ${r.damage}% (limit 1%)`);
      if (r.temp >= LIM.temp) p.push(`temperature ${Math.round(r.temp)} K (limit 1000 K)`);
      if (r.coolant <= LIM.coolant) p.push(`coolant ${pctM(r.coolant)} (limit 10%)`);
      if (r.heated >= LIM.heated) p.push(`heated coolant ${pctM(r.heated)} (limit 90%)`);
      if (r.waste >= LIM.waste) p.push(`waste ${pctM(r.waste)} (limit 80%)`);
      return p;
    };
    const time = () => { const d = new Date(); return `${d.getHours()}:${String(d.getMinutes()).padStart(2, "0")}`; };

    function step() {
      if (r.leak) r.coolant = Math.max(0, r.coolant - 0.06);
      else r.coolant = Math.min(1, r.coolant + 0.04);
      const target = r.on ? 420 + r.burn * 18 + (1 - r.coolant) * 900 : 300;
      r.temp += (target - r.temp) * 0.25;
      if (r.on) { r.waste = Math.min(1, r.waste + 0.0008 * r.burn); r.fuel = Math.max(0, r.fuel - 0.0004 * r.burn); }
      else r.waste = Math.max(0.05, r.waste - 0.01);
      r.heated = r.on ? 0.04 + r.burn * 0.003 : Math.max(0, r.heated - 0.02);
      const p = problems();
      if (r.on && p.length) { r.on = false; st.latch = { reason: p[0], time: time() }; st.msg = null; }
    }

    function draw() {
      s.clear();
      const [word, col] = st.latch ? ["SCRAMMED", "red"] : r.on ? ["RUNNING", "green"] : ["STOPPED", "gray"];
      s.fill(1, col); s.put(2, 1, "Fission reactor", "white", col); s.put(W - word.length, 1, word, "white", col);
      const above = (v, l) => (v >= l ? "red" : v >= l * 0.85 ? "orange" : "lime");
      const below = (v, l) => (v <= l ? "red" : v <= l * 1.5 ? "orange" : "lime");
      const rows = [
        ["Temperature", `${Math.round(r.temp)} K`, r.temp / 1200, above(r.temp, LIM.temp)],
        ["Damage", `${r.damage}%`, r.damage / 100, r.damage > 0 ? "red" : "lime"],
        ["Coolant", pctM(r.coolant), r.coolant, below(r.coolant, LIM.coolant)],
        ["Heated coolant", pctM(r.heated), r.heated, above(r.heated, LIM.heated)],
        ["Fuel", pctM(r.fuel), r.fuel, below(r.fuel, 0.05)],
        ["Waste", pctM(r.waste), r.waste, above(r.waste, LIM.waste)],
        ["Matrix", pctM(r.power), r.power, "lightBlue"],
      ];
      let y = 3;
      for (const [k, v, f, c] of rows) { s.put(2, y, fitM(k, 14), "lightGray"); s.put(17, y, fitM(v, 10), c); barM(s, 28, y, W - 28, f, c); y++; }
      y++;
      s.put(2, y, fitM("Burn rate", 14), "lightGray"); s.put(17, y, `${r.burn.toFixed(1)} mB/t`);
      s.put(28, y, fitM(`actual ${(r.on ? r.burn : 0).toFixed(1)}, max ${r.max}`, W - 28), "lightGray"); y++;
      s.put(2, y, fitM("Heating", 14), "lightGray"); s.put(17, y, `${scaledM(r.on ? r.burn * 20000 : 0)}mB/t`);
      s.button(W - 25, y, r.leak ? "Fix the coolant leak" : "Simulate a coolant leak", "white", r.leak ? "green" : "red", () => { r.leak = !r.leak; });
      y += 2;
      if (st.latch) { s.put(2, y++, fitM(`SCRAM at ${st.latch.time}: ${st.latch.reason}`, W - 2), "red"); }
      if (st.msg && y < H - 1) s.put(2, y, fitM(st.msg, W - 2), st.msgC);
      let x = s.button(2, H - 1, "Start", "white", st.latch ? "gray" : "green", () => {
        if (st.latch) return say("Latched: tap Reset first.", "orange");
        const p = problems(); if (p.length) return say(`Can't start: ${p[0]}`, "red");
        if (r.on) return say("Reactor is already active.", "orange");
        r.on = true; say("Started.", "lime");
      });
      x = s.button(x, H - 1, "SCRAM", "white", "red", () => { if (!r.on) return say("Already stopped.", "lightGray"); r.on = false; say("SCRAMmed by hand.", "orange"); });
      x = s.button(x, H - 1, "Reset", st.latch ? "black" : "white", st.latch ? "yellow" : "gray", () => {
        if (!st.latch) return say("Nothing to reset.", "lightGray");
        const p = problems(); if (p.length) return say(`Still unsafe: ${p[0]}`, "red");
        st.latch = null; say("Reset. Tap Start when ready.", "lime");
      });
      s.put(x, H - 1, "Burn", "lightGray"); x += 5;
      for (const [label, d] of [["-1", -1], ["-.1", -0.1], ["+.1", 0.1], ["+1", 1]]) {
        x = s.button(x, H - 1, label, "white", "gray", () => { r.burn = Math.max(0, Math.min(r.max, Math.round((r.burn + d) * 10) / 10)); say(`Burn rate set to ${r.burn.toFixed(1)} mB/t.`); });
      }
      s.put(2, H, fitM("Limits: 1000 K, coolant 10%, heated 90%, waste 80%", W - 2), "gray");
      s.render();
    }

    setInterval(() => { step(); draw(); }, 600);
    clickable(s, el, draw);
    draw();
    return s;
  }

  //---------------------------------------------------------------- power dashboard

  // computers/power-dashboard/power.lua on a monitor: a made-up matrix
  // charging and draining, the graph scrolling (sped up), two turbines and a cube.
  function power(el) {
    const W = 57, H = 24;
    const s = new Screen(W, H, el);
    const MAX = 2.56e12; // joules
    const st = { stored: 0.62 * MAX, t: 0, graph: [] };
    for (let i = 0; i < 40; i++) st.graph.push(0.45 + 0.17 * Math.sin(i / 7) + i * 0.002);
    const fe = (j, suf = "") => `${scaledM(j / 2.5)}FE${suf}`;
    const colourOf = (f) => (f < 0.05 ? "red" : f < 0.2 ? "orange" : f < 0.5 ? "yellow" : "lime");
    const duration = (sec) => { const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60); return h > 0 ? `${h}h ${m}m` : `${m}m ${Math.floor(sec % 60)}s`; };

    function draw() {
      st.t++;
      const input = 2.0e6 + 0.8e6 * Math.sin(st.t / 5), output = 1.6e6 + 0.5e6 * Math.cos(st.t / 4);
      st.stored = Math.max(0, Math.min(MAX, st.stored + (input - output) * 20 * 600));
      const fill = st.stored / MAX, net = input - output;
      if (st.t % 2 === 0) { st.graph.push(fill); if (st.graph.length > W - 2) st.graph.shift(); }
      s.clear();
      s.fill(1, "gray"); s.put(2, 1, "Power: Induction Matrix", "yellow", "gray");
      s.put(2, 3, "Stored", "lightGray"); s.put(10, 3, fitM(`${fe(st.stored)} / ${fe(MAX)}`, W - 16)); s.put(W - 4, 3, fitM(pctM(fill), 4), colourOf(fill));
      barM(s, 2, 4, W - 2, fill, colourOf(fill));
      s.put(2, 6, "In", "lightGray"); s.put(6, 6, fe(input, "/t"), "lime"); s.put(23, 6, "Out", "lightGray"); s.put(28, 6, fe(output, "/t"), "orange");
      const status = net > 0 ? [`Full in ${duration((MAX - st.stored) / net / 20)}`, "lime"] : [`Empty in ${duration(st.stored / -net / 20)}`, "orange"];
      s.put(2, 7, status[0], status[1]); s.put(W - 10, 7, "Signal off", "lightGray");
      s.put(2, 8, fitM(`32 cells, 16 providers, up to ${fe(1.024e9, "/t")}`, W - 2), "lightGray");
      const top = 10, bottom = 20, rows = bottom - top + 1, gw = W - 2, n = st.graph.length;
      for (let x = 2; x <= 1 + gw - n; x++) for (let yy = top; yy <= bottom; yy++) s.put(x, yy, " ", "white", "gray");
      st.graph.forEach((f, i) => {
        const x = 2 + (gw - n) + i, filled = Math.round(f * rows);
        for (let r = 0; r < rows; r++) s.put(x, bottom - r, " ", "white", r < filled ? colourOf(f) : "gray");
      });
      s.put(W - 11, top, "last 60 min", "white", "gray");
      const lines = [
        ["Turbine 1", fe(1.1e6 + 0.2e6 * Math.sin(st.t / 3), "/t"), "steam 38% flow 72%", "white"],
        ["Turbine 2", fe(0.9e6 + 0.2e6 * Math.cos(st.t / 3), "/t"), "steam 41% flow 64%", "white"],
        ["Ultimate cube", fe(1.8e8), "70%", "lime"],
      ];
      lines.forEach(([a, b, c, col], i) => { const y = H - lines.length + 1 + i; s.put(2, y, fitM(a, 14), "lightGray"); s.put(17, y, fitM(b, 14), col); s.put(32, y, fitM(c, W - 32), col); });
      s.render();
    }

    setInterval(draw, 1000);
    draw();
    return s;
  }

  //---------------------------------------------------------------- fusion control

  // computers/fusion-control/fusion.lua on a monitor with a made-up,
  // water-cooled reactor. The injection buttons, Stop and Resume work.
  function fusion(el) {
    const W = 57, H = 24;
    const s = new Screen(W, H, el);
    const MAXP = 1.0e9, MAXC = 1.0e8, IGNITE = 1.0e8, MIN = 2;
    const r = { rate: 24, plasma: 4.6e8, kase: 4.1e7, deut: 0.72, trit: 0.66, dt: 0.5, water: 0.93, steam: 0.18, lit: true, last: null };
    const st = { msg: null, msgC: "white" };
    const say = (t, c = "white") => { st.msg = t; st.msgC = c; };
    const K = (k) => `${scaledM(k)}K`;

    function step() {
      if (r.lit) {
        r.plasma += ((2.0e8 + r.rate * 1.2e7) - r.plasma) * 0.2;
        r.dt = r.rate > 0 ? 0.5 : Math.max(0, r.dt - 0.12);
        if (r.dt === 0) r.lit = false;
      } else r.plasma = Math.max(3e5, r.plasma * 0.85);
      r.kase += ((r.lit ? 3.0e7 + r.rate * 5e5 : 3e2) - r.kase) * 0.2;
      r.deut = Math.max(0, Math.min(1, r.deut + (r.lit ? -0.002 : 0.004) * (r.rate / 10)));
      r.trit = Math.max(0, Math.min(1, r.trit + (r.lit ? -0.002 : 0.004) * (r.rate / 10)));
      r.steam = r.lit ? 0.1 + r.rate * 0.004 : Math.max(0, r.steam - 0.05);
    }

    function draw() {
      s.clear();
      const [word, col] = r.lit ? ["IGNITED", "green"] : ["NOT IGNITED", "gray"];
      s.fill(1, col); s.put(2, 1, "Fusion reactor", "white", col); s.put(W - word.length, 1, word, "white", col);
      const heat = (v, m) => (v / m >= 0.9 ? "red" : v / m >= 0.75 ? "orange" : "lime");
      const level = (f, low) => (f <= low ? "red" : f <= low * 2 ? "orange" : "lime");
      const rows = [
        ["Plasma", K(r.plasma), r.plasma / MAXP, heat(r.plasma, MAXP)],
        ["Case", K(r.kase), r.kase / MAXC, heat(r.kase, MAXC)],
        ["Deuterium", pctM(r.deut), r.deut, level(r.deut, 0.1)],
        ["Tritium", pctM(r.trit), r.trit, level(r.trit, 0.1)],
        ["D-T fuel", pctM(r.dt), r.dt, "lightBlue"],
        ["Water", pctM(r.water), r.water, level(r.water, 0.1)],
        ["Steam", pctM(r.steam), r.steam, r.steam >= 0.95 ? "orange" : "lightBlue"],
      ];
      let y = 3;
      for (const [k, v, f, c] of rows) { s.put(2, y, fitM(k, 14), "lightGray"); s.put(16, y, fitM(v, 11), c); barM(s, 28, y, W - 28, f, c); y++; }
      y++;
      s.put(2, y, fitM("Injection", 14), "lightGray"); s.put(16, y, `${r.rate} mB/t`); s.put(28, y, `needs ${MIN}+, max 98`, "lightGray"); y++;
      s.put(2, y, fitM("Making", 14), "lightGray"); s.put(16, y, `${scaledM(r.lit ? r.rate * 2.4e5 : 0)}FE/t`, r.lit ? "lime" : "white"); y++;
      s.put(2, y, fitM("Cooling", 14), "lightGray"); s.put(16, y, "water-cooled (steam to turbines)"); y += 2;
      if (!r.lit) {
        const hot = r.plasma >= IGNITE;
        const w = r.rate === 0 ? ["Stopped: injection rate is 0.", "lightGray"] : hot ? ["Plasma is still hot: add a filled Hohlraum to reignite.", "yellow"] : ["Not ignited: needs a filled Hohlraum and a laser burst.", "orange"];
        s.put(2, y++, fitM(w[0], W - 2), w[1]);
      }
      if (st.msg && y < H - 1) s.put(2, y, fitM(st.msg, W - 2), st.msgC);
      s.put(2, H - 1, "Inject", "lightGray");
      let x = 9;
      for (const [label, d] of [["-10", -10], ["-2", -2], ["+2", 2], ["+10", 10]]) {
        x = s.button(x, H - 1, label, "white", "gray", () => { r.rate = Math.max(0, Math.min(98, r.rate + d)); say(`Injection rate set to ${r.rate} mB/t.`); });
      }
      if (r.rate === 0 && r.last) s.button(x, H - 1, `Resume ${r.last}`, "white", "green", () => { r.rate = r.last; say(`Injection rate set to ${r.rate} mB/t.`); });
      else s.button(x, H - 1, "Stop", "white", "red", () => { if (r.rate > 0) r.last = r.rate; r.rate = 0; say("Injection rate set to 0 mB/t."); });
      s.put(2, H, fitM(`Limits: plasma ${K(MAXP)}, case ${K(MAXC)}`, W - 2), "gray");
      s.render();
    }

    setInterval(() => { step(); draw(); }, 900);
    clickable(s, el, draw);
    draw();
    return s;
  }

  //---------------------------------------------------------------- digital miner manager

  // computers/digital-miner-manager/dminer.lua on a monitor with four
  // made-up miners. Tap one for its page; the buttons change the mock-up.
  function dminer(el) {
    const W = 57, H = 24;
    const s = new Screen(W, H, el);
    const miners = [
      { title: "North quarry", state: "mining", left: 8412, radius: 32, minY: -64, maxY: 40, power: 0.92, silk: false, eject: true, filters: ["tag c:ores"] },
      { title: "South quarry", state: "mining", left: 5120, radius: 32, minY: -64, maxY: 40, power: 0.81, silk: false, eject: true, filters: ["tag c:ores"] },
      { title: "Diamond pit", state: "stopped", left: 63, radius: 24, minY: -64, maxY: 16, power: 0.40, silk: true, eject: true, filters: ["tag c:ores/diamond"] },
      { title: "Miner 4", state: "finished", left: 0, radius: 16, minY: 0, maxY: 60, power: 1, silk: false, eject: true, filters: [] },
    ];
    const st = { page: null, msg: null, msgC: "white" };
    const say = (t, c = "white") => { st.msg = t; st.msgC = c; };
    const COL = { mining: "lime", searching: "yellow", stopped: "orange", finished: "green", idle: "lightGray" };
    const idleOnly = (m, fn) => () => { if (m.state === "mining" || m.state === "stopped") return say(`${m.title}: Requires miner to be stopped/reset first`, "orange"); fn(); };

    function step() { for (const m of miners) if (m.state === "mining") { m.left = Math.max(0, m.left - 7); if (!m.left) m.state = "finished"; } }

    function drawList() {
      s.fill(1, "gray"); s.put(2, 1, `Digital Miners (${miners.length})`, "yellow", "gray");
      const x = s.button(2, 2, "Start all", "white", "green", () => { miners.forEach((m) => { if (m.left) m.state = "mining"; }); say("Start sent to 4 miners.", "lime"); });
      s.button(x, 2, "Stop all", "white", "red", () => { miners.forEach((m) => { if (m.state === "mining") m.state = "stopped"; }); say("Stop sent to 4 miners.", "lime"); });
      [["Miner", 2, 12], ["State", 15, 9], ["Left", 25, 7], ["Rad", 33, 3], ["Y", 37, 9], ["Power", 47, 5]].forEach(([t, x0, w]) => s.put(x0, 4, fitM(t, w), "yellow"));
      miners.forEach((m, i) => {
        const y = 5 + i;
        s.put(2, y, fitM(m.title, 12)); s.put(15, y, fitM(m.state, 9), COL[m.state]); s.put(25, y, fitM(String(m.left), 7));
        s.put(33, y, fitM(String(m.radius), 3), "lightGray"); s.put(37, y, fitM(`${m.minY}..${m.maxY}`, 9), "lightGray"); s.put(47, y, pctM(m.power), m.power < 0.1 ? "red" : "white");
        s.zones.push({ x1: 1, x2: W, y1: y, y2: y, action: () => { st.page = m; st.msg = null; } });
      });
      s.put(2, H, fitM(st.msg || "Tap a miner to control it.", W - 2), st.msg ? st.msgC : "gray");
    }

    function drawMiner(m) {
      s.fill(1, "gray");
      s.button(1, 1, "<", "white", "lightGray", () => { st.page = null; st.msg = null; });
      s.put(5, 1, fitM(m.title, W - 16), "yellow", "gray"); s.put(W - m.state.length, 1, m.state, COL[m.state], "gray");
      s.put(2, 3, fitM(`Left ${m.left} blocks   Radius ${m.radius}/32   Y ${m.minY}..${m.maxY}`, W - 2));
      s.put(2, 4, `Power ${pctM(m.power)}, using ${m.state === "mining" ? "4.6 kFE/t" : "0 FE/t"}`, "lightGray");
      let x = s.button(2, 6, "Start", "white", "green", () => { if (m.left) { m.state = "mining"; say(`${m.title} started.`, "lime"); } });
      x = s.button(x, 6, "Stop", "white", "red", () => { if (m.state === "mining") m.state = "stopped"; say(`${m.title} stopped.`, "orange"); });
      x = s.button(x, 6, "Reset", "black", "yellow", () => { m.state = "idle"; say(`${m.title} reset: settings can change now.`); });
      x = s.button(x + 1, 6, `Silk ${m.silk ? "on" : "off"}`, "white", m.silk ? "green" : "gray", () => { m.silk = !m.silk; });
      s.button(x, 6, `Eject ${m.eject ? "on" : "off"}`, "white", m.eject ? "green" : "gray", () => { m.eject = !m.eject; });
      const steps = (y, label, list, fn) => { s.put(2, y, label, "lightGray"); let xx = 9; for (const [t, d] of list) xx = s.button(xx, y, t, "white", "gray", () => fn(d)); };
      steps(8, "Radius", [["-8", -8], ["-1", -1], ["+1", 1], ["+8", 8]], (d) => idleOnly(m, () => { m.radius = Math.max(1, Math.min(32, m.radius + d)); say(`${m.title}: radius set to ${m.radius}.`); })());
      steps(9, "Min Y", [["-16", -16], ["-1", -1], ["+1", 1], ["+16", 16]], (d) => idleOnly(m, () => { m.minY = Math.max(-64, Math.min(m.maxY, m.minY + d)); say(`${m.title}: min Y set to ${m.minY}.`); })());
      steps(10, "Max Y", [["-16", -16], ["-1", -1], ["+1", 1], ["+16", 16]], (d) => idleOnly(m, () => { m.maxY = Math.max(m.minY, Math.min(320, m.maxY + d)); say(`${m.title}: max Y set to ${m.maxY}.`); })());
      s.put(2, 12, `Filters (${m.filters.length})`, "yellow");
      let y = 13;
      m.filters.forEach((f, i) => { s.button(2, y, "x", "white", "red", idleOnly(m, () => { m.filters.splice(i, 1); say("Filter removed."); })); s.put(6, y, fitM(f, W - 6)); y++; });
      if (!m.filters.length) s.put(2, y, "None: it mines everything it finds.", "lightGray");
      x = 2;
      for (const tag of ["c:ores", "c:ores/diamond", "c:ores/iron"]) {
        if (m.filters.includes(`tag ${tag}`)) continue;
        x = s.button(x, H - 1, `+ ${tag}`, "white", "blue", idleOnly(m, () => { m.filters.push(`tag ${tag}`); say(`Added tag ${tag}.`, "lime"); }));
      }
      s.put(2, H, fitM(st.msg || "Settings and filters change after Reset.", W - 2), st.msg ? st.msgC : "gray");
    }

    function draw() { s.clear(); if (st.page) drawMiner(st.page); else drawList(); s.render(); }
    setInterval(() => { step(); draw(); }, 2000);
    clickable(s, el, draw);
    draw();
    return s;
  }

  //---------------------------------------------------------------- enricher

  // The enricher's screen: same layout as computers/enricher-computer/enricher.lua.
  // Three chambers work through the ores in storage; the fourth has run out
  // of power.
  function enricher(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const stock = { "iron ore": 412, "raw gold": 147, "deepslate copper ore": 58, "redstone ore": 12 };
    const rows = [
      { title: "Chamber 1", item: "iron ore", queued: 64, power: 0.96 },
      { title: "Chamber 2", item: "raw gold", queued: 63, power: 0.88 },
      { title: "Factory", item: "deepslate copper ore", queued: 140, power: 0.71 },
      { title: "Chamber 4", item: "-", queued: 0, power: 0, state: "no power", colour: "red" },
    ];

    function step() {
      rows.slice(0, 3).forEach((r, i) => {
        r.queued -= i === 1 ? 3 : 1 + i;
        r.state = "enriching"; r.colour = "lime";
        if (r.queued < 20) r.queued += i === 1 ? 45 : 44;
      });
      stock["iron ore"] = Math.max(0, stock["iron ore"] - 1);
      stock["raw gold"] = Math.max(0, stock["raw gold"] - 3);
      if (stock["raw gold"] < 3) { stock["raw gold"] = 147; stock["iron ore"] = 412; }
    }

    function draw() {
      s.clear();
      s.fill(1, "gray");
      s.put(2, 1, "Enrichment chambers", "yellow", "gray");
      [["Chamber", 2], ["Ore", 15], ["Queue", 29], ["Pwr", 35], ["Doing", 40]].forEach(([t, x]) => s.put(x, 3, t, "yellow"));
      rows.forEach((r, i) => {
        const y = 4 + i, pct = Math.round(r.power * 100);
        s.put(2, y, fitT(r.title, 12), "white");
        s.put(15, y, fitT(r.item, 13), "lightGray");
        s.put(29, y, fitT(String(r.queued), 5), "white");
        s.put(35, y, fitT(pct + "%", 4), pct < 10 ? "red" : pct < 50 ? "orange" : "lime");
        s.put(40, y, fitT(r.state, W - 40), r.colour);
      });
      const list = Object.entries(stock).sort((a, b) => b[1] - a[1]);
      const total = list.reduce((n, [, c]) => n + c, 0);
      s.put(2, H - 2, fitT(`To enrich: ${total} (${list.map(([n, c]) => `${n} ${c}`).join(", ")})`, W - 2), "white");
      s.put(1, H - 1, fitT("Chamber 4: it has no power", W), "red");
      s.put(1, H, fitT("Ctrl+T twice, then enricher add / remove", W), "gray");
      s.render();
    }

    step();
    setInterval(() => { step(); draw(); }, 1000);
    draw();
    return s;
  }

  //---------------------------------------------------------------- essence computer

  // The essence computer's Recipes tab: same layout as
  // computers/essence-computer/essence.lua. The pots keep adding essence, so
  // the Can column creeps up; iron ingot is picked, with 4 crafts set.
  function essence(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    const fitT = (t, w) => (t.length > w ? t.slice(0, w) : t.padEnd(w));
    const ess = { iron: 212, copper: 96, dirt: 64, coal: 40, diamond: 9, honey: 6 };
    const stored = { "coal": 88, "copper ingot": 31, "diamond": 4, "dirt": 1210, "honey bottle": 0, "iron ingot": 143 };
    // item, what it takes, how many a craft makes, its essence, essence per craft
    const rows = [
      ["coal", "8 coal essence", 12, "coal", 8],
      ["copper ingot", "8 copper essence", 6, "copper", 8],
      ["diamond", "9 diamond essence", 1, "diamond", 9],
      ["dirt", "8 dirt essence", 24, "dirt", 8],
      ["honey bottle", "1 honey essence + 1 glass bottle", 1, "honey", 1],
      ["iron ingot", "8 iron essence", 6, "iron", 8],
    ];
    const sel = 5;

    function step() {
      ess.iron += 3; ess.copper += 2; ess.dirt += 1; ess.coal += 1;
      if (ess.iron > 400) Object.assign(ess, { iron: 212, copper: 96, dirt: 64, coal: 40 });
    }

    function draw() {
      s.clear();
      s.fill(1, "gray");
      const total = Object.values(ess).reduce((a, b) => a + b, 0);
      s.put(2, 1, fitT(`Essence ${total} (${Object.keys(ess).length} kinds)`, W - 20), "yellow", "gray");
      s.put(W - 16, 1, " Recipes ", "black", "yellow");
      s.put(W - 6, 1, " Pots ", "white", "gray");
      s.put(1, 2, "Find: ", "yellow");
      s.put(7, 2, fitT("", W - 7), "white", "gray");
      [["Makes", 2], ["From", 21], ["  Can", W - 12], ["Stored", W - 6]].forEach(([t, x]) => s.put(x, 3, t, "yellow"));
      rows.forEach(([name, from, count, e, per], i) => {
        const y = 4 + i, bg = i === sel ? "gray" : "black";
        const can = Math.floor(ess[e] / per) * count;
        s.put(1, y, " ".repeat(W), "white", bg);
        s.put(2, y, fitT(name, 18), "white", bg);
        s.put(21, y, fitT(from, W - 34), "lightGray", bg);
        s.put(W - 12, y, String(can).padStart(5), can > 0 ? "lime" : "gray", bg);
        s.put(W - 6, y, String(stored[name]).padStart(6), "lightGray", bg);
      });
      const y = H - 2;
      s.put(1, y, " - ", "black", "lightGray");
      s.put(5, y, "4 x 6 = 24", "white");
      s.put(16, y, " + ", "black", "lightGray");
      s.put(20, y, " Max ", "black", "lightGray");
      s.put(26, y, " Order ", "white", "green");
      s.put(1, H - 1, fitT("Crafting 24 iron ingot.", W), "lime");
      s.put(1, H, fitT("Type to find, arrows pick + amount, Enter orders", W), "gray");
      s.render();
    }

    step();
    setInterval(() => { step(); draw(); }, 1500);
    draw();
    return s;
  }

  //---------------------------------------------------------------- build control

  // computers/build-control/build.lua on a pocket computer: the sky station
  // handed to four builders, then their progress line as it changes (the
  // program's own print text).
  function buildControl(el) {
    const W = 26, H = 20;
    const s = new Screen(W, H, el);
    const total = 21166;
    const intro = [
      ["> build skystation", "white"], ["  100 150 -40", "white"],
      ["Sky Station facing north:", "white"], ["63 x 63 x 98, 21166 blocks,", "white"],
      ["from 100,150,-40 to", "white"], ["162,247,22.", "white"],
      ["It's built in the air:", "lightGray"], ["nothing is dug out first.", "lightGray"],
      ["Build it? (y/n) y", "yellow"], ["Looking for free builder", "white"], ["turtles...", "white"],
      ["4 builder turtles are", "lime"], ["building Sky Station.", "lime"],
    ];
    let done = 0;
    // wrap a line to the pocket computer's width, as print does
    const wrap = (t) => {
      const out = [];
      let line = "";
      for (const word of t.split(" ")) {
        if (line && (line + " " + word).length > W) { out.push(line); line = word; } else line = line ? line + " " + word : word;
      }
      out.push(line);
      return out;
    };
    function draw() {
      s.clear();
      const progress = wrap(`4 builders: ${done} of ${total} (${Math.floor(done / total * 100)}%)`);
      const lines = [...intro, ...progress.map((t) => [t, "white"])].slice(-H);
      lines.forEach(([t, c], i) => s.put(1, i + 1, t.slice(0, W), c));
      s.render();
    }
    setInterval(() => { done = done >= total ? 0 : Math.min(total, done + 137); draw(); }, 1200);
    draw();
    return s;
  }

  //---------------------------------------------------------------- instabuild

  // computers/instabuild/instabuild.lua on a command computer: the sky
  // station going in, with the program's own print text.
  function instabuild(el) {
    const W = 51, H = 19;
    const s = new Screen(W, H, el);
    const runs = 10459;
    let done = 0;
    function draw() {
      s.clear();
      const lines = [
        ["> instabuild skystation 100 150 -40", "white"],
        ["Sky Station facing north: 63 x 63 x 98, 21166", "white"], ["blocks,", "white"],
        ["from 100,150,-40 to 162,247,22.", "white"],
        ["It's built in the air: only its own blocks are", "lightGray"], ["placed.", "lightGray"],
        ["Build it? (y/n) y", "yellow"],
        ["Looking at what's there...", "white"],
        [`Building: ${done} of ${runs} runs`, "white"],
      ];
      if (done >= runs) {
        lines.push(["Built Sky Station: 21166 blocks changed.", "lime"], ["'instabuild undo' puts back what was there.", "white"]);
      }
      lines.forEach(([t, c], i) => s.put(1, i + 1, t.slice(0, W), c));
      s.render();
    }
    let pause = 0;
    setInterval(() => {
      if (done >= runs) { if (++pause > 4) { done = 0; pause = 0; } } else done = Math.min(runs, done + 800);
      draw();
    }, 600);
    draw();
    return s;
  }

  window.CC = { PALETTE, Screen, Typer, fit, screens: { automine, dashboard, projector, storage, storageMonitor, smelter, cooker, cookerMonitor, overseer, colony, fission, power, fusion, dminer, enricher, essence, buildControl, instabuild } };
})();
