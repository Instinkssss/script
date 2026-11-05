--[[
    Growblox Auto Farm
    Untuk Delta Executor (Android / iOS / PC)

    Alur:
      1. Cari block terdekat di sekitar player
      2. Teleport/pindah ke block itu
      3. Break block (remote + fallback tool activation)
      4. Tunggu item masuk ke Backpack/Inventory
      5. Ulangi sampai tidak ada block lagi
      6. Stop sendiri / idle

    CATATAN PENTING
    ----------------
    Script ini TIDAK mengarang nama RemoteEvent milik Growblox.
    Bagian yang menyentuh server dipisah ke CONFIG.REMOTES dan CONFIG.BLOCK_DETECT.
    Jalankan dulu bagian "MODE DISCOVERY" di bawah supaya script bisa
    menebak nama remote/block secara otomatis dari isi game.
]]

--=====================================================================
-- [1] KONFIGURASI
--=====================================================================

local CONFIG = {
    -- Jarak maksimal block yang mau di-farm (stud)
    MAX_DISTANCE       = 60,
    -- Jeda antar aksi (detik). Naikkan kalau kena kick anti-cheat.
    ACTION_DELAY       = 0.35,
    -- Berapa lama tunggu item muncul di inventory sebelum dianggap gagal
    COLLECT_TIMEOUT    = 3,
    -- Auto teleport ke block sebelum break
    TELEPORT_TO_BLOCK  = true,
    -- Aktifkan anti-AFK (biar tidak kena kick idle 20 menit)
    ANTI_AFK           = true,
    -- Auto farm langsung jalan saat script diload
    AUTO_START         = false,
    -- Anggap SEMUA Part di dalam BLOCK_CONTAINERS sebagai block.
    -- Set true kalau nama block di game generik (mis. "Part", "1", "2") dan
    -- keyword/material di atas tidak menangkapnya. Risiko: Part dekoratif ikut kena.
    ACCEPT_ANY_PART_IN_CONTAINER = true,
    -- Berhenti otomatis kalau tidak ada block terdeteksi N kali berturut-turut
    IDLE_STRIKES_MAX   = 5,

    -- Nama RemoteEvent / RemoteFunction.
    -- KOSONGKAN kalau tidak tahu -> script akan coba auto-detect.
    -- Isi manual kalau auto-detect gagal. Contoh format:
    --   REMOTES = { break = "BreakBlock", collect = "CollectItem" }
    -- CATATAN: key "break" ditulis ["break"] karena `break` itu reserved word di Lua.
    REMOTES = {
        ["break"] = nil,   -- remote untuk menghancurkan block
        collect   = nil,   -- remote untuk ambil item (kalau ada)
        hit       = nil,   -- remote damage berulang (kalau break butuh multi-hit)
    },

    -- Cara mendeteksi block.
    -- Block dicari sebagai BasePart di dalam folder-folder ini.
    BLOCK_CONTAINERS = {
        "Blocks", "World", "Tiles", "Map", "GameObjects",
        "Plot", "Fields", "Farms", "Crops",
    },

    -- Nama/atribut yang menandakan sebuah part adalah block yang bisa di-break.
    -- Dicek case-insensitive terhadap Name dan ClassName.
    BLOCK_KEYWORDS = {
        "block", "tile", "seed", "crop", "plant", "tree", "ore", "rock", "dirt",
    },
}

--=====================================================================
-- [2] SERVICE & UTIL
--=====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local VirtualUser      = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local HttpService      = game:GetService("HttpService")

local LP = Players.LocalPlayer

local STATE = {
    running      = false,
    idleStrikes  = 0,
    broken       = 0,
    collected    = 0,
    lastError    = "-",
    currentTarget= "-",
    ui           = nil,
    conns        = {},
    thread       = nil,
}

-- lower-case helper
local function lc(s) return string.lower(tostring(s)) end

-- cek apakah sebuah objek cocok dengan BLOCK_KEYWORDS
-- Menerima BasePart langsung maupun Model yang isinya BasePart (banyak game
-- Growtopia-like menyimpan block sebagai Model, bukan Part telanjang).
local PART_CLASSES = { "BasePart", "Part", "MeshPart", "UnionOperation", "TrussPart", "WedgePart" }

local function isPartLike(obj)
    if not obj or type(obj.IsA) ~= "function" then return false end
    for _, cls in ipairs(PART_CLASSES) do
        local ok, res = pcall(function() return obj:IsA(cls) end)
        if ok and res then return true end
    end
    return false
end

local function looksLikeBlock(obj)
    if not isPartLike(obj) then return false end
    local name = lc(obj.Name)
    local cls  = lc(obj.ClassName)
    for _, kw in ipairs(CONFIG.BLOCK_KEYWORDS) do
        if string.find(name, kw, 1, true) or string.find(cls, kw, 1, true) then
            return true
        end
    end
    -- block sering ditandai lewat atribut / material tanah
    local okA, atr = pcall(function() return obj:GetAttribute("Breakable") or obj:GetAttribute("IsBlock") end)
    if okA and atr then return true end
    local mat = obj.Material
    if mat == Enum.Material.Grass or mat == Enum.Material.Ground
       or mat == Enum.Material.Mud or mat == Enum.Material.LeafyGrass then
        return true
    end
    -- fallback: Part di dalam container block tetap dianggap block meski namanya generik
    if CONFIG.ACCEPT_ANY_PART_IN_CONTAINER then return true end
    return false
end

-- cari semua container block yang ada
local function getContainers()
    local found = {}
    local function scan(root)
        for _, child in ipairs(root:GetChildren()) do
            for _, want in ipairs(CONFIG.BLOCK_CONTAINERS) do
                if lc(child.Name) == lc(want) then
                    table.insert(found, child)
                end
            end
        end
    end
    scan(workspace)
    scan(ReplicatedStorage)
    -- kalau tidak ketemu container bernama, pakai workspace langsung
    if #found == 0 then
        table.insert(found, workspace)
    end
    return found
end

-- cari block terdekat dari posisi player
local function findNearestBlock()
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local origin = root.Position

    local best, bestDist = nil, CONFIG.MAX_DISTANCE
    for _, container in ipairs(getContainers()) do
        for _, obj in ipairs(container:GetDescendants()) do
            if looksLikeBlock(obj) and obj.Transparency < 1 then
                local ok, pos = pcall(function() return obj.Position end)
                if ok and pos then
                    local d = (pos - origin).Magnitude
                    if d < bestDist then
                        best, bestDist = obj, d
                    end
                end
            end
        end
    end
    return best, bestDist
end

--=====================================================================
-- [3] REMOTE RESOLVER
--=====================================================================

-- Cari remote berdasarkan nama yang diberikan, atau tebak dari kata kunci.
local function resolveRemote(kind)
    local manual = CONFIG.REMOTES[kind]
    if manual then
        local obj = ReplicatedStorage:FindFirstChild(manual, true)
        if obj then return obj end
    end

    local patterns = {
        ["break"] = { "break", "destroy", "dig", "mine", "harvest", "punch", "hitblock" },
        collect   = { "collect", "pickup", "grab", "takeitem", "claim" },
        hit       = { "hit", "damage", "attack", "swing" },
    }
    local words = patterns[kind] or {}

    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local n = lc(obj.Name)
            for _, w in ipairs(words) do
                if string.find(n, w, 1, true) then
                    return obj
                end
            end
        end
    end
    return nil
end

--=====================================================================
-- [4] AKSI INTI
--=====================================================================

-- Teleport karakter ke dekat block
local function moveToBlock(block)
    if not CONFIG.TELEPORT_TO_BLOCK then return true end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local ok = pcall(function()
        local target = block.Position + Vector3.new(0, 3, 0)
        root.CFrame = CFrame.new(target)
    end)
    return ok
end

-- Break satu block. Coba remote dulu, lalu fallback ke tool/click.
local function breakBlock(block)
    -- 1) lewat RemoteEvent
    local remote = resolveRemote("break")
    if remote then
        local payloads = {
            { block },
            { block.Position },
            { block.Name },
            { block, block.Position },
        }
        for _, args in ipairs(payloads) do
            local ok = pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer(table.unpack(args))
                else
                    remote:InvokeServer(table.unpack(args))
                end
            end)
            if ok then return true, "remote:" .. remote.Name end
        end
    end

    -- 2) fallback: aktifkan tool di tangan (banyak game Growtopia-like pakai tool)
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
        return true, "tool:" .. tool.Name
    end

    -- 3) fallback terakhir: klik di posisi block
    local cam = workspace.CurrentCamera
    if cam then
        local ok, screenPos = pcall(function()
            return cam:WorldToViewportPoint(block.Position)
        end)
        if ok then
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, true, game, 1)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, false, game, 1)
            end)
            return true, "click"
        end
    end

    return false, "no-remote-no-tool"
end

-- Hitung isi inventory (Backpack + semua container di Character + PlayerGui yang mungkin)
local function countInventory()
    local total = 0
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then total = total + #bp:GetChildren() end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then total = total + #pg:GetChildren() end
    return total
end

-- Tunggu sampai jumlah inventory naik (artinya item berhasil dikumpulkan)
-- Dibatasi ganda: waktu (os.clock) DAN jumlah iterasi. Kalau executor men-stub
-- os.clock jadi konstan, batas iterasi tetap menyelamatkan dari hang.
local function waitForCollect(before, timeout)
    local maxTicks = math.max(1, math.floor(timeout / 0.1)) + 5
    local ticks = 0
    local deadline = os.clock() + timeout
    while ticks < maxTicks do
        ticks = ticks + 1
        if countInventory() > before then
            return true, countInventory() - before
        end
        if os.clock() >= deadline then break end
        task.wait(0.1)
    end
    return false, 0
end

--=====================================================================
-- [5] LOOP UTAMA
--=====================================================================

local function log(msg)
    STATE.lastError = msg
    if STATE.ui and STATE.ui.log then
        STATE.ui.log(msg)
    end
end

local function farmLoop()
    log("Auto farm dimulai")
    STATE.idleStrikes = 0

    while STATE.running do
        local block, dist = findNearestBlock()

        if not block then
            STATE.idleStrikes = STATE.idleStrikes + 1
            STATE.currentTarget = "-"
            log(("Tidak ada block (%d/%d)"):format(STATE.idleStrikes, CONFIG.IDLE_STRIKES_MAX))
            if STATE.idleStrikes >= CONFIG.IDLE_STRIKES_MAX then
                log("Semua block habis. Auto farm berhenti.")
                STATE.running = false
                if STATE.ui then STATE.ui.refresh() end
                break
            end
            task.wait(1)
        else
            STATE.idleStrikes = 0
            STATE.currentTarget = block.Name
            if STATE.ui then STATE.ui.refresh() end

            moveToBlock(block)
            task.wait(CONFIG.ACTION_DELAY)

            local before = countInventory()
            local ok, how = breakBlock(block)

            if ok then
                STATE.broken = STATE.broken + 1
            else
                log("Break gagal: " .. tostring(how))
            end

            task.wait(CONFIG.ACTION_DELAY)

            local got, amount = waitForCollect(before, CONFIG.COLLECT_TIMEOUT)
            if got then
                STATE.collected = STATE.collected + amount
                log(("Kumpul %d item dari %s"):format(amount, block.Name))
            end

            if STATE.ui then STATE.ui.refresh() end

            task.wait(CONFIG.ACTION_DELAY)
        end
    end

    log("Loop selesai")
    if STATE.ui then STATE.ui.refresh() end
end

--=====================================================================
-- [6] PUBLIC API
--=====================================================================

local API = {}

function API.start()
    if STATE.running then return end
    STATE.running = true
    STATE.idleStrikes = 0
    STATE.thread = task.spawn(farmLoop)
    if STATE.ui then STATE.ui.refresh() end
end

function API.stop()
    STATE.running = false
    if STATE.ui then STATE.ui.refresh() end
end

function API.toggle()
    if STATE.running then API.stop() else API.start() end
end

function API.reset()
    STATE.broken, STATE.collected, STATE.idleStrikes = 0, 0, 0
    if STATE.ui then STATE.ui.refresh() end
end

function API.status()
    return STATE
end

function API.destroy()
    API.stop()
    for _, c in ipairs(STATE.conns) do pcall(function() c:Disconnect() end) end
    if STATE.ui and STATE.ui.destroy then STATE.ui.destroy() end
end

--=====================================================================
-- [7] ANTI AFK
--=====================================================================

if CONFIG.ANTI_AFK then
    table.insert(STATE.conns, LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end

--=====================================================================
-- [8] LOAD UI + START
--=====================================================================

local uiOk, UI = pcall(function()
    return loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/USERNAME/REPO/main/UI.lua"
    ))()
end)

if uiOk and type(UI) == "table" then
    STATE.ui = UI.build(API)
else
    warn("[Growblox AutoFarm] UI gagal dimuat, jalan tanpa UI.")
end

if CONFIG.AUTO_START then
    API.start()
end

-- expose ke executor supaya bisa dikontrol manual dari console
getgenv().GrowbloxAutoFarm = API
print("[Growblox AutoFarm] Loaded. Gunakan getgenv().GrowbloxAutoFarm untuk kontrol.")
