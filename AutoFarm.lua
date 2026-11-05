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

    File ini SINGLE-FILE: UI sudah di-embed di dalamnya.
    Cukup satu loadstring, tidak perlu file lain.

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

-- UI di-embed langsung di file ini supaya cukup satu loadstring saja.
local function buildUI(api)
    local UI = {}
    local STATE = {
    api      = nil,
    gui      = nil,
    logs     = {},
    running  = false,
    refresh  = nil,
    log      = nil,
    destroy  = nil,
}

    --=====================================================================
-- WARNA
    --=====================================================================
    local C = {
    bg      = Color3.fromRGB(14, 16, 20),
    panel   = Color3.fromRGB(22, 25, 31),
    panel2  = Color3.fromRGB(30, 34, 42),
    accent  = Color3.fromRGB(60, 220, 130),
    accentD = Color3.fromRGB(35, 150, 90),
    text    = Color3.fromRGB(235, 238, 242),
    textDim = Color3.fromRGB(150, 158, 170),
    danger  = Color3.fromRGB(240, 90, 95),
    stroke  = Color3.fromRGB(48, 54, 64),
}

    --=====================================================================
-- UTIL
    --=====================================================================
    local function new(className, props, children)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then obj[k] = v end
    end
    for _, c in ipairs(children or {}) do
        c.Parent = obj
    end
    if props and props.Parent then obj.Parent = props.Parent end
    return obj
    end

    local function corner(r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
    end

    local function stroke(color, thick, trans)
    return new("UIStroke", {
        Color = color or C.stroke,
        Thickness = thick or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    end

    --=====================================================================
-- BUILD
    --=====================================================================
    function UI.build(API)
    STATE.api = API
    local LP = game:GetService("Players").LocalPlayer
    local pg = LP:WaitForChild("PlayerGui")

    local screen = new("ScreenGui", {
        Name = "GrowbloxAutoFarm",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        Parent = pg,
    })
    STATE.gui = screen

        --================ Frame utama ================
    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 340, 0, 396),
        Position = UDim2.new(0, 24, 0.5, -198),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Parent = screen,
    }, { corner(14), stroke(C.stroke, 1) })

        --================ Header ================
    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Parent = main,
    }, { corner(14) })

    -- tutup sudut bawah header biar rata
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 1, -14),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Parent = header,
    })

    new("Frame", {
        Name = "AccentBar",
        Size = UDim2.new(0, 4, 0, 26),
        Position = UDim2.new(0, 16, 0.5, -13),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
        Parent = header,
    }, { corner(2) })

    new("TextLabel", {
        Name = "Title",
        Text = "GROWBLOX AUTOFARM",
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -90, 0, 18),
        Position = UDim2.new(0, 30, 0, 10),
        Parent = header,
    })

    local statusLabel = new("TextLabel", {
        Name = "Status",
        Text = "● IDLE",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = C.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -90, 0, 16),
        Position = UDim2.new(0, 30, 0, 28),
        Parent = header,
    })

    local closeBtn = new("TextButton", {
        Name = "Close",
        Text = "×",
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = C.textDim,
        BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(1, -40, 0.5, -14),
        AutoButtonColor = true,
        Parent = header,
    }, { corner(8) })

    dragify(main, header)

        --================ Stats ================
    local statsFrame = new("Frame", {
        Name = "Stats",
        Size = UDim2.new(1, -28, 0, 66),
        Position = UDim2.new(0, 14, 0, 64),
        BackgroundTransparency = 1,
        Parent = main,
    })

    local function makeStat(idx, label, color)
        local w = 1 / 3
        local f = new("Frame", {
            Size = UDim2.new(w, -8, 1, 0),
            Position = UDim2.new(w * idx, 4 + idx * 0, 0, 0),
            BackgroundColor3 = C.panel,
            BorderSizePixel = 0,
            Parent = statsFrame,
        }, { corner(10), stroke(C.stroke, 1) })
        f.Position = UDim2.new(w * idx, 4, 0, 0)
        f.Size = UDim2.new(w, -6, 1, 0)

        local val = new("TextLabel", {
            Text = "0",
            Font = Enum.Font.GothamBold,
            TextSize = 19,
            TextColor3 = color,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 24),
            Position = UDim2.new(0, 0, 0, 10),
            Parent = f,
        })
        new("TextLabel", {
            Text = label,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = C.textDim,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Position = UDim2.new(0, 0, 0, 36),
            Parent = f,
        })
        return val
    end

    local brokenVal    = makeStat(0, "BLOCK DIHANCURKAN", C.accent)
    local collectedVal = makeStat(1, "ITEM TERKUMPUL", Color3.fromRGB(90, 170, 255))
    local targetVal    = makeStat(2, "TARGET SEKARANG", C.text)

        --================ Info baris ================
    local infoLabel = new("TextLabel", {
        Name = "Info",
        Text = "Menunggu perintah...",
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -28, 0, 28),
        Position = UDim2.new(0, 14, 0, 140),
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = main,
    }, { corner(8) })

        --================ Tombol utama ================
    local actionBtn = new("TextButton", {
        Name = "Action",
        Text = "MULAI AUTO FARM",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Color3.fromRGB(10, 14, 12),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -28, 0, 42),
        Position = UDim2.new(0, 14, 0, 178),
        AutoButtonColor = false,
        Parent = main,
    }, { corner(10) })

        --================ Baris tombol kecil ================
    local row = new("Frame", {
        Size = UDim2.new(1, -28, 0, 34),
        Position = UDim2.new(0, 14, 0, 228),
        BackgroundTransparency = 1,
        Parent = main,
    })

    local function smallBtn(text, x, w, danger)
        return new("TextButton", {
            Text = text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = danger and C.danger or C.text,
            BackgroundColor3 = C.panel2,
            BorderSizePixel = 0,
            Size = UDim2.new(w, -6, 1, 0),
            Position = UDim2.new(x, 0, 0, 0),
            AutoButtonColor = true,
            Parent = row,
        }, { corner(8), stroke(C.stroke, 1) })
    end

    local resetBtn = smallBtn("RESET STAT", 0,    0.5, false)
    local hideBtn  = smallBtn("SEMBUNYIKAN", 0.5, 0.5, false)

        --================ Log ================
    new("TextLabel", {
        Text = "LOG AKTIVITAS",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = C.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 16),
        Position = UDim2.new(0, 16, 0, 272),
        Parent = main,
    })

    local logFrame = new("Frame", {
        Size = UDim2.new(1, -28, 0, 92),
        Position = UDim2.new(0, 14, 0, 290),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = main,
    }, { corner(10), stroke(C.stroke, 1) })

    local logLayout = new("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = logFrame,
    })
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = logFrame,
    })

        --================ Tombol buka kembali ================
    local reopen = new("TextButton", {
        Name = "Reopen",
        Text = "GB",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Color3.fromRGB(10, 14, 12),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 24, 0.5, -20),
        Visible = false,
        Parent = screen,
    }, { corner(20), stroke(C.accentD, 2) })
    dragify(reopen, reopen)

        --=====================================================================
    -- FUNGSI UI
        --=====================================================================
    local function pushLog(msg)
        local t = os.date("%H:%M:%S")
        table.insert(STATE.logs, 1, ("[%s] %s"):format(t, msg))
        while #STATE.logs > 7 do table.remove(STATE.logs) end
        logFrame:ClearAllChildren()
        logLayout.Parent = logFrame
        new("UIPadding", {
            PaddingTop = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
            Parent = logFrame,
        })
        for i, line in ipairs(STATE.logs) do
            new("TextLabel", {
                Text = line,
                Font = Enum.Font.Code,
                TextSize = 10,
                TextColor3 = i == 1 and C.accent or C.textDim,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 12),
                LayoutOrder = i,
                Parent = logFrame,
            })
        end
    end

    STATE.log = pushLog

    local function refresh()
        local s = API.status()
        brokenVal.Text    = tostring(s.broken)
        collectedVal.Text = tostring(s.collected)
        targetVal.Text    = tostring(s.currentTarget == "-" and "-" or s.currentTarget)
        targetVal.TextSize = 12

        if s.running then
            statusLabel.Text = "● RUNNING"
            statusLabel.TextColor3 = C.accent
            actionBtn.Text = "STOP AUTO FARM"
            actionBtn.BackgroundColor3 = C.danger
            actionBtn.TextColor3 = Color3.fromRGB(255, 245, 245)
            infoLabel.Text = "Sedang bekerja... target: " .. tostring(s.currentTarget)
        else
            statusLabel.Text = "● IDLE"
            statusLabel.TextColor3 = C.textDim
            actionBtn.Text = "MULAI AUTO FARM"
            actionBtn.BackgroundColor3 = C.accent
            actionBtn.TextColor3 = Color3.fromRGB(10, 14, 12)
            infoLabel.Text = "Siap. Tekan MULAI untuk memulai."
        end
    end

    STATE.refresh = refresh

        --=====================================================================
    -- EVENT
        --=====================================================================
    actionBtn.MouseButton1Click:Connect(function()
        API.toggle()
        refresh()
    end)

    resetBtn.MouseButton1Click:Connect(function()
        API.reset()
        pushLog("Statistik direset")
        refresh()
    end)

    hideBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        reopen.Visible = true
    end)

    reopen.MouseButton1Click:Connect(function()
        main.Visible = true
        reopen.Visible = false
    end)

    closeBtn.MouseButton1Click:Connect(function()
        API.destroy()
    end)

    STATE.destroy = function()
        pcall(function() screen:Destroy() end)
    end

    pushLog("UI dimuat. Menunggu perintah.")
    refresh()

    -- sinkronkan tiap 400ms biar angka selalu segar
    task.spawn(function()
        while STATE.gui and STATE.gui.Parent do
            refresh()
            task.wait(0.4)
        end
    end)

    return STATE
end

return UI
end

-- panggil .build(API) -- UI.build mengembalikan tabel kontrol (refresh/log/destroy)
local uiOk, uiErr = pcall(function()
    local UImod = buildUI()
    if type(UImod) ~= "table" or type(UImod.build) ~= "function" then
        error("modul UI tidak valid")
    end
    STATE.ui = UImod.build(API)
end)

if not uiOk then
    warn("[Growblox AutoFarm] UI gagal dibangun: " .. tostring(uiErr))
    STATE.ui = nil
end

if CONFIG.AUTO_START then
    API.start()
end

-- expose ke executor supaya bisa dikontrol manual dari console
getgenv().GrowbloxAutoFarm = API
print("[Growblox AutoFarm] Loaded. Gunakan getgenv().GrowbloxAutoFarm untuk kontrol.")
