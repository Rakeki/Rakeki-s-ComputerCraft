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
    const kind = ["dashboard", "projector", "colony", "storageMonitor", "fission", "power", "fusion", "dminer"].includes(scene) ? "monitor" : "advanced";
    const b = h(`<div class="bezel ${kind} lit"><div class="screen"><pre class="cc-term"></pre></div></div>`);
    if (compact) { b.style.padding = "8px 8px 14px"; b.style.boxShadow = "inset 3px 3px 0 var(--frame-hi), inset -3px -3px 0 var(--frame-lo)"; }
    CC.screens[scene]($("pre", b));
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
      const b = screenEl(r.scene, true);
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

    // a section per group, in the order of "groups"; chips show one group
    const holder = $("#program-groups");
    const filters = $("#group-filters");
    const sections = {};
    for (const g of SITE.groups || []) {
      const members = SITE.programs.filter((p) => p.group === g.id);
      if (!members.length) continue;
      const sec = h(`<section class="group" id="group-${g.id}" data-group="${g.id}">
        <div class="group-head"><h3>${esc(g.title)} <span class="count">${members.length}</span></h3><p>${esc(g.tagline)}</p></div>
        <div class="grid"></div></section>`);
      holder.append(sec);
      sections[g.id] = $(".grid", sec);
    }
    const chip = (id, label) => `<button class="chip" data-filter="${id}" aria-pressed="${id === "all"}">${esc(label)}</button>`;
    filters.innerHTML = chip("all", "All") + (SITE.groups || []).filter((g) => sections[g.id]).map((g) => chip(g.id, g.title)).join("");
    for (const p of SITE.programs) {
      const grid = sections[p.group];
      if (!grid) continue;
      const card = h(`
        <a class="card" href="${progUrl(p.name)}" style="--c:${cc(p.color)}" data-device="${p.device}">
          <div class="thumb"><span class="tag">${esc(p.deviceLabel)}</span></div>
          <div class="body">
            <h3>${esc(p.title)} <code>${esc(p.command)}</code></h3>
            <p>${esc(p.tagline)}</p>
            <div class="meta">
              ${p.libs.map((l) => `<span class="pill lib">lib/${l}</span>`).join("")}
              ${p.files.length ? `<span class="pill">${p.files.length} files</span>` : ""}
              <span class="go">Open &rarr;</span>
            </div>
          </div>
        </a>`);
      grid.append(card);
      thumb(p, $(".thumb", card));
    }
    const pick = (f) => {
      filters.querySelectorAll(".chip").forEach((c) => c.setAttribute("aria-pressed", c.dataset.filter === f));
      holder.querySelectorAll(".group").forEach((s) => { s.hidden = f !== "all" && s.dataset.group !== f; });
    };
    filters.querySelectorAll(".chip").forEach((c) => c.addEventListener("click", () => pick(c.dataset.filter)));
    // a link to #group-<id> (from a program page) shows just that group
    const follow = (wait) => {
      const linked = location.hash.match(/^#group-(\w+)$/);
      if (!linked || !sections[linked[1]]) return;
      pick(linked[1]);
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

  // How the programs talk to each other. Every program reports to the
  // dashboard (the lime bus and the lime corner on each box); the coloured
  // lines are the other ways they work together.
  function diagram() {
    const N = {
      status: [600, 60, 240, "status-server", "Status Dashboard", "computer", "cyan"],
      server: [130, 220, 190, "mine-server", "AutoMine Server", "computer", "yellow"],
      projector: [390, 220, 200, "blueprint-projector", "Blueprint Projector", "computer", "magenta"],
      storage: [690, 220, 180, "storage-computer", "Storage System", "computer", "blue"],
      colony: [900, 220, 190, "colony-dashboard", "Colony Dashboard", "computer", "orange"],
      hosts: [1100, 220, 160, "gps-deployer", "GPS hosts × 4", "computer", "purple"],
      miners: [130, 380, 190, "mine-turtle", "AutoMine Turtles", "turtle", "orange"],
      crafter: [345, 380, 140, "crafter-turtle", "Crafter", "turtle", "brown"],
      village: [540, 380, 150, "village-turtle", "Village", "turtle", "lime"],
      tree: [740, 380, 150, "tree-farm-turtle", "Tree Farm", "turtle", "green"],
      crop: [920, 380, 150, "crop-farm-turtle", "Crop Farm", "turtle", "yellow"],
      deployer: [1100, 380, 160, "gps-deployer", "GPS Deployer", "turtle", "purple"],
      excavate: [340, 540, 150, "excavate-turtle", "Excavator", "turtle", "orange"],
      strip: [540, 540, 150, "strip-mine-turtle", "Strip Miner", "turtle", "lightBlue"],
      mob: [740, 540, 150, "mob-farm-turtle", "Mob Farm", "turtle", "red"],
      smelter: [920, 540, 150, "smelter-computer", "Smelter", "computer", "red"],
      builder: [130, 540, 150, "builder-turtle", "Builders", "turtle", "pink"],
      overseer: [1100, 540, 160, "craft-overseer", "Craft Overseer", "computer", "orange"],
    };
    const P = CC.PALETTE;
    const line = (d, c, w = 2.5, extra = "") => `<path class="flow" d="${d}" stroke="${c}" stroke-width="${w}" fill="none"${extra}/>`;
    const curve = (x1, y1, x2, y2) => `M${x1},${y1} C${x1},${(y1 + y2) / 2} ${x2},${(y1 + y2) / 2} ${x2},${y2}`;
    let edges = "";
    // status: a bus under the dashboard to the row of computers (turtles report too: see the corners)
    edges += line("M600,88 L600,140 M130,140 L1100,140", P.lime, 2.5, ` opacity=".75"`);
    for (const k of ["server", "projector", "storage", "colony", "hosts"]) edges += line(`M${N[k][0]},140 L${N[k][0]},192`, P.lime, 2.5, ` opacity=".75"`);
    // AutoMine jobs and progress
    edges += line("M100,248 L100,352", P.orange, 3) + line("M150,352 L150,248", P.orange, 3);
    // the deployer builds the GPS hosts
    edges += line("M1100,352 L1100,248", P.purple, 3);
    // GPS: from the hosts to every turtle that checks its position
    edges += line("M1040,248 L1040,300 L200,300", P.lightBlue);
    for (const x of [200, 480, 690, 870]) edges += line(`M${x},300 L${x},352`, P.lightBlue);
    edges += line("M440,300 L440,470 M100,470 L700,470", P.lightBlue);
    for (const x of [100, 300, 500, 700]) edges += line(`M${x},470 L${x},512`, P.lightBlue);
    // the village shares its current building with the projector
    edges += line(curve(430, 248, 510, 352), P.magenta, 3);
    // the projector hands its plan to the builders (down the gap left of the crafter)
    edges += line("M320,248 L320,320 L250,320 L250,490 L170,490 L170,512", P.magenta, 3);
    // the storage system sends the village its blocks
    edges += line(curve(650, 248, 575, 352), P.blue, 3);
    // the storage system hands crafting jobs to the crafter
    edges += line(curve(615, 248, 380, 352), P.brown, 3);
    // the storage system hands its crafting queue to the overseer (down the gap by the GPS deployer)
    edges += line("M750,248 L750,286 L1008,286 L1008,500 L1060,500 L1060,512", P.brown, 3);
    // the storage system loads the smelter's furnaces (down the gap between the farms)
    edges += line("M770,248 L770,272 L830,272 L830,470 L900,470 L900,512", P.red, 3);
    // farms drop their harvest into the storage system's input chest
    edges += line(curve(740, 352, 715, 248), P.green);
    edges += line(curve(900, 352, 760, 248), P.green);

    let nodes = "";
    for (const [key, [x, y, w, link, title, dev, col]] of Object.entries(N)) {
      nodes += `<a href="${progUrl(link)}"><g class="node">
        <rect x="${x - w / 2 + 4}" y="${y - 24}" width="${w}" height="56" fill="#000" opacity=".5"/>
        <rect class="face" x="${x - w / 2}" y="${y - 28}" width="${w}" height="56" fill="#1d1d24" stroke="#000" stroke-width="2"/>
        <rect x="${x - w / 2}" y="${y - 28}" width="${w}" height="4" fill="${P[col]}"/>
        ${key === "status" ? "" : `<rect x="${x + w / 2 - 12}" y="${y - 20}" width="7" height="7" fill="${P.lime}"/>`}
        <image href="${icon(dev)}" x="${x - w / 2 + 8}" y="${y - 16}" width="32" height="32" style="image-rendering:pixelated"/>
        <text x="${x - w / 2 + 46}" y="${y + 5}" data-room="${w - 64}" fill="#ecebe6" font-family="Pixelify Sans, monospace" font-size="${w < 160 ? 14 : 16}">${esc(title)}</text>
      </g></a>`;
    }
    const tag = (x, y, t, c) => `<text x="${x}" y="${y}" fill="${c}" font-family="VT323, monospace" font-size="19">${t}</text>`;
    const labels = tag(612, 124, "report.set()", P.lime) + tag(30, 305, "rednet", P.orange)
      + tag(210, 292, "gps.locate()", P.lightBlue) + tag(1110, 305, "builds", P.purple)
      + tag(262, 340, "current building", P.magenta) + tag(628, 322, "blocks", P.blue)
      + tag(912, 337, "harvest", P.green) + tag(546, 270, "crafts", P.brown) + tag(838, 462, "ores, fuel", P.red)
      + tag(178, 484, "plans", P.magenta) + tag(1016, 492, "queue", P.brown);
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
      $(".screen-holder", stage).append(screenEl(r.scene));
      holder.append(stage, h(`<p class="caption">${esc(r.caption)}</p>`));
      // more screens of the same program (render.more in programs.json), e.g. its monitor
      for (const m of r.more || []) {
        const more = h(`<figure class="stage" style="margin:16px 0 0"><div class="screen-holder"></div></figure>`);
        $(".screen-holder", more).append(screenEl(m.scene));
        holder.append(more, h(`<p class="caption">${esc(m.caption)}</p>`));
      }
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
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}#programs">Programs</a> / ${groupById[p.group] ? `<a href="${ROOT}#group-${p.group}">${esc(groupById[p.group].title)}</a> / ` : ""}${esc(p.title)}</div>
          <div class="p-title"><img class="icon" src="${icon(p.device)}" alt=""><h1>${esc(p.title)}<small>computers/${esc(p.name)}</small></h1></div>
          <p class="lead">${esc(p.tagline)}</p>
          <div class="meta">
            <span class="pill">${esc(p.deviceLabel)}</span>
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
  const planUses = (name) => `
    <div class="box"><h3>Show it</h3>${field(`projector ${name}`)}<p>On the <a href="${progUrl("blueprint-projector")}">blueprint projector</a>: outlines in the world, moved and turned from the monitor, then Build.</p></div>
    <div class="box"><h3>Have turtles build it</h3>${field(`build ${name} <x> <y> <z> north`)}<p>From <a href="${progUrl("build-control")}">build control</a>: the builder turtles share it, in strips. x y z is its north-west bottom corner.</p></div>
    <div class="box"><h3>Place it at once (creative)</h3>${field(`instabuild ${name} <x> <y> <z> north`)}<p>From a command computer with <a href="${progUrl("instabuild")}">instabuild</a>; <code>instabuild undo</code> takes it away again.</p></div>`;

  // A plan for underground (its "hole") is dug first with the excavator.
  const planDig = (pl) => pl.hole ? `
    <div class="box"><h3>Dig the hole first</h3>${field(`excavate ${pl.name}`)}<p>An <a href="${progUrl("excavate-turtle")}">excavator turtle</a> digs the ${esc(pl.hole)} hole it fills, walled in and dry, and prints where the builder goes and the build command.</p></div>` : "";

  function planPage(pl) {
    document.body.style.setProperty("--c", cc("pink"));
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}#plans">Plans</a> / ${esc(pl.title)}</div>
          <div class="p-title"><img class="icon" src="${ROOT}assets/floppy.svg" alt=""><h1>${esc(pl.title)}<small>plans/${esc(pl.file)}</small></h1></div>
          <p class="lead">${esc(pl.tagline)}</p>
          <div class="meta"><span class="pill">${esc(pl.size)}</span>${pl.hole ? `<span class="pill">hole ${esc(pl.hole)}</span>` : ""}<span class="pill">${pl.blocks.toLocaleString("en")} blocks</span><a class="pill" href="https://github.com/${SITE.repo}/blob/main/plans/${pl.file}">Source on GitHub</a></div>
        </div>
        <div class="mc-panel install-panel">
          <h3><img src="${ROOT}assets/floppy.svg" alt=""> Install</h3>
          ${field(`install plan ${pl.name}`)}
          <p>Puts it in <code>/plans</code> on the computer, where the projector, build control and instabuild find it. It comes with all three already.</p>
        </div>
      </div></section>
      <section class="block" style="padding-top:20px"><div class="wrap"><div id="plan-view"></div></div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Use it</small>Build it</h2></div>
        <div class="plan-uses${pl.hole ? " four" : ""}">${planDig(pl)}${planUses(pl.name)}</div>
      </div></section>
      <section class="block"><div class="wrap">
        <div class="sec-head"><h2><small>Source</small>plans/${esc(pl.file)}</h2><p>${pl.file.endsWith(".lua") ? "Made by code: a Lua plan returns the same table a JSON plan holds." : "A JSON plan: each layer drawn as rows of letters, seen from above."} <a href="${ROOT}viewer/">View a plan of your own</a>.</p></div>
        <div id="files"></div>
      </div></section>`;
    showPlan($("#plan-view"), PlanView.load(`${ROOT}plans/${pl.file}`));
    filesSection(pl.files, $("#files"), true);
  }

  // Any plan: drop or pick a file, or paste JSON, and see it.
  function viewerPage() {
    document.body.style.setProperty("--c", cc("pink"));
    const main = $("main");
    main.innerHTML = `
      <section class="p-hero"><div class="wrap">
        <div>
          <div class="crumbs"><a href="${ROOT}">Home</a> / <a href="${ROOT}#plans">Plans</a> / Plan viewer</div>
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

  //---------------------------------------------------------------- go

  const kind = document.body.dataset.kind;
  const name = document.body.dataset.name;
  const start = () => {
    if (kind === "program") programPage(byName[name]);
    else if (kind === "library") libraryPage(libByName[name]);
    else if (kind === "plan") planPage((SITE.plans || []).find((p) => p.name === name));
    else if (kind === "viewer") viewerPage();
    else home();
  };
  // fonts first, so canvases and terminals measure correctly
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(start);
})();
