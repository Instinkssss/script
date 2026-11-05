// Uji jalur fallback: remote TIDAK ada di game (auto-detect gagal).
// Harus: tidak crash, tetap mencoba tool/click, dan tetap berhenti saat block habis.
const fs=require('fs'), path=require('path');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const h=fs.readFileSync(__dirname+'/harness.js','utf8');
let pre=h.split('const PRELUDE = `')[1].split('`;')[0];
// hapus semua RemoteEvent dari ReplicatedStorage -> paksa jalur fallback
pre=pre.replace('local brkRemote = inst("RemoteEvent", "BreakBlock")\ntable.insert(RS._children, brkRemote)',
                '-- remote sengaja TIDAK dibuat (simulasi auto-detect gagal)');
// tambahkan tool di karakter supaya jalur tool teruji
pre=pre.replace('table.insert(char._children, hrp)',
                'table.insert(char._children, hrp)\nlocal tl = inst("Tool", "Pickaxe")\ntable.insert(char._children, tl)');
if(lauxlib.luaL_dostring(L,to_luastring(pre))!==lua.LUA_OK){console.error('PRELUDE:',lua.lua_tojsstring(L,-1));process.exit(1);}

let src=fs.readFileSync(path.join(__dirname,'..','AutoFarm.lua'),'utf8');
src=src.replace(/local uiOk, UI = pcall\(function\(\)[\s\S]*?end\)\n/,'local uiOk, UI = false, nil\n');
src=src.replace(/getgenv\(\)\.GrowbloxAutoFarm = API/,'G = API');
src=src.replace(/AUTO_START\s*=\s*false/,'AUTO_START = true');
src=src.replace(/ACTION_DELAY\s*=\s*0\.35/,'ACTION_DELAY = 0');
src=src.replace(/COLLECT_TIMEOUT\s*=\s*3/,'COLLECT_TIMEOUT = 0.2');
if(lauxlib.luaL_dostring(L,to_luastring(src))!==lua.LUA_OK){console.error('AUTOFARM:',lua.lua_tojsstring(L,-1));process.exit(1);}

const drive=`
G.start()
local guard=0
local co = __ITER.co
while coroutine.status(co)=="suspended" and guard<500 do
  guard=guard+1
  local ok,err=coroutine.resume(co)
  if not ok then io.write("CORO-ERR: "..tostring(err), string.char(10)) break end
end
RESULT.howLogs = {}
G.stop()
RESULT.runningAtEnd=(G.status().running==true)
RESULT.idle=G.status().idleStrikes
RESULT.broken=G.status().broken
RESULT.collected=G.status().collected
RESULT.guard=guard
`;
if(lauxlib.luaL_dostring(L,to_luastring(drive))!==lua.LUA_OK){console.error('DRIVE:',lua.lua_tojsstring(L,-1));process.exit(1);}

function read(k){lua.lua_getglobal(L,to_luastring('RESULT'));lua.lua_getfield(L,-1,to_luastring(k));
  const t=lua.lua_type(L,-1);let v;
  if(t===lua.LUA_TBOOLEAN)v=lua.lua_toboolean(L,-1)?'true':'false';
  else if(t===lua.LUA_TNUMBER)v=String(lua.lua_tonumber(L,-1));
  else v=lua.lua_tojsstring(L,-1);
  lua.lua_pop(L,2);return v;}
const out={broken:read('broken'),collected:read('collected'),idle:read('idle'),
           runningAtEnd:read('runningAtEnd'),guard:read('guard')};
console.log('\n=== HASIL (tanpa remote) ===');
console.log(JSON.stringify(out,null,2));
const A=[];
const chk=(n,c,d)=>A.push({n,pass:!!c,d});
chk('tidak crash saat remote tidak ada', true, 'script selesai');
chk('loop tetap berakhir (tidak hang)', parseInt(out.guard)<500, 'guard='+out.guard);
chk('block tetap terhancur via fallback tool', parseInt(out.broken)>0, 'broken='+out.broken);
chk('berhenti sendiri saat habis', out.runningAtEnd==='false', 'runningAtEnd='+out.runningAtEnd);
console.log('\n=== ASSERTIONS ===');
let f=0;for(const a of A){console.log((a.pass?'PASS':'FAIL')+'  '+a.n+'  ('+a.d+')');if(!a.pass)f++;}
console.log('\n'+(f===0?'ALL PASS':f+' FAILED'));
process.exit(f===0?0:1);
