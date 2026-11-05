// jalankan prelude + diag.lua untuk melihat kenapa block tidak terdeteksi
const fs=require('fs');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
// ambil prelude dari harness.js (sampai penanda akhir)
const h=fs.readFileSync(__dirname+'/harness.js','utf8');
const pre=h.split('const PRELUDE = `')[1].split('`;')[0];
if(lauxlib.luaL_dostring(L,to_luastring(pre))!==lua.LUA_OK){console.error('PRELUDE:',lua.lua_tojsstring(L,-1));process.exit(1);}
const diag=fs.readFileSync('diag.lua','utf8');
if(lauxlib.luaL_dostring(L,to_luastring(diag))!==lua.LUA_OK){console.error('DIAG:',lua.lua_tojsstring(L,-1));process.exit(1);}
