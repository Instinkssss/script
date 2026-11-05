--[[
    DISCOVERY MODE - Growblox
    Jalankan script ini SEKALI di Delta executor saat berada di dalam Growblox.
    Tujuan: menemukan nama RemoteEvent dan struktur block yang asli,
    supaya AutoFarm.lua bisa dikonfigurasi dengan benar.

    Hasil print akan muncul di Console/Output Delta.
    Copy hasilnya, kirim balik untuk dikonfigurasi.
]]

local RS = game:GetService("ReplicatedStorage")

local out = {}

local function add(s) out[#out+1] = s end

add("=========== [1] REMOTE DI REPLICATEDSTORAGE ===========")
for _, obj in ipairs(RS:GetDescendants()) do
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent") then
        add(("[%s] %s"):format(obj.ClassName, obj:GetFullName()))
    end
end

add("")
add("=========== [2] REMOTE DI WORKSPACE / LAINNYA ===========")
for _, root in ipairs({ workspace, game:GetService("ServerScriptService"), game:GetService("ReplicatedFirst") }) do
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            add(("[%s] %s"):format(obj.ClassName, obj:GetFullName()))
        end
    end
end

add("")
add("=========== [3] STRUKTUR LEVEL-2 WORKSPACE ===========")
for _, child in ipairs(workspace:GetChildren()) do
    add(("%s  (%s)  -> %d anak"):format(child.Name, child.ClassName, #child:GetChildren()))
    for _, sub in ipairs(child:GetChildren()) do
        if #sub:GetChildren() > 0 then
            add(("    %s (%s) -> %d anak"):format(sub.Name, sub.ClassName, #sub:GetChildren()))
        end
    end
end

add("")
add("=========== [4] KANDIDAT BLOCK ===========")
local shown = 0
local function scan(root, depth)
    if depth > 5 or shown > 60 then return end
    for _, obj in ipairs(root:GetChildren()) do
        if obj:IsA("BasePart") then
            local attrs = obj:GetAttributes()
            local attrStr = ""
            for k, v in pairs(attrs) do
                attrStr = attrStr .. (" %s=%s"):format(tostring(k), tostring(v))
            end
            if #attrStr > 0 or shown < 25 then
                add(("%s | %s | Material=%s | Size=%s | Attr:%s")
                    :format(obj:GetFullName(), obj.ClassName, tostring(obj.Material),
                            tostring(obj.Size), attrStr ~= "" and attrStr or " (none)"))
                shown = shown + 1
            end
        end
        scan(obj, depth + 1)
    end
end
scan(workspace, 0)

add("")
add("=========== [5] TOOL DI BACKPACK ===========")
local LP = game:GetService("Players").LocalPlayer
local bp = LP:FindFirstChildOfClass("Backpack")
if bp then
    for _, t in ipairs(bp:GetChildren()) do
        add(("%s (%s)"):format(t.Name, t.ClassName))
        for _, req in ipairs(t:GetChildren()) do
            if req:IsA("RemoteEvent") or req:IsA("RemoteFunction") then
                add(("    -> [%s] %s"):format(req.ClassName, req.Name))
            end
        end
    end
else
    add("(Backpack kosong / tidak ada)")
end

add("")
add("=========== [6] INFO GAME ===========")
add("PlaceId   : " .. tostring(game.PlaceId))
add("GameId    : " .. tostring(game.GameId))
add("JobId     : " .. tostring(game.JobId))
add("Workspace anak langsung: " .. #workspace:GetChildren())

local result = table.concat(out, "\n")
print(result)

-- kalau executor punya fungsi writefile, simpan juga ke file
if writefile then
    pcall(function()
        writefile("growblox_discovery.txt", result)
        print("[OK] Disimpan ke workspace/growblox_discovery.txt")
    end)
end
