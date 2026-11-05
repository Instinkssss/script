--[[
    SCOUT v2 - Growblox Deep Discovery
    Untuk Delta Executor / executor Roblox apa pun.

    TUJUAN
    ------
    Mengumpulkan SEMUA yang dibutuhkan untuk mengisi logika auto-farm:
      1. Nama RemoteEvent/RemoteFunction + argumennya (dari mana?)
      2. Bagaimana block disimpan (Part? Model? Folder apa?)
      3. Apakah ada grid koordinat (beberapa game Growtopia-like pakai ini)
      4. Bagaimana inventory bekerja (Backpack? atribut angka? GUI?)
      5. Area farm: berapa luas, berapa banyak block, di mana
      6. Tool apa yang dipakai untuk break/place

    CARA PAKAI
    ----------
    1. Masuk game Growblox sampai karakter spawn.
    2. Tempel SELURUH file ini ke executor, execute.
    3. Copy semua output dari tab Console/Output.
    4. Kirim ke saya.

    Kalau executor Anda punya writefile(), hasilnya juga disimpan ke
    growblox_scout.txt di workspace executor.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local out = {}
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
add("GameName     : " .. tostring(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "?"))
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
        add(("    Size      : %.2f, %.2f, %.2f"):format(obj.Size.X, obj.Size.Y, obj.Size.Z))
        add(("    Position  : %.2f, %.2f, %.2f"):format(obj.Position.X, obj.Position.Y, obj.Position.Z))
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

--=====================================================================
-- OUTPUT
--=====================================================================
local result = table.concat(out, "\n")
print(result)

if writefile then
    local ok, err = pcall(function()
        writefile("growblox_scout.txt", result)
    end)
    if ok then
        print("")
        print("[OK] Disimpan ke growblox_scout.txt di workspace executor.")
    else
        print("[!] Gagal menyimpan: " .. tostring(err))
    end
end
