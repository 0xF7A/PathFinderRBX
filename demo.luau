-- Pathfinder Demo GUI
-- Place this in a LocalScript inside StarterPlayerScripts or StarterGui

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Pathfinder = loadstring(game:HttpGet("https://raw.githubusercontent.com/0xF7A/PathFinderRBX/refs/heads/main/main.luau"))
local pf = Pathfinder.new()

local Window = Library:CreateWindow({
    Title = "Pathfinder Demo",
    Footer = "API Demonstration",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Main = Window:AddTab("Pathfinder", "map-pin"),
    UISettings = Window:AddTab("UI Settings", "settings"),
}

-- ====================== Waypoint Management UI ======================
local WaypointGroup = Tabs.Main:AddLeftGroupbox("Waypoints")

-- Permanent buttons
WaypointGroup:AddButton({
    Text = "Add Waypoint (Current Position)",
    Func = function()
        if pf:AddWaypoint() then
            Library:Notify("Waypoint added", 2)
            refreshWaypointList()
        else
            Library:Notify("Character not found", 2)
        end
    end,
    Tooltip = "Add current position as a new waypoint",
})

WaypointGroup:AddButton({
    Text = "Clear All Waypoints",
    Func = function()
        pf:ClearWaypoints()
        refreshWaypointList()
        Library:Notify("All waypoints cleared", 2)
    end,
    Tooltip = "Remove all waypoints and stop movement",
})

-- Dynamic waypoint list (will be refreshed)
local WaypointListElements = {} -- store UI elements for cleanup

local function refreshWaypointList()
    -- Remove old elements
    for _, elem in ipairs(WaypointListElements) do
        pcall(function() elem:Remove() end)
    end
    WaypointListElements = {}

    local waypoints = pf:GetWaypoints()
    if #waypoints == 0 then
        local label = WaypointGroup:AddLabel("No waypoints set.", true)
        table.insert(WaypointListElements, label)
        return
    end

    for i, wp in ipairs(waypoints) do
        local pos = wp.Position
        local text = string.format("%d: (%.1f, %.1f, %.1f)", i, pos.X, pos.Y, pos.Z)
        local label = WaypointGroup:AddLabel(text, false, "WPLabel_" .. i)
        table.insert(WaypointListElements, label)

        local removeBtn = WaypointGroup:AddButton({
            Text = "Remove Waypoint " .. i,
            Func = function()
                pf:RemoveWaypoint(i)
                refreshWaypointList()
                Library:Notify("Waypoint " .. i .. " removed", 2)
            end,
            Tooltip = "Remove this waypoint",
        })
        table.insert(WaypointListElements, removeBtn)
    end
end

-- Initial refresh
refreshWaypointList()

-- ====================== Controls ======================
local ControlGroup = Tabs.Main:AddRightGroupbox("Controls")

-- Looping toggle
ControlGroup:AddToggle("LoopingToggle", {
    Text = "Enable Looping",
    Default = false,
    Tooltip = "Repeat the path from start after reaching the last waypoint",
    Callback = function(v) pf:SetLooping(v) end,
})

-- Show User Path Tracer toggle
ControlGroup:AddToggle("UserTracerToggle", {
    Text = "Show User Path Tracer",
    Default = false,
    Tooltip = "Display green line between user-defined waypoints",
    Callback = function(v) pf:ShowUserPathTracer(v) end,
})

-- Show Computed Tracer toggle
ControlGroup:AddToggle("ComputedTracerToggle", {
    Text = "Show Computed Path Tracer",
    Default = false,
    Tooltip = "Display blue line of the actual pathfinding route",
    Callback = function(v) pf:ShowCalculatedTracer(v) end,
})

-- Force Find toggle
ControlGroup:AddToggle("ForceFindToggle", {
    Text = "Force Find Path (Never Skip)",
    Default = true,
    Tooltip = "If enabled, retry waypoint forever until reached; if disabled, skip on failure",
    Callback = function(v) pf:SetForceFindPath(v) end,
})

-- Calculation Timeout slider
ControlGroup:AddSlider("TimeoutSlider", {
    Text = "Stuck Timeout (seconds)",
    Default = 5,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Compact = false,
    Tooltip = "Seconds without movement before recalculating path",
    Callback = function(v) pf:SetCalculationTimeout(v) end,
})

-- Start/Stop buttons
ControlGroup:AddButton({
    Text = "Start Path",
    Func = function()
        pf:SetWalkingEnabled(true)
    end,
    Tooltip = "Start moving along the waypoints",
})

ControlGroup:AddButton({
    Text = "Stop Path",
    Func = function()
        pf:SetWalkingEnabled(false)
    end,
    Tooltip = "Stop movement",
})

-- Progress display
local ProgressLabel = ControlGroup:AddLabel("Progress: Not moving", true, "ProgressLabel")

-- Custom line color examples (optional)
ControlGroup:AddDivider()
ControlGroup:AddLabel("Customize Tracer Colors (optional)")

ControlGroup:AddButton({
    Text = "Set User Tracer → Red",
    Func = function()
        pf:SetUserTracer({ Color = Color3.new(1, 0, 0) })
        Library:Notify("User tracer color set to red", 2)
    end,
})

ControlGroup:AddButton({
    Text = "Set Computed Tracer → Yellow",
    Func = function()
        pf:SetComputedLine({ Color = Color3.new(1, 1, 0) })
        Library:Notify("Computed tracer color set to yellow", 2)
    end,
})

ControlGroup:AddButton({
    Text = "Reset Tracers to Default",
    Func = function()
        pf:SetUserTracer({ Color = Color3.new(0, 1, 0), Thickness = 2, Transparency = 0.5 })
        pf:SetComputedLine({ Color = Color3.new(0, 0, 1), Thickness = 2, Transparency = 0.3 })
        Library:Notify("Tracer colors reset", 2)
    end,
})

-- ====================== Event Callbacks ======================
pf:OnWaypointReached(function(idx, cframe)
    Library:Notify(string.format("Reached waypoint %d", idx), 2)
end)

pf:OnPathCompleted(function()
    Library:Notify("Path completed!", 3)
end)

pf:OnStuck(function()
    Library:Notify("Character stuck – recalculating...", 2)
end)

-- ====================== Progress Updater ======================
task.spawn(function()
    while true do
        task.wait(0.5)
        local prog = pf:GetProgress()
        if prog.isMoving then
            ProgressLabel:SetText(string.format("Progress: %d/%d waypoints", prog.currentIndex, prog.total))
        else
            ProgressLabel:SetText("Progress: Not moving")
        end
    end
end)

-- ====================== UI Settings Tab ======================
local MenuGroup = Tabs.UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(v) Library.KeybindFrame.Visible = v end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(v) Library.ShowCustomCursor = v end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(v) Library:SetNotifySide(v) end,
})
MenuGroup:AddButton("Unload", function()
    pf:Destroy() -- clean up pathfinder lines
    Library:Unload()
end)

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

-- Clean up on unload (in case user clicks Unload)
Library:OnUnload(function()
    pf:Destroy()
end)

-- ThemeManager and SaveManager (optional)
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("PathfinderDemo")
SaveManager:SetFolder("PathfinderDemo")
SaveManager:BuildConfigSection(Tabs.UISettings)
ThemeManager:ApplyToTab(Tabs.UISettings)

-- Load autoload config
SaveManager:LoadAutoloadConfig()
