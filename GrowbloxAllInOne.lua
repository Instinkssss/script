--[[
    ============================================================
      GROWBOX ALL-IN-ONE  --  Scout + Auto Farm + UI
      Untuk Delta Executor (Android / iOS / PC)
    ============================================================

    SATU FILE, SATU LOADSTRING. Tidak perlu file lain.

    Yang terjadi saat script dimuat:
      1. SCOUT otomatis jalan -> mengumpulkan nama RemoteEvent,
         struktur block, inventory, tool, dan grid dari game.
      2. Hasil scout ditampilkan di console + tersimpan ke
         growblox_scout.txt (kalau executor mendukung writefile).
      3. Nama remote hasil scout dipakai OTOMATIS kalau cocok.
      4. UI muncul, siap dipakai.

    Tombol di UI:
      Farm          - START/STOP loop auto farm
      AutoDF        - auto ambil item yang jatuh
      Break Kiri    - sapu block ke arah kiri
      Break Kanan   - sapu block ke arah kanan
      Break 3 Arah  - hancurkan cluster radius 8 stud sekaligus
      Plant         - tanam ulang setelah break
      Auto Trash    - buang item sampah saat inventory penuh
      SCOUT         - jalankan ulang scout kapan saja

    CATATAN
    -------
    Script ini TIDAK mengarang nama RemoteEvent Growblox. Nama remote
    diambil dari hasil scout (auto-detect dari kata kunci). Kalau
    auto-detect meleset, isi CONFIG.REMOTES manual pakai hasil scout.
]]

--=====================================================================
-- [1] KONFIGURASI
--=====================================================================

local CONFIG = {
    -- Jarak maksimal block yang mau di-farm (stud)
    MAX_DISTANCE       = 300,
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
    -- Berapa kali satu block boleh gagal dihancurkan sebelum dilewati.
    MAX_BLOCK_FAILS    = 3,

    -- Parameter mode sapuan (adaptasi dari break3way/place3way di script DF)
    THREE_WAY_RADIUS   = 8,    -- radius cluster saat mode "Break 3 Arah" aktif
    THREE_WAY_LIMIT    = 12,   -- maksimum block per cluster (jaga agar tidak spam)
    SWEEP_LENGTH       = 6,    -- berapa block yang disapu ke satu arah
    TRASH_THRESHOLD    = 25,   -- buang item sampah kalau isi inventory >= ini
    JUNK_KEYWORDS      = { "dirt", "soil", "rock", "stone", "grass", "leaf", "leaves" },

    -- Nama RemoteEvent / RemoteFunction.
    -- KOSONGKAN kalau tidak tahu -> script akan coba auto-detect.
    -- Isi manual kalau auto-detect gagal. Contoh format:
    --   REMOTES = { break = "BreakBlock", collect = "CollectItem" }
    -- CATATAN: key "break" ditulis ["break"] karena `break` itu reserved word di Lua.
    REMOTES = {
        ["break"] = nil,   -- remote untuk menghancurkan block
        collect   = nil,   -- remote untuk ambil item (kalau ada)
        hit       = nil,   -- remote damage berulang (kalau break butuh multi-hit)
        place     = nil,   -- remote untuk menanam / menaruh block
        trash     = nil,   -- remote untuk membuang item sampah
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
    -- mode yang dikendalikan UI (adaptasi dari script DF)
    modes        = {},
    autoCollect  = true,
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

    STATE.failed = STATE.failed or {}
    local best, bestDist = nil, CONFIG.MAX_DISTANCE
    for _, container in ipairs(getContainers()) do
        for _, obj in ipairs(container:GetDescendants()) do
            if looksLikeBlock(obj) and obj.Transparency < 1 then
                -- lewati block yang sudah beberapa kali gagal dihancurkan,
                -- supaya loop tidak terjebak memilih target yang sama
                local fails = STATE.failed[obj]
                if not fails or fails < CONFIG.MAX_BLOCK_FAILS then
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
        place     = { "place", "plant", "build", "setblock", "putblock" },
        trash     = { "trash", "drop", "discard", "deleteitem", "removeitem" },
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
-- [3.5] HELPER UMUM (dipakai mode sapuan / plant / trash)
--=====================================================================

-- Posisi sebuah objek (Part atau Model). Model diambil dari PrimaryPart
-- atau anak pertamanya yang Part-like.
local function getPos(obj)
    if not obj then return nil end
    local ok, p = pcall(function() return obj.Position end)
    if ok and p then return p end
    if obj:IsA("Model") then
        local base = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if base then
            local ok2, p2 = pcall(function() return base.Position end)
            if ok2 then return p2 end
        end
    end
    return nil
end

-- Block dianggap "mati" kalau sudah dihancurkan / tidak lagi di workspace
local function isDead(obj)
    if not obj or not obj.Parent then return true end
    local ok, tr = pcall(function() return obj.Transparency end)
    if ok and tr and tr >= 1 then return true end
    return false
end

-- Kandidat block saat ini (semua container di-scan sekali)
local function getBlockCandidates()
    local out = {}
    for _, container in ipairs(getContainers()) do
        for _, obj in ipairs(container:GetDescendants()) do
            if looksLikeBlock(obj) then table.insert(out, obj) end
        end
    end
    return out
end

-- Tool di tangan (kalau ada)
local function getTool()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool")
end

-- Backpack player
local function getBackpack()
    return LP:FindFirstChildOfClass("Backpack")
end

-- Apakah executor punya VirtualInputManager (untuk fallback klik)
local fireToolActivation = (type(VirtualInputManager) == "table")

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
-- PENTING: return true hanya kalau ada bukti block benar-benar hancur.
-- Tanpa verifikasi ini, loop akan menganggap block mati padahal masih hidup,
-- lalu memilih block yang sama terus-menerus (macet).
local function breakBlock(block)
    if not block or isDead(block) then return false, "sudah-hancur" end

    local function verifier()
        -- beri 1 frame supaya penghapusan dari server terpropagasi
        task.wait(0.05)
        return isDead(block) or not block.Parent
    end

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
            if ok and verifier() then return true, "remote:" .. remote.Name end
        end
    end

    -- 2) fallback: aktifkan tool di tangan (banyak game Growtopia-like pakai tool)
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
        if verifier() then return true, "tool:" .. tool.Name end
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
            if verifier() then return true, "click" end
        end
    end

    return false, "block-tidak-hancur"
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

-- Baca mode yang di-toggle di UI. Default mati, kecuali yang di-set lain.
local function mode(key)
    return STATE.modes and STATE.modes[key] == true
end

-- Kumpulkan block lain di sekitar target dalam radius tertentu.
-- Adaptasi dari break3way() di script DF: satu titik, hancurkan sekitarnya.
local function findClusterAround(center, radius)
    local result = {}
    local origin = getPos(center)
    if not origin then return result end
    for _, obj in ipairs(getBlockCandidates()) do
        if obj ~= center and isPartLike(obj) and not isDead(obj) then
            local p = getPos(obj)
            if p then
                local d = (p - origin).Magnitude
                if d <= radius then
                    table.insert(result, obj)
                    if #result >= CONFIG.THREE_WAY_LIMIT then break end
                end
            end
        end
    end
    return result
end

-- Block di satu sisi saja (kiri = -1, kanan = +1) pada sumbu X.
-- Adaptasi dari sapuan arah di script DF.
local function findSideBlocks(center, side, length)
    local result = {}
    local origin = getPos(center)
    if not origin then return result end
    local found = {}
    for _, obj in ipairs(getBlockCandidates()) do
        if obj ~= center and isPartLike(obj) and not isDead(obj) then
            local p = getPos(obj)
            if p then
                local dx = p.X - origin.X
                local dz = p.Z - origin.Z
                -- hanya ambil yang benar-benar di sisi itu dan tidak terlalu jauh
                if (side < 0 and dx < -0.5) or (side > 0 and dx > 0.5) then
                    if math.abs(dz) <= length and math.abs(dx) <= length * 2 then
                        table.insert(found, { obj = obj, d = math.abs(dx) })
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    for i = 1, math.min(length, #found) do
        table.insert(result, found[i].obj)
    end
    return result
end

-- Tanam ulang di posisi block yang baru dihancurkan.
-- Adaptasi dari place3way()/plantDirt(). Pakai tool kalau ada, kalau tidak
-- coba remote "place" hasil auto-detect.
local function tryPlantAt(block)
    if not block or isDead(block) then return false end
    local pos = getPos(block)
    if not pos then return false end
    local tool = getTool()
    if tool and fireToolActivation then
        local ok = pcall(function() tool:Activate() end)
        if ok then return true end
    end
    if CONFIG.REMOTES.place then
        local r = resolveRemote(CONFIG.REMOTES.place)
        if r then
            pcall(function() r:FireServer(pos) end)
            return true
        end
    end
    return false
end

-- Tanam ulang di beberapa titik sekaligus (dipakai saat block sudah habis)
local function tryPlantArea()
    local planted = 0
    for _, obj in ipairs(getBlockCandidates()) do
        if planted >= CONFIG.SWEEP_LENGTH then break end
        if isDead(obj) then
            if tryPlantAt(obj) then planted = planted + 1 end
        end
    end
    if planted > 0 then log(("Tanam ulang %d titik"):format(planted)) end
    return planted
end

-- Buang item sampah kalau inventory sudah menumpuk.
-- Adaptasi dari bot:trash() di script DF.
local function tryTrashJunk()
    local backpack = getBackpack()
    if not backpack then return 0 end
    local items = {}
    for _, it in ipairs(backpack:GetChildren()) do
        table.insert(items, it)
    end
    if #items < CONFIG.TRASH_THRESHOLD then return 0 end

    local dumped = 0
    for _, it in ipairs(items) do
        if dumped >= math.floor(#items / 2) then break end
        local n = lc(it.Name)
        for _, kw in ipairs(CONFIG.JUNK_KEYWORDS) do
            if string.find(n, kw, 1, true) then
                -- jalur 1: remote trash hasil auto-detect
                local done = false
                if CONFIG.REMOTES.trash then
                    local r = resolveRemote(CONFIG.REMOTES.trash)
                    if r then
                        pcall(function() r:FireServer(it) end)
                        done = true
                    end
                end
                -- jalur 2: destroy lokal (beberapa game izinkan)
                if not done then
                    pcall(function() it:Destroy() end)
                    done = true
                end
                if done then dumped = dumped + 1 end
                break
            end
        end
    end
    if dumped > 0 then log(("Buang %d item sampah"):format(dumped)) end
    return dumped
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
                if mode("plant") then tryPlantArea() end
                if mode("autoTrash") then tryTrashJunk() end
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

            -- Break 3 arah: hancurkan cluster di sekitar target, bukan hanya
            -- satu block. Ini adaptasi dari break3way() di script DF Growtopia.
            local hitCount = 0
            if mode("threeWay") then
                -- PENTING: target itu sendiri harus ikut, bukan cuma tetangganya.
                -- findClusterAround mengecualikan `center`, jadi tambahkan manual.
                local ok0 = breakBlock(block)
                if ok0 then
                    hitCount = hitCount + 1
                    STATE.broken = STATE.broken + 1
                end
                task.wait(CONFIG.ACTION_DELAY)

                local cluster = findClusterAround(block, CONFIG.THREE_WAY_RADIUS)
                for _, b in ipairs(cluster) do
                    if not STATE.running then break end
                    if breakBlock(b) then
                        hitCount = hitCount + 1
                        STATE.broken = STATE.broken + 1
                    end
                    task.wait(CONFIG.ACTION_DELAY)
                end
            else
                local ok, how = breakBlock(block)
                if ok then
                    hitCount = 1
                    STATE.broken = STATE.broken + 1
                else
                    STATE.failed = STATE.failed or {}
                    STATE.failed[block] = (STATE.failed[block] or 0) + 1
                    log(("Break gagal (%dx): %s"):format(STATE.failed[block], tostring(how)))
                end
            end

            -- Sapuan arah (kiri/kanan): ambil block di sisi yang dipilih saja
            if mode("sweepLeft") or mode("sweepRight") then
                local side = mode("sweepLeft") and -1 or 1
                local sideBlocks = findSideBlocks(block, side, CONFIG.SWEEP_LENGTH)
                for _, b in ipairs(sideBlocks) do
                    if not STATE.running then break end
                    if breakBlock(b) then
                        hitCount = hitCount + 1
                        STATE.broken = STATE.broken + 1
                    end
                    task.wait(CONFIG.ACTION_DELAY)
                end
            end

            task.wait(CONFIG.ACTION_DELAY)

            if STATE.autoCollect ~= false then
                local got, amount = waitForCollect(before, CONFIG.COLLECT_TIMEOUT)
                if got then
                    STATE.collected = STATE.collected + amount
                    log(("Kumpul %d item dari %s"):format(amount, block.Name))
                end
            end

            -- tanam ulang di posisi yang baru dikosongkan
            if mode("plant") then
                tryPlantAt(block)
            end

            -- buang item sampah kalau inventory mendekati penuh
            if mode("autoTrash") then
                tryTrashJunk()
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

--=====================================================================
-- [8] SCOUT OTOMATIS (dijalankan sekali saat script dimuat)
--=====================================================================
-- Mengumpulkan nama RemoteEvent, struktur block, inventory, tool, dan grid.
-- Hasilnya dipakai untuk mengisi CONFIG.REMOTES secara otomatis (kalau bisa)
-- dan ditampilkan di console + panel UI.

local SCOUT_RESULT = ""
local SCOUT_SUMMARY = ""

local function runScout()
    local out = {}
    SCOUT_RESULT = ""
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local LP = Players.LocalPlayer

    local function add(s) out[#out + 1] = tostring(s) end
    local function head(s)
        add("")
        add(("="):rep(64))
        add("== " .. s)
        add(("="):rep(64))
    end

    --=====================================================================
    head("0. INFO GAME")
    --=====================================================================
    add("PlaceId      : " .. tostring(game.PlaceId))
    add("GameId       : " .. tostring(game.GameId))
    add("JobId        : " .. tostring(game.JobId))
    -- GetProductInfo bisa gagal (rate limit / PlaceId tidak valid). Jangan sampai
    -- satu panggilan ini mematikan seluruh scout.
    local gameName = "?"
    pcall(function()
        gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "?"
    end)
    add("GameName     : " .. tostring(gameName))
    add("Character    : " .. tostring(LP.Character and LP.Character.Name or "belum spawn"))
    add("Waktu lokal  : " .. os.date("%Y-%m-%d %H:%M:%S"))

    --=====================================================================
    head("1. SEMUA REMOTE (RemoteEvent / RemoteFunction)")
    --=====================================================================
    local remotes = {}
    local function collectRemotes(root, label)
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                table.insert(remotes, { obj = obj, label = label })
            end
        end
    end
    collectRemotes(RS, "ReplicatedStorage")
    collectRemotes(workspace, "workspace")
    for _, svc in ipairs({ "ReplicatedFirst", "StarterGui", "StarterPack" }) do
        local ok, s = pcall(function() return game:GetService(svc) end)
        if ok and s then collectRemotes(s, svc) end
    end

    add("Total remote ditemukan: " .. #remotes)
    add("")
    for i, r in ipairs(remotes) do
        add(("[%2d] [%s] %s"):format(i, r.obj.ClassName, r.obj:GetFullName()))
    end

    -- remote yang namanya mencurigakan (kandidat break/place/collect)
    add("")
    add("--- KANDIDAT KUAT (nama mengandung break/place/collect/hit/plant) ---")
    local keywords = {
        "break", "destroy", "dig", "mine", "harvest", "hit", "punch", "swing",
        "place", "plant", "build", "set", "collect", "pickup", "grab", "take",
        "trash", "drop", "sell", "buy", "trade", "warp", "teleport", "move",
        "inventory", "item", "block", "tile", "world",
    }
    for _, r in ipairs(remotes) do
        local n = string.lower(r.obj.Name)
        for _, kw in ipairs(keywords) do
            if string.find(n, kw, 1, true) then
                add(("  %-40s  [%s]  (%s)"):format(r.obj.Name, r.obj.ClassName, r.label))
                break
            end
        end
    end

    --=====================================================================
    head("2. STRUKTUR WORKSPACE (2 level)")
    --=====================================================================
    for _, child in ipairs(workspace:GetChildren()) do
        local n = #child:GetChildren()
        add(("%-32s %-18s anak: %d"):format(child.Name, child.ClassName, n))
        if n > 0 and n <= 12 then
            for _, sub in ipairs(child:GetChildren()) do
                add(("    └─ %-28s %-14s anak: %d"):format(sub.Name, sub.ClassName, #sub:GetChildren()))
            end
        elseif n > 12 then
            add(("    └─ (terlalu banyak anak, contoh 5 pertama:) "))
            for i = 1, math.min(5, n) do
                local sub = child:GetChildren()[i]
                add(("        %-28s %-14s"):format(sub.Name, sub.ClassName))
            end
        end
    end

    --=====================================================================
    head("3. ANALISA BLOCK (Part/Model + atribut)")
    --=====================================================================
    local stats = {
        parts = 0, models = 0, withAttr = 0, withTag = 0,
        materials = {}, names = {}, attrKeys = {}, classes = {},
    }

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            stats.parts = stats.parts + 1
            stats.classes[obj.ClassName] = (stats.classes[obj.ClassName] or 0) + 1
            stats.materials[tostring(obj.Material)] = (stats.materials[tostring(obj.Material)] or 0) + 1
            local shortName = obj.Name:gsub("%d+", "#")
            stats.names[shortName] = (stats.names[shortName] or 0) + 1

            local attrs = obj:GetAttributes()
            for k, v in pairs(attrs) do
                stats.attrKeys[k] = (stats.attrKeys[k] or 0) + 1
                stats.withAttr = stats.withAttr + 1
            end
        elseif obj:IsA("Model") then
            stats.models = stats.models + 1
        end
    end

    add("Total BasePart : " .. stats.parts)
    add("Total Model    : " .. stats.models)
    add("Part dengan atribut: " .. stats.withAttr)
    add("")
    add("--- ClassName ---")
    local sorted = {}
    for k, v in pairs(stats.classes) do table.insert(sorted, { k, v }) end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(12, #sorted) do
        add(("  %-24s %d"):format(sorted[i][1], sorted[i][2]))
    end
    add("")
    add("--- Material ---")
    sorted = {}
    for k, v in pairs(stats.materials) do table.insert(sorted, { k, v }) end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(15, #sorted) do
        add(("  %-24s %d"):format(sorted[i][1], sorted[i][2]))
    end
    add("")
    add("--- Nama (angka diganti #) ---")
    sorted = {}
    for k, v in pairs(stats.names) do table.insert(sorted, { k, v }) end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(20, #sorted) do
        add(("  %-32s %d"):format(sorted[i][1], sorted[i][2]))
    end
    add("")
    add("--- Atribut yang dipakai ---")
    for k, v in pairs(stats.attrKeys) do
        add(("  %-28s dipakai di %d part"):format(k, v))
    end

    --=====================================================================
    head("4. CONTOH 8 PART (detail lengkap)")
    --=====================================================================
    local shown = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and shown < 8 then
            shown = shown + 1
            add(("[%d] %s"):format(shown, obj:GetFullName()))
            add(("    ClassName : %s"):format(obj.ClassName))
            -- semua field di bawah dibungkus pcall: di game nyata sebagian
            -- properti bisa error (streaming, destroyed part), dan satu error
            -- tidak boleh mematikan seluruh scout
            local sz = "?"
            pcall(function()
                sz = ("%.2f, %.2f, %.2f"):format(obj.Size.X, obj.Size.Y, obj.Size.Z)
            end)
            add("    Size      : " .. sz)
            local ps = "?"
            pcall(function()
                ps = ("%.2f, %.2f, %.2f"):format(obj.Position.X, obj.Position.Y, obj.Position.Z)
            end)
            add("    Position  : " .. ps)
            add(("    Material  : %s"):format(tostring(obj.Material)))
            add(("    Anchored  : %s"):format(tostring(obj.Anchored)))
            local attrs = obj:GetAttributes()
            if next(attrs) then
                for k, v in pairs(attrs) do add(("    Attr      : %s = %s"):format(k, tostring(v))) end
            else
                add("    Attr      : (tidak ada)")
            end
            if #obj:GetChildren() > 0 then
                local names = {}
                for _, c in ipairs(obj:GetChildren()) do table.insert(names, c.Name .. "(" .. c.ClassName .. ")") end
                add("    Children  : " .. table.concat(names, ", "))
            end
            add("")
        end
    end

    --=====================================================================
    head("5. GRID / KOORDINAT (penting untuk pola '3 arah')")
    --=====================================================================
    -- Beberapa game Growtopia-like pakai grid. Cek apakah ada pola.
    add("Analisa jarak antar Part (untuk deteksi grid):")
    local positions = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and #positions < 400 then
            table.insert(positions, obj.Position)
        end
    end

    if #positions >= 2 then
        local deltas = {}
        for i = 1, math.min(200, #positions) do
            for j = i + 1, math.min(200, #positions) do
                local d = (positions[i] - positions[j]).Magnitude
                if d > 0.01 and d < 20 then
                    deltas[math.floor(d * 10) / 10] = (deltas[math.floor(d * 10) / 10] or 0) + 1
                end
            end
        end
        local sortedD = {}
        for k, v in pairs(deltas) do table.insert(sortedD, { k, v }) end
        table.sort(sortedD, function(a, b) return a[2] > b[2] end)
        add("Jarak yang paling sering muncul (kandidat ukuran grid):")
        for i = 1, math.min(10, #sortedD) do
            add(("  %.1f stud  ->  %d pasang"):format(sortedD[i][1], sortedD[i][2]))
        end
        add("")
        add("Kalau angkanya konsisten (mis. selalu 3.0), berarti game pakai grid.")
    else
        add("  (Part terlalu sedikit untuk analisa)")
    end

    --=====================================================================
    head("6. INVENTORY")
    --=====================================================================
    local backpack = LP:FindFirstChildOfClass("Backpack")
    add("Backpack: " .. (backpack and ("ada, " .. #backpack:GetChildren() .. " item") or "TIDAK ADA"))
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            add(("  %-32s %-14s"):format(item.Name, item.ClassName))
            if #item:GetChildren() > 0 then
                for _, c in ipairs(item:GetChildren()) do
                    add(("      └─ %-26s %s"):format(c.Name, c.ClassName))
                end
            end
        end
    end
    add("")
    local pstats = LP:FindFirstChild("leaderstats")
    if pstats then
        add("leaderstats:")
        for _, s in ipairs(pstats:GetChildren()) do
            add(("  %-20s = %s"):format(s.Name, tostring(s.Value)))
        end
    end
    add("")
    add("Atribut di Player:")
    local pattrs = LP:GetAttributes()
    if next(pattrs) then
        for k, v in pairs(pattrs) do add(("  %-20s = %s"):format(k, tostring(v))) end
    else
        add("  (tidak ada)")
    end

    --=====================================================================
    head("7. TOOL (untuk break/place)")
    --=====================================================================
    local char = LP.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        add("Tool di tangan : " .. (tool and tool.Name or "(kosong)"))
        if tool then
            for _, c in ipairs(tool:GetChildren()) do
                add(("  └─ %-28s %s"):format(c.Name, c.ClassName))
            end
            local attrs = tool:GetAttributes()
            for k, v in pairs(attrs) do add(("  Attr: %s = %s"):format(k, tostring(v))) end
        end
    else
        add("Character belum spawn")
    end

    --=====================================================================
    head("8. PLAYER LAIN (info game multi-pemain)")
    --=====================================================================
    add("Jumlah pemain: " .. #Players:GetPlayers())
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        add(("  %-24s char: %s"):format(p.Name, c and c.Name or "belum spawn"))
    end

    --=====================================================================
    head("9. GUI (mungkin ada UI bawaan game)")
    --=====================================================================
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        add("ScreenGui di PlayerGui:")
        for _, g in ipairs(pg:GetChildren()) do
            if g:IsA("ScreenGui") then
                add(("  %-32s anak: %d"):format(g.Name, #g:GetChildren()))
            end
        end
    end

    --=====================================================================
    head("10. RINGKASAN UNTUK DIKIRIM")
    --=====================================================================
    add("Copy dari baris ini ke bawah, kirim ke saya:")
    add("")
    add("PlaceId        : " .. tostring(game.PlaceId))
    add("Total remote   : " .. #remotes)
    add("Total BasePart : " .. stats.parts)
    add("Total Model    : " .. stats.models)
    add("Grid terdeteksi: " .. (#positions >= 2 and "perlu lihat bagian 5" or "tidak"))
    add("Backpack item  : " .. (backpack and #backpack:GetChildren() or 0))

    SCOUT_RESULT = table.concat(out, string.char(10))
    return SCOUT_RESULT
end

local API = {}

function API.start()
    if STATE.running then return end

    -- Diagnosa cepat SEBELUM loop jalan. Kalau START kelihatan "tidak terjadi
    -- apa-apa", penyebabnya hampir selalu salah satu dari ini, dan sekarang
    -- alasannya muncul di log UI.
    local char = LP.Character
    if not char then
        STATE.diagnosa = "Karakter belum spawn - tunggu sampai masuk game"
        log(STATE.diagnosa)
        return
    end
    if not char:FindFirstChild("HumanoidRootPart") then
        STATE.diagnosa = "HumanoidRootPart tidak ada - karakter belum siap"
        log(STATE.diagnosa)
        return
    end

    local jumlahKandidat = 0
    for _, container in ipairs(getContainers()) do
        for _, obj in ipairs(container:GetDescendants()) do
            if looksLikeBlock(obj) then jumlahKandidat = jumlahKandidat + 1 end
        end
    end

    if jumlahKandidat == 0 then
        STATE.diagnosa = "Tidak ada block terdeteksi - coba tekan SCAN lalu lihat panel hasil"
        log(STATE.diagnosa)
        return
    end

    local dekat, jarak = findNearestBlock()
    if not dekat then
        STATE.diagnosa = ("Ada %d block tapi semuanya di luar %d stud - naikkan MAX_DISTANCE")
            :format(jumlahKandidat, CONFIG.MAX_DISTANCE)
        log(STATE.diagnosa)
        return
    end

    local remote = resolveRemote("break")
    -- Simpan di STATE.diagnosa supaya TIDAK tertimpa log loop yang berjalan
    -- cepat. Pesan ini yang dibaca UI untuk menjelaskan apa yang terjadi.
    STATE.diagnosa = ("%d block, target %s (%.0f stud), remote: %s")
        :format(jumlahKandidat, dekat.Name, jarak or 0,
                remote and remote.Name or "TIDAK ADA - pakai tool/click")
    log(STATE.diagnosa)

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

-- API.scout: jalankan scout, tulis ke file, dan pakai remote yang cocok.
-- Dipanggil otomatis saat script dimuat, dan lewat tombol SCAN di UI.
function API.scout()
    local hasil = runScout()

    print("")
    print(hasil)
    print("")

    -- simpan ke file kalau executor mendukung
    if type(writefile) == "function" then
        pcall(function() writefile("growblox_scout.txt", hasil) end)
    end

    -- pakai nama remote hasil scout untuk mengisi CONFIG.REMOTES
    local dipakai = {}
    local candidates = { ["break"] = "break", collect = "collect", hit = "hit",
                         place = "place", trash = "trash" }
    for key, _ in pairs(candidates) do
        local r = resolveRemote(key)
        if r then
            CONFIG.REMOTES[key] = r.Name
            dipakai[#dipakai + 1] = key .. "=" .. r.Name
        end
    end

    if #dipakai > 0 then
        local msg = "Remote terpakai: " .. table.concat(dipakai, ", ")
        print("[Growblox] " .. msg)
        SCOUT_SUMMARY = msg
    else
        print("[Growblox] Tidak ada remote yang cocok - pakai fallback tool/click")
        SCOUT_SUMMARY = "Tidak ada remote cocok"
    end

    if STATE.ui and STATE.ui.refresh then STATE.ui.refresh() end
    return hasil
end

function API.getScoutResult()
    return SCOUT_RESULT
end

-- setMode: dipanggil UI saat toggle diubah. Mode dari script DF asli
-- (sweep kiri/kanan, 3 arah, plant, trash) diadaptasi ke Growblox.
function API.setMode(key, value)
    STATE.modes = STATE.modes or {}
    STATE.modes[key] = value and true or false
    local label = ({
        sweepLeft  = "Break Kiri",
        sweepRight = "Break Kanan",
        threeWay   = "Break 3 Arah",
        plant      = "Plant",
        autoTrash  = "Auto Trash",
    })[key] or key
    STATE.lastError = label .. ": " .. (value and "aktif" or "mati")
    if STATE.ui and STATE.ui.refresh then STATE.ui.refresh() end
end

-- setAutoCollect: auto ambil item yang jatuh
function API.setAutoCollect(value)
    STATE.autoCollect = value and true or false
    STATE.lastError = "AutoDF: " .. (value and "aktif" or "mati")
end

function API.getMode(key)
    return STATE.modes and STATE.modes[key] or false
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
-- [9] LOAD UI + START
--=====================================================================

-- UI ter-embed dari FarmUI.lua (gaya JunnzxyHub: hitam + cyan).
-- Cukup satu loadstring, tidak perlu file terpisah.
local function buildUI(API)
    local UI = {}
    local STATE = {
        api = nil, gui = nil, logs = {},
        refresh = nil, log = nil, destroy = nil,
    }

local UI = {}
local STATE = {
    api = nil, gui = nil, logs = {},
    refresh = nil, log = nil, destroy = nil,
}

--=====================================================================
-- PALET (dari analisa pixel gambar referensi)
--=====================================================================
local C = {
    bg        = Color3.fromRGB(0, 0, 0),        -- #000000 latar
    panel     = Color3.fromRGB(14, 13, 21),     -- #0e0d15 panel
    panel2    = Color3.fromRGB(20, 17, 28),     -- #14111c panel terang
    accent    = Color3.fromRGB(91, 191, 217),   -- #5bbfd9 cyan
    accentDim = Color3.fromRGB(45, 110, 130),
    text      = Color3.fromRGB(235, 240, 245),
    textDim   = Color3.fromRGB(120, 128, 145),
    off       = Color3.fromRGB(55, 58, 70),
    danger    = Color3.fromRGB(230, 85, 95),
    stroke    = Color3.fromRGB(32, 30, 44),
    white     = Color3.fromRGB(255, 255, 255),
}

--=====================================================================
-- UTIL
--=====================================================================
local function new(cls, props, children)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then o[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = o end
    if props and props.Parent then o.Parent = props.Parent end
    return o
end

local function corner(r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 6) })
end

local function stroke(color, t, tr)
    return new("UIStroke", {
        Color = color or C.stroke, Thickness = t or 1,
        Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function dragify(frame, handle)
    handle = handle or frame
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

--=====================================================================
-- TOGGLE SWITCH (gaya iOS, cyan saat aktif)
--=====================================================================
local function makeToggle(parent, layoutOrder)
    local holder = new("TextButton", {
        Size = UDim2.new(0, 46, 0, 24),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = layoutOrder,
        Parent = parent,
    }, { corner(12) })

    local knob = new("Frame", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 3, 0.5, -9),
        BackgroundColor3 = C.white,
        BorderSizePixel = 0,
        Parent = holder,
    }, { corner(9) })

    local state = { on = false }

    local function render()
        if state.on then
            holder.BackgroundColor3 = C.accent
            knob.Position = UDim2.new(1, -21, 0.5, -9)
        else
            holder.BackgroundColor3 = C.off
            knob.Position = UDim2.new(0, 3, 0.5, -9)
        end
    end

    holder.MouseButton1Click:Connect(function()
        state.on = not state.on
        render()
        if state.onChanged then state.onChanged(state.on) end
    end)

    render()
    state.set = function(v)
        state.on = v and true or false
        render()
    end
    state.render = render
    return state, holder
end

--=====================================================================
-- BUILD
--=====================================================================
function UI.build(API)
    STATE.api = API
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local pg = LP:WaitForChild("PlayerGui")

    local screen = new("ScreenGui", {
        Name = "GrowbloxFarmUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        Parent = pg,
    })
    STATE.gui = screen

    --================ PANEL UTAMA ================
    -- Ukuran default sengaja kecil supaya tidak memenuhi layar HP.
    -- Bisa diperbesar/diperkecil lewat grip di sudut kanan bawah,
    -- dan isinya bisa di-scroll kalau tidak muat.
    local main = new("Frame", {
        Size = UDim2.new(0, 260, 0, 340),
        Position = UDim2.new(0, 12, 0.5, -170),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = screen,
    }, { corner(12), stroke(C.stroke, 1) })

    --================ HEADER ================
    local header = new("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Parent = main,
    }, { corner(12) })
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 1, -16),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Parent = header,
    })

    new("TextLabel", {
        Text = "JunnzxyHub",
        Font = Enum.Font.GothamBold, TextSize = 17,
        TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 0, 20),
        Position = UDim2.new(0, 16, 0, 10),
        Parent = header,
    })
    new("TextLabel", {
        Text = "v3.0",
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Right,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 60, 0, 20),
        Position = UDim2.new(1, -78, 0, 12),
        Parent = header,
    })
    new("TextLabel", {
        Text = "Farm Auto DF-Tools",
        Font = Enum.Font.Gotham, TextSize = 12,
        TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 0, 18),
        Position = UDim2.new(0, 16, 0, 32),
        Parent = header,
    })

    local closeBtn = new("TextButton", {
        Text = "×", Font = Enum.Font.GothamBold, TextSize = 18,
        TextColor3 = C.textDim, BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(1, -38, 0, 14),
        AutoButtonColor = true, Parent = header,
    }, { corner(7) })

    dragify(main, header)

    --================ GRIP RESIZE (sudut kanan bawah) ================
    -- Tarik untuk mengubah ukuran panel. Ada tombol kecil untuk reset ukuran.
    local MIN_W, MIN_H = 200, 200
    local MAX_W, MAX_H = 900, 1200

    local grip = new("TextButton", {
        Text = "◢", Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = C.accentDim, BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -26, 1, -26),
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = main,
    }, { corner(4) })

    do
        local resizing, startPos, startSize = false, nil, nil
        grip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                startPos = input.Position
                startSize = main.AbsoluteSize
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                    end
                end)
            end
        end)
        grip.InputChanged:Connect(function(input)
            if not resizing then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local d = input.Position - startPos
            local w = math.clamp(startSize.X + d.X, MIN_W, MAX_W)
            local h = math.clamp(startSize.Y + d.Y, MIN_H, MAX_H)
            main.Size = UDim2.new(0, w, 0, h)
        end)
    end

    --================ TOMBOL UKURAN (kecil / sedang / besar) ================
    local sizeBtn = new("TextButton", {
        Text = "⤢", Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = C.textDim, BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(1, -68, 0, 14),
        AutoButtonColor = true, Parent = header,
    }, { corner(7) })

    local SIZES = {
        { 260, 340 },   -- kecil
        { 340, 440 },   -- sedang
        { 420, 560 },   -- besar
    }
    local sizeStep = 1
    sizeBtn.MouseButton1Click:Connect(function()
        sizeStep = sizeStep + 1
        if sizeStep > #SIZES then sizeStep = 1 end
        local s = SIZES[sizeStep]
        main.Size = UDim2.new(0, s[1], 0, s[2])
    end)

    --================ DAFTAR FITUR ================
    -- Daftar fitur bisa di-scroll, jadi tetap bisa dipakai walau panel dikecilkan.
    local list = new("ScrollingFrame", {
        Size = UDim2.new(1, -20, 1, -110),
        Position = UDim2.new(0, 10, 0, 62),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.accentDim,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = main,
    })
    local listLayout = new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    -- helper: buat satu baris fitur
    local function makeRow(order, icon, name, desc)
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 54),
            BackgroundColor3 = C.panel,
            BorderSizePixel = 0,
            LayoutOrder = order,
            Parent = list,
        }, { corner(8), stroke(C.stroke, 1) })

        -- garis aksen kiri
        new("Frame", {
            Size = UDim2.new(0, 3, 1, -16),
            Position = UDim2.new(0, 0, 0, 8),
            BackgroundColor3 = C.accent,
            BorderSizePixel = 0,
            Parent = row,
        }, { corner(2) })

        new("TextLabel", {
            Text = icon,
            Font = Enum.Font.GothamBold, TextSize = 15,
            TextColor3 = C.accent, BackgroundTransparency = 1,
            Size = UDim2.new(0, 26, 0, 26),
            Position = UDim2.new(0, 12, 0, 14),
            Parent = row,
        })

        new("TextLabel", {
            Text = name,
            Font = Enum.Font.GothamBold, TextSize = 13,
            TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -100, 0, 16),
            Position = UDim2.new(0, 44, 0, 10),
            Parent = row,
        })

        new("TextLabel", {
            Text = desc,
            Font = Enum.Font.Gotham, TextSize = 10,
            TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -110, 0, 24),
            Position = UDim2.new(0, 44, 0, 26),
            TextWrapped = true,
            Parent = row,
        })

        return row
    end

    -- -- Baris 1: Farm (tombol)
    local rowFarm = makeRow(1, "▶", "Farm", "Jalankan / hentikan auto farm")
    local farmBtn = new("TextButton", {
        Text = "START", Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
        Size = UDim2.new(0, 62, 0, 26),
        Position = UDim2.new(1, -72, 0.5, -13),
        AutoButtonColor = false, Parent = rowFarm,
    }, { corner(6) })

    -- -- Baris 2: Auto DF (toggle)
    local rowAuto = makeRow(2, "◈", "AutoDF", "Auto collect saat block di-break")
    local autoToggle = makeToggle(rowAuto, 2)
    autoToggle.holder = nil
    -- pindahkan toggle ke kanan
    for _, c in ipairs(rowAuto:GetChildren()) do
        if c:IsA("TextButton") then
            c.Position = UDim2.new(1, -58, 0.5, -12)
        end
    end

    -- -- Baris 3: Break Kiri
    local rowLeft = makeRow(3, "◀", "Break Kiri", "Sapu kolom kiri, dari atas ke bawah")
    local leftToggle = makeToggle(rowLeft, 3)
    for _, c in ipairs(rowLeft:GetChildren()) do
        if c:IsA("TextButton") then c.Position = UDim2.new(1, -58, 0.5, -12) end
    end

    -- -- Baris 4: Break Kanan
    local rowRight = makeRow(4, "▶", "Break Kanan", "Sapu kolom kanan, dari atas ke bawah")
    local rightToggle = makeToggle(rowRight, 4)
    for _, c in ipairs(rowRight:GetChildren()) do
        if c:IsA("TextButton") then c.Position = UDim2.new(1, -58, 0.5, -12) end
    end

    -- -- Baris 5: Break 3 Arah
    local row3 = makeRow(5, "≡", "Break 3 Arah", "Break baris + 2 lapis atas/bawah sekaligus")
    local threeToggle = makeToggle(row3, 5)
    for _, c in ipairs(row3:GetChildren()) do
        if c:IsA("TextButton") then c.Position = UDim2.new(1, -58, 0.5, -12) end
    end

    -- -- Baris 6: Plant
    local rowPlant = makeRow(6, "✚", "Plant", "Tanam ulang setelah break")
    local plantToggle = makeToggle(rowPlant, 6)
    for _, c in ipairs(rowPlant:GetChildren()) do
        if c:IsA("TextButton") then c.Position = UDim2.new(1, -58, 0.5, -12) end
    end

    -- -- Baris 7: Auto Trash
    local rowTrash = makeRow(7, "⌫", "Auto Trash", "Buang item sampah saat inventory penuh")
    local trashToggle = makeToggle(rowTrash, 7)
    for _, c in ipairs(rowTrash:GetChildren()) do
        if c:IsA("TextButton") then c.Position = UDim2.new(1, -58, 0.5, -12) end
    end

    -- -- Baris 8: Scout + lihat hasil
    local rowScout = makeRow(8, "◉", "Scout", "Deteksi remote, block, inventory di game ini")
    local scoutBtn = new("TextButton", {
        Text = "SCAN", Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
        Size = UDim2.new(0, 52, 0, 24),
        Position = UDim2.new(1, -60, 0.5, -12),
        AutoButtonColor = false, Parent = rowScout,
    }, { corner(6) })

    --================ STATISTIK ================
    local statsBar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 34),
        Position = UDim2.new(0, 10, 1, -102),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Parent = main,
    }, { corner(8), stroke(C.stroke, 1) })

    local statText = new("TextLabel", {
        Text = "Block: 0   Item: 0   Target: -",
        Font = Enum.Font.Code, TextSize = 11,
        TextColor3 = C.textDim, BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = statsBar,
    })

    --================ STATUS FOOTER ================
    local footer = new("TextLabel", {
        Text = "Auto DF: Dihentikan.",
        Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = C.textDim, BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.new(0, 10, 1, -68),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Parent = main,
    })

    --================ LOG ================
    local logFrame = new("Frame", {
        Size = UDim2.new(1, -20, 0, 42),
        Position = UDim2.new(0, 10, 1, -56),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = main,
    }, { corner(6) })

    -- Log multi-baris: 4 baris terakhir terlihat sekaligus, supaya kelihatan
    -- apa yang sedang dilakukan loop (bukan cuma satu pesan yang tertimpa).
    local logText = new("TextLabel", {
        Text = "siap.",
        Font = Enum.Font.Code, TextSize = 9,
        TextColor3 = C.textDim, BackgroundTransparency = 1,
        Size = UDim2.new(1, -12, 1, -6),
        Position = UDim2.new(0, 6, 0, 4),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Parent = logFrame,
    })
    STATE.logLines = {}

    --================ PANEL HASIL SCOUT ================
    local scoutPanel = new("ScrollingFrame", {
        Size = UDim2.new(1, -20, 0, 140),
        Position = UDim2.new(0, 10, 1, -200),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Visible = false, Parent = main,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, { corner(6), stroke(C.stroke, 1) })

    local scoutText = new("TextLabel", {
        Text = "",
        Font = Enum.Font.Code, TextSize = 9,
        TextColor3 = C.textDim, BackgroundTransparency = 1,
        Size = UDim2.new(1, -12, 0, 0),
        Position = UDim2.new(0, 6, 0, 6),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = scoutPanel,
    })

    --================ TOMBOL BUKA KEMBALI ================
    local reopen = new("TextButton", {
        Text = "DF", Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 20, 0.5, -20),
        Visible = false, Parent = screen,
    }, { corner(20), stroke(C.accentDim, 2) })
    dragify(reopen, reopen)

    --=====================================================================
    -- LOGIKA
    --=====================================================================
    -- pushLog: tulis ke label UI + teruskan ke callback eksternal kalau ada
    -- Log multi-baris: simpan 4 pesan terakhir supaya kelihatan urutan kejadian.
    local LOG_MAX = 4
    local function pushLog(msg)
        local line = tostring(msg)
        table.insert(STATE.logLines, 1, line)
        while #STATE.logLines > LOG_MAX do
            table.remove(STATE.logLines)
        end
        logText.Text = table.concat(STATE.logLines, "\n")
        -- externalLog dipasang oleh AutoFarm.lua kalau perlu; TIDAK boleh
        -- menunjuk ke pushLog sendiri (itu bikin rekursi tak terbatas).
        if STATE.externalLog then
            pcall(STATE.externalLog, line)
        end
    end
    STATE.log = pushLog
    STATE.pushLog = pushLog

    local function refresh()
        local s = API and API.status and API.status() or {}
        local broken = s.broken or 0
        local collected = s.collected or 0
        local target = s.currentTarget or "-"
        statText.Text = ("Block: %d   Item: %d   Target: %s"):format(broken, collected, tostring(target))

        if s.running then
            farmBtn.Text = "STOP"
            farmBtn.BackgroundColor3 = C.danger
            footer.Text = "Auto DF: Berjalan... (" .. tostring(target) .. ")"
            footer.TextColor3 = C.accent
        else
            farmBtn.Text = "START"
            farmBtn.BackgroundColor3 = C.accent
            footer.Text = "Auto DF: Dihentikan."
            footer.TextColor3 = C.textDim
            -- Tampilkan alasan terakhir supaya START yang "tidak terjadi apa-apa"
            -- bisa langsung dilihat penyebabnya.
            if s.diagnosa and s.diagnosa ~= "" then
                footer.Text = "Dihentikan - " .. tostring(s.diagnosa)
            end
        end
    end
    STATE.refresh = refresh

    --================ EVENT ================
    farmBtn.MouseButton1Click:Connect(function()
        if API and API.toggle then API.toggle() end
        refresh()
    end)

    -- Tombol SCAN: jalankan ulang scout, tampilkan hasil, pakai remote yang cocok
    scoutBtn.MouseButton1Click:Connect(function()
        scoutBtn.Text = "..."
        pushLog("Scout jalan...")
        task.spawn(function()
            local ok, hasil = pcall(API.scout)
            if ok and hasil then
                scoutText.Text = hasil
                scoutPanel.Visible = true
                pushLog("Scout selesai - hasil di panel bawah")
            else
                pushLog("Scout gagal: " .. tostring(hasil))
            end
            scoutBtn.Text = "SCAN"
        end)
    end)

    -- klik kanan pada baris Scout = sembunyikan/tampilkan panel hasil
    rowScout.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            scoutPanel.Visible = not scoutPanel.Visible
        end
    end)

    if autoToggle and autoToggle.set then
        -- toggle auto collect: placeholder, dihubungkan ke API kalau ada
        autoToggle.onChanged = function(v)
            if API and API.setAutoCollect then API.setAutoCollect(v) end
            pushLog("AutoDF: " .. (v and "aktif" or "mati"))
        end
    end

    local function bindMode(toggle, key, label)
        toggle.onChanged = function(v)
            if API and API.setMode then API.setMode(key, v) end
            pushLog(label .. ": " .. (v and "aktif" or "mati"))
        end
    end
    bindMode(leftToggle, "sweepLeft", "Break Kiri")
    bindMode(rightToggle, "sweepRight", "Break Kanan")
    bindMode(threeToggle, "threeWay", "Break 3 Arah")
    bindMode(plantToggle, "plant", "Plant")
    bindMode(trashToggle, "autoTrash", "Auto Trash")

    closeBtn.MouseButton1Click:Connect(function()
        if API and API.destroy then API.destroy() end
    end)

    reopen.MouseButton1Click:Connect(function()
        main.Visible = true
        reopen.Visible = false
    end)

    -- sembunyikan lewat klik kanan / tahan lama di header
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            main.Visible = false
            reopen.Visible = true
        end
    end)

    STATE.destroy = function()
        pcall(function() screen:Destroy() end)
    end

    pushLog("UI siap. Tekan START untuk mulai.")
    refresh()

    task.spawn(function()
        while STATE.gui and STATE.gui.Parent do
            refresh()
            task.wait(0.4)
        end
    end)

    return STATE
end



    return UI.build(API)
end

-- panggil buildUI(API) -- mengembalikan tabel kontrol (refresh/log/destroy)
local uiOk, uiErr = pcall(function()
    local uiCtrl = buildUI(API)
    if type(uiCtrl) ~= "table" then
        error("UI tidak mengembalikan tabel kontrol")
    end
    STATE.ui = uiCtrl
end)

if not uiOk then
    warn("[Growblox AutoFarm] UI gagal dibangun: " .. tostring(uiErr))
    STATE.ui = nil
end

if CONFIG.AUTO_START then
    API.start()
end

-- jalankan scout otomatis saat script dimuat
local scoutOk, scoutErr = pcall(API.scout)
if not scoutOk then
    print("[Growblox] Scout gagal: " .. tostring(scoutErr))
end

-- expose ke executor supaya bisa dikontrol manual dari console
getgenv().GrowbloxAutoFarm = API
print("[Growblox AutoFarm] Loaded. Gunakan getgenv().GrowbloxAutoFarm untuk kontrol.")
