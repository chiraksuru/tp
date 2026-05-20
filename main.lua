--!nonstrict
local Players    = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ─── Preset storage ────────────────────────────────────────────────────────

local PRESET_FILE = "C:/matcha/workspace/tp_presets.json"

local function loadPresets()
    if isfile(PRESET_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(PRESET_FILE))
        end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function savePresets(p)
    pcall(function()
        writefile(PRESET_FILE, HttpService:JSONEncode(p))
    end)
end

local presets = loadPresets()

-- ─── Helpers ───────────────────────────────────────────────────────────────

local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getTargetCoords()
    local nx = tonumber(UI.GetValue("tp_x"))
    local ny = tonumber(UI.GetValue("tp_y"))
    local nz = tonumber(UI.GetValue("tp_z"))
    return nx, ny, nz
end
-- ─── Noclip ────────────────────────────────────────────────────────────────

local noclipActive = false

local function setNoclip(enabled)
    noclipActive = enabled
end

-- Runs inside the master RenderStepped loop each frame
local function noclipTick()
    if not noclipActive then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        local ok, isBase = pcall(function() return part:IsA("BasePart") end)
        if ok and isBase == true then
            local ok2, _ = pcall(function() part.CanCollide = false end)
        end
    end
end

-- ─── ESP target highlight ──────────────────────────────────────────────────

local espEnabled   = false
local espDrawings  = {}
local espTargetPos = nil  -- Vector3 or nil

local function makeEspDrawings()
    -- 4 lines for a ground diamond, 1 vertical line, 1 label
    local d = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 2
        l.Color     = Color3.fromRGB(255, 80, 80)
        l.Visible   = false
        d[i] = l
    end
    -- vertical pillar line
    local pillar = Drawing.new("Line")
    pillar.Thickness = 1
    pillar.Color     = Color3.fromRGB(255, 80, 80)
    pillar.Visible   = false
    d[5] = pillar
    -- label
    local lbl = Drawing.new("Text")
    lbl.Size    = 14
    lbl.Color   = Color3.fromRGB(255, 80, 80)
    lbl.Outline = true
    lbl.Center  = true
    lbl.Visible = false
    d[6] = lbl
    return d
end

espDrawings = makeEspDrawings()

local espConn = nil

local function startEsp()
    if espConn then return end
    local running = true
    espConn = RunService.RenderStepped:Connect(function()
        if not running then return end
        if not espEnabled or not espTargetPos then
            for _, d in ipairs(espDrawings) do d.Visible = false end
            return
        end

        local pos = espTargetPos
        local r   = 3  -- diamond radius

        -- 4 diamond corners at ground level
        local corners3d = {
            Vector3.new(pos.X + r, pos.Y, pos.Z),
            Vector3.new(pos.X - r, pos.Y, pos.Z),
            Vector3.new(pos.X,     pos.Y, pos.Z + r),
            Vector3.new(pos.X,     pos.Y, pos.Z - r),
        }
        local corners2d = {}
        local allOn = true
        for i = 1, 4 do
            local ok, sc, on = pcall(WorldToScreen, corners3d[i])
            if ok and sc and on then
                corners2d[i] = sc
            else
                allOn = false
            end
        end

        -- diamond lines: 0-2, 2-1, 1-3, 3-0  (cross pattern)
        local lineMap = { {1,3},{3,2},{2,4},{4,1} }
        for i = 1, 4 do
            local line = espDrawings[i]
            if allOn then
                local a = corners2d[lineMap[i][1]]
                local b = corners2d[lineMap[i][2]]
                line.From    = a
                line.To      = b
                line.Visible = true
            else
                line.Visible = false
            end
        end

        -- vertical pillar
        local topPos = Vector3.new(pos.X, pos.Y + 8, pos.Z)
        local ok1, sc1, on1 = pcall(WorldToScreen, pos)
        local ok2, sc2, on2 = pcall(WorldToScreen, topPos)
        local pillar = espDrawings[5]
        if ok1 and ok2 and sc1 and sc2 and on1 and on2 then
            pillar.From    = sc1
            pillar.To      = sc2
            pillar.Visible = true
        else
            pillar.Visible = false
        end

        -- label
        local lbl = espDrawings[6]
        if ok2 and sc2 and on2 then
            local nx, ny, nz = pos.X, pos.Y, pos.Z
            lbl.Text     = string.format("TARGET\n%.1f, %.1f, %.1f", nx, ny, nz)
            lbl.Position = Vector2.new(sc2.X, sc2.Y - 18)
            lbl.Visible  = true
        else
            lbl.Visible = false
        end
    end)
end

startEsp()

local function updateEspTarget()
    local nx, ny, nz = getTargetCoords()
    if nx and ny and nz then
        espTargetPos = Vector3.new(nx, ny, nz)
    else
        espTargetPos = nil
    end
end

-- ─── Teleport modes ────────────────────────────────────────────────────────

-- Mode 1: Instant
local function tpInstant(nx, ny, nz)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end
    root.CFrame = CFrame.new(nx, ny, nz)
    root.AssemblyLinearVelocity = Vector3.zero
    notify(string.format("Teleported to %.1f, %.1f, %.1f", nx, ny, nz), "TP GUI", 2)
end

-- Mode 2: Tween — uses flag instead of Disconnect inside callback (Matcha crashes otherwise)
local tweenRunning  = false
local tweenTarget   = nil
local tweenDuration = 3
local tweenElapsed  = 0
local tweenStart    = nil

local function tpTween(nx, ny, nz, duration)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end
    if tweenRunning then notify("Cancel the current tween first.", "TP GUI", 2) return end

    -- enable noclip if toggle is on
    if UI.GetValue("tp_noclip") then setNoclip(true) end

    tweenRunning  = true
    tweenTarget   = Vector3.new(nx, ny, nz)
    tweenDuration = duration
    tweenElapsed  = 0
    tweenStart    = root.Position

    notify(string.format("Tweening to %.1f, %.1f, %.1f (%.1fs)...", nx, ny, nz, duration), "TP GUI", 2)
end

-- Mode 3: Velocity
local velRunning = false
local velTarget  = nil

local function tpVelocity(nx, ny, nz, speed)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end

    local startPos = root.Position
    local dir = Vector3.new(nx - startPos.X, ny - startPos.Y, nz - startPos.Z)
    local mag = math.sqrt(dir.X*dir.X + dir.Y*dir.Y + dir.Z*dir.Z)
    if mag < 0.01 then notify("Already at destination.", "TP GUI", 2) return end

    -- enable noclip if toggle is on
    if UI.GetValue("tp_noclip") then setNoclip(true) end

    local unit = Vector3.new(dir.X/mag, dir.Y/mag, dir.Z/mag)
    root.AssemblyLinearVelocity = Vector3.new(unit.X*speed, unit.Y*speed, unit.Z*speed)

    velRunning = true
    velTarget  = Vector3.new(nx, ny, nz)

    notify(string.format("Launching toward %.1f, %.1f, %.1f...", nx, ny, nz), "TP GUI", 2)
end

-- ─── Master RenderStepped loop ─────────────────────────────────────────────
-- One single loop handles both tween and velocity to avoid stacking connections

local masterRunning = true
RunService.RenderStepped:Connect(function(dt)
    if not masterRunning then return end
	
noclipTick() --work plz
    -- Tween tick
    if tweenRunning and tweenStart and tweenTarget then
        tweenElapsed = tweenElapsed + dt
        local t = tweenElapsed / tweenDuration
        if t > 1 then t = 1 end

        -- Cubic ease-in-out
        local et
        if t < 0.5 then
            et = 4 * t * t * t
        else
            local f = (2 * t) - 2
            et = 1 + (f * f * f) / 2
        end

        local root = getRoot()
        if root then
            root.CFrame = CFrame.new(
                tweenStart.X + (tweenTarget.X - tweenStart.X) * et,
                tweenStart.Y + (tweenTarget.Y - tweenStart.Y) * et,
                tweenStart.Z + (tweenTarget.Z - tweenStart.Z) * et
            )
            root.AssemblyLinearVelocity = Vector3.zero
        end

if t >= 1 then
    tweenRunning = false
    setNoclip(false)   -- add this
    -- restore CanCollide on all parts
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            local ok, isBase = pcall(function() return part:IsA("BasePart") end)
            if ok and isBase == true then
                pcall(function() part.CanCollide = true end)
            end
        end
    end
    local tgt = tweenTarget
    notify(string.format("Arrived at %.1f, %.1f, %.1f", tgt.X, tgt.Y, tgt.Z), "TP GUI", 2)
    tweenTarget = nil
    tweenStart  = nil
end
    end

    -- Velocity arrival check
    if velRunning and velTarget then
        local root = getRoot()
        if root then
            local cur = root.Position
            local dx = cur.X - velTarget.X
            local dy = cur.Y - velTarget.Y
            local dz = cur.Z - velTarget.Z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
if dist < 6 then
    root.CFrame = CFrame.new(velTarget.X, velTarget.Y, velTarget.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    setNoclip(false)   -- add this
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            local ok, isBase = pcall(function() return part:IsA("BasePart") end)
            if ok and isBase == true then
                pcall(function() part.CanCollide = true end)
            end
        end
    end
    velRunning = false
    local tgt = velTarget
    velTarget = nil
    notify(string.format("Arrived at %.1f, %.1f, %.1f", tgt.X, tgt.Y, tgt.Z), "TP GUI", 2)
end
        end
    end
end)

-- ─── Shared dispatch ───────────────────────────────────────────────────────

local function dispatchTP(nx, ny, nz)
    local mode = UI.GetValue("tp_mode")
    if mode == 1 then
        local dur = tonumber(UI.GetValue("tween_time")) or 3
        if dur < 0.1 then dur = 0.1 end
        tpTween(nx, ny, nz, dur)
    elseif mode == 2 then
        local spd = UI.GetValue("velocity_speed") or 150
        tpVelocity(nx, ny, nz, spd)
    else
        tpInstant(nx, ny, nz)
    end
end

-- ─── Path resolver ─────────────────────────────────────────────────────────

local function resolvePath(pathStr)
    if not pathStr or pathStr == "" then return nil, "Empty path" end
    local parts = {}
    for seg in pathStr:gmatch("[^%.]+") do table.insert(parts, seg) end
    if #parts == 0 then return nil, "Invalid path" end
    local roots = {
        Workspace         = game:GetService("Workspace"),
        workspace         = game:GetService("Workspace"),
        game              = game,
        Players           = game:GetService("Players"),
        ReplicatedStorage = game:GetService("ReplicatedStorage"),
    }
    local current  = roots[parts[1]]
    local startIdx = 2
    if not current then
        current = game:GetService("Workspace"):FindFirstChild(parts[1])
        if not current then return nil, "Unknown root: " .. parts[1] end
        startIdx = 2
    end
    for i = startIdx, #parts do
        local child = current:FindFirstChild(parts[i])
        if not child then return nil, "Not found: " .. parts[i] end
        current = child
    end
    return current, nil
end

local function getInstancePosition(inst)
    if not inst then return nil end
    local ok, pos = pcall(function() return inst.Position end)
    if ok and pos and typeof(pos) == "Vector3" then return pos end
    local ok2, pp = pcall(function() return inst.PrimaryPart end)
    if ok2 and pp then
        local ok3, p3 = pcall(function() return pp.Position end)
        if ok3 and p3 then return p3 end
    end
    for _, child in ipairs(inst:GetDescendants()) do
        local ok4, p4 = pcall(function() return child.Position end)
        if ok4 and p4 and typeof(p4) == "Vector3" then return p4 end
    end
    return nil
end

-- ─── Preset helpers ────────────────────────────────────────────────────────

local presetCombo = nil

local function getPresetNames()
    local names = {}
    for _, p in ipairs(presets) do table.insert(names, p.name) end
    if #names == 0 then table.insert(names, "(no presets)") end
    return names
end

local function refreshCombo()
    if not presetCombo then return end
    presetCombo:Clear()
    for _, n in ipairs(getPresetNames()) do presetCombo:Add(n) end
end

-- ─── UI ────────────────────────────────────────────────────────────────────

UI.AddTab("Teleport", function(tab)

    -- ════════════════ LEFT COLUMN ════════════════

    -- ── Mode + settings ─────────────────────────
    local modeSec = tab:Section("Mode", "Left")

    modeSec:Combo("tp_mode", "Mode", {"Instant", "Tween", "Velocity"}, 1, function(_) end)
    modeSec:Tip("Instant: snap  |  Tween: smooth glide  |  Velocity: physics launch")

    modeSec:SliderFloat("tween_time",     "Tween Time (s)",   0.5, 30,   3,   "%.1f", function(_) end)
    modeSec:Tip("Duration of tween. Only used in Tween mode.")

    modeSec:SliderInt("velocity_speed", "Velocity Speed",  10,  2000, 150,        function(_) end)
    modeSec:Tip("Launch speed in studs/s. Only used in Velocity mode.")

    modeSec:Button("Cancel Tween / Stop Velocity", function()
        local didSomething = false
        if tweenRunning then
            tweenRunning = false
            tweenTarget  = nil
            tweenStart   = nil
            didSomething = true
        end
        if velRunning then
            velRunning = false
            velTarget  = nil
            local root = getRoot()
            if root then root.AssemblyLinearVelocity = Vector3.zero end
            didSomething = true
        end
        notify(didSomething and "Stopped." or "Nothing was running.", "TP GUI", 2)
    end)
	-- NOCLIP
modeSec:Toggle("tp_noclip", "Noclip During Movement", false, function(val)
    -- if manually toggled off while moving, restore collision immediately
    if not val then
        setNoclip(false)
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                local ok, isBase = pcall(function() return part:IsA("BasePart") end)
                if ok and isBase == true then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
    end
end)
modeSec:Tip("Disables collision on your character during Tween/Velocity. Auto-restores on arrival.")

    -- ── Coordinates ─────────────────────────────
    local coordSec = tab:Section("Coordinates", "Left")

    coordSec:InputText("tp_x", "X", "0",  function(_) updateEspTarget() end)
    coordSec:InputText("tp_y", "Y", "50", function(_) updateEspTarget() end)
    coordSec:InputText("tp_z", "Z", "0",  function(_) updateEspTarget() end)
    coordSec:Spacing()

    coordSec:Button("Teleport", function()
        local nx, ny, nz = getTargetCoords()
        if not nx or not ny or not nz then
            notify("Invalid coordinates — numbers only.", "TP GUI", 3)
            return
        end
        dispatchTP(nx, ny, nz)
    end)

    coordSec:Button("Grab My Position", function()
        local root = getRoot()
        if not root then notify("No character found.", "TP GUI", 2) return end
        local pos = root.Position
        UI.SetValue("tp_x", string.format("%.2f", pos.X))
        UI.SetValue("tp_y", string.format("%.2f", pos.Y))
        UI.SetValue("tp_z", string.format("%.2f", pos.Z))
        updateEspTarget()
        notify("Fields filled with your current position.", "TP GUI", 2)
    end)
    coordSec:Tip("Fills X/Y/Z with your current world position")

    -- ── Path teleport ────────────────────────────
    local pathSec = tab:Section("Path Teleport", "Left")

    pathSec:Text("e.g. Workspace.Map.SpawnPoint")
    pathSec:InputText("tp_path", "Path", "Workspace.", function(_) end)
    pathSec:Spacing()

    pathSec:Button("Teleport to Path", function()
        local inst, err = resolvePath(UI.GetValue("tp_path"))
        if not inst then notify("Path error: " .. (err or "?"), "TP GUI", 4) return end
        local pos = getInstancePosition(inst)
        if not pos then notify("Instance has no readable Position.", "TP GUI", 3) return end
        dispatchTP(pos.X, pos.Y + 3, pos.Z)
    end)
    pathSec:Tip("+3 Y offset so you land on top, not inside")

    pathSec:Button("Copy Path to X/Y/Z Fields", function()
        local inst, err = resolvePath(UI.GetValue("tp_path"))
        if not inst then notify("Path error: " .. (err or "?"), "TP GUI", 4) return end
        local pos = getInstancePosition(inst)
        if not pos then notify("Instance has no readable Position.", "TP GUI", 3) return end
        UI.SetValue("tp_x", string.format("%.2f", pos.X))
        UI.SetValue("tp_y", string.format("%.2f", pos.Y + 3))
        UI.SetValue("tp_z", string.format("%.2f", pos.Z))
        updateEspTarget()
        notify("Coordinates copied to X/Y/Z fields.", "TP GUI", 2)
    end)

    -- ════════════════ RIGHT COLUMN ════════════════

    -- ── ESP ─────────────────────────────────────
    local espSec = tab:Section("Target ESP", "Right")

    espSec:Toggle("esp_enabled", "Show Target Marker", false, function(val)
        espEnabled = val
        if not val then
            for _, d in ipairs(espDrawings) do d.Visible = false end
        else
            updateEspTarget()
        end
    end)
    espSec:Tip("Draws a marker at the X/Y/Z target position")

    espSec:Button("Refresh ESP Target", function()
        updateEspTarget()
        notify("ESP target updated.", "TP GUI", 2)
    end)
    espSec:Tip("Press after changing X/Y/Z if the marker didn't move")

    -- ── Presets ──────────────────────────────────
    local presetSec = tab:Section("Presets", "Right")

    presetSec:InputText("preset_name", "Name", "MySpot", function(_) end)

    presetSec:Button("Save X/Y/Z as Preset", function()
        local name = UI.GetValue("preset_name")
        if not name or name == "" then
            notify("Enter a preset name first.", "TP GUI", 3)
            return
        end
        local nx, ny, nz = getTargetCoords()
        if not nx or not ny or not nz then
            notify("Fill in valid X/Y/Z coordinates first.", "TP GUI", 3)
            return
        end
        local found = false
        for _, p in ipairs(presets) do
            if p.name == name then
                p.x = nx; p.y = ny; p.z = nz
                found = true
                break
            end
        end
        if not found then
            table.insert(presets, { name = name, x = nx, y = ny, z = nz })
        end
        savePresets(presets)
        refreshCombo()
        notify("Saved preset: " .. name, "TP GUI", 2)
    end)

    presetSec:Spacing()

    presetCombo = presetSec:Combo(
        "preset_select", "Saved Presets", getPresetNames(), 1, function(_) end
    )

    presetSec:Button("Teleport to Selected", function()
        local idx = UI.GetValue("preset_select")
        if not idx or #presets == 0 then notify("No presets saved yet.", "TP GUI", 3) return end
        local preset = presets[idx + 1]
        if not preset then notify("Invalid selection.", "TP GUI", 2) return end
        UI.SetValue("tp_x", string.format("%.2f", preset.x))
        UI.SetValue("tp_y", string.format("%.2f", preset.y))
        UI.SetValue("tp_z", string.format("%.2f", preset.z))
        updateEspTarget()
        dispatchTP(preset.x, preset.y, preset.z)
    end)

    presetSec:Button("Load into X/Y/Z", function()
        local idx = UI.GetValue("preset_select")
        if not idx or #presets == 0 then notify("No presets saved yet.", "TP GUI", 3) return end
        local preset = presets[idx + 1]
        if not preset then return end
        UI.SetValue("tp_x", string.format("%.2f", preset.x))
        UI.SetValue("tp_y", string.format("%.2f", preset.y))
        UI.SetValue("tp_z", string.format("%.2f", preset.z))
        updateEspTarget()
        notify("Loaded: " .. preset.name, "TP GUI", 2)
    end)

    presetSec:Button("Delete Selected", function()
        local idx = UI.GetValue("preset_select")
        if not idx or #presets == 0 then notify("No presets to delete.", "TP GUI", 2) return end
        local preset = presets[idx + 1]
        if not preset then return end
        local name = preset.name
        table.remove(presets, idx + 1)
        savePresets(presets)
        refreshCombo()
        notify("Deleted: " .. name, "TP GUI", 2)
    end)

end)

notify("Teleport GUI loaded!", "TP GUI", 3)
