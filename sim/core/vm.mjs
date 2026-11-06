// One Lua state per simulated computer (Fengari, patched to act like CC's
// Cobalt), plus the bridge between JS values and Lua values.
//
// Lua strings are bytes; on the JS side they're "binary" strings (one char
// per byte, 0-255), the same as CC's own view of text.
import { createRequire } from "node:module";
process.env.FENGARICONF = JSON.stringify({ LUA_COMPAT_FLOATSTRING: true });
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib } = require("fengari");

export { lua };

//---------------------------------------------------------------- strings

export function toLuaBytes(s) {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}
export function fromLuaBytes(u8) {
  if (!u8) return "";
  let s = "";
  for (let i = 0; i < u8.length; i += 8192) s += String.fromCharCode.apply(null, u8.subarray(i, i + 8192));
  return s;
}
const ls = (s) => toLuaBytes(s);

//---------------------------------------------------------------- values

// Several return values from a JS function called from Lua.
export class Multi {
  constructor(values) { this.values = values; }
}
export const multi = (...values) => new Multi(values);

// A Lua error raised from JS (the message is shown as is, no position).
export class LuaError extends Error {}

// A Lua value with no JS equivalent (a function, a coroutine), kept in the
// registry so JS can pass it back to the same state later.
export class LuaRef {
  constructor(vm, ref) { this.vm = vm; this.ref = ref; }
}

export function push(L, v, vm) {
  if (v === undefined || v === null) return lua.lua_pushnil(L);
  switch (typeof v) {
    case "boolean": return lua.lua_pushboolean(L, v);
    case "number":
      if (Number.isInteger(v) && v >= -2147483648 && v <= 2147483647) return lua.lua_pushinteger(L, v);
      return lua.lua_pushnumber(L, v);
    case "string": return lua.lua_pushstring(L, ls(v));
    case "function": return lua.lua_pushjsfunction(L, wrapFunction(v, vm));
    case "object": {
      if (v instanceof LuaRef) return lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, v.ref);
      if (v instanceof Uint8Array) return lua.lua_pushstring(L, v);
      if (Array.isArray(v)) {
        lua.lua_createtable(L, v.length, 0);
        for (let i = 0; i < v.length; i++) { push(L, v[i], vm); lua.lua_rawseti(L, -2, i + 1); }
        return;
      }
      if (v instanceof Map) {
        lua.lua_createtable(L, 0, v.size);
        for (const [k, x] of v) { push(L, k, vm); push(L, x, vm); lua.lua_rawset(L, -3); }
        return;
      }
      lua.lua_createtable(L, 0, 4);
      for (const k of Object.keys(v)) {
        if (v[k] === undefined) continue;
        push(L, k, vm); push(L, v[k], vm); lua.lua_rawset(L, -3);
      }
      return;
    }
  }
  lua.lua_pushnil(L);
}

// Lua value at idx → JS. Tables become arrays when their keys are exactly
// 1..n, else objects (number keys as strings) unless asMap.
export function get(L, idx, vm, seen = new Set(), depth = 0) {
  idx = lua.lua_absindex(L, idx);
  switch (lua.lua_type(L, idx)) {
    case lua.LUA_TNIL: case lua.LUA_TNONE: return null;
    case lua.LUA_TBOOLEAN: return lua.lua_toboolean(L, idx);
    case lua.LUA_TNUMBER: return lua.lua_tonumber(L, idx);
    case lua.LUA_TSTRING: return fromLuaBytes(lua.lua_tostring(L, idx));
    case lua.LUA_TTABLE: {
      const p = lua.lua_topointer(L, idx);
      if (seen.has(p) || depth > 60) throw new LuaError("Cannot serialize table with recursive entries");
      seen.add(p);
      const keys = [], vals = [];
      lua.lua_pushnil(L);
      while (lua.lua_next(L, idx)) {
        const t = lua.lua_type(L, -2);
        const k = t === lua.LUA_TNUMBER ? lua.lua_tonumber(L, -2) : t === lua.LUA_TSTRING ? fromLuaBytes(lua.lua_tostring(L, -2)) : t === lua.LUA_TBOOLEAN ? lua.lua_toboolean(L, -2) : null;
        const vt = lua.lua_type(L, -1);
        if (k !== null && vt !== lua.LUA_TFUNCTION && vt !== lua.LUA_TTHREAD && vt !== lua.LUA_TUSERDATA) {
          keys.push(k); vals.push(get(L, -1, vm, seen, depth + 1));
        }
        lua.lua_pop(L, 1);
      }
      seen.delete(p);
      const n = keys.length;
      let isArr = n > 0;
      if (isArr) {
        const have = new Array(n + 1).fill(false);
        for (const k of keys) { if (typeof k !== "number" || !Number.isInteger(k) || k < 1 || k > n || have[k]) { isArr = false; break; } have[k] = true; }
      }
      if (isArr) { const a = new Array(n); keys.forEach((k, i) => { a[k - 1] = vals[i]; }); return a; }
      const o = {};
      keys.forEach((k, i) => { o[String(k)] = vals[i]; });
      // remember which keys were numbers, so the table goes back the same way
      if (keys.some((k) => typeof k === "number")) Object.defineProperty(o, "__numkeys", { value: new Set(keys.filter((k) => typeof k === "number").map(String)) });
      return o;
    }
    case lua.LUA_TFUNCTION:
    case lua.LUA_TTHREAD: {
      if (!vm) return null;
      lua.lua_pushvalue(L, idx);
      return new LuaRef(vm, lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX));
    }
  }
  return null;
}

// JS value → Lua, keeping number keys numbers (for values that came from Lua).
export function pushCopy(L, v, vm) {
  if (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Map) && !(v instanceof LuaRef) && v.__numkeys) {
    lua.lua_createtable(L, 0, 4);
    for (const k of Object.keys(v)) {
      if (v.__numkeys.has(k)) lua.lua_pushnumber(L, Number(k)); else push(L, k, vm);
      pushCopy(L, v[k], vm); lua.lua_rawset(L, -3);
    }
    return;
  }
  if (Array.isArray(v)) {
    lua.lua_createtable(L, v.length, 0);
    for (let i = 0; i < v.length; i++) { pushCopy(L, v[i], vm); lua.lua_rawseti(L, -2, i + 1); }
    return;
  }
  if (v && typeof v === "object" && !(v instanceof Map) && !(v instanceof LuaRef) && !(v instanceof Uint8Array)) {
    lua.lua_createtable(L, 0, 4);
    for (const k of Object.keys(v)) { if (v[k] === undefined) continue; push(L, k, vm); pushCopy(L, v[k], vm); lua.lua_rawset(L, -3); }
    return;
  }
  push(L, v, vm);
}

function wrapFunction(fn, vm) {
  return (L) => {
    const n = lua.lua_gettop(L);
    const args = [];
    for (let i = 1; i <= n; i++) args.push(get(L, i, vm));
    let r;
    try {
      r = fn(...args);
    } catch (e) {
      if (e instanceof LuaError) return lauxlib.luaL_error(L, ls(e.message));
      if (e && e.__luaYield) throw e;
      // a bug in the simulator: show it, as a Lua error
      return lauxlib.luaL_error(L, ls(`[sim] ${e && e.stack ? e.stack.split("\n").slice(0, 3).join(" | ") : e}`));
    }
    if (r instanceof Multi) { for (const v of r.values) pushCopy(L, v, vm); return r.values.length; }
    if (r === undefined) return 0;
    pushCopy(L, r, vm);
    return 1;
  };
}

//---------------------------------------------------------------- the VM

const YIELD_LIMIT_MS = 7000; // CC kills a computer that runs this long without yielding

export class VM {
  // natives: object of globals (tables of JS functions) set before the prelude
  constructor(natives) {
    const L = (this.L = lauxlib.luaL_newstate());
    lualib.luaL_openlibs(L);
    for (const [name, v] of Object.entries(natives)) { push(L, v, this); lua.lua_setglobal(L, ls(name)); }
    this.co = null;
    this.dead = false;
    this.started = 0;
  }

  setGlobal(name, v) { push(this.L, v, this); lua.lua_setglobal(this.L, ls(name)); }

  // Run code in the main state (no yielding), for the prelude.
  run(source, chunk) {
    const L = this.L;
    if (lauxlib.luaL_loadbufferx(L, ls(source), null, ls("@" + chunk), null) !== lua.LUA_OK) throw new Error(fromLuaBytes(lua.lua_tostring(L, -1)));
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { const m = fromLuaBytes(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); throw new Error(m); }
  }

  // Start the main coroutine from a global function.
  start(globalName) {
    const L = this.L;
    this.co = lua.lua_newthread(L);
    this.coRef = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX); // keep it alive
    lua.lua_sethook(this.co, (C) => {
      if (Date.now() - this.started > YIELD_LIMIT_MS) lauxlib.luaL_error(C, ls("Too long without yielding"));
    }, lua.LUA_MASKCOUNT, 20000);
    lua.lua_getglobal(this.co, ls(globalName));
    this.pending = 0;
  }

  // Resume with an event (array of JS values). Returns { done, filter, error }.
  resume(event) {
    if (this.dead) return { done: true };
    const co = this.co;
    let nargs = this.pending;
    this.pending = 0;
    if (event) { for (const v of event) pushCopy(co, v, this); nargs += event.length; }
    this.started = Date.now();
    const st = lua.lua_resume(co, this.L, nargs);
    if (st === lua.LUA_YIELD) {
      const n = lua.lua_gettop(co);
      const filter = n >= 1 && lua.lua_type(co, 1) === lua.LUA_TSTRING ? fromLuaBytes(lua.lua_tostring(co, 1)) : null;
      lua.lua_settop(co, 0);
      return { done: false, filter };
    }
    this.dead = true;
    if (st === lua.LUA_OK) return { done: true };
    const msg = lua.lua_type(co, -1) === lua.LUA_TSTRING ? fromLuaBytes(lua.lua_tostring(co, -1)) : "(error object is not a string)";
    return { done: true, error: msg };
  }

  // Call a Lua function kept as a LuaRef (no yielding), returns its results.
  call(ref, ...args) {
    const L = this.L;
    lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, ref.ref);
    for (const a of args) pushCopy(L, a, this);
    const top = lua.lua_gettop(L) - args.length - 1;
    if (lua.lua_pcall(L, args.length, lua.LUA_MULTRET, 0) !== lua.LUA_OK) { const m = fromLuaBytes(lua.lua_tostring(L, -1)); lua.lua_settop(L, top); throw new LuaError(m); }
    const out = [];
    for (let i = top + 1; i <= lua.lua_gettop(L); i++) out.push(get(L, i, this));
    lua.lua_settop(L, top);
    return out;
  }
}
