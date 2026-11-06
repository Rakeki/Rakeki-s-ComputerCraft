// The network map: the base the simulator ran (sim/map.mjs writes
// network.json), drawn with voxel.js, with every computer marked and what
// they sent each other drawn on top. Drag to move, wheel or pinch to zoom,
// tap a computer for what it is, who it talks to and its screen at the end.
(function () {
  const COLOURS = {
    cc_status: "#7fcc19", automine: "#f2b233", storage: "#dede6c", projector_build: "#e57fd8", craft_overseer: "#b266e5",
    storage_crafter: "#f2b2cc", factory: "#a0805c", factory_crafter: "#c79a6a", gps: "#99b2f2", instabuild: "#4c99b2",
    village_plan: "#57a64e", village_crew: "#57a64e", wired: "#e0e0e0", http: "#cc4c4c", ender: "#3fb8a8",
  };
  const colourOf = (p) => COLOURS[p] || "#999999";
  const NAMES = {
    cc_status: "status reports", automine: "AutoMine jobs", storage: "storage requests", projector_build: "builds",
    craft_overseer: "crafting queue", storage_crafter: "craft jobs", factory: "factory parts", gps: "GPS", http: "overseer server (http)",
  };
  const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
  const svgNS = "http://www.w3.org/2000/svg";
  const el = (tag, attrs = {}, parent) => { const e = document.createElementNS(svgNS, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); if (parent) parent.append(e); return e; };

  function mount(holder, data, opts = {}) {
    const progUrl = opts.progUrl || ((n) => n);
    const byId = new Map(data.computers.map((c) => [c.id, c]));
    const box = data.box;
    const ground = 64;

    //---------------------------------------------------------------- where things are drawn

    // GPS hosts float high above the base: draw them lower, so the map isn't
    // mostly sky; computers far away go to the edge, towards where they are
    const cx = (box.x0 + box.x1) / 2, cz = (box.z0 + box.z1) / 2;
    const shown = (c) => {
      let [x, y, z] = c.pos;
      if (c.far) {
        const dx = x - cx, dz = z - cz, k = Math.min((box.x1 - cx - 2) / Math.abs(dx || 1), (box.z1 - cz - 2) / Math.abs(dz || 1));
        return { pos: [Math.round(cx + dx * k), ground, Math.round(cz + dz * k)], note: `really at ${x}, ${y}, ${z}` };
      }
      if (y > 110) return { pos: [x, Math.round(ground + 16 + (y - 110) * 0.25), z], note: `really at Y ${y}` };
      return { pos: [x, y, z] };
    };
    for (const c of data.computers) Object.assign(c, { shown: shown(c) });
    // several far computers in one place (the Nether outpost): side by side along the edge
    const spots = new Map();
    for (const c of data.computers.filter((x) => x.far)) {
      const k = c.shown.pos.join();
      const n = spots.get(k) || 0;
      spots.set(k, n + 1);
      const [x, y, z] = c.shown.pos;
      const alongZ = Math.abs(x - box.x0) < 3 || Math.abs(x - box.x1) < 3;
      c.shown.pos = alongZ ? [x, y, z - n * 3] : [x - n * 3, y, z];
    }

    const world = new Voxel.World();
    for (const [x, y, z, k] of data.blocks) if (Voxel.BLOCKS[k]) world.set(x - box.x0, y - ground, z - box.z0, k);
    for (const c of data.computers) {
      const [x, y, z] = c.shown.pos;
      if (c.far || c.pos[1] > 110) world.set(x - box.x0, y - ground, z - box.z0, c.kind === "turtle" ? "turtle" : c.kind === "computer" ? "computer" : "advanced");
      if (c.far) world.set(x - box.x0, y - ground - 1, z - box.z0, "enderchest");
    }
    const at = (c) => { const [x, y, z] = c.shown.pos; return [x - box.x0 + 0.5, y - ground + 1, z - box.z0 + 0.5]; };

    //---------------------------------------------------------------- the picture

    holder.innerHTML = `
      <div class="netmap">
        <div class="netmap-bar">
          <span class="grow netmap-hint">Drag to move, scroll to zoom, tap a computer</span>
          <button class="chip" data-act="rotate">Turn</button>
          <button class="chip" data-act="reset">Whole base</button>
        </div>
        <div class="netmap-view"><div class="netmap-stage"><canvas></canvas><svg class="netmap-over"></svg></div></div>
        <div class="netmap-protos"></div>
      </div>
      <div class="netmap-side mc-panel"><p class="netmap-empty">Tap a computer on the map, or pick one:</p><div class="netmap-list"></div></div>`;
    const view = holder.querySelector(".netmap-view");
    const stage = holder.querySelector(".netmap-stage");
    const canvas = holder.querySelector("canvas");
    const svg = holder.querySelector("svg");
    const side = holder.querySelector(".netmap-side");
    let rot = 0, P = null, W = 0, H = 0;

    // protocols, each a chip that hides or shows its lines
    const protos = new Map();
    const note = (p, n) => protos.set(p, (protos.get(p) || 0) + n);
    for (const l of data.links) note(l.protocol, l.count);
    for (const b of data.broadcasts) if (b.heardBy.length) note(b.protocol, b.count);
    if (data.gps.askers.length) note("gps", data.gps.askers.reduce((n, a) => n + a.count, 0));
    if (data.http.posts) note("http", data.http.posts);
    const hidden = new Set();
    const protoBar = holder.querySelector(".netmap-protos");
    protoBar.innerHTML = [...protos.entries()].sort((a, b) => b[1] - a[1]).map(([p, n]) =>
      `<button class="chip netmap-proto" aria-pressed="true" data-proto="${esc(p)}"><i style="background:${colourOf(p)}"></i>${esc(NAMES[p] || p)} <span class="count">${n.toLocaleString("en")}</span></button>`).join("")
      + `<span class="netmap-key"><i class="wired"></i>cable (wired network)</span>`;
    protoBar.onclick = (e) => {
      const b = e.target.closest("[data-proto]");
      if (!b) return;
      const p = b.dataset.proto;
      hidden.has(p) ? hidden.delete(p) : hidden.add(p);
      b.setAttribute("aria-pressed", String(!hidden.has(p)));
      drawOver();
    };

    const turnPt = ([x, y, z]) => { for (let i = 0; i < rot; i++) { const t = x; x = -z; z = t; } return [x, y, z]; };
    function draw() {
      const width = Math.max(900, Math.min(2400, view.clientWidth * 2));
      const r = Voxel.render(canvas, world.rotated(rot), { width, pad: 0.03, detail: 1, edges: false });
      P = r.P; W = r.w; H = r.h;
      canvas.style.width = W + "px"; canvas.style.height = H + "px";
      svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
      svg.style.width = W + "px"; svg.style.height = H + "px";
      drawOver();
      fit();
    }
    const pt = (p) => P(...turnPt(p));

    // lines and markers
    let selected = null;
    function drawOver() {
      svg.innerHTML = "";
      const lines = el("g", { class: "lines" }, svg);
      const arc = (a, b, colour, width, dashed, title) => {
        const [x1, y1] = pt(a), [x2, y2] = pt(b);
        const mx = (x1 + x2) / 2, my = (y1 + y2) / 2 - Math.max(20, Math.hypot(x2 - x1, y2 - y1) * 0.25);
        const path = el("path", { d: `M${x1},${y1} Q${mx},${my} ${x2},${y2}`, stroke: colour, fill: "none", class: "netmap-line" + (dashed ? " dashed" : ""), style: `--w:${width}px` }, lines);
        if (title) el("title", {}, path).textContent = title;
        return path;
      };
      const w = (n) => Math.min(6, 1.2 + Math.log10(n + 1) * 1.4);
      const involved = (a, b) => !selected || a === selected.id || b === selected.id;
      // GPS: every computer that asked, to the hosts
      if (!hidden.has("gps")) for (const a of data.gps.askers) {
        const c = byId.get(a.id);
        if (!c || !involved(a.id, -1)) continue;
        for (const h of data.gps.hosts) if (byId.get(h) && (!selected || a.id === selected.id || h === selected.id)) arc(at(c), at(byId.get(h)), colourOf("gps"), 0.8, true, `${c.label}: ${a.count} GPS fixes`).style.opacity = selected ? 0.9 : 0.18;
      }
      for (const b of data.broadcasts) {
        if (hidden.has(b.protocol)) continue;
        for (const to of b.heardBy) {
          const A = byId.get(b.from), B = byId.get(to);
          if (A && B && involved(b.from, to)) arc(at(A), at(B), colourOf(b.protocol), 1, true, `${A.label} → ${B.label}: ${b.count} ${b.protocol} broadcasts`).style.opacity = selected ? 0.9 : 0.35;
        }
      }
      for (const l of data.links) {
        if (hidden.has(l.protocol)) continue;
        const A = byId.get(l.from), B = byId.get(l.to);
        if (A && B && involved(l.from, l.to)) arc(at(A), at(B), colourOf(l.protocol), w(l.count), false, `${A.label} → ${B.label}: ${l.count} ${l.protocol} messages`);
      }
      // the bridge posts to the overseer server on the PC: off the map, up
      if (!hidden.has("http") && data.http.posts) {
        const b = data.computers.find((c) => c.program === "overseer-bridge");
        if (b && involved(b.id, -2)) { const a = at(b); arc(a, [a[0], a[1] + 14, a[2]], colourOf("http"), 2.5, false, `${data.http.posts} posts (${data.http.packets} messages) to the overseer server`); }
      }
      // markers
      const marks = el("g", {}, svg);
      for (const c of data.computers) {
        const [x, y] = pt(at(c));
        const g = el("g", { class: "netmap-mark" + (selected && selected.id === c.id ? " on" : ""), transform: `translate(${x},${y})`, "data-id": c.id }, marks);
        if (c.pos[1] < ground - 2 && !c.far) {
          // underground: a drop line from the surface
          const [sx, sy] = pt([at(c)[0], 1, at(c)[2]]);
          el("line", { x1: sx - x, y1: sy - y, x2: 0, y2: 0, class: "netmap-drop" }, g);
        }
        // markers and labels keep their size as the map zooms (--k)
        const k = el("g", { class: "k" }, g);
        el("circle", { r: 7, class: "dot", fill: c.on ? (c.kind === "turtle" ? "#f2b233" : "#7fcc19") : "#cc4c4c" }, k);
        const t = el("text", { y: -12, class: "lbl" }, k);
        t.textContent = c.label || `#${c.id}`;
        if (c.shown.note) { const n = el("text", { y: 22, class: "lbl sub" }, k); n.textContent = c.shown.note; }
        el("title", {}, g).textContent = `${c.label || "#" + c.id}: ${c.program}`;
      }
      scaleText();
    }

    //---------------------------------------------------------------- pan and zoom

    let zoom = 1, ox = 0, oy = 0, minZoom = 0.1;
    const apply = () => { stage.style.transform = `translate(${ox}px,${oy}px) scale(${zoom})`; scaleText(); };
    function scaleText() { svg.style.setProperty("--k", String(1 / Math.max(zoom, 0.0001))); declutter(); }
    // labels that would cover another are hidden (shown on hover), the
    // selected computer's first, then computers before turtles
    function declutter() {
      const taken = [];
      const marks = [...svg.querySelectorAll(".netmap-mark")];
      const rank = (m) => { const c = byId.get(Number(m.dataset.id)); return (selected && selected.id === c.id ? 0 : 2) + (c.kind === "turtle" ? 1 : 0); };
      marks.sort((a, b) => rank(a) - rank(b));
      for (const m of marks) {
        const [, x, y] = m.getAttribute("transform").match(/translate\(([-\d.]+),([-\d.]+)\)/).map(Number);
        const sx = x * zoom + ox, sy = y * zoom + oy;
        const lbl = m.querySelector(".lbl");
        const half = ((lbl.textContent.length * 7.5) / 2) + 3;
        const r = [sx - half, sy - 26, sx + half, sy - 8];
        const clash = taken.some((t) => r[0] < t[2] && r[2] > t[0] && r[1] < t[3] && r[3] > t[1]);
        m.classList.toggle("quiet", clash);
        if (!clash) taken.push(r);
      }
    }
    function fit() {
      const vw = view.clientWidth, vh = view.clientHeight;
      minZoom = Math.min(vw / W, vh / H);
      zoom = minZoom; ox = (vw - W * zoom) / 2; oy = (vh - H * zoom) / 2;
      apply();
    }
    const zoomAt = (k, px, py) => {
      const nz = Math.max(minZoom * 0.8, Math.min(minZoom * 6, zoom * k));
      ox = px - (px - ox) * (nz / zoom); oy = py - (py - oy) * (nz / zoom); zoom = nz; apply();
    };
    view.addEventListener("wheel", (e) => { e.preventDefault(); const r = view.getBoundingClientRect(); zoomAt(Math.exp(-e.deltaY * 0.0015), e.clientX - r.left, e.clientY - r.top); }, { passive: false });
    const pointers = new Map();
    let moved = 0, pinch = null;
    view.addEventListener("pointerdown", (e) => { view.setPointerCapture(e.pointerId); pointers.set(e.pointerId, [e.clientX, e.clientY]); moved = 0; });
    view.addEventListener("pointermove", (e) => {
      if (!pointers.has(e.pointerId)) return;
      const [px, py] = pointers.get(e.pointerId);
      pointers.set(e.pointerId, [e.clientX, e.clientY]);
      if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        const d = Math.hypot(a[0] - b[0], a[1] - b[1]);
        const r = view.getBoundingClientRect();
        if (pinch) zoomAt(d / pinch, (a[0] + b[0]) / 2 - r.left, (a[1] + b[1]) / 2 - r.top);
        pinch = d; moved += 10;
        return;
      }
      ox += e.clientX - px; oy += e.clientY - py; moved += Math.abs(e.clientX - px) + Math.abs(e.clientY - py);
      apply();
    });
    const up = (e) => { pointers.delete(e.pointerId); if (pointers.size < 2) pinch = null; };
    view.addEventListener("pointerup", (e) => {
      up(e);
      if (moved > 6) return;
      const m = document.elementFromPoint(e.clientX, e.clientY)?.closest(".netmap-mark");
      select(m ? byId.get(Number(m.dataset.id)) : null);
    });
    view.addEventListener("pointercancel", up);
    holder.querySelector('[data-act="rotate"]').onclick = () => { rot = (rot + 1) % 4; draw(); };
    holder.querySelector('[data-act="reset"]').onclick = () => { select(null); fit(); };
    let resizeT;
    window.addEventListener("resize", () => { clearTimeout(resizeT); resizeT = setTimeout(fit, 200); });

    //---------------------------------------------------------------- details

    const listHtml = () => data.computers.map((c) => `<button class="chip" data-pick="${c.id}"><i class="dot ${c.kind === "turtle" ? "t" : ""}"></i>${esc(c.label || "#" + c.id)}</button>`).join("");
    side.querySelector(".netmap-list").innerHTML = listHtml();
    side.addEventListener("click", (e) => { const b = e.target.closest("[data-pick]"); if (b) select(byId.get(Number(b.dataset.pick))); const x = e.target.closest("[data-close]"); if (x) select(null); });

    function talks(c) {
      const rows = [];
      for (const l of data.links) {
        if (l.from === c.id) rows.push([l.protocol, `to ${byId.get(l.to)?.label || "#" + l.to}`, l.count]);
        else if (l.to === c.id) rows.push([l.protocol, `from ${byId.get(l.from)?.label || "#" + l.from}`, l.count]);
      }
      // what it hears is one line per protocol: "hears 22 computers"
      const heard = new Map();
      for (const b of data.broadcasts) {
        if (b.from === c.id) rows.push([b.protocol, b.heardBy.length ? `broadcast, heard by ${b.heardBy.map((i) => byId.get(i)?.label).join(", ")}` : "broadcast", b.count]);
        else if (b.heardBy.includes(c.id)) { const h = heard.get(b.protocol) || { n: 0, from: 0 }; h.n += b.count; h.from++; heard.set(b.protocol, h); }
      }
      for (const [p, h] of heard) rows.push([p, `hears ${h.from} computer${h.from === 1 ? "" : "s"}`, h.n]);
      const g = data.gps.askers.find((a) => a.id === c.id);
      if (g) rows.push(["gps", "asks the GPS hosts where it is", g.count]);
      if (data.gps.hosts.includes(c.id)) rows.push(["gps", `answers ${data.gps.askers.length} computers`, ""]);
      if (c.program === "overseer-bridge" && data.http.posts) rows.push(["http", `posts to the overseer server: ${data.http.packets.toLocaleString("en")} messages`, data.http.posts]);
      for (const h of data.hosts.filter((x) => x.id === c.id)) rows.push([h.protocol, `hosts it as "${h.name}"`, ""]);
      rows.sort((a, b) => (Number(b[2]) || 0) - (Number(a[2]) || 0));
      return rows;
    }
    const screenHtml = (lines) => `<div class="screen netmap-screen"><pre class="cc-term">${esc(lines.join("\n").replace(/\s+$/, ""))}</pre></div>`;

    function select(c) {
      selected = c;
      drawOver();
      if (!c) { side.innerHTML = `<p class="netmap-empty">Tap a computer on the map, or pick one:</p><div class="netmap-list">${listHtml()}</div>`; return; }
      const nets = data.nets.filter((n) => n.computers.includes(c.id));
      const modems = c.modems.map((m) => m.type === "wired" ? `wired (${m.net} cable)` : `${m.type} modem`).join(", ") || "none";
      const rows = talks(c);
      side.innerHTML = `
        <div class="netmap-head"><b>${esc(c.label || "#" + c.id)}</b><button class="chip" data-close>Back</button></div>
        <p><a href="${progUrl(c.program)}">${esc(c.program)}</a> on ${c.kind === "turtle" ? "a turtle" : c.kind === "pocket" ? "a pocket computer" : c.kind === "computer" ? "a computer" : "an advanced computer"} #${c.id}${c.on ? "" : ", <b>off</b>"}</p>
        <p class="netmap-facts">At ${c.pos.join(", ")}${c.kind === "turtle" ? `, fuel ${c.fuel}` : ""}<br>Modems: ${esc(modems)}${nets.map((n) => `<br>On the ${esc(n.name)} cable with ${n.members.length} blocks: ${esc([...new Set(n.members.map((m) => m.type.replace(/^\w+:/, "")))].join(", "))}`).join("")}${c.state ? `<br>Says: ${esc(c.state)}${c.detail ? ": " + esc(c.detail) : ""}` : ""}</p>
        ${rows.length ? `<table class="netmap-talk">${rows.map(([p, what, n]) => `<tr><td><i style="background:${colourOf(p)}"></i>${esc(p)}</td><td>${esc(what)}</td><td>${n === "" ? "" : Number(n).toLocaleString("en")}</td></tr>`).join("")}</table>` : `<p class="netmap-facts">Works on its own: no messages.</p>`}
        <h4>Its screen at the end</h4>${screenHtml(c.screen)}
        ${c.monitor ? `<h4>Its monitor</h4>${screenHtml(c.monitor)}` : ""}`;
    }

    draw();
    return { select, redraw: draw };
  }

  window.NetMap = { mount, COLOURS };
})();
