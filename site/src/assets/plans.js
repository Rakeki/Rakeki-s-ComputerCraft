// Plan viewer: loads a building plan (a JSON file, or a Lua plan run in the
// browser with fengari) the same way lib/plan.lua does on the computers, and
// draws it with the voxel renderer: rotate, step through the layers, and the
// blocks it needs. Used by each plan's page and the "view your own" page.
//
//   const plan = await PlanView.load(url)              // .json or .lua
//   const plan = await PlanView.fromText(text, "x.json")
//   PlanView.mount(holder, plan)
(function () {
  const FENGARI = "https://cdn.jsdelivr.net/npm/fengari-web@0.1.4/dist/fengari-web.js";

  //---------------------------------------------------------------- loading

  let fengariReady = null;
  function loadFengari() {
    if (window.fengari) return Promise.resolve(window.fengari);
    if (!fengariReady) {
      fengariReady = new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = FENGARI;
        s.onload = () => resolve(window.fengari);
        s.onerror = () => reject(new Error("Couldn't load the Lua runner (fengari) to read a .lua plan."));
        document.head.append(s);
      });
    }
    return fengariReady;
  }

  // Runs a Lua plan and hands back its table as JSON text: the plan returns
  // the same table a JSON plan holds.
  const LUA_WRAPPER = `
local fn, err = load(PLAN_SOURCE, "=plan", "t", setmetatable({}, { __index = _G }))
if not fn then error(err, 0) end
local raw = fn()
local function enc(v)
  local t = type(v)
  if t == "table" then
    local n = #v
    local isList = n > 0
    if isList then for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isList = false break end end end
    local out = {}
    if isList then
      for i = 1, n do out[i] = enc(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do out[#out + 1] = enc(tostring(k)) .. ":" .. enc(x) end
    return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\\\]', function(c) return string.format("\\\\u%04x", c:byte()) end) .. '"'
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return string.format("%.14g", v)
  elseif t == "boolean" then return tostring(v) end
  return "null"
end
return enc(raw)`;

  async function runLua(source) {
    const { lua, lauxlib, lualib, to_luastring } = await loadFengari();
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    lua.lua_pushstring(L, to_luastring(source));
    lua.lua_setglobal(L, to_luastring("PLAN_SOURCE"));
    if (lauxlib.luaL_dostring(L, to_luastring(LUA_WRAPPER)) !== 0) throw new Error(lua.lua_tojsstring(L, -1));
    return JSON.parse(lua.lua_tojsstring(L, -1));
  }

  // A plan table as one shape, like lib/plan.lua's fromTable: blocks
  // { x, y, z, m } from 0, mats { block, total }, size w x l x h.
  function fromTable(raw, id) {
    if (!raw || typeof raw !== "object") throw new Error("the plan must be a table (a JSON object)");
    const mats = [], byKey = {};
    const material = (key, def) => {
      if (byKey[key] !== undefined) return byKey[key];
      const block = typeof def === "string" ? def : def && (def.block || def[0]);
      if (typeof block !== "string") throw new Error(`the legend entry for '${key}' needs a block name`);
      mats.push({ block, total: 0 });
      return (byKey[key] = mats.length - 1);
    };
    const blocks = [];
    if (raw.layers) {
      const legend = raw.legend || {};
      raw.layers.forEach((layer, y) => {
        if (!Array.isArray(layer)) throw new Error(`layer ${y + 1} should be a list of rows`);
        layer.forEach((row, z) => {
          for (let x = 0; x < row.length; x++) {
            const ch = row[x];
            if (ch === "." || ch === " ") continue;
            if (legend[ch] === undefined) throw new Error(`layer ${y + 1} row ${z + 1}: '${ch}' isn't in the legend`);
            blocks.push({ x, y, z, m: material(ch, legend[ch]) });
          }
        });
      });
    } else if (raw.blocks) {
      raw.blocks.forEach((b, i) => {
        const x = b.x ?? b[0], y = b.y ?? b[1], z = b.z ?? b[2], block = b.block ?? b[3];
        if (typeof x !== "number" || typeof y !== "number" || typeof z !== "number" || typeof block !== "string") {
          throw new Error(`block ${i + 1} should look like [x, y, z, "minecraft:stone"]`);
        }
        blocks.push({ x: Math.floor(x), y: Math.floor(y), z: Math.floor(z), m: material(block, block) });
      });
    } else {
      throw new Error("the plan needs either layers or blocks");
    }
    if (!blocks.length) throw new Error("the plan has no blocks");
    let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
    for (const b of blocks) {
      x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y); z0 = Math.min(z0, b.z);
      x1 = Math.max(x1, b.x); y1 = Math.max(y1, b.y); z1 = Math.max(z1, b.z);
    }
    // later blocks win, as on the computers
    const at = new Map();
    for (const b of blocks) at.set(`${b.x - x0},${b.y - y0},${b.z - z0}`, { x: b.x - x0, y: b.y - y0, z: b.z - z0, m: b.m });
    const unique = [...at.values()];
    for (const b of unique) mats[b.m].total++;
    return { id, name: raw.name || id, clear: raw.clear !== false, mats, blocks: unique, w: x1 - x0 + 1, h: y1 - y0 + 1, l: z1 - z0 + 1 };
  }

  async function fromText(text, fileName) {
    const id = fileName.replace(/^.*\//, "").replace(/\.\w+$/, "");
    const lua = /\.lua$/i.test(fileName) || (!/\.json$/i.test(fileName) && !/^\s*[{[]/.test(text));
    let raw;
    if (lua) raw = await runLua(text);
    else {
      try { raw = JSON.parse(text); } catch (e) { throw new Error(`that isn't valid JSON (${e.message})`); }
    }
    return fromTable(raw, id);
  }

  async function load(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`couldn't fetch ${url} (${res.status})`);
    return fromText(await res.text(), url);
  }

  //---------------------------------------------------------------- looks

  // Colour from words in the block name, as the projector picks them.
  // Earlier entries win, so dye colours beat "glass"/"wool" and "dark_oak" beats "oak".
  const COLOR_WORDS = [
    ["light_blue", "#3ab3da"], ["light_gray", "#9d9d97"], ["white", "#e9ecec"], ["gray", "#4c5257"],
    ["black", "#1d1d21"], ["brown", "#835432"], ["red", "#a12722"], ["orange", "#f9801d"],
    ["yellow", "#fed83d"], ["lime", "#80c71f"], ["green", "#5e7c16"], ["cyan", "#169c9c"],
    ["blue", "#3c44aa"], ["purple", "#8932b8"], ["magenta", "#c74ebd"], ["pink", "#f38baa"],
    ["dark_oak", "#4f3218"], ["oak", "#b8945f"], ["spruce", "#72543a"], ["birch", "#d7cb8d"],
    ["jungle", "#b88764"], ["acacia", "#ba6337"], ["mangrove", "#773934"], ["cherry", "#e4b4a5"],
    ["bamboo", "#d2bd5a"], ["crimson", "#7e3a56"], ["warped", "#2b6963"],
    ["nether", "#5a2a2e"], ["mossy", "#6a7d4f"], ["cobblestone", "#7a7a7a"], ["deepslate", "#4d4d52"],
    ["blackstone", "#2a2328"], ["sandstone", "#d8cb9b"], ["sand", "#dbcfa3"], ["gravel", "#847f7e"],
    ["andesite", "#888889"], ["diorite", "#bcbcbc"], ["granite", "#956755"], ["tuff", "#6c6d66"],
    ["calcite", "#dfe0dc"], ["smooth_stone", "#a0a0a0"], ["stone", "#8f8f8f"], ["bricks", "#976253"], ["brick", "#976253"],
    ["quartz", "#ebe5de"], ["prismarine", "#63a598"], ["sea_lantern", "#d6e6e0"], ["purpur", "#a77aa7"], ["terracotta", "#985e43"],
    ["mud", "#8c6a4f"], ["dirt", "#866043"], ["grass", "#5d9a3a"], ["leaves", "#3f8a2f"],
    ["hay", "#c9a42a"], ["glass", "#a8d8ea"], ["ice", "#91b7fd"], ["snow", "#f6fefe"],
    ["water", "#3f76e4"], ["lava", "#d96415"], ["iron", "#d8d8d8"], ["gold", "#f5cd3c"],
    ["oxidized", "#4fa58a"], ["amethyst", "#8d63c8"], ["obsidian", "#1e1530"], ["pearlescent", "#e6c6dc"],
    ["verdant", "#d4e8b8"], ["shroomlight", "#f0a050"], ["moss", "#5a7a2c"], ["barrel", "#86643a"],
    ["bookshelf", "#7a5a32"], ["crafting", "#9c6a3a"], ["smithing", "#3a3a46"], ["cartography", "#8a7050"],
    ["fletching", "#c9b27a"], ["enchanting", "#7a2030"], ["brewing", "#8a8a6a"], ["cauldron", "#3c3c40"],
    ["campfire", "#e08a2c"], ["candle", "#e8dcb0"], ["azalea", "#5f8a30"], ["fern", "#4f7f30"], ["poppy", "#c0282a"],
    ["cornflower", "#4a64c8"], ["cane", "#8cbf5a"],
    ["copper", "#c0704c"], ["lantern", "#f2b84a"], ["torch", "#f2c84a"], ["glowstone", "#f8d58a"], ["end_rod", "#f0ece0"],
    ["log", "#6b5131"], ["wood", "#6b5131"], ["planks", "#b8945f"],
  ];
  const FALLBACK = ["#ff6b6b", "#ffd166", "#06d6a0", "#4cc9f0", "#b388eb", "#f78c6b", "#83e377", "#f15bb5"];

  function colourFor(block) {
    const words = "_" + block.replace(/^.*:/, "").replace(/\[.*$/, "") + "_";
    for (const [w, c] of COLOR_WORDS) if (words.includes("_" + w + "_")) return c;
    let h = 0;
    for (let i = 0; i < block.length; i++) h = (h * 31 + block.charCodeAt(i)) % 65536;
    return FALLBACK[h % FALLBACK.length];
  }

  // A voxel.js block type for a block name: its colour, see-through for
  // glass, and a rough shape for slabs, panes, bars, fences, torches and the like.
  function blockType(block) {
    const key = "plan:" + block;
    if (Voxel.BLOCKS[key]) return key;
    const n = block.replace(/^.*:/, "").replace(/\[.*$/, "");
    const def = { c: colourFor(block), tex: "noise", amt: 0.06 };
    if (/glass/.test(n)) Object.assign(def, { alpha: 0.55, clear: true, amt: 0.03 });
    if (/_slab$/.test(n)) Object.assign(def, { box: [0, 1, 0, 0.5, 0, 1], clear: true });
    if (/(pane|_bars)$/.test(n)) Object.assign(def, { box: [0.42, 0.58, 0, 1, 0, 1], clear: true });
    if (/(_fence|_wall)$/.test(n)) Object.assign(def, { box: [0.32, 0.68, 0, 1, 0.32, 0.68], clear: true });
    if (/(torch|end_rod|lightning_rod)$/.test(n)) Object.assign(def, { box: [0.42, 0.58, 0, 0.8, 0.42, 0.58], clear: true, glow: /torch/.test(n) });
    if (/lantern$/.test(n) && !/sea_lantern/.test(n)) Object.assign(def, { box: [0.3, 0.7, 0, 0.6, 0.3, 0.7], clear: true, glow: true });
    if (/_door$/.test(n)) Object.assign(def, { box: [0, 1, 0, 1, 0.42, 0.58], clear: true, tex: "planks" });
    if (/(carpet|pressure_plate|_rail)$/.test(n)) Object.assign(def, { box: [0, 1, 0, 0.08, 0, 1], clear: true });
    if (/(planks|_stairs)$/.test(n) && !def.box) def.tex = "planks";
    if (/bricks$/.test(n)) def.tex = "bricks";
    if (/(leaves|_log|gravel|dirt|cobble)/.test(n)) def.amt = 0.16;
    Voxel.BLOCKS[key] = def;
    return key;
  }

  //---------------------------------------------------------------- the viewer

  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
  const short = (b) => b.replace(/^minecraft:/, "").replace(/_/g, " ");

  // Draws plan into holder: the picture, the layer slider (up to a layer, or
  // just that layer), the turn slider, and the blocks it needs.
  function mount(holder, plan, opts = {}) {
    holder.innerHTML = `
      <figure class="stage plan-stage" style="margin:0">
        <canvas aria-label="${esc(plan.name)}"></canvas>
        <div class="plan-layers">
          <div class="row">
            <label>Layer <b class="layer-n"></b> of ${plan.h}</label>
            <input type="range" class="layer" min="1" max="${plan.h}" value="${plan.h}" aria-label="Layer">
            <label class="only"><input type="checkbox"> only this layer</label>
          </div>
          <div class="row">
            <label>Turn <b class="turn-n"></b></label>
            <input type="range" class="turn" min="0" max="359" step="1" value="0" aria-label="Turn">
          </div>
        </div>
      </figure>
      <div class="plan-info">
        <div class="meta">
          <span class="pill">${plan.w} × ${plan.l} × ${plan.h}</span>
          <span class="pill">${plan.blocks.length.toLocaleString("en")} blocks</span>
          <span class="pill">${plan.clear ? "built on the ground" : "built in the air"}</span>
        </div>
        <table class="api plan-mats"></table>
      </div>`;
    const canvas = holder.querySelector("canvas");
    const slider = holder.querySelector("input.layer");
    const turn = holder.querySelector("input.turn");
    const only = holder.querySelector(".only input");
    const types = plan.mats.map((m) => blockType(m.block));
    turn.value = ((opts.rotation || 0) % 4) * 90;
    const big = plan.blocks.length > 6000;

    const mats = holder.querySelector(".plan-mats");
    const sorted = plan.mats.map((m, i) => ({ ...m, i })).sort((a, b) => b.total - a.total);
    mats.innerHTML = sorted.map((m) => `<tr><td><span class="swatch" style="background:${Voxel.BLOCKS[types[m.i]].c}"></span>${esc(short(m.block))}</td><td>${m.total.toLocaleString("en")}</td></tr>`).join("");

    let pending = 0;
    function draw() {
      cancelAnimationFrame(pending);
      pending = requestAnimationFrame(() => {
        const layer = +slider.value;
        holder.querySelector(".layer-n").textContent = layer;
        // the slider's angle as quarter turns of the blocks plus a -45..45 degree turn of the view
        const deg = +turn.value;
        holder.querySelector(".turn-n").textContent = deg + "°";
        const rot = Math.round(deg / 90) % 4, yaw = deg - Math.round(deg / 90) * 90;
        const w = new Voxel.World();
        for (const b of plan.blocks) {
          if (only.checked ? b.y === layer - 1 : b.y < layer) w.set(b.x, b.y, b.z, types[b.m]);
        }
        // fit the whole building at every angle, so the picture doesn't jump as layers change or it turns
        const bounds = [];
        for (const x of [0, plan.w - 1]) for (const y of [0, plan.h - 1]) for (const z of [0, plan.l - 1]) {
          let rx = x, rz = z;
          for (let i = 0; i < rot; i++) [rx, rz] = [-rz, rx];
          bounds.push([rx, y, rz]);
        }
        const rw = w.rotated(rot);
        if (!rw.m.size) { const ctx = canvas.getContext("2d"); ctx.clearRect(0, 0, canvas.width, canvas.height); return; }
        Voxel.render(canvas, rw, { width: holder.clientWidth, maxH: opts.maxH || 620, bounds, yaw, spin: true, detail: big ? 1 : undefined, pad: 0.05 });
      });
    }
    turn.oninput = draw;
    slider.oninput = draw;
    only.onchange = draw;
    let resizeT;
    window.addEventListener("resize", () => { clearTimeout(resizeT); resizeT = setTimeout(draw, 200); });
    draw();
    return { draw };
  }

  window.PlanView = { load, fromText, fromTable, mount, colourFor };
})();
