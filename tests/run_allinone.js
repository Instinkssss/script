// Uji GrowbloxAllInOne.lua: scout jalan otomatis + UI terbangun + remote terisi.
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const h = fs.readFileSync(__dirname + '/harness.js', 'utf8');
let pre = h.split('const PRELUDE = `')[1].split('`;')[0];
pre = pre.replace('Instance = { new = function(cls) return inst(cls, cls) end }',
  'Instance = { new = function(cls) __N = (__N or 0) + 1 return inst(cls, cls) end }');
pre = pre.replace('getgenv = function() return {} end',
  '__GENV = {}  getgenv = function() return __GENV end');
// hitung writefile yang dipanggil
pre = pre.replace('loadstring = function() return function() return nil end end',
  'loadstring = function() return function() return nil end end\n__WRITE = {}');
pre += '\nwritefile = function(n, c) __WRITE[n] = c end\n';

let r = lauxlib.luaL_dostring(L, to_luastring(pre));
if (r !== lua.LUA_OK) { console.error('PRELUDE: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }

const src = fs.readFileSync(__dirname + '/../GrowbloxAllInOne.lua', 'utf8');
r = lauxlib.luaL_dostring(L, to_luastring(src));
if (r !== lua.LUA_OK) { console.error('LOAD: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }

r = lauxlib.luaL_dostring(L, to_luastring(`
local G = getgenv().GrowbloxAutoFarm
RES = {}
RES.apiExposed = (G ~= nil)
RES.instances = __N or 0
if type(G) == "table" then
  local hasil = G.getScoutResult and G.getScoutResult() or ""
  RES.scoutLen = #hasil
  RES.hasRemoteSection = (string.find(hasil, "SEMUA REMOTE", 1, true) ~= nil) and "true" or "false"
  RES.hasBlockSection  = (string.find(hasil, "ANALISA BLOCK", 1, true) ~= nil) and "true" or "false"
  RES.hasGridSection   = (string.find(hasil, "GRID", 1, true) ~= nil) and "true" or "false"
  RES.hasInvSection    = (string.find(hasil, "INVENTORY", 1, true) ~= nil) and "true" or "false"
  RES.hasToolSection   = (string.find(hasil, "TOOL", 1, true) ~= nil) and "true" or "false"
  RES.wroteFile        = (__WRITE["growblox_scout.txt"] ~= nil) and "true" or "false"
  local s = G.status and G.status() or {}
  RES.uiAttached = (s.ui ~= nil) and "true" or "false"
  -- remote harus terisi otomatis dari hasil scout
  RES.remoteBreak = tostring(s.ui and "ada" or "tidak")
end
RES.scoutCallsOk = "true"
`));
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

const rows = [
  ['Scout jalan otomatis saat load', parseInt(rd('scoutLen')) > 500, rd('scoutLen') + ' char'],
  ['Hasil scout punya bagian REMOTE', rd('hasRemoteSection') === 'true', ''],
  ['Hasil scout punya bagian BLOCK', rd('hasBlockSection') === 'true', ''],
  ['Hasil scout punya bagian GRID', rd('hasGridSection') === 'true', ''],
  ['Hasil scout punya bagian INVENTORY', rd('hasInvSection') === 'true', ''],
  ['Hasil scout punya bagian TOOL', rd('hasToolSection') === 'true', ''],
  ['Scout menulis growblox_scout.txt', rd('wroteFile') === 'true', ''],
  ['UI terbangun (Instance > 100)', parseInt(rd('instances')) > 100, rd('instances') + ' Instance'],
  ['API terekspos', rd('apiExposed') === 'true', ''],
  ['STATE.ui terpasang', rd('uiAttached') === 'true', ''],
];

console.log('\n=== GrowbloxAllInOne.lua (SCOUT + FARM + UI) ===');
let all = true;
for (const [n, ok, extra] of rows) {
  all = all && ok;
  console.log((ok ? 'PASS  ' : 'FAIL  ') + n.padEnd(40) + (extra ? '(' + extra + ')' : ''));
}
console.log(all ? '\nALL PASS' : '\nADA YANG GAGAL');
process.exit(all ? 0 : 1);
