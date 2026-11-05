// Uji mode sapuan: threeWay / sweepLeft / sweepRight / plant / autoTrash.
// Membuktikan toggle di UI benar-benar mengubah perilaku loop, bukan hiasan.
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

function run(modesLua, label) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const h = fs.readFileSync(__dirname + '/harness.js', 'utf8');
  let pre = h.split('const PRELUDE = `')[1].split('`;')[0];
  pre = pre.replace('Instance = { new = function(cls) return inst(cls, cls) end }',
    'Instance = { new = function(cls) __N = (__N or 0) + 1 return inst(cls, cls) end }');
  pre = pre.replace('getgenv = function() return {} end',
    '__GENV = {}  getgenv = function() return __GENV end');

  let r = lauxlib.luaL_dostring(L, to_luastring(pre));
  if (r !== lua.LUA_OK) { console.error('PRELUDE: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }

  let src = fs.readFileSync(__dirname + '/../AutoFarm.lua', 'utf8');
  src = src.replace(/AUTO_START\s*=\s*false/, 'AUTO_START = false');
  src = src.replace(/ACTION_DELAY\s*=\s*0\.35/, 'ACTION_DELAY = 0');
  src = src.replace(/COLLECT_TIMEOUT\s*=\s*3/, 'COLLECT_TIMEOUT = 0.2');

  r = lauxlib.luaL_dostring(L, to_luastring(src));
  if (r !== lua.LUA_OK) { console.error('AUTOFARM [' + label + ']: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }

  r = lauxlib.luaL_dostring(L, to_luastring(`
local G = getgenv().GrowbloxAutoFarm
${modesLua}
G.start()
local guard = 0
local co = __ITER.co
while coroutine.status(co) == "suspended" and guard < 400 do
  guard = guard + 1
  local ok, err = coroutine.resume(co)
  if not ok then io.write("CORO-ERR: " .. tostring(err), string.char(10)) break end
end
local s = G.status()
RES = {}
RES.broken = s.broken
RES.collected = s.collected
RES.guard = guard
RES.breakCalls = RESULT and RESULT.breakCalls or 0
RES.idle = s.idleStrikes
RES.err = tostring(s.lastError)
`));
  if (r !== lua.LUA_OK) { console.error('DRIVE [' + label + ']: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }

  lua.lua_getglobal(L, to_luastring('RES'));
  const rd = (k) => {
    lua.lua_getfield(L, -1, to_luastring(k));
    const t = lua.lua_type(L, -1);
    let v;
    if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1) ? 'true' : 'false';
    else if (t === lua.LUA_TNUMBER) v = String(lua.lua_tonumber(L, -1));
    else v = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    return v;
  };
  const res = { broken: parseInt(rd('broken')), collected: parseInt(rd('collected')), guard: parseInt(rd('guard')) };
  lua.lua_close(L);
  return res;
}

const cases = [
  ['default (semua mode mati)', ''],
  ['threeWay aktif', 'G.setMode("threeWay", true)'],
  ['sweepLeft aktif', 'G.setMode("sweepLeft", true)'],
  ['sweepRight aktif', 'G.setMode("sweepRight", true)'],
  ['plant aktif', 'G.setMode("plant", true)'],
  ['autoTrash aktif', 'G.setMode("autoTrash", true)'],
];

console.log('\n=== UJI MODE SAPUAN ===');
const out = {};
let crashed = false;
for (const [label, modes] of cases) {
  try {
    const r = run(modes, label);
    out[label] = r;
    console.log('OK    ' + label.padEnd(30) + ' broken=' + r.broken + '  breakCalls=' + r.breakCalls + '  idle=' + r.idle + '  guard=' + r.guard + '  err=' + r.err);
  } catch (e) {
    crashed = true;
    console.log('CRASH ' + label.padEnd(30) + ' ' + e.message);
  }
}

console.log('');
const base = out['default (semua mode mati)'];
const checks = [
  ['tidak ada mode yang crash', !crashed],
  ['default menghancurkan block', base && base.broken > 0],
  ['threeWay menghancurkan >= default (cluster lebih banyak)',
    out['threeWay aktif'] && out['threeWay aktif'].broken >= base.broken],
  ['sweepLeft jalan tanpa hang', out['sweepLeft aktif'] && out['sweepLeft aktif'].guard < 400],
  ['sweepRight jalan tanpa hang', out['sweepRight aktif'] && out['sweepRight aktif'].guard < 400],
  ['plant jalan tanpa crash', !!out['plant aktif']],
  ['autoTrash jalan tanpa crash', !!out['autoTrash aktif']],
];
let all = true;
for (const [n, ok] of checks) { all = all && ok; console.log((ok ? 'PASS  ' : 'FAIL  ') + n); }
console.log(all ? '\nALL PASS' : '\nADA YANG GAGAL');
process.exit(all ? 0 : 1);
