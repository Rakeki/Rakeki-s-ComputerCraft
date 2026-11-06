// The replay viewer: plays back a recorded simulation (sim/replay.mjs) with
// the site's voxel renderer. The world is redrawn when blocks change (a few
// times a second at most); turtles, labels and messages are drawn on a
// second canvas every frame, so they move smoothly.
(async function () {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const name = new URLSearchParams(location.search).get("replay") || "bootstrap";
  let data;
  try { data = await (await fetch(`replays/${name}.json`)).json(); } catch {
    document.body.innerHTML = `<p style="padding:20px">No replay called "${esc(name)}". Make one with <code>node sim/replay.mjs ${esc(name)}</code>.</p>`;
    return;
  }
  const box = data.meta.box, END = data.meta.seconds, G = 64;
  const MOVE = 0.4; // seconds a turtle move takes
  // the GPS hosts float high up: draw them lower, so the view isn't mostly sky
  const dispY = (y) => (y > 110 ? Math.round(G + 16 + (y - 110) * 0.25) : y);
  const PALETTE = ["#f2b233", "#e57fd8", "#99b2f2", "#7fcc19", "#cc4c4c", "#4c99b2", "#dede6c", "#b266e5"];
  const PROTO = { cc_status: "#7fcc19", gps: "#99b2f2", automine: "#f2b233", storage: "#dede6c", projector_build: "#e57fd8", craft_overseer: "#b266e5" };
  const byId = new Map(data.computers.map((c) => [c.id, c]));
  const turtles = data.computers.filter((c) => c.kind === "turtle");
  turtles.forEach((c, i) => { c.colour = PALETTE[i % PALETTE.length]; });
  const fmt = (t) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;
  $("title").textContent = data.meta.scenario;
  $("summary").textContent = `${turtles.length} turtles, ${data.computers.length - turtles.length} computers, ${fmt(END)} of game time, simulated ${data.meta.made}`;

  //---------------------------------------------------------------- state at time T

  let blocks, pos, status, screens, msgs, idx, cur, dirty;
  function reset() {
    blocks = new Map(data.blocks0.map(([x, y, z, k]) => [`${x},${y},${z}`, k]));
    pos = new Map(data.computers.map((c) => [c.id, { x: c.start[0], y: c.start[1], z: c.start[2], h: 0, fuel: 0, fx: c.start[0], fy: c.start[1], fz: c.start[2], t0: -1 }]));
    status = new Map(); screens = new Map(); msgs = [];
    idx = 0; cur = 0; dirty = true;
  }
  function apply(e) {
    switch (e[0]) {
      case "b": { const k = `${e[2]},${e[3]},${e[4]}`; if (e[5]) blocks.set(k, e[5]); else blocks.delete(k); dirty = true; break; }
      case "p": { const p = pos.get(e[2]); pos.set(e[2], { x: e[3], y: e[4], z: e[5], h: e[6], fuel: e[7], fx: p ? p.x : e[3], fy: p ? p.y : e[4], fz: p ? p.z : e[5], t0: e[1] }); break; }
      case "s": status.set(e[2], [e[3], e[4]]); break;
      case "t": screens.set(e[2], e[3]); break;
      case "m": msgs.push(e); if (msgs.length > 200) msgs.splice(0, 100); break;
    }
  }
  function seek(T) {
    if (T < cur) reset();
    while (idx < data.ev.length && data.ev[idx][1] <= T) apply(data.ev[idx++]);
    for (const c of data.computers) if (c.born > cur && c.born <= T) dirty = true;
    cur = T;
  }

  //---------------------------------------------------------------- drawing

  const canvas = $("world"), over = $("over"), view = $("view"), stage = $("stage");
  let rot = 0, P = null, W = 0, H = 0, lastRender = 0;
  // cut: hide every block above this Y (null: none), to see the mines
  let cut = null;
  const lowY = () => (cut === null ? Math.max(box.y0, 40) : box.y0);
  const turn = ([x, y, z]) => { for (let i = 0; i < rot; i++) { const t = x; x = -z; z = t; } return [x, y, z]; };
  // display coordinates: relative to the box corner, ground at 0
  const local = (x, y, z) => [x - box.x0, dispY(y) - G, z - box.z0];
  const corners = () => {
    const out = [];
    for (const x of [0, box.x1 - box.x0]) for (const y of [lowY() - G, (cut === null ? dispY(box.y1) : cut) - G]) for (const z of [0, box.z1 - box.z0]) out.push(turn([x, y, z]));
    return out;
  };
  function renderWorld() {
    const world = new Voxel.World();
    for (const [k, kind] of blocks) {
      if (!Voxel.BLOCKS[kind]) continue;
      const [x, y, z] = k.split(",").map(Number);
      if (cut !== null && y > cut) continue;
      if (y < lowY()) continue;
      world.set(...local(x, y, z), kind);
    }
    for (const c of data.computers) if (c.kind !== "turtle" && c.kind !== "pocket" && c.born <= cur && (cut === null || c.start[1] <= cut)) world.set(...local(...c.start), c.kind === "computer" ? "computer" : "advanced");
    const width = Math.max(900, Math.min(2200, view.clientWidth * 1.6));
    const r = Voxel.render(canvas, world.rotated(rot), { width, pad: 0.04, detail: 1, edges: false, bounds: corners() });
    if (!r) return;
    P = r.P; W = r.w; H = r.h;
    canvas.style.width = W + "px"; canvas.style.height = H + "px";
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (over.width !== Math.round(W * dpr)) { over.width = Math.round(W * dpr); over.height = Math.round(H * dpr); }
    over.style.width = W + "px"; over.style.height = H + "px";
    dirty = false; lastRender = performance.now();
  }
  const pt = (x, y, z) => P(...turn([x, y, z]));

  // where a computer is drawn at time T (turtles slide over a move)
  function where(c, T) {
    const p = pos.get(c.id);
    if (!p) return local(...c.start);
    const k = p.t0 < 0 ? 1 : Math.min(1, (T - p.t0) / MOVE);
    return local(p.fx + (p.x - p.fx) * k, p.fy + (p.y - p.fy) * k, p.fz + (p.z - p.fz) * k);
  }

  function cube(ctx, [x, y, z], colour, size = 0.8) {
    const m = (1 - size) / 2, x0 = x + m, x1 = x + 1 - m, z0 = z + m, z1 = z + 1 - m, y0 = y, y1 = y + size;
    const face = (pts, shade) => {
      ctx.beginPath();
      pts.forEach(([a, b, c], i) => { const [px, py] = pt(a, b, c); i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); });
      ctx.closePath();
      ctx.fillStyle = colour; ctx.globalAlpha = 1; ctx.fill();
      ctx.fillStyle = "#000"; ctx.globalAlpha = shade; ctx.fill();
      ctx.globalAlpha = 1; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.lineWidth = 1; ctx.stroke();
    };
    // the three faces facing the viewer, whichever way the view is turned
    const near = [[[x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1]]];
    const sides = [
      [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], [[x1, y0, z0], [x1, y0, z1], [x1, y1, z1], [x1, y1, z0]],
      [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]], [[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]],
    ];
    const show = [[0, 1], [1, 2], [2, 3], [3, 0]][rot];
    face(sides[show[0]], 0.2); face(sides[show[1]], 0.38); face(near[0], 0);
  }

  function label(ctx, x, y, text, colour) {
    ctx.font = `600 ${13 / zoom}px "Pixelify Sans", monospace`;
    ctx.textAlign = "center"; ctx.textBaseline = "bottom";
    ctx.lineWidth = 4 / zoom; ctx.strokeStyle = "rgba(0,0,0,0.85)"; ctx.strokeText(text, x, y);
    ctx.fillStyle = colour; ctx.fillText(text, x, y);
  }

  function drawOver(T) {
    if (!P) return;
    const dpr = over.width / W;
    const ctx = over.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    // messages of the last second and a half: a line to whoever it was for,
    // a ring for a broadcast
    for (const m of msgs) {
      const age = T - m[1];
      if (age < 0 || age > 1.5) continue;
      const a = byId.get(m[2]); if (!a) continue;
      const [ax, ay, az] = where(a, T);
      const [sx, sy] = pt(ax + 0.5, ay + 0.6, az + 0.5);
      ctx.globalAlpha = 1 - age / 1.5;
      ctx.strokeStyle = PROTO[m[4]] || "#bbbbbb"; ctx.lineWidth = 2 / zoom;
      if (m[3] >= 0 && byId.get(m[3])) {
        const [bx, by, bz] = where(byId.get(m[3]), T);
        const [ex, ey] = pt(bx + 0.5, by + 0.6, bz + 0.5);
        ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke();
      } else {
        ctx.beginPath(); ctx.ellipse(sx, sy, (6 + age * 40) / Math.sqrt(zoom), (3.5 + age * 23) / Math.sqrt(zoom), 0, 0, Math.PI * 2); ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
    // turtles, far ones first
    const order = turtles.map((c) => ({ c, p: where(c, T) })).sort((a, b) => { const [ax, , az] = turn(a.p), [bx, , bz] = turn(b.p); return (ax + az) - (bx + bz); });
    for (const { c, p } of order) {
      cube(ctx, p, c.colour, selected === c ? 0.95 : 0.8);
      const [lx, ly] = pt(p[0] + 0.5, p[1] + 1.3, p[2] + 0.5);
      label(ctx, lx, ly, c.label, selected === c ? "#ffffff" : c.colour);
    }
    if (selected && selected.kind !== "turtle") {
      const [x, y, z] = where(selected, T);
      const [lx, ly] = pt(x + 0.5, y + 1.3, z + 0.5);
      label(ctx, lx, ly, selected.label, "#ffffff");
    }
  }

  //---------------------------------------------------------------- pan, zoom, pick

  let zoom = 1, ox = 0, oy = 0, minZoom = 0.2;
  const apply2 = () => { stage.style.transform = `translate(${ox}px,${oy}px) scale(${zoom})`; };
  function fit() {
    const vw = view.clientWidth, vh = view.clientHeight;
    minZoom = Math.min(vw / W, vh / H);
    zoom = minZoom; ox = (vw - W * zoom) / 2; oy = (vh - H * zoom) / 2; apply2();
  }
  const zoomAt = (k, px, py) => {
    const nz = Math.max(minZoom * 0.8, Math.min(minZoom * 10, zoom * k));
    ox = px - (px - ox) * (nz / zoom); oy = py - (py - oy) * (nz / zoom); zoom = nz; apply2();
  };
  view.addEventListener("wheel", (e) => { e.preventDefault(); const r = view.getBoundingClientRect(); zoomAt(Math.exp(-e.deltaY * 0.0015), e.clientX - r.left, e.clientY - r.top); }, { passive: false });
  const pointers = new Map(); let moved = 0, pinch = null;
  view.addEventListener("pointerdown", (e) => { view.setPointerCapture(e.pointerId); pointers.set(e.pointerId, [e.clientX, e.clientY]); moved = 0; });
  view.addEventListener("pointermove", (e) => {
    if (!pointers.has(e.pointerId)) return;
    const [px, py] = pointers.get(e.pointerId);
    pointers.set(e.pointerId, [e.clientX, e.clientY]);
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()], d = Math.hypot(a[0] - b[0], a[1] - b[1]), r = view.getBoundingClientRect();
      if (pinch) zoomAt(d / pinch, (a[0] + b[0]) / 2 - r.left, (a[1] + b[1]) / 2 - r.top);
      pinch = d; moved += 10; return;
    }
    ox += e.clientX - px; oy += e.clientY - py; moved += Math.abs(e.clientX - px) + Math.abs(e.clientY - py); apply2();
  });
  view.addEventListener("pointerup", (e) => {
    pointers.delete(e.pointerId); if (pointers.size < 2) pinch = null;
    if (moved > 6 || !P) return;
    const r = view.getBoundingClientRect();
    const sx = (e.clientX - r.left - ox) / zoom, sy = (e.clientY - r.top - oy) / zoom;
    let best = null, bestD = 18 / zoom;
    for (const c of data.computers) {
      if (c.born > cur) continue;
      const [x, y, z] = where(c, cur);
      const [px, py] = pt(x + 0.5, y + 0.5, z + 0.5);
      const d = Math.hypot(px - sx, py - sy);
      if (d < bestD) { best = c; bestD = d; }
    }
    select(best);
  });

  //---------------------------------------------------------------- side panel

  let selected = null;
  const rows = [...turtles, ...data.computers.filter((c) => c.kind !== "turtle")];
  $("list").innerHTML = rows.map((c) => `<div class="row" data-id="${c.id}"><span class="dot" style="background:${c.colour || "#666"}"></span><span><b>${esc(c.label)}</b><span class="what"></span></span><span class="fuel"></span></div>`).join("");
  $("list").onclick = (e) => { const r = e.target.closest(".row"); if (r) select(byId.get(Number(r.dataset.id))); };
  function select(c) { selected = selected === c ? null : c; panel(true); }
  let lastPanel = "";
  function panel(force) {
    for (const r of $("list").children) {
      const c = byId.get(Number(r.dataset.id));
      r.hidden = c.born > cur;
      const st = status.get(c.id);
      r.classList.toggle("on", selected === c);
      r.querySelector(".what").textContent = `${c.role}${st && st[0] ? ": " + st[0] + (st[1] ? ", " + st[1] : "") : ""}`;
      const p = pos.get(c.id);
      r.querySelector(".fuel").textContent = c.kind === "turtle" && p ? `fuel ${p.fuel}` : "";
    }
    if (!selected) { if (force || lastPanel) $("detail").innerHTML = `<p>Tap a turtle on the map, or in the list, to see its screen.</p>`; lastPanel = ""; return; }
    const p = pos.get(selected.id), st = status.get(selected.id);
    const html = `<h2>${esc(selected.label)}</h2><p>${esc(selected.role)}${p ? ` · at ${p.x}, ${p.y}, ${p.z}` : ""}${st && st[0] ? ` · ${esc(st[0])}${st[1] ? ": " + esc(st[1]) : ""}` : ""}</p><div class="screen"><pre>${esc(screens.get(selected.id) || "")}</pre></div>`;
    if (html !== lastPanel || force) { $("detail").innerHTML = html; lastPanel = html; }
  }
  function ticker(T) {
    const recent = [];
    for (let i = msgs.length - 1; i >= 0 && recent.length < 6; i--) if (msgs[i][1] <= T) recent.push(msgs[i]);
    $("ticker").innerHTML = recent.map((m) => `<li><i style="background:${PROTO[m[4]] || "#bbb"}"></i>${fmt(m[1])} <b>${esc(byId.get(m[2])?.label)}</b> → ${m[3] >= 0 ? `<b>${esc(byId.get(m[3])?.label || "#" + m[3])}</b>` : "everyone"}: ${esc(m[4])}</li>`).join("");
  }

  //---------------------------------------------------------------- playing

  const slider = $("time");
  slider.max = END;
  let playing = false, T = 0, last = performance.now(), uiAt = 0;
  const setPlaying = (on) => { playing = on; $("play").textContent = on ? "❚❚" : "▶"; };
  $("play").onclick = () => { if (T >= END) T = 0; setPlaying(!playing); };
  slider.oninput = () => { T = Number(slider.value); seek(T); };
  $("turn").onclick = () => { rot = (rot + 1) % 4; renderWorld(); fit(); };
  $("cut").onchange = () => { cut = $("cut").value === "" ? null : Number($("cut").value); renderWorld(); fit(); };
  $("fit").onclick = fit;
  window.addEventListener("resize", () => fit());
  document.addEventListener("keydown", (e) => { if (e.key === " " && e.target === document.body) { e.preventDefault(); $("play").click(); } });

  function frame(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    if (playing) {
      T = Math.min(END, T + dt * Number($("speed").value));
      seek(T);
      slider.value = T;
      if (T >= END) setPlaying(false);
    }
    if (dirty && now - lastRender > 350) renderWorld();
    drawOver(T);
    if (now - uiAt > 250) { uiAt = now; $("clock").textContent = `${fmt(T)} / ${fmt(END)}`; panel(); ticker(T); }
    requestAnimationFrame(frame);
  }
  reset(); seek(0); renderWorld(); fit(); panel(true);
  requestAnimationFrame(frame);
})();
