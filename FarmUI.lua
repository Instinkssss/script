--[[
    Growblox Farm UI -- gaya JunnzxyHub
    Palet dari analisa gambar: latar #000000, panel #0e0d15, aksen #5bbfd9

    Ini MODUL UI saja. Dipakai oleh AutoFarm.lua (ter-embed)
    atau berdiri sendiri untuk pratinjau tampilan.

    Struktur yang ditiru dari gambar:
      - Header: judul "JunnzxyHub v3.0" + subjudul "Farm Auto DF-Tools"
      - Daftar fitur vertikal: label fitur di kiri, kontrol di kanan
      - Setiap item: nama fitur + deskripsi kecil di bawahnya
      - Footer: status "Auto DF: Dihentikan."
]]

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
    local main = new("Frame", {
        Size = UDim2.new(0, 330, 0, 470),
        Position = UDim2.new(0, 20, 0.5, -235),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
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

    --================ DAFTAR FITUR ================
    local list = new("Frame", {
        Size = UDim2.new(1, -20, 0, 296),
        Position = UDim2.new(0, 10, 0, 72),
        BackgroundTransparency = 1,
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

    --================ STATISTIK ================
    local statsBar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 34),
        Position = UDim2.new(0, 10, 0, 376),
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
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 416),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = main,
    })

    --================ LOG ================
    local logFrame = new("Frame", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 438),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = main,
    }, { corner(6) })

    local logText = new("TextLabel", {
        Text = "siap.",
        Font = Enum.Font.Code, TextSize = 10,
        TextColor3 = C.textDim, BackgroundTransparency = 1,
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.new(0, 6, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = logFrame,
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
    local function pushLog(msg)
        logText.Text = tostring(msg)
        -- externalLog dipasang oleh AutoFarm.lua kalau perlu; TIDAK boleh
        -- menunjuk ke pushLog sendiri (itu bikin rekursi tak terbatas).
        if STATE.externalLog then
            pcall(STATE.externalLog, tostring(msg))
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
        end
    end
    STATE.refresh = refresh

    --================ EVENT ================
    farmBtn.MouseButton1Click:Connect(function()
        if API and API.toggle then API.toggle() end
        refresh()
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

return UI
