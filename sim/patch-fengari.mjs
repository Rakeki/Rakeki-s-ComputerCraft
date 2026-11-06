// Makes Fengari (Lua 5.3 in JS, 32-bit integers) behave like CC: Tweaked's
// Cobalt (Lua 5.2, every number a double) where the programs could tell:
//   - integer + - * and unary minus that overflow 32 bits give a float
//     instead of wrapping round (Cobalt never wraps)
//   - tostring(2.0) is "2", not "2.0" (LUA_COMPAT_FLOATSTRING, set in vm.mjs)
//   - "%." in a gsub replacement is "." (5.3 says "invalid use of '%'")
// Run by `npm install` (postinstall); safe to run again.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SRC = path.join(path.dirname(fileURLToPath(import.meta.url)), "node_modules", "fengari", "src");
const MARK = "/* cc-sim patched */";

function patch(file, edits) {
  const p = path.join(SRC, file);
  let s = fs.readFileSync(p, "utf8");
  if (s.includes(MARK)) return;
  for (const [from, to] of edits) {
    if (!s.includes(from)) throw new Error(`${file}: can't find ${from}`);
    s = s.split(from).join(to);
  }
  s = `${MARK}\nconst __ccnum = (v, r) => { if (r === (r | 0)) v.setivalue(r); else v.setfltvalue(r); };\n` + s;
  fs.writeFileSync(p, s);
}

patch("lvm.js", [
  ["L.stack[ra].setivalue((op1.value + op2.value)|0);", "__ccnum(L.stack[ra], op1.value + op2.value);"],
  ["L.stack[ra].setivalue((op1.value - op2.value)|0);", "__ccnum(L.stack[ra], op1.value - op2.value);"],
  ["L.stack[ra].setivalue(luaV_imul(op1.value, op2.value));", "__ccnum(L.stack[ra], op1.value * op2.value);"],
  ["L.stack[ra].setivalue((-op.value)|0);", "__ccnum(L.stack[ra], -op.value);"],
]);

patch("lobject.js", [
  [
    "            if (p1.ttisinteger() && p2.ttisinteger()) {\n                res.setivalue(intarith(L, op, p1.value, p2.value));",
    "            if (p1.ttisinteger() && p2.ttisinteger() && (op === LUA_OPADD || op === LUA_OPSUB || op === LUA_OPMUL || op === LUA_OPUNM)) {\n                __ccnum(res, numarith(L, op, p1.value, p2.value));\n                return;\n            }\n            if (p1.ttisinteger() && p2.ttisinteger()) {\n                res.setivalue(intarith(L, op, p1.value, p2.value));",
  ],
]);
patch("lstrlib.js", [
  ["if (news[i] !== L_ESC)\n                    luaL_error(", "if (false)\n                    luaL_error("],
]);
console.log("fengari patched for CC (Lua 5.2 numbers)");
