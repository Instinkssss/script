// Uji UI.lua: build(API) harus jalan tanpa error dan mengembalikan tabel UI.
const fs=require('fs');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const h=fs.readFileSync(__dirname+'/harness.js','utf8');
let pre=h.split('const PRELUDE = `')[1].split('`;')[0];

// Mock Instance.new + parenting supaya UI bisa dibangun
pre += `
-- Instance.new sudah ada; tambah pencatatan objek UI
UI_COUNT = 0
local realInst = Instance.new
Instance.new = function(cls)
  UI_COUNT = UI_COUNT + 1
  local o = inst(cls, cls)
  return o
end
-- PlayerGui.WaitForChild harus mengembalikan sesuatu yang bisa jadi Parent
local LP2 = game:GetService("Players").LocalPlayer
LP2.PlayerGui = LP2:FindFirstChildOfClass("PlayerGui") or inst("PlayerGui","PlayerGui")
function __getPG() return LP2.PlayerGui end
`;
if(lauxlib.luaL_dostring(L,to_luastring(pre))!==lua.LUA_OK){console.error('PRELUDE:',lua.lua_tojsstring(L,-1));process.exit(1);}

const driver=`
local API = { status=function() return {running=false, broken=0, collected=0, currentTarget="-", idleStrikes=0} end,
              toggle=function() end, start=function() end, stop=function() end,
              reset=function() end, destroy=function() end }
local UI = dofile("UI.lua")
local ok, err = pcall(function() return UI.build(API) end)
if not ok then RESULT_UI = { ok=false, err=tostring(err) } else
  RESULT_UI = { ok=true, count=UI_COUNT }
end
`;
// UI.lua berakhir dengan `return UI`, jadi harus dibungkus fungsi agar bisa disambung
let uisrc=fs.readFileSync(__dirname+'/../UI.lua','utf8');
let src = "local function __loadUI()\n" + uisrc + "\nend\nlocal UI = __loadUI()\n"
        + driver.replace('local UI = dofile("UI.lua")','');
if(lauxlib.luaL_dostring(L,to_luastring(src))!==lua.LUA_OK){
  console.error('UI LOAD ERROR:\n'+lua.lua_tojsstring(L,-1));process.exit(1);
}
lua.lua_getglobal(L,to_luastring('RESULT_UI'));
lua.lua_getfield(L,-1,to_luastring('ok'));
const okv=lua.lua_toboolean(L,-1); lua.lua_pop(L,1);
lua.lua_getfield(L,-1,to_luastring('err'));
const errv=lua.lua_tojsstring(L,-1); lua.lua_pop(L,1);
lua.lua_getfield(L,-1,to_luastring('count'));
const cnt=lua.lua_tonumber(L,-1);
console.log('\n=== UI BUILD ===');
console.log('ok =', okv, '| err =', errv, '| objek Instance dibuat =', cnt);
console.log(okv ? '\nALL PASS' : '\nFAILED');
process.exit(okv?0:1);
