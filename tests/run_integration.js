// Uji AutoFarm.lua nyata: UI terbangun + API terekspos + loop jalan
const fs=require('fs');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const h=fs.readFileSync(__dirname+'/harness.js','utf8');
let pre=h.split('const PRELUDE = `')[1].split('`;')[0];
pre=pre.replace('Instance = { new = function(cls) return inst(cls, cls) end }',
 'Instance = { new = function(cls) __N=(__N or 0)+1 return inst(cls, cls) end }');
pre=pre.replace('getgenv = function() return {} end','__GENV = {}  getgenv = function() return __GENV end');
let r=lauxlib.luaL_dostring(L,to_luastring(pre));
if(r!==lua.LUA_OK){console.error('PRELUDE: '+lua.lua_tojsstring(L,-1));process.exit(1);}
const src=fs.readFileSync(__dirname+'/../AutoFarm.lua','utf8');
r=lauxlib.luaL_dostring(L,to_luastring(src));
if(r!==lua.LUA_OK){console.error('AUTOFARM: '+lua.lua_tojsstring(L,-1));process.exit(1);}
lauxlib.luaL_dostring(L,to_luastring(`
local G = getgenv().GrowbloxAutoFarm
RES = {}
RES.instances = __N or 0
RES.apiExposed = (G ~= nil)
if type(G) == "table" then
  local s = G.status and G.status() or {}
  RES.uiAttached = (s.ui ~= nil)
  RES.modesExists = (s.modes ~= nil)
  RES.autoCollect = tostring(s.autoCollect)
  if G.setMode then G.setMode("threeWay", true) RES.modeReadback = tostring(G.getMode("threeWay")) end
end
`));
lua.lua_getglobal(L,to_luastring('RES'));
const rd=(k)=>{lua.lua_getfield(L,-1,to_luastring(k));const t=lua.lua_type(L,-1);
 let v; if(t===lua.LUA_TBOOLEAN)v=lua.lua_toboolean(L,-1)?'true':'false';
 else if(t===lua.LUA_TNUMBER)v=String(lua.lua_tonumber(L,-1));else v=lua.lua_tojsstring(L,-1);
 lua.lua_pop(L,1);return v;};
const rows=[
 ['Instance UI dibuat', rd('instances'), v=>parseInt(v)>80],
 ['API terekspos ke getgenv()', rd('apiExposed'), v=>v==='true'],
 ['STATE.ui terpasang', rd('uiAttached'), v=>v==='true'],
 ['STATE.modes ada', rd('modesExists'), v=>v==='true'],
 ['setMode -> getMode konsisten', rd('modeReadback'), v=>v==='true'],
 ['autoCollect default true', rd('autoCollect'), v=>v==='true'],
];
console.log('\n=== AutoFarm.lua INTEGRATION ===');
let all=true;
for(const [n,v,fn] of rows){const ok=fn(v);all=all&&ok;console.log((ok?'PASS  ':'FAIL  ')+n.padEnd(34)+' ('+v+')');}
console.log(all?'\nALL PASS':'\nADA YANG GAGAL');
process.exit(all?0:1);
