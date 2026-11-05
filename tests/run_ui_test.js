// Uji FarmUI.lua: build(API) harus jalan dan menghasilkan tabel kontrol.
const fs=require('fs');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const h=fs.readFileSync(__dirname+'/harness.js','utf8');
let pre=h.split('const PRELUDE = `')[1].split('`;')[0];
// Instance.new dicatat
pre=pre.replace('Instance = { new = function(cls) return inst(cls, cls) end }',
  'Instance = { new = function(cls) __UI_N = (__UI_N or 0) + 1 return inst(cls, cls) end }');
if(lauxlib.luaL_dostring(L,to_luastring(pre))!==lua.LUA_OK){console.error('PRELUDE:',lua.lua_tojsstring(L,-1));process.exit(1);}

let uisrc=fs.readFileSync(__dirname+'/../FarmUI.lua','utf8');
const driver=`
local API = {
  status = function() return {running=false, broken=7, collected=3, currentTarget="Block1", idleStrikes=0} end,
  toggle = function() end, start = function() end, stop = function() end,
  reset = function() end, destroy = function() end,
  setMode = function(k,v) end, setAutoCollect = function(v) end,
}
local UI = __loadUI()
local res = { }
local ok, err = pcall(function() return UI.build(API) end)
res.ok = ok
res.err = tostring(err)
res.instances = __UI_N or 0
if ok then
  local st = UI.build and nil
  res.hasRefresh = false
  res.hasLog = false
  res.hasDestroy = false
end
HASIL = res
`;
let src="local function __loadUI()\n"+uisrc+"\nend\n"+driver;
if(lauxlib.luaL_dostring(L,to_luastring(src))!==lua.LUA_OK){
  console.error('LOAD ERROR:\n'+lua.lua_tojsstring(L,-1));process.exit(1);
}
lua.lua_getglobal(L,to_luastring('HASIL'));
const rd=(k)=>{lua.lua_getfield(L,-1,to_luastring(k));const t=lua.lua_type(L,-1);
 let v; if(t===lua.LUA_TBOOLEAN)v=lua.lua_toboolean(L,-1)?'true':'false';
 else if(t===lua.LUA_TNUMBER)v=String(lua.lua_tonumber(L,-1));else v=lua.lua_tojsstring(L,-1);
 lua.lua_pop(L,1);return v;};
console.log('\n=== FarmUI BUILD ===');
console.log('build sukses      :', rd('ok'));
console.log('error             :', rd('err'));
console.log('Instance dibuat   :', rd('instances'));
const ok = rd('ok')==='true' && parseInt(rd('instances'))>60;
console.log(ok ? '\nPASS' : '\nFAIL');
process.exit(ok?0:1);
