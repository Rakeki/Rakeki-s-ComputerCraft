// Plays the display monitor's animations (animations/*.lua) in the browser:
// runs the display's own anim.lua in fengari, the same code the computer
// uses, paints every frame for a monitor-sized screen and plays them on a
// CC.Screen at the animation's own speed.
(function () {
  const FENGARI = "https://cdn.jsdelivr.net/npm/fengari-web@0.1.4/dist/fengari-web.js";
  const HEX = { 0: "white", 1: "orange", 2: "magenta", 3: "lightBlue", 4: "yellow", 5: "lime", 6: "pink", 7: "gray", 8: "lightGray", 9: "cyan", a: "purple", b: "blue", c: "brown", d: "green", e: "red", f: "black" };
  const CHARS = { "\u0001": "♫" }; // CC's note character (14), marked by the Lua side

  let fengariReady = null;
  function loadFengari() {
    if (window.fengari) return Promise.resolve(window.fengari);
    if (!fengariReady) {
      fengariReady = new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = FENGARI;
        s.onload = () => resolve(window.fengari);
        s.onerror = () => reject(new Error("Couldn't load the Lua runner (fengari)."));
        document.head.append(s);
      });
    }
    return fengariReady;
  }

  // Every frame as text: length, frame time, then a line per row ("text\tfg\tbg").
  // Characters a browser can't show from CC's font become spaces; the note, \1.
  const LUA = `
local anim = assert(load(ANIM_SOURCE, "=anim"))()
local a, err = anim.load(SOURCE, NAME)
if not a then error(err, 0) end
local bad = "[%z" .. string.char(1) .. "-" .. string.char(31) .. string.char(127) .. "-" .. string.char(255) .. "]"
local note = string.char(14)
local out = { tostring(a.length), tostring(a.frameTime), a.title }
for t = 1, a.length do
  for _, row in ipairs(anim.frame(a, t, W, H)) do
    local text = row[1]:gsub(bad, function(c) return c == note and string.char(1) or " " end)
    out[#out + 1] = text .. "\\t" .. row[2] .. "\\t" .. row[3]
  end
end
return table.concat(out, "\\n")`;

  const sources = {};
  const text = (url) => (sources[url] ||= fetch(url).then((r) => { if (!r.ok) throw new Error(`${url}: ${r.status}`); return r.text(); }));

  async function frames(root, file, name, W, H) {
    const [animSource, source] = await Promise.all([text(`${root}computers/display-monitor/anim.lua`), text(`${root}animations/${file}`)]);
    const { lua, lauxlib, lualib, to_luastring } = await loadFengari();
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    const set = (k, v) => { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setglobal(L, to_luastring(k)); };
    set("ANIM_SOURCE", animSource); set("SOURCE", source); set("NAME", name);
    lua.lua_pushinteger(L, W); lua.lua_setglobal(L, to_luastring("W"));
    lua.lua_pushinteger(L, H); lua.lua_setglobal(L, to_luastring("H"));
    if (lauxlib.luaL_dostring(L, to_luastring(LUA)) !== 0) throw new Error(lua.lua_tojsstring(L, -1));
    const lines = lua.lua_tojsstring(L, -1).split("\n");
    const length = Number(lines[0]), frameTime = Number(lines[1]), title = lines[2], rows = lines.slice(3);
    const out = [];
    for (let t = 0; t < length; t++) out.push(rows.slice(t * H, (t + 1) * H).map((l) => l.split("\t")));
    return { frames: out, frameTime, title };
  }

  // Plays animations/<file> in a <pre>. A 3 x 2 monitor's size unless told.
  async function mount(pre, { root = "./", file, name, w = 57, h = 24 }) {
    const s = new CC.Screen(w, h, pre);
    s.put(2, 2, "Loading...", "lightGray"); s.render();
    let anim;
    try {
      anim = await frames(root, file, name || file.replace(/\.lua$/, ""), w, h);
    } catch (e) {
      s.clear(); s.put(2, 2, "Can't play this one:", "red");
      String(e.message || e).match(new RegExp(`.{1,${w - 2}}`, "g")).slice(0, h - 3).forEach((l, i) => s.put(2, 4 + i, l, "white"));
      s.render();
      return s;
    }
    let t = 0;
    const draw = () => {
      const rows = anim.frames[t];
      s.clear();
      rows.forEach(([txt, fg, bg], r) => {
        for (let c = 0; c < w; c++) s.put(c + 1, r + 1, CHARS[txt[c]] || txt[c] || " ", HEX[fg[c]] || "white", HEX[bg[c]] || "black");
      });
      s.render();
      t = (t + 1) % anim.frames.length;
    };
    draw();
    setInterval(draw, Math.max(50, anim.frameTime * 1000));
    return s;
  }

  window.Anims = { mount };
})();
