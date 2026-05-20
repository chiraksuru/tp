--!nonstrict
local Players        = game:GetService("Players")
local HttpService    = game:GetService("HttpService")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

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

local function getMouseWorldPosition()
    local mouse = LocalPlayer:GetMouse()
    if not mouse then
        return nil
    end

    local hit = mouse.Hit
    if not hit then
        return nil
    end

    return hit.Position
end

local noclipActive = false

local function setNoclip(enabled)
    noclipActive = enabled
end

local function restoreCollision()
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        local ok, isBase = pcall(function() return part:IsA("BasePart") end)
        if ok and isBase == true then
            pcall(function() part.CanCollide = true end)
        end
    end
end

local function noclipTick()
    if not noclipActive then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        local ok, isBase = pcall(function() return part:IsA("BasePart") end)
        if ok and isBase == true then
            pcall(function() part.CanCollide = false end)
        end
    end
end

local espEnabled   = false
local espColor     = Color3.fromRGB(255, 80, 80)
local espDrawings  = {}
local espTargetPos = nil

local function makeEspDrawings()
    local d = {}
    for i = 1, 4 do
        local l        = Drawing.new("Line")
        l.Thickness    = 2
        l.Color        = espColor
        l.Visible      = false
        d[i]           = l
    end
    local pillar       = Drawing.new("Line")
    pillar.Thickness   = 1
    pillar.Color       = espColor
    pillar.Visible     = false
    d[5]               = pillar
    local lbl          = Drawing.new("Text")
    lbl.Size           = 14
    lbl.Color          = espColor
    lbl.Outline        = true
    lbl.Center         = true
    lbl.Visible        = false
    d[6]               = lbl
    return d
end

espDrawings = makeEspDrawings()

local function updateEspColors()
    for i = 1, 5 do
        espDrawings[i].Color = espColor
    end
    espDrawings[6].Color = espColor
end

local espConn = nil

local function startEsp()
    if espConn then return end
    espConn = RunService.RenderStepped:Connect(function()
        if not espEnabled or not espTargetPos then
            for _, d in ipairs(espDrawings) do d.Visible = false end
            return
        end

        local pos = espTargetPos
        local r   = 3

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

        local lineMap = { {1,3},{3,2},{2,4},{4,1} }
        for i = 1, 4 do
            local line = espDrawings[i]
            if allOn then
                line.From    = corners2d[lineMap[i][1]]
                line.To      = corners2d[lineMap[i][2]]
                line.Visible = true
            else
                line.Visible = false
            end
        end

        local topPos         = Vector3.new(pos.X, pos.Y + 8, pos.Z)
        local ok1, sc1, on1  = pcall(WorldToScreen, pos)
        local ok2, sc2, on2  = pcall(WorldToScreen, topPos)
        local pillar         = espDrawings[5]
        if ok1 and ok2 and sc1 and sc2 and on1 and on2 then
            pillar.From    = sc1
            pillar.To      = sc2
            pillar.Visible = true
        else
            pillar.Visible = false
        end

        local lbl = espDrawings[6]
        if ok2 and sc2 and on2 then
            lbl.Text     = string.format("TARGET  %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
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

local function tpInstant(nx, ny, nz)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end
    root.CFrame = CFrame.new(nx, ny, nz)
    root.AssemblyLinearVelocity = Vector3.zero
    notify(string.format("Teleported to %.1f, %.1f, %.1f", nx, ny, nz), "TP GUI", 2)
end

local tweenRunning  = false
local tweenTarget   = nil
local tweenDuration = 3
local tweenElapsed  = 0
local tweenStart    = nil

local function tpTween(nx, ny, nz, duration)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end
    if tweenRunning then notify("Cancel the current tween first.", "TP GUI", 2) return end
    if UI.GetValue("tp_noclip") then setNoclip(true) end
    tweenRunning  = true
    tweenTarget   = Vector3.new(nx, ny, nz)
    tweenDuration = duration
    tweenElapsed  = 0
    tweenStart    = root.Position
    notify(string.format("Tweening to %.1f, %.1f, %.1f  (%.1fs)", nx, ny, nz, duration), "TP GUI", 2)
end

local velRunning = false
local velTarget  = nil

local function tpVelocity(nx, ny, nz, speed)
    local root = getRoot()
    if not root then notify("No HumanoidRootPart found.", "TP GUI", 2) return end
    local startPos = root.Position
    local dir      = Vector3.new(nx - startPos.X, ny - startPos.Y, nz - startPos.Z)
    local mag      = math.sqrt(dir.X*dir.X + dir.Y*dir.Y + dir.Z*dir.Z)
    if mag < 0.01 then notify("Already at destination.", "TP GUI", 2) return end
    if UI.GetValue("tp_noclip") then setNoclip(true) end
    velRunning = true
    velTarget  = Vector3.new(nx, ny, nz)
    notify(string.format("Launching toward %.1f, %.1f, %.1f", nx, ny, nz), "TP GUI", 2)
end

local masterRunning = true
RunService.RenderStepped:Connect(function(dt)
    if not masterRunning then return end

    noclipTick()

    if tweenRunning and tweenStart and tweenTarget then
        tweenElapsed = tweenElapsed + dt
        local t = tweenElapsed / tweenDuration
        if t > 1 then t = 1 end

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
            setNoclip(false)
            restoreCollision()
            local tgt = tweenTarget
            tweenTarget = nil
            tweenStart  = nil
            notify(string.format("Arrived at %.1f, %.1f, %.1f", tgt.X, tgt.Y, tgt.Z), "TP GUI", 2)
        end
    end

    if velRunning and velTarget then
        local root = getRoot()
        if root then
            local cur  = root.Position
            local dx   = velTarget.X - cur.X
            local dy   = velTarget.Y - cur.Y
            local dz   = velTarget.Z - cur.Z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            if dist < 4 then
                root.CFrame = CFrame.new(velTarget.X, velTarget.Y, velTarget.Z)
                root.AssemblyLinearVelocity = Vector3.zero
                setNoclip(false)
                restoreCollision()
                velRunning = false
                local tgt  = velTarget
                velTarget  = nil
                notify(string.format("Arrived at %.1f, %.1f, %.1f", tgt.X, tgt.Y, tgt.Z), "TP GUI", 2)
            else
                local speed = UI.GetValue("velocity_speed") or 150
                local overshoot = UI.GetValue("velocity_overshoot")
                
                -- Bypasses clamp checks entirely if overshoot option is toggled on
                local currentForce = overshoot and speed or math.min(dist, speed)
                local unit = Vector3.new(dx/dist, dy/dist, dz/dist)
                
                root.AssemblyLinearVelocity = Vector3.new(
                    unit.X * currentForce,
                    unit.Y * currentForce,
                    unit.Z * currentForce
                )
            end
        end
    end
end)

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

-- Mouse positioning selection hook

local mouseHookConnection = nil
local function listenForMouseClick()
    if mouseHookConnection then mouseHookConnection:Disconnect() end
    
    local mouse = LocalPlayer:GetMouse()
    if not mouse then 
        notify("Mouse object not available.", "TP GUI", 3) 
        return 
    end
    
    notify("Click anywhere in the game world to select target location...", "TP GUI", 4)
    
    mouseHookConnection = mouse.Button1Down:Connect(function()
        -- Disconnect immediately so future normal clicks don't re-trigger it
        if mouseHookConnection then
            mouseHookConnection:Disconnect()
            mouseHookConnection = nil
        end
        
        local pos = getMouseWorldPosition()
        if not pos then
            notify("Could not grab click position.", "TP GUI", 3)
            return
        end
        
        UI.SetValue("tp_x", string.format("%.2f", pos.X))
        UI.SetValue("tp_y", string.format("%.2f", pos.Y))
        UI.SetValue("tp_z", string.format("%.2f", pos.Z))
        updateEspTarget()
        notify(string.format("Grabbed coordinate: %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z), "TP GUI", 2)
    end)
end

UI.AddTab("Teleport", function(tab)

    local modeSec = tab:Section("Mode", "Left")

    modeSec:Combo("tp_mode", "Mode", {"Instant", "Tween", "Velocity"}, 1, function(_) end)
    modeSec:Tip("Instant: snap  |  Tween: smooth glide  |  Velocity: physics launch")
    modeSec:SliderFloat("tween_time",    "Tween Time (s)",  0.5, 30,   3,   "%.1f", function(_) end)
    modeSec:Tip("Only used in Tween mode.")
    modeSec:SliderInt("velocity_speed",  "Velocity Speed",  10,  2000, 150,          function(_) end)
    modeSec:Toggle("velocity_overshoot", "Disable Force Clamping (Overshoot)", false, function(_) end)
    modeSec:Tip("Bypasses dampening close to arrival to fling character through destinations.")
    modeSec:Button("Cancel / Stop", function()
        local did = false
        if tweenRunning then
            tweenRunning = false
            tweenTarget  = nil
            tweenStart   = nil
            did          = true
        end
        if velRunning then
            velRunning = false
            velTarget  = nil
            local root = getRoot()
            if root then root.AssemblyLinearVelocity = Vector3.zero end
            did = true
        end
        setNoclip(false)
        restoreCollision()
        notify(did and "Stopped." or "Nothing running.", "TP GUI", 2)
    end)
    modeSec:Toggle("tp_noclip", "Noclip During Movement", false, function(val)
        if not val then
            setNoclip(false)
            restoreCollision()
        end
    end)
    modeSec:Tip("Disables collision while moving. Auto-restores on arrival.")

    local coordSec = tab:Section("Coordinates", "Left")

    coordSec:InputText("tp_x", "X", "0",  function(_) updateEspTarget() end)
    coordSec:InputText("tp_y", "Y", "50", function(_) updateEspTarget() end)
    coordSec:InputText("tp_z", "Z", "0",  function(_) updateEspTarget() end)
    coordSec:Spacing()
    coordSec:Button("Teleport", function()
        local nx, ny, nz = getTargetCoords()
        if not nx or not ny or not nz then
            notify("Invalid coordinates.", "TP GUI", 3)
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
        notify("Fields filled with current position.", "TP GUI", 2)
    end)
    coordSec:Button("Grab Mouse Position", function()
        listenForMouseClick()
    end)
    coordSec:Tip("Fills X/Y/Z with your next click target in the game world")

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
    pathSec:Tip("+3 Y so you land on top, not inside")
    pathSec:Button("Copy Path to X/Y/Z", function()
        local inst, err = resolvePath(UI.GetValue("tp_path"))
        if not inst then notify("Path error: " .. (err or "?"), "TP GUI", 4) return end
        local pos = getInstancePosition(inst)
        if not pos then notify("Instance has no readable Position.", "TP GUI", 3) return end
        UI.SetValue("tp_x", string.format("%.2f", pos.X))
        UI.SetValue("tp_y", string.format("%.2f", pos.Y + 3))
        UI.SetValue("tp_z", string.format("%.2f", pos.Z))
        updateEspTarget()
        notify("Copied to X/Y/Z fields.", "TP GUI", 2)
    end)

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
    espSec:ColorPicker("esp_color", 255, 80, 80, 255, function(r, g, b, a)
        espColor = Color3.new(r, g, b)
        updateEspColors()
    end)
    espSec:Tip("Color of the target ESP marker")
    espSec:Button("Refresh ESP Target", function()
        updateEspTarget()
        notify("ESP target updated.", "TP GUI", 2)
    end)

    local presetSec = tab:Section("Presets", "Right")

    presetSec:InputText("preset_name", "Name", "MySpot", function(_) end)
    presetSec:Button("Save X/Y/Z as Preset", function()
        local name = UI.GetValue("preset_name")
        if not name or name == "" then notify("Enter a preset name first.", "TP GUI", 3) return end
        local nx, ny, nz = getTargetCoords()
        if not nx or not ny or not nz then notify("Fill in valid X/Y/Z first.", "TP GUI", 3) return end
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
        notify("Saved: " .. name, "TP GUI", 2)
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
