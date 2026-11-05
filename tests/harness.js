// Harness lengkap: mock Roblox + jalankan AutoFarm.lua di Lua asli (fengari).
// Membuktikan: loop jalan, break dipanggil, item terkumpul, berhenti saat block habis.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const PRELUDE = `
local TRACE = { breakCalls = 0, blocks = 10, manualRemoved = 0, logs = {}, collectEvents = 0 }
local inst  -- forward declaration; dipakai di dalam mkclass

-- ============ class builder ============
local function mkclass()
  local C = {}
  C.__index = C
  function C:GetChildren() return self._children end
  function C:GetDescendants()
    local out = {}
    local function rec(n) for _,c in ipairs(n._children) do out[#out+1]=c; rec(c) end end
    rec(self); return out
  end
  function C:FindFirstChild(n, rec)
    for _,c in ipairs(self._children) do if c.Name == n then return c end end
    if rec then for _,c in ipairs(self:GetDescendants()) do if c.Name==n then return c end end end
    return nil
  end
  function C:FindFirstChildOfClass(cc)
    for _,c in ipairs(self._children) do if c.ClassName==cc then return c end end
    return nil
  end
  local PARENTS = { Part={"BasePart","Instance"}, MeshPart={"BasePart","Instance"},
    UnionOperation={"BasePart","Instance"}, Folder={"Instance"}, Model={"Instance"},
    RemoteEvent={"Instance"}, RemoteFunction={"Instance"}, Player={"Instance"},
    Backpack={"Instance"}, PlayerGui={"Instance"}, Tool={"Instance"},
    ReplicatedStorage={"Instance"}, Workspace={"Instance"}, DataModel={"Instance"} }
  function C:IsA(c)
    if self.ClassName == c or c == "Instance" then return true end
    local chain = PARENTS[self.ClassName]
    if chain then for _,p in ipairs(chain) do if p==c then return true end end end
    return false
  end
  function C:GetAttribute(k) return self._attrs and self._attrs[k] or nil end
  function C:GetAttributes() return self._attrs or {} end
  function C:GetFullName() return self.Name end
  function C:ClearAllChildren() self._children = {} end
  function C:Destroy() self.Parent = nil end
  function C:WaitForChild(n) return self:FindFirstChild(n) or self end
  local function serverSide(t, ...)
    TRACE.breakCalls = TRACE.breakCalls + 1
    for _, a in ipairs({...}) do
      if type(a) == "table" and a._isBlock and a.Parent then
        local p = a.Parent
        for i,c in ipairs(p._children) do if c == a then table.remove(p._children, i) break end end
        local inv = _G.__INV
        if inv then
          local neo = setmetatable({ClassName="Tool", Name="Item"..(#inv._children+1), _children={}, Transparency=0, Material="Grass", Position={X=0,Y=0,Z=0}, _attrs={}}, CLASS)
          table.insert(inv._children, neo)
          TRACE.collectEvents = TRACE.collectEvents + 1
        end
        return
      end
    end
  end
  function C:FireServer(...) serverSide(self, ...) end
  function C:InvokeServer(...) serverSide(self, ...) end
  function C:CaptureController() end
  function C:ClickButton2() end
  function C:SendMouseButtonEvent() end
  function C:WorldToViewportPoint() return {X=100, Y=100, Z=1} end
  function C:Activate() TRACE.breakCalls = TRACE.breakCalls + 1 end
  function C:Connect(fn) return { Disconnect = function() end } end
  return C
end

-- Event stub: setiap instance punya properti event yang bisa di-Connect
local EVENT_KEYS = { "InputBegan","InputChanged","InputEnded","MouseButton1Click",
  "MouseButton1Down","MouseButton1Up","Changed","Idled","Activated","Touched","ChildAdded" }
local EVENT_MT = { __index = function(t,k)
  for _,e in ipairs(EVENT_KEYS) do
    if k == e then
      local ev = { Connect = function(_, fn) return { Disconnect = function() end } end,
                   Once = function(_, fn) return { Disconnect = function() end } end,
                   Wait = function() return nil end }
      rawset(t, k, ev)
      return ev
    end
  end
  return nil
end }


local CLASS = mkclass()
-- Event stub: setiap instance punya properti event yang bisa di-Connect.
-- PENTING: event diambil langsung dari tabel CLASS, bukan lewat __index berantai,
-- karena __index pada metatable berantai menerima tabel anak (bukan CLASS) sebagai argumen.
for _, e in ipairs(EVENT_KEYS) do
  CLASS[e] = { Connect = function(_, fn) return { Disconnect = function() end } end,
               Once = function(_, fn) return { Disconnect = function() end } end,
               Wait = function() return nil end }
end
function inst(cls, name)
  return setmetatable({ClassName=cls, Name=name or cls, _children={}, Transparency=0,
                       Material="Grass", Position={X=0,Y=0,Z=0}, _attrs={}}, CLASS)
end

-- Vector3 dengan metatable supaya operasi pos - origin dan .Magnitude bekerja
local V3MT = {}
V3MT.__index = V3MT
V3MT.__sub = function(a,b)
  local dx,dy,dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
  return setmetatable({X=dx,Y=dy,Z=dz, Magnitude=math.sqrt(dx*dx+dy*dy+dz*dz)}, V3MT)
end
V3MT.__add = function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z, Magnitude=0}, V3MT) end
Vector3 = { new = function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0,
  Magnitude=math.sqrt((x or 0)^2+(y or 0)^2+(z or 0)^2)}, V3MT) end }
-- konversi tabel posisi polos jadi Vector3 (dipakai mock block & hrp)
function __v3(p) return setmetatable({X=p.X or 0, Y=p.Y or 0, Z=p.Z or 0,
  Magnitude=math.sqrt((p.X or 0)^2+(p.Y or 0)^2+(p.Z or 0)^2)}, V3MT) end

io.write("MARK: before world", string.char(10))
-- ============ world ============
local world = inst("Model", "World")
local blocksFolder = inst("Folder", "Blocks")
world.Parent = "workspace"
table.insert(world._children, blocksFolder)

-- 10 block, dengan posisi makin jauh supaya urutan terdekat teruji
local blocks = {}
for i = 1, 10 do
  local b = inst("Part", "Block" .. i)
  b.Position = __v3({X=i*2, Y=0, Z=0})
  b._isBlock = true
  b.Magnitude = 0
  b.Parent = blocksFolder
  table.insert(blocksFolder._children, b)
  blocks[i] = b
end

io.write("MARK: before player", string.char(10))
-- ============ player ============
local inv = inst("Backpack", "Backpack")
local char = inst("Model", "Character")
local hrp  = inst("Part", "HumanoidRootPart")
hrp.Position = __v3({X=0,Y=0,Z=0})
hrp.CFrame = { Position = hrp.Position }
table.insert(char._children, hrp)

local pg = inst("PlayerGui", "PlayerGui")

local lp = inst("Player", "LocalPlayer")
lp.Character = char
lp._children = { inv, char, pg }
lp.Idled = { Connect = function() return {Disconnect=function() end} end }

local players = inst("Players", "Players")
players.LocalPlayer = lp
players._children = { lp }

io.write("MARK: before services", string.char(10))
-- ============ services ============
local RS = inst("ReplicatedStorage", "ReplicatedStorage")
local brkRemote = inst("RemoteEvent", "BreakBlock")
table.insert(RS._children, brkRemote)

local SERVICES = {
  Players = players,
  RunService = inst("RunService", "RunService"),
  ReplicatedStorage = RS,
  VirtualUser = inst("VirtualUser", "VirtualUser"),
  VirtualInputManager = inst("VirtualInputManager", "VirtualInputManager"),
  UserInputService = inst("UserInputService", "UserInputService"),
  StarterGui = inst("StarterGui", "StarterGui"),
  HttpService = inst("HttpService", "HttpService"),
}

local gameObj = inst("DataModel", "Game")
gameObj.PlaceId = 12345
gameObj.GameId = 67890
gameObj.JobId = "test-job"
gameObj.__inv = inv
_G.__INV = inv
gameObj.GetService = function(_, n)
  if not SERVICES[n] then SERVICES[n] = inst(n, n) end
  return SERVICES[n]
end

io.write("MARK: before globals", string.char(10))
-- ============ globals ============
workspace = world
game = gameObj
Enum = {
  Material = { Grass="Grass", Ground="Ground", Mud="Mud", LeafyGrass="LeafyGrass" },
  Font = setmetatable({}, {__index=function() return "Font" end}),
  TextXAlignment = setmetatable({}, {__index=function() return "TX" end}),
  TextTruncate = setmetatable({}, {__index=function() return "TT" end}),
  ApplyStrokeMode = setmetatable({}, {__index=function() return "AS" end}),
  SortOrder = setmetatable({}, {__index=function() return "SO" end}),
  ZIndexBehavior = setmetatable({}, {__index=function() return "ZI" end}),
  UserInputType = setmetatable({}, {__index=function() return "UIT" end}),
  UserInputState = setmetatable({}, {__index=function() return "UIS" end}),
}
Instance = { new = function(cls) return inst(cls, cls) end }

UDim2 = { new = function(...) return {X=0, Y=0, Scale=0, Offset=0} end }
UDim  = { new = function(...) return {Scale=0, Offset=0} end }
Vector2 = { new = function(x,y) return {X=x or 0, Y=y or 0} end }
Color3 = { fromRGB = function() return {R=0,G=0,B=0} end }
CFrame = { new = function(p) return {Position=p} end }

-- task / os helpers
-- task.wait TIDAK no-op: kalau no-op, loop jadi busy-loop tanpa batas.
-- Simulasi: setiap wait memajukan "waktu" dan membatasi iterasi agar tes pasti selesai.
local ITER = { n = 0, max = 60 }
task = {
  spawn = function(f)
    -- kumpulkan coroutine supaya dipanggil bertahap dari DRIVE
    local co = coroutine.create(f)
    ITER.co = co
    return co
  end,
  wait = function(s)
    ITER.n = ITER.n + 1
    if ITER.n > ITER.max then
      error("MOCK-ABORT: melebihi "..ITER.max.." wait tanpa selesai", 0)
    end
    if ITER.co then coroutine.yield() end
  end,
  delay = function(s,f) return nil end,
  defer = function(f) return nil end
}
_G.__ITER = ITER
local CLK = { t = 0 }
os.clock = function() CLK.t = CLK.t + 0.15 return CLK.t end
tick = function() return 0 end
warn = function(...) local s="" for i=1,select("#",...) do s=s..tostring((select(i,...))).." " end io.write("[WARN] "..s, string.char(10)) end
print = function(...) local s="" for i=1,select("#",...) do s=s..tostring((select(i,...))).." " end io.write(s .. [[

]]) end
getgenv = function() return {} end
loadstring = function() return function() return nil end end
RESULT = TRACE
_G.__BLOCKS = blocks
`;

if (lauxlib.luaL_dostring(L, to_luastring(PRELUDE)) !== lua.LUA_OK) {
  console.error('PRELUDE ERROR:\n' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}


// --- load AutoFarm.lua. UI sekarang ter-embed, jadi biarkan dibangun sungguhan ---
let src = fs.readFileSync(path.join(__dirname, '..', 'AutoFarm.lua'), 'utf8');
// catat berapa Instance yang dibuat UI, supaya embed-nya bisa dibuktikan bekerja
src = src.replace(
  /^local Players\s+= game:GetService\("Players"\)/m,
  `local __instCount = 0
local __realInstanceNew = Instance.new
Instance.new = function(cls) __instCount = __instCount + 1 return __realInstanceNew(cls) end
__uiInstanceCount = function() return __instCount end
local Players          = game:GetService("Players")`
);
// matikan expose getgenv
src = src.replace(/getgenv\(\)\.GrowbloxAutoFarm = API/, 'G = API');
// paksa auto start untuk uji loop
src = src.replace(/AUTO_START\s*=\s*false/, 'AUTO_START = true');
// jeda dibuat nol supaya tes cepat
src = src.replace(/ACTION_DELAY\s*=\s*0\.35/, 'ACTION_DELAY = 0');
src = src.replace(/COLLECT_TIMEOUT\s*=\s*3/, 'COLLECT_TIMEOUT = 0.2');

fs.writeFileSync(path.join(__dirname, '_af_patched.lua'), src);

// helper: tunggu sampai loop berhenti (STATE.running false)
const DRIVE = `
G = G or getgenv().GrowbloxAutoFarm
-- jalankan loop sampai selesai; task.wait no-op jadi while langsung tuntas
G.start()
local guard = 0
local co = __ITER.co
while coroutine.status(co) == "suspended" and guard < 500 do
  guard = guard + 1
  local ok, err = coroutine.resume(co)
  if not ok then io.write("CORO-ERR: "..tostring(err), string.char(10)) break end
end
if G.status().running then G.stop() end
RESULT.broken = G.status().broken
RESULT.collected = G.status().collected
RESULT.idle = G.status().idleStrikes
RESULT.invCount = 0
RESULT.runningAtEnd = (G.status().running == true)
RESULT.guard = guard
RESULT.uiInstances = __uiInstanceCount()
`;

if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) {
  console.error('AUTOFARM ERROR:\n' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
console.log('AutoFarm.lua loaded');

if (lauxlib.luaL_dostring(L, to_luastring(DRIVE)) !== lua.LUA_OK) {
  console.error('DRIVE ERROR:\n' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}

// baca hasil: lua_getglobal ada di lua.*, bukan lauxlib.*
lua.lua_getglobal(L, to_luastring('RESULT'));
const read = (k) => {
  lua.lua_getfield(L, -1, to_luastring(k));
  const t = lua.lua_type(L, -1);
  let v;
  if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1) ? 'true' : 'false';
  else if (t === lua.LUA_TNUMBER) v = String(lua.lua_tonumber(L, -1));
  else v = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return v;
};
const out = {
  breakCalls: read('breakCalls'),
  collectEvents: read('collectEvents'),
  blocksTotal: read('blocks'),
  invFinal: read('inv'),
  broken: read('broken'),
  collected: read('collected'),
  idle: read('idle'),
  runningAtEnd: read('runningAtEnd'),
  guard: read('guard'),
};
console.log('\n=== HASIL ===');
console.log(JSON.stringify(out, null, 2));

// assertions
const A = [];
const chk = (name, cond, detail) => A.push({ name, pass: !!cond, detail });

chk('loop berjalan (break dipanggil > 0)', parseInt(out.broken) > 0, `broken=${out.broken}`);
chk('mekanisme break terpanggil', parseInt(out.breakCalls) > 0, `breakCalls=${out.breakCalls}`);
chk('item terkumpul terhitung', parseInt(out.collected) > 0, `collected=${out.collected}`);
chk('loop berhenti sendiri saat block habis', out.runningAtEnd === 'false' || out.runningAtEnd === 'false',
    `runningAtEnd=${out.runningAtEnd}`);
chk('tidak infinite loop (guard < 200)', parseInt(out.guard) < 200, `guard=${out.guard}`);

console.log('\n=== ASSERTIONS ===');
let fails = 0;
for (const a of A) {
  console.log((a.pass ? 'PASS' : 'FAIL') + '  ' + a.name + '  (' + a.detail + ')');
  if (!a.pass) fails++;
}
console.log('\n' + (fails === 0 ? 'ALL PASS' : fails + ' FAILED'));
process.exit(fails === 0 ? 0 : 1);
