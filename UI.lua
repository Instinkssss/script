--[[
    Growblox AutoFarm - UI Module
    Dependency-free (tidak butuh Rayfield / Fluent).
    Return table dengan build(API) dan destroy().

    Palet: dark glass + aksen hijau neon.
]]

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

    return UI
end

return UI
