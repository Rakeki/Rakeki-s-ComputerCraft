// Builds the home page and the program / library pages from window.SITE.
(function () {
  const SITE = window.SITE;
  const ROOT = document.body.dataset.root || "./";
  const $ = (sel, root = document) => root.querySelector(sel);
  const h = (html) => { const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
  const cc = (name) => `var(--cc-${name})`;
  const icon = (device) => `${ROOT}assets/${device === "turtle" ? "turtle" : "computer"}.svg`;
  const progUrl = (name) => `${ROOT}programs/${name}/`;
  const groupById = Object.fromEntries((SITE.groups || []).map((g) => [g.id, g]));
  // which parts of the home page a program is in: modded if it needs a mod
  // besides CC: Tweaked, or the ones its "parts" names (the factory: both)
  const partsOf = (p) => p.parts || [(p.mods || []).length ? "modded" : "vanilla"];
  const partOf = (p) => partsOf(p)[0];
  const partById = Object.fromEntries((SITE.sections || []).map((k) => [k.id, k]));
  const planUrl = (name) => `${ROOT}plans/${name}/`;
  const libUrl = (name) => `${ROOT}libraries/${name}/`;
  const byName = Object.fromEntries(SITE.programs.map((p) => [p.name, p]));
  const libByName = Object.fromEntries(SITE.libraries.map((l) => [l.name, l]));

  //---------------------------------------------------------------- copy

  let toastT;
  function toast(text) {
    let t = $(".toast");
    if (!t) { t = h(`<div class="toast" role="status"></div>`); document.body.append(t); }
    t.textContent = text; t.classList.add("show");
    clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove("show"), 1600);
  }
  document.addEventListener("click", async (e) => {
    const b = e.target.closest("[data-copy]");
    if (!b) return;
    try { await navigator.clipboard.writeText(b.dataset.copy); } catch {
      const ta = h(`<textarea></textarea>`); ta.value = b.dataset.copy; document.body.append(ta); ta.select(); document.execCommand("copy"); ta.remove();
    }
    b.classList.add("done"); const old = b.textContent; b.textContent = "Copied";
    setTimeout(() => { b.classList.remove("done"); b.textContent = old; }, 1400);
    toast("Copied. Paste it in-game with Ctrl+V");
  });

  const installCmd = (name) => `wget run ${SITE.url}/install.lua${name ? " " + name : ""}`;
  function cmdHtml(cmd) {
    return esc(cmd)
      .replace(/^(wget|mkdir)( run)?/, (m) => `<span class="p">${m}</span>`)
      .replace(/(https?:\/\/\S+)/, `<span class="u">$1</span>`)
      .replace(/(\.lua|\.json) (\S+)$/, `$1 <span class="a">$2</span>`);
  }
  const field = (cmd) => `<div class="mc-field"><code>${cmdHtml(cmd)}</code><button class="copy-btn" data-copy="${esc(cmd)}" aria-label="Copy command">Copy</button></div>`;

  //---------------------------------------------------------------- renders

  function lazy(el, fn) {
    if (!("IntersectionObserver" in window)) return fn();
    const io = new IntersectionObserver((es) => { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { rootMargin: "200px" });
    io.observe(el);
  }

  function screenEl(scene, compact) {
    const kind = ["dashboard", "projector", "colony", "storageMonitor", "fission", "breeder", "power", "fusion", "dminer"].includes(scene) ? "monitor" : "advanced";
    const b = h(`<div class="bezel ${kind} lit"><div class="screen"><pre class="cc-term"></pre></div></div>`);
    if (compact) { b.style.padding = "8px 8px 14px"; b.style.boxShadow = "inset 3px 3px 0 var(--frame-hi), inset -3px -3px 0 var(--frame-lo)"; }
    CC.screens[scene]($("pre", b));
    return b;
  }

  // One of the display monitor's animations (programs.json "animations"),
  // played by its own anim.lua in the browser once it's scrolled into view.
  function animEl(name, compact) {
    const a = (SITE.animations || []).find((x) => x.name === name);
    const b = h(`<div class="bezel monitor lit"><div class="screen"><pre class="cc-term"></pre></div></div>`);
    if (compact) { b.style.padding = "8px 8px 14px"; b.style.boxShadow = "inset 3px 3px 0 var(--frame-hi), inset -3px -3px 0 var(--frame-lo)"; }
    const pre = $("pre", b);
    new CC.Screen(57, 24, pre).render(); // its size before it loads
    if (a) lazy(b, () => Anims.mount(pre, { root: ROOT, file: a.file, name: a.name }));
    return b;
  }

  function thumb(p, holder) {
    const r = p.render;
    if (r.kind === "voxel") {
      const c = document.createElement("canvas");
      holder.append(c);
      lazy(holder, () => Voxel.mount(c, r.scene, { width: holder.clientWidth, aspect: 16 / 10, labels: false, detail: 2, animate: false, pad: 0.07 }));
    } else if (r.kind === "gallery") {
      holder.append(h(`<img class="cover" loading="lazy" alt="${esc(r.images[0][0])}" src="${ROOT}${r.images[0][1]}">`));
    } else {
      // a screen: below the tag, and narrow enough to fit the picture's
      // height (its text grows with its width, so its shape stays the same)
      holder.classList.add("screen-thumb");
      const b = r.kind === "animation" ? animEl(r.name, true) : screenEl(r.scene, true);
      b.style.width = "86%";
      holder.append(b);
      let shape = 0;
      const size = () => {
        const cs = getComputedStyle(holder);
        const room = holder.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
        if (room <= 0 || !b.offsetHeight) return;
        if (!shape) shape = b.offsetWidth / b.offsetHeight;
        b.style.width = `${Math.floor(Math.min(holder.clientWidth * 0.86, room * shape))}px`;
      };
      requestAnimationFrame(() => requestAnimationFrame(size)); // once the text has been sized
      window.addEventListener("resize", size);
    }
  }

  //---------------------------------------------------------------- home

  function home() {
    // hero terminal: install a program, then run it
    const scripts = ["excavate-turtle", "village-turtle", "gps-deployer"].map((name) => {
      const p = byName[name];
      const lines = [["> ", installCmd(name), "cmd"], [`Connecting to ${SITE.url}/install.lua... Success.`, "", "lightGray"], [`Installing ${p.title}...`, "", "yellow"]];
      p.files.forEach((f) => lines.push([`  ${f.dest} ok`, "", "lime"]));
      lines.push([`${p.title} is installed.`, "", "lime"]);
      lines.push(...p.terminal.lines.slice(0, 5));
      return lines;
    });
    new CC.Typer($("#hero-term"), 51, 19, scripts, { header: [["CraftOS 1.9", "yellow"]] });
    $("#hero-cmd").innerHTML = field(installCmd(""));

    const lua = new Set(); let lines = 0;
    for (const p of SITE.programs) for (const f of p.files) if (!lua.has(f.src)) { lua.add(f.src); lines += f.lines; }
    $("#stat-programs").textContent = SITE.programs.length;
    $("#stat-libs").textContent = SITE.libraries.length;
    $("#stat-lines").textContent = lines.toLocaleString("en");

    // two parts (vanilla & CC, modded: "sections"), each with a section per
    // group in the order of "groups"; chips show one part, one group, or both
    const holder = $("#program-groups");
    const filters = $("#group-filters");
    const sections = {}, usedGroups = new Set();
    const parts = SITE.sections || [{ id: "vanilla", title: "", tagline: "" }];
    for (const k of parts) {
      const inPart = SITE.programs.filter((p) => partsOf(p).includes(k.id));
      if (!inPart.length) continue;
      const part = h(`<section class="part" id="part-${k.id}" data-part="${k.id}">
        <div class="part-head"><h3>${esc(k.title)} <span class="count">${inPart.length}</span></h3><p>${esc(k.tagline)}</p></div></section>`);
      holder.append(part);
      for (const g of SITE.groups || []) {
        const members = inPart.filter((p) => p.group === g.id);
        if (!members.length) continue;
        usedGroups.add(g.id);
        const sec = h(`<section class="group" id="group-${k.id}-${g.id}" data-group="${g.id}" data-part="${k.id}">
          <div class="group-head"><h3>${esc(g.title)} <span class="count">${members.length}</span></h3><p>${esc(g.tagline)}</p></div>
          <div class="grid"></div></section>`);
        part.append(sec);
        sections[`${k.id}/${g.id}`] = $(".grid", sec);
      }
    }
    const chip = (kind, id, label) => `<button class="chip" data-${kind}="${id}" aria-pressed="${id === "all"}">${esc(label)}</button>`;
    filters.innerHTML = `<div class="filters" role="group" aria-label="Show vanilla or modded">${chip("part", "all", "Everything")}${parts.filter((k) => holder.querySelector(`#part-${k.id}`)).map((k) => chip("part", k.id, k.title)).join("")}</div>`
      + `<div class="filters" role="group" aria-label="Show one group">${chip("group", "all", "All")}${(SITE.groups || []).filter((g) => usedGroups.has(g.id)).map((g) => chip("group", g.id, g.title)).join("")}</div>`;
    for (const p of SITE.programs) for (const part of partsOf(p)) {
      const grid = sections[`${part}/${p.group}`];
      if (!grid) continue;
      // in the modded part, a program that needs no mod shows the ones it works with
      const mods = (p.mods || []).length ? p.mods.map((m) => [m, ""]) : part === "modded" ? (p.worksWith || []).map((m) => [m, " soft"]) : [];
      const card = h(`
        <a class="card" href="${progUrl(p.name)}" style="--c:${cc(p.color)}" data-device="${p.device}">
          <div class="thumb"><span class="tag">${esc(p.deviceLabel)}</span></div>
          <div class="body">
            <h3>${esc(p.title)} <code>${esc(p.command)}</code></h3>
            <p>${esc(p.tagline)}</p>
            <div class="meta">
              ${mods.map(([m, soft]) => `<span class="pill mod${soft}">${esc(m)}</span>`).join("")}
              ${p.libs.map((l) => `<span class="pill lib">lib/${l}</span>`).join("")}
              ${p.files.length ? `<span class="pill">${p.files.length} files</span>` : ""}
              <span class="go">Open &rarr;</span>
            </div>
          </div>
        </a>`);
      grid.append(card);
      thumb(p, $(".thumb", card));
    }
    const shown = { part: "all", group: "all" };
    const pick = (kind, f) => {
      shown[kind] = f;
      filters.querySelectorAll(`[data-${kind}]`).forEach((c) => c.setAttribute("aria-pressed", c.dataset[kind] === f));
      holder.querySelectorAll(".group").forEach((s) => {
        s.hidden = (shown.part !== "all" && s.dataset.part !== shown.part) || (shown.group !== "all" && s.dataset.group !== shown.group);
      });
      holder.querySelectorAll(".part").forEach((k) => { k.hidden = !k.querySelector(".group:not([hidden])"); });
    };
    filters.querySelectorAll("[data-part]").forEach((c) => c.addEventListener("click", () => pick("part", c.dataset.part)));
    filters.querySelectorAll("[data-group]").forEach((c) => c.addEventListener("click", () => pick("group", c.dataset.group)));
    // a link to #group-<id> or #part-<id> (from a program page) shows just that
    const follow = (wait) => {
      const linked = location.hash.match(/^#(group|part)-(\w+)$/);
      if (!linked) return;
      const [, kind, id] = linked;
      if (kind === "group" ? !usedGroups.has(id) : !holder.querySelector(`#part-${id}`)) return;
      pick(kind === "group" ? "part" : "group", "all");
      pick(kind, id);
      // once the cards have laid out, or the page jumps under it
      setTimeout(() => $("#programs").scrollIntoView(), wait);
    };
    follow(300);
    window.addEventListener("hashchange", () => follow(0));

    $("#diagram").innerHTML = diagram();
    // squeeze any title that renders wider than its box
    document.querySelectorAll("#diagram text[data-room]").forEach((t) => {
      const room = +t.dataset.room;
      if (t.getComputedTextLength() > room) { t.setAttribute("textLength", room); t.setAttribute("lengthAdjust", "spacingAndGlyphs"); }
    });

    const example = byName["excavate-turtle"];
    $("#way-installer").innerHTML = field(installCmd("excavate-turtle"));
    $("#way-wget").innerHTML = field(`wget ${SITE.url}/${example.files[0].src} ${example.files[0].dest}`);

    const planCards = $("#plan-cards");
    for (const pl of SITE.plans || []) {
      const card = h(`
        <div class="lib-card">
          <h3><a href="${planUrl(pl.name)}">${esc(pl.title)}</a></h3>
          <p>${esc(pl.tagline)}</p>
          ${field(`install plan ${pl.name}`)}
          <div class="meta"><span class="pill">${esc(pl.size)}</span>${pl.hole ? `<span class="pill">hole ${esc(pl.hole)}</span>` : ""}<span class="pill">${pl.blocks.toLocaleString("en")} blocks</span><a class="pill" href="${planUrl(pl.name)}">See it in 3D</a></div>
        </div>`);
      planCards.append(card);
    }

    const libs = $("#libs");
    for (const l of SITE.libraries) {
      const card = h(`
        <a class="lib-card" href="${libUrl(l.name)}">
          <h3><code>require("lib.${l.name}")</code></h3>
          <p>${esc(l.tagline)}</p>
          <pre class="code"><code class="language-lua"></code></pre>
          <div class="meta">${l.usedBy.map((n) => `<span class="pill">${esc(byName[n].title)}</span>`).join(" ")}</div>
        </a>`);
      $("pre code", card).textContent = l.usage;
      libs.append(card);
    }
    highlight();
  }

  // How the programs talk to each other. The lime bus is status (lib/report):
  // the dashboard, turtle finder, update watcher and overseer bridge hear it,
  // and the lime corner on a box means it reports. The light blue corner means
  // it finds itself by GPS. The coloured lines are the other ways they work
  // together. Lines run down the gaps between boxes so they cross as little
  // as possible: move a box and check its lines still miss the others.
  function diagram() {
    // [x, y, width, program page, title, device, accent, corners: r = reports, g = GPS]
    const N = {
      finder: [250, 60, 180, "turtle-finder", "Turtle Finder", "computer", "lime", "g"],
      status: [510, 60, 220, "status-server", "Status Dashboard", "computer", "cyan", ""],
      watcher: [770, 60, 200, "update-watcher", "Update Watcher", "computer", "lime", "r"],
      bridge: [1030, 60, 200, "overseer-bridge", "Overseer Bridge", "computer", "cyan", "r"],
      server: [110, 220, 180, "mine-server", "AutoMine Server", "computer", "yellow", "r"],
      projector: [340, 220, 200, "blueprint-projector", "Blueprint Projector", "computer", "magenta", "r"],
      storage: [640, 220, 200, "storage-computer", "Storage System", "computer", "blue", "r"],
      overseer: [900, 220, 180, "craft-overseer", "Craft Overseer", "computer", "orange", "r"],
      hosts: [1100, 220, 150, "gps-deployer", "GPS hosts × 4", "computer", "purple", ""],
      miners: [110, 380, 180, "mine-turtle", "AutoMine Turtles", "turtle", "orange", "rg"],
      builders: [285, 380, 130, "builder-turtle", "Builders", "turtle", "pink", "rg"],
      village: [435, 380, 130, "village-turtle", "Village", "turtle", "lime", "rg"],
      farms: [580, 380, 120, "tree-farm-turtle", "Farms", "turtle", "green", "rg"],
      factory: [740, 380, 140, "factory", "Factory", "computer", "red", "r"],
      crafters: [905, 380, 150, "crafter-turtle", "Crafters", "turtle", "brown", "r"],
      deployer: [1100, 380, 150, "gps-deployer", "GPS Deployer", "turtle", "purple", "r"],
      strip: [110, 540, 150, "strip-mine-turtle", "Strip Miner", "turtle", "lightBlue", "rg"],
      control: [285, 540, 150, "build-control", "Build Control", "computer", "pink", "r"],
      instabuild: [445, 540, 140, "instabuild", "Instabuild", "computer", "purple", ""],
      excavate: [575, 540, 130, "excavate-turtle", "Excavator", "turtle", "orange", "rg"],
      terminals: [745, 540, 150, "craft-terminal", "Terminals", "computer", "lightBlue", "r"],
      mob: [1100, 540, 150, "mob-farm-turtle", "Mob Farm", "turtle", "red", "rg"],
    };
    const P = CC.PALETTE;
    const line = (d, c, w = 2.5, extra = "") => `<path class="flow" d="${d}" stroke="${c}" stroke-width="${w}" fill="none"${extra}/>`;
    let edges = "";
    // status: a bus between the listeners and the row of computers (turtles report too: see the corners)
    edges += line("M110,134 L1100,134", P.lime, 2.5, ` opacity=".75"`);
    for (const k of ["finder", "status", "watcher", "bridge"]) edges += line(`M${N[k][0]},88 L${N[k][0]},134`, P.lime, 2.5, ` opacity=".75"`);
    for (const k of ["server", "projector", "storage", "overseer", "hosts"]) edges += line(`M${N[k][0]},134 L${N[k][0]},192`, P.lime, 2.5, ` opacity=".75"`);
    // AutoMine jobs and progress
    edges += line("M90,248 L90,352", P.orange, 3) + line("M130,352 L130,248", P.orange, 3);
    // the deployer builds the GPS hosts
    edges += line("M1100,352 L1100,248", P.purple, 3);
    // the village shares its current building with the projector
    edges += line("M400,352 L400,248", P.magenta, 3);
    // the projector and build control hand their plan to the builders; the projector's to instabuild too
    edges += line("M270,248 L270,352", P.magenta, 3) + line("M285,512 L285,408", P.magenta, 3);
    edges += line("M360,248 L360,490 L420,490 L420,512", P.magenta, 3);
    // the storage system delivers blocks and fuel to the builders and the village
    edges += line("M560,248 L560,310 L310,310 L310,352 M470,310 L470,352", P.blue, 3);
    // farms drop their harvest into the storage system's input chest
    edges += line("M625,352 L625,248", P.green, 3);
    // the excavator and the terminals: deliveries and loot, up the gap by the farms
    edges += line("M575,512 L575,490 L745,490 L745,512 M655,490 L655,248", P.blue, 3);
    // the storage system fills the factory's machines
    edges += line("M700,248 C700,300 720,300 720,352", P.red, 3);
    // the overseer reads storage's stock and has it load chests; it hands out crafts and machine jobs
    edges += line("M740,212 L810,212 M810,228 L740,228", P.brown, 3);
    edges += line("M930,248 L930,352", P.brown, 3);
    edges += line("M850,248 C850,300 790,300 790,352", P.brown, 3);
    // the craft terminal orders from the overseer (round the right of the crafters)
    edges += line("M820,540 L1005,540 L1005,290 L970,290 L970,248", P.brown, 3);

    let nodes = "";
    for (const [, [x, y, w, link, title, dev, col, marks]] of Object.entries(N)) {
      const corner = (i, c) => `<rect x="${x + w / 2 - 12 - i * 10}" y="${y - 20}" width="7" height="7" fill="${c}"/>`;
      const corners = [marks.includes("r") && P.lime, marks.includes("g") && P.lightBlue].filter(Boolean).map((c, i) => corner(i, c)).join("");
      nodes += `<a href="${progUrl(link)}"><g class="node">
        <rect x="${x - w / 2 + 4}" y="${y - 24}" width="${w}" height="56" fill="#000" opacity=".5"/>
        <rect class="face" x="${x - w / 2}" y="${y - 28}" width="${w}" height="56" fill="#1d1d24" stroke="#000" stroke-width="2"/>
        <rect x="${x - w / 2}" y="${y - 28}" width="${w}" height="4" fill="${P[col]}"/>
        ${corners}
        <image href="${icon(dev)}" x="${x - w / 2 + 8}" y="${y - 16}" width="32" height="32" style="image-rendering:pixelated"/>
        <text x="${x - w / 2 + 46}" y="${y + 5}" data-room="${w - 74}" fill="#ecebe6" font-family="Pixelify Sans, monospace" font-size="${w < 160 ? 14 : 16}">${esc(title)}</text>
      </g></a>`;
    }
    const tag = (x, y, t, c) => `<text x="${x}" y="${y}" fill="${c}" font-family="VT323, monospace" font-size="19">${t}</text>`;
    const labels = tag(518, 120, "report.set()", P.lime) + tag(778, 120, "update", P.lime)
      + tag(30, 305, "jobs", P.orange) + tag(1110, 305, "builds", P.purple)
      + tag(208, 292, "plan", P.magenta) + tag(406, 282, "building", P.magenta)
      + tag(292, 466, "plan", P.magenta) + tag(366, 470, "build", P.magenta)
      + tag(478, 336, "items", P.blue) + tag(566, 290, "crops", P.green) + tag(662, 462, "items, loot", P.blue)
      + tag(708, 290, "fills", P.red) + tag(746, 270, "stock", P.brown) + tag(808, 342, "jobs", P.brown)
      + tag(936, 300, "crafts", P.brown) + tag(1010, 470, "orders", P.brown);
    return `<svg viewBox="0 0 1200 600" role="img" aria-label="How the programs connect">${edges}${labels}${nodes}</svg>`;
  }

  //---------------------------------------------------------------- program page

  function installPanel(p) {
    const wget = p.files.map((f) => `wget ${SITE.url}/${f.src} ${f.dest}`);
    const hasLib = p.files.some((f) => f.lib);
    return `
      <div class="mc-panel install-panel">
        <h3><img src="${ROOT}assets/floppy.svg" alt=""> Install</h3>
        <div class="mc-tabs" role="tablist">
          <button class="mc-tab" role="tab" aria-selected="true" data-tab="i">Installer</button>
          <button class="mc-tab" role="tab" aria-selected="false" data-tab="w">wget</button>
          <button class="mc-tab" role="tab" aria-selected="false" data-tab="d">Download</button>
        </div>
        <div class="tab-pane" data-pane="i">
          ${field(installCmd(p.name))}
          <p>Downloads ${p.files.length} files${hasLib ? `, including <code>lib/</code>,` : ""} onto the ${p.device === "turtle" ? "turtle" : "computer"}. It updates itself from this site each time it boots (<code>set install.autoupdate false</code> turns that off), and <code>install update</code> fetches the newest version now${p.keep ? ` and keeps your <code>${p.keep.join(", ")}</code>` : ""}.</p>
        </div>
        <div class="tab-pane" data-pane="w" hidden>
          <div class="wget-list">${wget.map(field).join("")}</div>
          <p class="hint">Run each line in-game. CC pastes one line at a time.</p>
        </div>
        <div class="tab-pane" data-pane="d" hidden>
          <p><a class="mc-btn small green" href="${ROOT}zips/${p.name}.zip" download>Download ZIP</a></p>
          <p>Unzip into <code>saves/&lt;world&gt;/computercraft/computer/&lt;id&gt;/</code> (run <code>id</code> in-game for the number), or drag the files onto the computer's screen in-game to upload them.</p>
        </div>
      </div>`;
  }
  function wireTabs(root) {
    root.querySelectorAll(".mc-tab").forEach((tab) => tab.addEventListener("click", () => {
      const box = tab.closest(".mc-panel");
      box.querySelectorAll(".mc-tab").forEach((t) => t.setAttribute("aria-selected", t === tab));
      box.querySelectorAll(".tab-pane").forEach((pane) => { pane.hidden = pane.dataset.pane !== tab.dataset.tab; });
    }));
  }

  function showcase(p, holder) {
    const r = p.render;
    if (r.kind === "voxel") {
      const stage = h(`<figure class="stage" style="margin:0"><canvas aria-label="${esc(r.caption)}"></canvas><div class="tools"></div></figure>`);
      holder.append(stage, h(`<p class="caption">${esc(r.caption)} Rendered in your browser from the program's own dimensions.</p>`));
      requestAnimationFrame(() => {
        const ctl = Voxel.mount($("canvas", stage), r.scene, { width: stage.clientWidth, maxH: 640, animate: r.animate });
        const tools = $(".tools", stage);
        const rb = h(`<button class="mc-btn small">Rotate</button>`); rb.onclick = () => ctl.rotate(); tools.append(rb);
        if (ctl.hasReplay) { const pb = h(`<button class="mc-btn small green">Replay</button>`); pb.onclick = () => ctl.replay(); tools.append(pb); }
      });
    } else if (r.kind === "gallery") {
      const tabs = h(`<div class="gallery-tabs"></div>`);
      const stage = h(`<figure class="stage light" style="margin:0"><img alt=""><a class="mc-btn small open-full" target="_blank" rel="noopener">Open full size</a></figure>`);
      const img = $("img", stage), open = $("a", stage);
      const pick = (i) => {
        const [title, src] = r.images[i];
        img.src = ROOT + src; img.alt = title; open.href = ROOT + src;
        tabs.querySelectorAll(".chip").forEach((c, j) => c.setAttribute("aria-pressed", i === j));
      };
      if (r.images.length > 1) r.images.forEach(([title], i) => { const c = h(`<button class="chip">${esc(title)}</button>`); c.onclick = () => pick(i); tabs.append(c); });
      holder.append(tabs, stage, h(`<p class="caption">${esc(r.caption)}</p>`));
      pick(0);
    } else {
      const stage = h(`<figure class="stage" style="margin:0"><div class="screen-holder"></div></figure>`);
      $(".screen-holder", stage).append(r.kind === "animation" ? animEl(r.name) : screenEl(r.scene));
      holder.append(stage, h(`<p class="caption">${esc(r.caption)}</p>`));
      // more screens of the same program (render.more in programs.json), e.g. its monitor
      for (const m of r.more || []) {
        const more = h(`<figure class="stage" style="margin:16px 0 0"><div class="screen-holder"></div></figure>`);
        $(".screen-holder", more).append(screenEl(m.scene));
        holder.append(more, h(`<p class="caption">${esc(m.caption)}</p>`));
      }
    }
  }

  // Every animation the display can install: a preview, what it is, its install command.
  function animationsSection(holder) {
    for (const a of SITE.animations || []) {
      const card = h(`<div class="anim-card"><div class="anim-screen"></div><div class="anim-text"><b>${esc(a.title)}</b>
        <span class="pill">${esc(a.kind || "")}</span><p>${esc(a.tagline)}</p>${field("install animation " + a.name)}
        <a class="mc-btn small" target="_blank" rel="noopener" href="${ROOT}animations/${esc(a.file)}">animations/${esc(a.file)}</a></div></div>`);
      $(".anim-screen", card).append(animEl(a.name, true));
      holder.append(card);
    }
  }

  // Example layouts: tabs of block scenes from voxel.js (programs.json "layouts").
  function layoutsSection(p, holder) {
    const tabs = h(`<div class="gallery-tabs"></div>`);
    const stage = h(`<figure class="stage" style="margin:0"><div class="layout-canvas"></div><div class="tools"></div></figure>`);
    const cap = h(`<p class="caption"></p>`);
    let ctl;
    const pick = (i) => {
      const l = p.layouts[i];
      // a fresh canvas each time: a mounted scene keeps redrawing its own on resize
      const canvas = h(`<canvas aria-label="${esc(l.caption)}"></canvas>`);
      $(".layout-canvas", stage).replaceChildren(canvas);
      ctl = Voxel.mount(canvas, l.scene, { width: stage.clientWidth, maxH: 560 });
      cap.textContent = l.caption;
      tabs.querySelectorAll(".chip").forEach((c, j) => c.setAttribute("aria-pressed", i === j));
    };
    p.layouts.forEach((l, i) => { const c = h(`<button class="chip">${esc(l.title)}</button>`); c.onclick = () => pick(i); tabs.append(c); });
    const rb = h(`<button class="mc-btn small">Rotate</button>`); rb.onclick = () => ctl && ctl.rotate();
    $(".tools", stage).append(rb);
    holder.append(tabs, stage, cap);
    requestAnimationFrame(() => pick(0));
  }

  function filesSection(files, holder, openFirst) {
    const slots = h(`<div class="slots"></div>`);
    const viewer = h(`<div class="viewer" hidden><div class="bar"><span class="name"></span><span class="pill lines"></span><span class="grow"></span><a class="mc-btn small raw" target="_blank" rel="noopener">Raw</a><a class="mc-btn small gh" target="_blank" rel="noopener">GitHub</a></div><pre class="code"><code class="language-lua"></code></pre></div>`);
    const show = async (f) => {
      viewer.hidden = false;
      $(".name", viewer).textContent = f.dest;
      $(".lines", viewer).textContent = `${f.lines} lines`;
      $(".raw", viewer).href = ROOT + f.src;
      $(".gh", viewer).href = `https://github.com/${SITE.repo}/blob/main/${f.src}`;
      const code = $("code", viewer);
      code.textContent = "Loading...";
      try {
        code.textContent = await (await fetch(ROOT + f.src)).text();
        delete code.dataset.highlighted;
        if (window.hljs) hljs.highlightElement(code);
      } catch { code.textContent = "Couldn't load this file."; }
    };
    for (const f of files) {
      const s = h(`<button class="slot"><img class="ico" src="${ROOT}assets/${f.lib ? "book" : "floppy"}.svg" alt=""><span class="nm">${esc(f.dest)}<small>${f.lines} lines${f.keep ? " · your settings" : ""}</small></span></button>`);
      s.onclick = () => show(f);
      slots.append(s);
    }
    holder.append(slots, viewer);
    if (openFirst) show(files[0]);
  }

  // README: drop the empty per-world fields, then point links at site pages.
  async function readme(src, holder, baseDir) {
    holder.innerHTML = `<div class="loading">Loading the guide</div>`;
    try {
      const md = await (await fetch(ROOT + src)).text();
      const div = h(`<div class="readme"></div>`);
      div.innerHTML = marked.parse(md);
      div.querySelector("h1")?.remove();
      div.querySelectorAll("li").forEach((li) => {
        if (/^(Computer IDs?|Label|Location):\s*(\(.*\))?\s*$/.test(li.textContent.trim())) li.remove();
      });
      div.querySelectorAll("ul").forEach((ul) => { if (!ul.children.length) ul.remove(); });
      const slug = (t) => t.toLowerCase().trim().replace(/[^\w\s-]/g, "").replace(/\s+/g, "-");
      div.querySelectorAll("h2, h3, h4").forEach((hd) => { hd.id = slug(hd.textContent); });
      div.querySelectorAll("a[href]").forEach((a) => {
        const href = a.getAttribute("href");
        if (/^(https?:|#|mailto:)/.test(href)) return;
        const [p, hash] = href.split("#");
        const abs = new URL(p, `https://x/${baseDir}/`).pathname.slice(1);
        let m;
        if ((m = abs.match(/^computers\/([^/]+)\/(README\.md)?$/))) a.href = progUrl(m[1]) + (hash ? `#${hash}` : "#guide");
        else if ((m = abs.match(/^lib\/(\w+)\.lua$/))) a.href = libUrl(m[1]);
        else if ((m = abs.match(/^plans\/([\w-]+)\.(lua|json)$/)) && (SITE.plans || []).some((pl) => pl.name === m[1])) a.href = planUrl(m[1]);
        else { a.href = ROOT + abs; a.target = "_blank"; }
      });
      // pictures (preview/setup.svg): relative to the README, and open full size when clicked
      div.querySelectorAll("img[src]").forEach((img) => {
        const src = img.getAttribute("src");
        if (/^(https?:|data:|\/)/.test(src)) return;
        img.src = ROOT + new URL(src, `https://x/${baseDir}/`).pathname.slice(1);
        img.loading = "lazy";
        if (!img.closest("a")) {
          const a = h(`<a class="readme-pic" target="_blank" rel="noopener"></a>`);
          a.href = img.src;
          img.replaceWith(a);
          a.append(img);
        }
      });
      div.querySelectorAll("pre code").forEach((c) => { if (!c.className) c.className = /^\s*(local|--|report\.|nav\.)/.test(c.textContent) ? "language-lua" : "language-plaintext"; });
      holder.replaceChildren(div);
      highlight();
      if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView();
    } catch (e) {
      holder.innerHTML = `<p class="caption">Couldn't load the guide. <a href="https://github.com/${SITE.repo}/blob/main/${src}">Read it on GitHub</a>.</p>`;
    }
  }

  function highlight() { if (window.hljs) document.querySelectorAll("pre code[class*=language-]:not([data-highlighted])").forEach((c) => hljs.highlightElement(c)); }

  function programPage(p) {
    document.body.style.setProperty("--c", cc(p.color));
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}#programs">Programs</a> / ${partById[partOf(p)] ? `<a href="${ROOT}#part-${partOf(p)}">${esc(partById[partOf(p)].title)}</a> / ` : ""}${groupById[p.group] ? `<a href="${ROOT}#group-${p.group}">${esc(groupById[p.group].title)}</a> / ` : ""}${esc(p.title)}</div>
          <div class="p-title"><img class="icon" src="${icon(p.device)}" alt=""><h1>${esc(p.title)}<small>computers/${esc(p.name)}</small></h1></div>
          <p class="lead">${esc(p.tagline)}</p>
          <div class="meta">
            <span class="pill">${esc(p.deviceLabel)}</span>
            ${(p.mods || []).map((m) => `<span class="pill mod" title="Needs this mod">Needs ${esc(m)}</span>`).join("")}
            ${(p.worksWith || []).map((m) => `<span class="pill mod soft" title="Optional: used if you have it">Works with ${esc(m)}</span>`).join("")}
            ${p.libs.map((l) => `<a class="pill lib" href="${libUrl(l)}">lib/${l}</a>`).join("")}
            <a class="pill" href="https://github.com/${SITE.repo}/tree/main/computers/${p.name}">Source on GitHub</a>
          </div>
          <div class="stats">${p.stats.map(([k, v]) => `<div><b>${esc(v)}</b><span>${esc(k)}</span></div>`).join("")}</div>
        </div>
        ${installPanel(p)}
      </div></section>
      <section class="wrap showcase" id="render"></section>
      <section class="block"><div class="wrap two">
        <div class="box"><h3>Setting it up</h3><ol class="steps">${p.setup.map((s) => `<li>${esc(s)}</li>`).join("")}</ol>
          <ul class="features">${p.features.map((f) => `<li>${esc(f)}</li>`).join("")}</ul></div>
        <div class="watch">${p.terminal ? `<div class="bezel ${p.terminal.device === "turtle" ? "turtle" : "advanced"} lit" style="margin-bottom:28px"><div class="screen"><pre class="cc-term" id="watch-term"></pre></div></div>` : ""}
          <div class="box"><h3>Commands</h3><div class="cmds">${p.commands.map(([c, d]) => `<div><code>${esc(c)}</code><span>${esc(d)}</span></div>`).join("")}</div></div>
        </div>
      </div></section>
      ${p.layouts ? `<section class="block" id="layouts"><div class="wrap">
        <div class="sec-head"><h2><small>Ideas</small>Example layouts</h2><p>Pick one to see how the blocks go together.</p></div>
        <div id="layout-stage"></div>
      </div></section>` : ""}
      ${p.render.kind === "animation" ? `<section class="block" id="animations"><div class="wrap">
        <div class="sec-head"><h2><small>Install</small>Animations</h2><p>Install the ones you want on the display's computer; it shows each in turn, an hour at a time.</p></div>
        ${field("install animation " + (SITE.animations || []).map((a) => a.name).join(" "))}
        <div class="anim-grid"></div>
      </div></section>` : ""}
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Integration</small>Works with</h2></div>
        <div class="integrations">${p.integrates.map(([n, why]) => {
          const t = byName[n] || libByName[n];
          const href = byName[n] ? progUrl(n) : libUrl(n);
          const img = byName[n] ? icon(t.device) : `${ROOT}assets/book.svg`;
          return `<a href="${href}"><img src="${img}" alt=""><div><b>${esc(t.title)}</b><span>${esc(why)}</span></div></a>`;
        }).join("")}</div>
      </div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Source</small>Files</h2><p>Click a file to read it.</p></div>
        <div id="files"></div>
      </div></section>
      <section class="block" id="guide"><div class="wrap">
        <div class="sec-head"><h2><small>Guide</small>The full manual</h2></div>
        <div id="readme"></div>
      </div></section>`;
    wireTabs(main);
    showcase(p, $("#render"));
    if (p.layouts) layoutsSection(p, $("#layout-stage"));
    if (p.render.kind === "animation") animationsSection($("#animations .anim-grid"));
    if (p.terminal) new CC.Typer($("#watch-term"), p.terminal.device === "turtle" ? 39 : 51, p.terminal.device === "turtle" ? 13 : 19, [p.terminal.lines], { pause: 6000 });
    filesSection(p.files, $("#files"));
    readme(`computers/${p.name}/README.md`, $("#readme"), `computers/${p.name}`);
  }

  function libraryPage(l) {
    document.body.style.setProperty("--c", cc(l.color));
    const main = $("main");
    const file = { src: l.file, dest: l.file, lines: l.lines, lib: true };
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}#libraries">Libraries</a> / ${esc(l.title)}</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/book.svg" alt=""><h1>${esc(l.title)}<small>require("lib.${l.name}")</small></h1></div>
          <p class="lead">${esc(l.tagline)}</p>
          <div class="meta"><span class="pill">${l.lines} lines</span><a class="pill" href="https://github.com/${SITE.repo}/blob/main/${l.file}">Source on GitHub</a></div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/book.svg" alt=""> Install</h3>
          ${field(`wget ${SITE.url}/${l.file} ${l.file}`)}
          <p>Every program that needs it gets it from the installer automatically. Use this to add it to a program of your own.</p>
        </div>
      </div></section>
      <section class="block" style="padding-top:30px"><div class="wrap two">
        <div class="box"><h3>Quick start</h3><pre class="code"><code class="language-lua"></code></pre><p class="caption">${esc(l.notes)}</p></div>
        <div class="box"><h3>API</h3><table class="api">${l.api.map(([c, d]) => `<tr><td>${esc(c)}</td><td>${esc(d)}</td></tr>`).join("")}</table></div>
      </div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Used by</small>Programs</h2></div>
        <div class="integrations">${l.usedBy.map((n) => `<a href="${progUrl(n)}"><img src="${icon(byName[n].device)}" alt=""><div><b>${esc(byName[n].title)}</b><span>${esc(byName[n].tagline)}</span></div></a>`).join("")}</div>
      </div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Source</small>${esc(l.file)}</h2></div>
        <div id="files"></div>
      </div></section>`;
    $(".box pre code", main).textContent = l.usage;
    filesSection([file], $("#files"), true);
    highlight();
  }

  //---------------------------------------------------------------- plans

  // The plan, loaded and drawn into holder by plans.js; says why if it can't.
  async function showPlan(holder, loading) {
    holder.innerHTML = `<div class="loading">Loading the plan</div>`;
    try {
      const plan = await loading;
      PlanView.mount(holder, plan);
      return plan;
    } catch (e) {
      holder.innerHTML = `<div class="box"><h3>Couldn't show that plan</h3><p>${esc(e.message || e)}</p></div>`;
    }
  }

  // How to use a plan, in each program that takes one.
  // A plan that takes a size ("sizes") shows it on each command.
  const planUses = (name, size) => {
    const s = size ? " " + size : "";
    return `
    <div class="box"><h3>Show it</h3>${field(`projector ${name}${s}`)}<p>On the <a href="${progUrl("blueprint-projector")}">blueprint projector</a>: outlines in the world, moved and turned from the monitor, then Build.</p></div>
    <div class="box"><h3>Have turtles build it</h3>${field(`build ${name} <x> <y> <z> north${s}`)}<p>From <a href="${progUrl("build-control")}">build control</a>: the builder turtles share it, in strips. x y z is its north-west bottom corner.</p></div>
    <div class="box"><h3>Place it at once (creative)</h3>${field(`instabuild ${name} <x> <y> <z> north${s}`)}<p>From a command computer with <a href="${progUrl("instabuild")}">instabuild</a>; <code>instabuild undo</code> takes it away again.</p></div>`;
  };

  // A plan built to any size: the size word, or a setting that holds it.
  const planSize = (pl) => pl.sizes ? `
    <div class="box"><h3>Any size</h3>${field(`set ${pl.sizes.setting} ${pl.sizes.example}`)}<p>Or type the size after the plan's name, as in the commands here. ${esc(pl.sizes.notes)}</p></div>` : "";

  // A plan for underground (its "hole") is dug first with the excavator.
  const planDig = (pl) => pl.hole ? `
    <div class="box"><h3>Dig the hole first</h3>${field(`excavate ${pl.name}`)}<p>An <a href="${progUrl("excavate-turtle")}">excavator turtle</a> digs the ${esc(pl.hole)} hole it fills, walled in and dry, and prints where the builder goes and the build command.</p></div>` : "";

  function planPage(pl) {
    document.body.style.setProperty("--c", cc("pink"));
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}plans/">Plans</a> / ${esc(pl.title)}</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/floppy.svg" alt=""><h1>${esc(pl.title)}<small>plans/${esc(pl.file)}</small></h1></div>
          <p class="lead">${esc(pl.tagline)}</p>
          <div class="meta"><span class="pill">${esc(pl.size)}</span>${pl.hole ? `<span class="pill">hole ${esc(pl.hole)}</span>` : ""}<span class="pill">${pl.blocks.toLocaleString("en")} blocks</span><a class="pill" href="https://github.com/${SITE.repo}/blob/main/plans/${pl.file}">Source on GitHub</a></div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/floppy.svg" alt=""> Install</h3>
          ${field(`install plan ${pl.name}`)}
          <p>Puts it in <code>/plans</code> on the computer, where the projector, build control and instabuild find it. Install the program first; no program comes with plans.</p>
        </div>
      </div></section>
      <section class="block" style="padding-top:20px"><div class="wrap"><div id="plan-view"></div></div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Use it</small>Build it</h2></div>
        <div class="plan-uses${pl.hole || pl.sizes ? " four" : ""}">${planDig(pl)}${planUses(pl.name, pl.sizes && pl.sizes.example)}${planSize(pl)}</div>
      </div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Source</small>plans/${esc(pl.file)}</h2><p>${pl.file.endsWith(".lua") ? "Made by code: a Lua plan returns the same table a JSON plan holds." : "A JSON plan: each layer drawn as rows of letters, seen from above."} <a href="${ROOT}viewer/">View a plan of your own</a>.</p></div>
        <div id="files"></div>
      </div></section>`;
    showPlan($("#plan-view"), PlanView.load(`${ROOT}plans/${pl.file}`));
    filesSection(pl.files, $("#files"), true);
  }

  // Every plan on one page: a picture of each (drawn as its card scrolls
  // into view: the Lua plans run in fengari), filters for above ground and
  // underground, a search, a sort, and how a plan becomes a building.
  function plansPage() {
    document.body.style.setProperty("--c", cc("pink"));
    const plans = SITE.plans || [];
    const under = plans.filter((p) => p.hole);
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / Plans</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/floppy.svg" alt=""><h1>Plans<small>/plans</small></h1></div>
          <p class="lead">Buildings for the <a href="${progUrl("blueprint-projector")}">blueprint projector</a>, the <a href="${progUrl("builder-turtle")}">builder turtles</a> and <a href="${progUrl("instabuild")}">instabuild</a>: houses and towers to stand on the ground, and underground bases whose hole the <a href="${progUrl("excavate-turtle")}">excavator</a> digs first. Open one to turn it round and step through its layers.</p>
          <div class="meta"><span class="pill">${plans.length} plans</span><span class="pill">${under.length} underground</span><span class="pill">${plans.reduce((n, p) => n + p.blocks, 0).toLocaleString("en")} blocks between them</span></div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/floppy.svg" alt=""> Get one</h3>
          ${field("install plans")}
          <p>Lists them on the computer; <code>install plan &lt;name&gt;</code> puts one in <code>/plans</code>, and it updates on boot like a program. Or tap <b>Pick</b> on the ones you want below for one command that installs them all. Have your own? <a href="${ROOT}viewer/">See it in the plan viewer</a>.</p>
        </div>
      </div></section>
      <section class="block" style="padding-top:20px"><div class="wrap">
        <div class="plan-tools">
          <div class="filters" id="plan-filters"></div>
          <input class="plan-search" type="search" placeholder="Find a plan" aria-label="Find a plan">
          <select class="plan-sort" aria-label="Sort">
            <option value="site">As listed</option><option value="small">Smallest first</option><option value="big">Biggest first</option><option value="name">A to Z</option>
          </select>
        </div>
        <div class="plan-grid" id="plan-grid"></div>
        <p class="plan-none" hidden>No plan matches that.</p>
      </div></section>
      <div class="plan-tray mc-panel" hidden>
        <div class="plan-tray-head"><b class="plan-tray-count"></b><div class="plan-tray-picks"></div><button class="chip plan-tray-clear">Clear</button></div>
        <div class="plan-tray-cmd"></div>
      </div>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>From plan to building</small>How it goes</h2></div>
        <div class="plan-uses four">
          <div class="box"><h3>1. Install it</h3>${field("install plan cellar")}<p>Into <code>/plans</code> on the projector, build control or instabuild computer, once the program is installed.</p></div>
          <div class="box"><h3>2. Underground? Dig first</h3>${field("excavate cellar")}<p>The <a href="${progUrl("excavate-turtle")}">excavator</a> digs the plan's hole, walls it in so it stays dry, and prints where the builder goes.</p></div>
          <div class="box"><h3>3. See where it goes</h3>${field("projector cellar")}<p>The <a href="${progUrl("blueprint-projector")}">projector</a> shows it in the world; move and turn it from the monitor, then tap Build.</p></div>
          <div class="box"><h3>4. Build it</h3>${field("build cellar 100 60 -40 north")}<p>Or send it to the builder turtles with <a href="${progUrl("build-control")}">build control</a> at a corner you type, or place it at once in creative with <a href="${progUrl("instabuild")}">instabuild</a>.</p></div>
        </div>
      </div></section>`;

    const grid = $("#plan-grid");
    const cards = plans.map((pl, i) => {
      const card = h(`
        <div class="lib-card plan-card" data-kind="${pl.hole ? "under" : "above"}">
          <a class="plan-thumb" href="${planUrl(pl.name)}" aria-label="${esc(pl.title)} in 3D"><canvas></canvas><span class="loading">Drawing</span></a>
          <button class="chip plan-pick" aria-pressed="false" aria-label="Pick ${esc(pl.title)}">Pick</button>
          <h3><a href="${planUrl(pl.name)}">${esc(pl.title)}</a></h3>
          <p>${esc(pl.tagline)}</p>
          ${field(`install plan ${pl.name}`)}
          <div class="meta"><span class="pill">${esc(pl.size)}</span>${pl.hole ? `<span class="pill">hole ${esc(pl.hole)}</span>` : ""}<span class="pill">${pl.blocks.toLocaleString("en")} blocks</span></div>
        </div>`);
      card._plan = pl;
      card._order = i;
      grid.append(card);
      return card;
    });

    // each picture once its card comes near the screen, one at a time
    let queue = Promise.resolve();
    const draw = (card) => {
      const pl = card._plan;
      queue = queue.then(async () => {
        const holder = $(".plan-thumb", card);
        try {
          const plan = await PlanView.load(`${ROOT}plans/${pl.file}`);
          // an underground plan's roof hides its rooms: leave off its top layers
          PlanView.thumb($("canvas", holder), plan, { width: holder.clientWidth || 360, maxH: 240, cut: pl.hole ? Math.min(2, plan.h - 1) : 0 });
          $(".loading", holder).remove();
        } catch (e) {
          $(".loading", holder).textContent = "Couldn't draw it";
        }
      });
    };
    const seen = "IntersectionObserver" in window ? new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { seen.unobserve(e.target); draw(e.target); }
    }, { rootMargin: "300px" }) : null;
    cards.forEach((c) => (seen ? seen.observe(c) : draw(c)));

    // filters, search and sort
    const filters = $("#plan-filters");
    const HASHES = { under: "#underground", above: "#above", picked: "#picked" };
    let kind = Object.keys(HASHES).find((k) => HASHES[k] === location.hash) || "all";
    const chip = (id, label, n) => `<button class="chip" data-kind="${id}" aria-pressed="${id === kind}">${esc(label)} <span class="count">${n}</span></button>`;
    filters.innerHTML = chip("all", "All", plans.length) + chip("above", "Above ground", plans.length - under.length) + chip("under", "Underground", under.length) + chip("picked", "Picked", 0);

    // picking: the plans you want, kept in this browser, as one install command
    const PICKS_KEY = "plans.picked";
    let picked = new Set();
    try { picked = new Set(JSON.parse(localStorage.getItem(PICKS_KEY) || "[]").filter((n) => plans.some((p) => p.name === n))); } catch {}
    const tray = $(".plan-tray", main);
    function showPicks() {
      try { localStorage.setItem(PICKS_KEY, JSON.stringify([...picked])); } catch {}
      const list = plans.filter((p) => picked.has(p.name));
      for (const c of cards) {
        const on = picked.has(c._plan.name);
        c.classList.toggle("picked", on);
        const b = $(".plan-pick", c);
        b.setAttribute("aria-pressed", on);
        b.textContent = on ? "Picked" : "Pick";
      }
      $('.chip[data-kind="picked"] .count', filters).textContent = list.length;
      tray.hidden = !list.length;
      document.body.classList.toggle("has-plan-tray", list.length > 0);
      if (!list.length) return;
      const blocks = list.reduce((n, p) => n + p.blocks, 0);
      $(".plan-tray-count", tray).textContent = `${list.length} picked · ${blocks.toLocaleString("en")} blocks`;
      $(".plan-tray-picks", tray).innerHTML = list.map((p) => `<button class="chip" data-unpick="${esc(p.name)}" aria-label="Remove ${esc(p.title)}">${esc(p.title)} ✕</button>`).join("");
      $(".plan-tray-cmd", tray).innerHTML = field(`install plan ${list.map((p) => p.name).join(" ")}`);
    }
    const toggle = (name) => { picked.has(name) ? picked.delete(name) : picked.add(name); showPicks(); if (kind === "picked") apply(); };
    cards.forEach((c) => $(".plan-pick", c).addEventListener("click", () => toggle(c._plan.name)));
    tray.addEventListener("click", (e) => {
      const b = e.target.closest("[data-unpick]");
      if (b) toggle(b.dataset.unpick);
    });
    $(".plan-tray-clear", tray).addEventListener("click", () => { picked.clear(); showPicks(); if (kind === "picked") apply(); });
    const search = $(".plan-search", main), sort = $(".plan-sort", main);
    const area = (p) => p.blocks;
    function apply() {
      const q = search.value.trim().toLowerCase();
      const order = [...cards].sort((a, b) => {
        const x = a._plan, y = b._plan;
        if (sort.value === "small") return area(x) - area(y);
        if (sort.value === "big") return area(y) - area(x);
        if (sort.value === "name") return x.title.localeCompare(y.title);
        return a._order - b._order;
      });
      let shown = 0;
      for (const c of order) {
        const p = c._plan;
        const ok = (kind === "all" || c.dataset.kind === kind || (kind === "picked" && picked.has(p.name))) && (!q || (p.title + " " + p.tagline + " " + p.name).toLowerCase().includes(q));
        c.hidden = !ok;
        if (ok) shown++;
        grid.append(c);
      }
      $(".plan-none", main).hidden = shown > 0;
      $(".plan-none", main).textContent = kind === "picked" && !picked.size ? "Nothing picked yet: tap Pick on a plan you want." : "No plan matches that.";
      filters.querySelectorAll(".chip").forEach((b) => b.setAttribute("aria-pressed", b.dataset.kind === kind));
    }
    filters.querySelectorAll(".chip").forEach((b) => b.addEventListener("click", () => {
      kind = b.dataset.kind;
      history.replaceState(null, "", HASHES[kind] || location.pathname);
      apply();
    }));
    search.addEventListener("input", apply);
    sort.addEventListener("change", apply);
    showPicks();
    apply();
  }

  // Any plan: drop or pick a file, or paste JSON, and see it.
  function viewerPage() {
    document.body.style.setProperty("--c", cc("pink"));
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}plans/">Plans</a> / Plan viewer</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/floppy.svg" alt=""><h1>Plan viewer<small>JSON or Lua</small></h1></div>
          <p class="lead">See any building plan in 3D before it goes on a computer: drop in a plan file, or paste one. It's read the way the computers read it, so if it shows here, it loads there.</p>
          <div class="meta">${(SITE.plans || []).map((p) => `<button class="chip" data-plan="${esc(p.file)}">${esc(p.title)}</button>`).join(" ")}</div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/floppy.svg" alt=""> Your plan</h3>
          <label class="drop" tabindex="0"><input type="file" accept=".json,.lua" hidden><b>Drop a .json or .lua plan here</b><span>or click to pick one</span></label>
          <textarea class="paste" spellcheck="false" placeholder='{ "name": "Hut", "legend": { "P": "minecraft:oak_planks" }, "layers": [["PPP", "P.P", "PPP"]] }'></textarea>
          <button class="mc-btn small green show">Show it</button>
        </div>
      </div></section>
      <section class="block" style="padding-top:20px"><div class="wrap"><div id="plan-view"><div class="box"><p>Pick a plan above, or drop one in.</p></div></div></div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Writing one</small>The plan format</h2><p>The full guide is in the <a href="${progUrl("blueprint-projector")}#plans">blueprint projector's manual</a>.</p></div>
        <pre class="code"><code class="language-json"></code></pre>
      </div></section>`;
    $("pre code", main).textContent = `{
  "name": "Gatehouse",
  "legend": {
    "C": "minecraft:cobblestone",
    "P": "minecraft:oak_planks",
    "G": ["minecraft:glass", "#99ddff"]
  },
  "layers": [
    ["CCCCC", "C...C", "CCCCC"],
    ["PPGPP", "P...P", "PPPPP"]
  ]
}`;
    highlight();
    const view = $("#plan-view");
    const input = $(".drop input", main);
    const fromFile = async (file) => showPlan(view, PlanView.fromText(await file.text(), file.name));
    input.onchange = () => input.files[0] && fromFile(input.files[0]);
    const drop = $(".drop", main);
    drop.ondragover = (e) => { e.preventDefault(); drop.classList.add("over"); };
    drop.ondragleave = () => drop.classList.remove("over");
    drop.ondrop = (e) => { e.preventDefault(); drop.classList.remove("over"); if (e.dataTransfer.files[0]) fromFile(e.dataTransfer.files[0]); };
    $(".show", main).onclick = () => {
      const text = $(".paste", main).value;
      if (text.trim()) showPlan(view, PlanView.fromText(text, /^\s*[{[]/.test(text) ? "pasted.json" : "pasted.lua"));
    };
    main.querySelectorAll("[data-plan]").forEach((b) => { b.onclick = () => showPlan(view, PlanView.load(`${ROOT}plans/${b.dataset.plan}`)); });
  }

  //---------------------------------------------------------------- network map

  // Every program on one simulated base (sim/map.mjs ran them together and
  // wrote network.json): where each computer is and what they sent each other.
  async function networkPage() {
    document.body.style.setProperty("--c", cc("lightBlue"));
    const main = $("main");
    let data;
    try { data = await (await fetch(`${ROOT}network.json`)).json(); } catch {
      main.innerHTML = `<div class="wrap"><p class="loading">The map's data (network.json) isn't on the site yet: run <code>node sim/map.mjs</code>.</p></div>`;
      return;
    }
    const onBase = data.computers.filter((c) => !c.far);
    const messages = data.links.reduce((n, l) => n + l.count, 0) + data.broadcasts.reduce((n, b) => n + b.count, 0);
    const programs = new Set(data.computers.map((c) => c.program).filter((p) => byName[p]));
    const mins = Math.round(data.simulated / 60);
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / Network map</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/computer.svg" alt=""><h1>Network map<small>${data.computers.length} computers, ${programs.size} programs</small></h1></div>
          <p class="lead">One base with every program on it, all running at once: installed with the real installer and run for ${mins} minutes of game time in a simulated world. Each dot is a computer or turtle where it ended up; each line is what they actually sent each other over rednet, thicker for more. Tap one to see what it is, who it talks to and what its screen said at the end.</p>
          <div class="meta"><span class="pill">${onBase.length} on the base, ${data.computers.length - onBase.length} far away</span><span class="pill">${data.nets.length} cables</span><span class="pill">${messages.toLocaleString("en")} messages</span><span class="pill">simulated ${esc(data.made)}</span></div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/computer.svg" alt=""> How it was made</h3>
          <p>The simulator in <a href="https://github.com/${SITE.repo}/tree/main/sim"><code>sim/</code></a> runs CC: Tweaked's own ROM on a Lua VM, one per computer, with turtles, chests, furnaces, cables, wireless and ender modems, GPS and http. Each program is set up the way its manual says, then left to run.</p>
          ${field("node sim/map.mjs")}
        </div>
      </div></section>
      <section class="block" style="padding-top:20px"><div class="wrap"><div class="netmap-layout" id="netmap"></div></div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>What the run found</small>Checks</h2><p>Every scenario checks the things players would notice: the miners brought ore home, the smelter's ingots reached storage, the remote terminal's ender chest got its items, the fission guard SCRAMmed when the coolant ran out.</p></div>
        <div class="box">${data.problems.length || data.errors.length
          ? `<ul class="netmap-found">${data.problems.map((p) => `<li>${esc(p)}</li>`).join("")}${data.errors.map((e) => `<li>${esc(data.computers.find((c) => c.id === e.id)?.label || "#" + e.id)} at ${Math.floor(e.t / 60)}:${String(e.t % 60).padStart(2, "0")}: <code>${esc(e.msg)}</code></li>`).join("")}</ul>`
          : `<p>Every check passed and no program stopped with an error.</p>`}</div>
      </div></section>`;
    NetMap.mount($("#netmap"), data, { progUrl: (n) => (byName[n] ? progUrl(n) : `${ROOT}#programs`) });
  }

  //---------------------------------------------------------------- go

  const kind = document.body.dataset.kind;
  const name = document.body.dataset.name;
  const start = () => {
    if (kind === "program") programPage(byName[name]);
    else if (kind === "library") libraryPage(libByName[name]);
    else if (kind === "plan") planPage((SITE.plans || []).find((p) => p.name === name));
    else if (kind === "viewer") viewerPage();
    else if (kind === "plans") plansPage();
    else if (kind === "network") networkPage();
    else home();
  };
  // fonts first, so canvases and terminals measure correctly
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(start);
})();
