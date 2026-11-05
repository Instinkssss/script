// Uji tombol START: diagnostik + loop benar-benar jalan + log UI terisi.
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

function build(prep) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const h = fs.readFileSync(__dirname + '/harness.js', 'utf8');
  let pre = h.split('const PRELUDE = `')[1].split('`;')[0];
  pre = pre.replace('getgenv = function() return {} end', '__GENV = {}  getgenv = function() return __GENV end');
  pre = prep ? prep(pre) : pre;
  let r = lauxlib.luaL_dostring(L, to_luastring(pre));
  if (r !== lua.LUA_OK) { console.error('PRE: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }
  let src = fs.readFileSync(__dirname + '/../GrowbloxAllInOne.lua', 'utf8');
  src = src.replace(/ACTION_DELAY\s*=\s*0\.35/, 'ACTION_DELAY = 0');
  src = src.replace(/COLLECT_TIMEOUT\s*=\s*3/, 'COLLECT_TIMEOUT = 0.2');
  r = lauxlib.luaL_dostring(L, to_luastring(src));
  if (r !== lua.LUA_OK) { console.error('LOAD: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }
  return L;
}

function probe(L, extra) {
  const r = lauxlib.luaL_dostring(L, to_luastring(`
local G = getgenv().GrowbloxAutoFarm
G.start()
local guard = 0
local co = __ITER.co
while coroutine.status(co) == "suspended" and guard < 400 do
  guard = guard + 1
  local ok, err = coroutine.resume(co)
  if not ok then io.write("ERR: " .. tostring(err), string.char(10)) break end
end
local s = G.status()
RES = {}
RES.broken = tostring(s.broken)
RES.running = tostring(s.running)
RES.err = tostring(s.lastError)
RES.diag = tostring(s.diagnosa)
RES.idle = tostring(s.idleStrikes)
RES.guard = guard
` + (extra || '')));
  if (r !== lua.LUA_OK) { console.error('PROBE: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }
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
  const o = { broken: rd('broken'), running: rd('running'), err: rd('err'), diag: rd('diag'), idle: rd('idle'), guard: rd('guard') };
  lua.lua_close(L);
  return o;
}

console.log('\n=== UJI TOMBOL START ===');
const checks = [];

// A. normal
const a = probe(build());
console.log('A. normal           broken=' + a.broken + '  guard=' + a.guard);
console.log('   diagnosa: ' + a.diag);
checks.push(['START memulai loop', parseInt(a.guard) > 5]);
checks.push(['diagnostik terisi & tidak tertimpa', a.diag && a.diag.indexOf('block, target') > 0]);
checks.push(['block terhancur', parseInt(a.broken) > 0]);

// B. tanpa karakter (belum spawn)
const b = probe(build((p) => p.replace('lp.Character = char', 'lp.Character = nil')));
console.log('B. tanpa karakter   diagnosa=' + b.diag);
checks.push(['ditolak + alasan jelas kalau belum spawn', b.diag.indexOf('belum spawn') >= 0]);

// C. tanpa block
// kosongkan folder Blocks -> tidak ada kandidat sama sekali
const c = probe(build((p) => p.replace(
  /-- 10 block, dengan posisi makin jauh supaya urutan terdekat teruji[\s\S]*?^end$/m,
  '-- sengaja tanpa block'
)));
console.log('C. tanpa block      diagnosa=' + c.diag);
checks.push(['lapor alasan jelas kalau tidak ada block',
  c.diag.indexOf('Tidak ada block') >= 0 || c.diag.indexOf('di luar') >= 0]);

console.log('');
let all = true;
for (const [n, ok] of checks) { all = all && ok; console.log((ok ? 'PASS  ' : 'FAIL  ') + n); }
console.log(all ? '\nALL PASS' : '\nADA YANG GAGAL');
process.exit(all ? 0 : 1);
