-- Pathfinder Module
-- Place in ReplicatedStorage as a ModuleScript
-- Provides API for dynamic waypoint pathfinding with visual tracers

local Pathfinder = {}
Pathfinder.__index = Pathfinder

-- Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

-- Private variables (will be set per instance)
local Player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Character access helpers
local function getCharacter()
    return Player.Character
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChild("Humanoid")
end

local function getRootPart()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Update camera if it changes
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    camera = workspace.CurrentCamera
end)

-- Constructor
function Pathfinder.new()
    local self = setmetatable({}, Pathfinder)

    -- Waypoint storage
    self.Waypoints = {}  -- array of CFrame

    -- State
    self.IsMoving = false
    self.IsLooping = false
    self.ForceFindPath = true   -- retry forever (default)
    self.ShowUserPathLine = false
    self.ShowComputedPathLine = false
    self.MovementCoroutine = nil

    -- Progress tracking
    self.CurrentWaypointIndex = 0
    self.TotalWaypoints = 0

    -- Current computed path (for visualization)
    self.CurrentPathWaypoints = {}  -- array of Vector3

    -- Line customisation settings
    self.UserLineSettings = {
        Color = Color3.new(0, 1, 0),  -- green
        Thickness = 2,
        Transparency = 0.5,
    }
    self.ComputedLineSettings = {
        Color = Color3.new(0, 0, 1),  -- blue
        Thickness = 2,
        Transparency = 0.3,
    }

    -- Drawing objects
    self.UserPathLines = {}      -- green lines
    self.ComputedPathLines = {}  -- blue lines
    self.LineRenderConnection = nil

    -- Callbacks
    self._waypointReachedCallbacks = {}
    self._pathCompletedCallbacks = {}
    self._stuckCallbacks = {}

    -- Stuck detection parameters (adjustable)
    self.StuckThreshold = 5       -- seconds
    self.MoveThreshold = 0.2      -- studs per frame to count as moving

    -- Character size (updated on respawn)
    self.AgentRadius = 2
    self.AgentHeight = 5
    self:_updateCharacterSize()

    -- Connect to character added to update size
    Player.CharacterAdded:Connect(function()
        self:_updateCharacterSize()
    end)

    return self
end

-- Private: update character size for pathfinding agent
function Pathfinder:_updateCharacterSize()
    local char = getCharacter()
    if not char then return end
    local size = Vector3.new(2, 5, 1) -- default
    local success, cf, sizeVec = pcall(function()
        return char:GetBoundingBox()
    end)
    if success then
        size = sizeVec
    end
    local radius = math.max(size.X, size.Z) / 2
    local height = size.Y
    self.AgentRadius = math.max(radius, 2)
    self.AgentHeight = math.max(height, 5)
end

-- Private: ensure render connection for drawing lines
function Pathfinder:_ensureRenderConnection()
    if not self.LineRenderConnection then
        self.LineRenderConnection = RunService.RenderStepped:Connect(function()
            self:_updateLinePositions()
        end)
    end
end

-- Private: update line positions each frame (WorldToScreen with behind-camera hiding)
function Pathfinder:_updateLinePositions()
    -- User path lines (green)
    if self.ShowUserPathLine and #self.UserPathLines > 0 then
        for i = 1, #self.Waypoints - 1 do
            local line = self.UserPathLines[i]
            if line then
                local fromPos = self.Waypoints[i].Position
                local toPos = self.Waypoints[i + 1].Position

                local fromVec = camera:WorldToViewportPoint(fromPos)
                local toVec = camera:WorldToViewportPoint(toPos)

                if fromVec.Z < 0 or toVec.Z < 0 then
                    line.Visible = false
                else
                    line.Visible = true
                    line.From = Vector2.new(fromVec.X, fromVec.Y)
                    line.To = Vector2.new(toVec.X, toVec.Y)
                end
            end
        end
    end

    -- Computed path lines (blue)
    if self.ShowComputedPathLine and #self.ComputedPathLines > 0 and #self.CurrentPathWaypoints > 1 then
        for i = 1, #self.CurrentPathWaypoints - 1 do
            local line = self.ComputedPathLines[i]
            if line then
                local fromPos = self.CurrentPathWaypoints[i]
                local toPos = self.CurrentPathWaypoints[i + 1]

                local fromVec = camera:WorldToViewportPoint(fromPos)
                local toVec = camera:WorldToViewportPoint(toPos)

                if fromVec.Z < 0 or toVec.Z < 0 then
                    line.Visible = false
                else
                    line.Visible = true
                    line.From = Vector2.new(fromVec.X, fromVec.Y)
                    line.To = Vector2.new(toVec.X, toVec.Y)
                end
            end
        end
    end
end

-- Private: refresh user path lines
function Pathfinder:_refreshUserPathLines()
    for _, line in ipairs(self.UserPathLines) do
        pcall(function() line:Remove() end)
    end
    self.UserPathLines = {}

    if not self.ShowUserPathLine or #self.Waypoints < 2 then return end

    for i = 1, #self.Waypoints - 1 do
        local line = Drawing.new("Line")
        line.Thickness = self.UserLineSettings.Thickness
        line.Color = self.UserLineSettings.Color
        line.Transparency = self.UserLineSettings.Transparency
        line.Visible = true
        line.From = Vector2.new(0, 0)
        line.To = Vector2.new(0, 0)
        table.insert(self.UserPathLines, line)
    end
end

-- Private: refresh computed path lines
function Pathfinder:_refreshComputedPathLines()
    for _, line in ipairs(self.ComputedPathLines) do
        pcall(function() line:Remove() end)
    end
    self.ComputedPathLines = {}

    if not self.ShowComputedPathLine or #self.CurrentPathWaypoints < 2 then return end

    for i = 1, #self.CurrentPathWaypoints - 1 do
        local line = Drawing.new("Line")
        line.Thickness = self.ComputedLineSettings.Thickness
        line.Color = self.ComputedLineSettings.Color
        line.Transparency = self.ComputedLineSettings.Transparency
        line.Visible = true
        line.From = Vector2.new(0, 0)
        line.To = Vector2.new(0, 0)
        table.insert(self.ComputedPathLines, line)
    end
end

-- ====================== PUBLIC API ======================

-- Add a waypoint at the current character position or specified CFrame
function Pathfinder:AddWaypoint(cframe)
    cframe = cframe or (getRootPart() and getRootPart().CFrame)
    if not cframe then
        warn("Pathfinder: Cannot add waypoint - character not found")
        return false
    end
    table.insert(self.Waypoints, cframe)
    self:_refreshUserPathLines()
    self:_ensureRenderConnection()
    return true
end

-- Remove a waypoint by index
function Pathfinder:RemoveWaypoint(index)
    if index < 1 or index > #self.Waypoints then return false end
    table.remove(self.Waypoints, index)
    self:_refreshUserPathLines()
    return true
end

-- Clear all waypoints
function Pathfinder:ClearWaypoints()
    self.Waypoints = {}
    self:_refreshUserPathLines()
    self:SetWalkingEnabled(false)
end

-- Get current waypoints list (read‑only copy)
function Pathfinder:GetWaypoints()
    return { unpack(self.Waypoints) }
end

-- Set looping mode
function Pathfinder:SetLooping(enabled)
    self.IsLooping = enabled
end

-- Enable/disable user path tracer (green line) with custom settings (optional)
function Pathfinder:ShowUserPathTracer(enabled, settings)
    if settings then
        self.UserLineSettings.Color = settings.Color or self.UserLineSettings.Color
        self.UserLineSettings.Thickness = settings.Thickness or self.UserLineSettings.Thickness
        self.UserLineSettings.Transparency = settings.Transparency or self.UserLineSettings.Transparency
    end
    self.ShowUserPathLine = enabled
    if enabled then
        self:_refreshUserPathLines()
    else
        for _, line in ipairs(self.UserPathLines) do
            pcall(function() line:Remove() end)
        end
        self.UserPathLines = {}
    end
    self:_ensureRenderConnection()
end

-- Enable/disable computed path tracer (blue line) with custom settings (optional)
function Pathfinder:ShowCalculatedTracer(enabled, settings)
    if settings then
        self.ComputedLineSettings.Color = settings.Color or self.ComputedLineSettings.Color
        self.ComputedLineSettings.Thickness = settings.Thickness or self.ComputedLineSettings.Thickness
        self.ComputedLineSettings.Transparency = settings.Transparency or self.ComputedLineSettings.Transparency
    end
    self.ShowComputedPathLine = enabled
    if enabled then
        self:_refreshComputedPathLines()
    else
        for _, line in ipairs(self.ComputedPathLines) do
            pcall(function() line:Remove() end)
        end
        self.ComputedPathLines = {}
    end
    self:_ensureRenderConnection()
end

-- Set custom appearance for computed line (applies next refresh)
function Pathfinder:SetComputedLine(settings)
    self.ComputedLineSettings.Color = settings.Color or self.ComputedLineSettings.Color
    self.ComputedLineSettings.Thickness = settings.Thickness or self.ComputedLineSettings.Thickness
    self.ComputedLineSettings.Transparency = settings.Transparency or self.ComputedLineSettings.Transparency
    if self.ShowComputedPathLine then
        self:_refreshComputedPathLines()
    end
end

-- Set custom appearance for user tracer (applies next refresh)
function Pathfinder:SetUserTracer(settings)
    self.UserLineSettings.Color = settings.Color or self.UserLineSettings.Color
    self.UserLineSettings.Thickness = settings.Thickness or self.UserLineSettings.Thickness
    self.UserLineSettings.Transparency = settings.Transparency or self.UserLineSettings.Transparency
    if self.ShowUserPathLine then
        self:_refreshUserPathLines()
    end
end

-- Get current progress: index of current waypoint, total count, and moving status
function Pathfinder:GetProgress()
    return {
        currentIndex = self.CurrentWaypointIndex,
        total = #self.Waypoints,
        isMoving = self.IsMoving,
        currentWaypoint = self.Waypoints[self.CurrentWaypointIndex],
    }
end

-- Set force‑find mode: if true, retry a waypoint forever until reached; if false, skip after one failure
function Pathfinder:SetForceFindPath(enabled)
    self.ForceFindPath = enabled
end

-- Set stuck detection timeout (seconds before recalculating)
function Pathfinder:SetCalculationTimeout(seconds)
    self.StuckThreshold = seconds
end

-- Start/stop walking
function Pathfinder:SetWalkingEnabled(enabled)
    if enabled == self.IsMoving then return end
    if enabled then
        self:_startWalking()
    else
        self:_stopWalking()
    end
end

-- Private: start walking coroutine
function Pathfinder:_startWalking()
    if #self.Waypoints == 0 then
        warn("Pathfinder: No waypoints to walk")
        return
    end
    if self.IsMoving then return end

    self.IsMoving = true
    self.CurrentWaypointIndex = 1
    self.TotalWaypoints = #self.Waypoints

    if self.MovementCoroutine then
        task.cancel(self.MovementCoroutine)
    end
    self.MovementCoroutine = task.spawn(function()
        self:_movementLoop()
    end)
end

-- Private: stop walking
function Pathfinder:_stopWalking()
    self.IsMoving = false
    self.CurrentWaypointIndex = 0
    local humanoid = getHumanoid()
    if humanoid then
        local root = getRootPart()
        if root then
            humanoid:MoveTo(root.Position)
        end
    end
    -- Clear computed path
    self.CurrentPathWaypoints = {}
    if self.ShowComputedPathLine then
        self:_refreshComputedPathLines()
    end
end

-- Private: movement loop (core pathfinding)
function Pathfinder:_movementLoop()
    while self.IsMoving and self.CurrentWaypointIndex <= #self.Waypoints do
        local targetCFrame = self.Waypoints[self.CurrentWaypointIndex]

        local reached = self:_moveToWaypoint(targetCFrame)

        if reached then
            -- Trigger waypoint reached callback
            for _, cb in ipairs(self._waypointReachedCallbacks) do
                pcall(cb, self.CurrentWaypointIndex, targetCFrame)
            end
            self.CurrentWaypointIndex = self.CurrentWaypointIndex + 1
        else
            -- Failed to reach. If force find is off, skip this waypoint.
            if not self.ForceFindPath then
                self.CurrentWaypointIndex = self.CurrentWaypointIndex + 1
            else
                -- Force find: will retry indefinitely (loop continues)
                task.wait(1)
            end
        end
    end

    -- Path completed or stopped
    if self.IsMoving and self.CurrentWaypointIndex > #self.Waypoints then
        -- All waypoints reached
        if not self.IsLooping then
            for _, cb in ipairs(self._pathCompletedCallbacks) do
                pcall(cb)
            end
        else
            -- Restart from first waypoint
            self.CurrentWaypointIndex = 1
            self:_movementLoop() -- recursive loop
            return
        end
    end

    -- Clean up
    self.CurrentPathWaypoints = {}
    if self.ShowComputedPathLine then
        self:_refreshComputedPathLines()
    end
    self.IsMoving = false
    self.CurrentWaypointIndex = 0
end

-- Private: move to a specific waypoint, retrying according to ForceFindPath setting
function Pathfinder:_moveToWaypoint(targetCFrame)
    local humanoid = getHumanoid()
    local rootPart = getRootPart()
    if not humanoid or not rootPart then return false end

    -- Stuck detection variables
    local lastPosition = rootPart.Position
    local stuckTimer = 0
    local jumpTriggered = false

    -- Keep trying until we reach the target or movement is stopped
    while self.IsMoving do
        -- Create path
        local path = PathfindingService:CreatePath({
            AgentRadius = self.AgentRadius,
            AgentHeight = self.AgentHeight,
            AgentCanJump = true,
            AgentCanClimb = true,
        })

        local success = pcall(function()
            path:ComputeAsync(rootPart.Position, targetCFrame.Position)
        end)

        if not success or path.Status == Enum.PathStatus.NoPath then
            -- No path, wait and retry
            if not self.ForceFindPath then
                return false
            end
            task.wait(1)
            continue
        end

        local waypoints = path:GetWaypoints()
        if #waypoints == 0 then
            if not self.ForceFindPath then
                return false
            end
            task.wait(1)
            continue
        end

        -- Update computed path visualization
        self.CurrentPathWaypoints = {}
        for _, wp in ipairs(waypoints) do
            table.insert(self.CurrentPathWaypoints, wp.Position)
        end
        if self.ShowComputedPathLine then
            self:_refreshComputedPathLines()
        end

        -- Follow the path waypoints
        local pathIndex = 1
        local blockedConnection = path.Blocked:Connect(function()
            -- Path blocked, will recompute on next loop iteration
            if self.IsMoving then
                pathIndex = #waypoints + 1 -- force exit
            end
        end)

        while self.IsMoving and pathIndex <= #waypoints do
            local wp = waypoints[pathIndex]

            -- Jump handling
            if wp.Action == Enum.PathWaypointAction.Jump and not jumpTriggered then
                if (rootPart.Position - wp.Position).Magnitude < 5 then
                    humanoid.Jump = true
                    jumpTriggered = true
                end
            end

            humanoid:MoveTo(wp.Position)

            -- Wait until we reach this waypoint or get stuck
            local reached = false
            while self.IsMoving and not reached do
                -- Check distance to current path waypoint
                if (rootPart.Position - wp.Position).Magnitude <= 3 then
                    reached = true
                    break
                end

                -- Stuck detection
                local moved = (rootPart.Position - lastPosition).Magnitude
                if moved < self.MoveThreshold then
                    stuckTimer = stuckTimer + task.wait()
                else
                    stuckTimer = 0
                    lastPosition = rootPart.Position
                end

                if stuckTimer >= self.StuckThreshold then
                    -- Stuck, fire callback
                    for _, cb in ipairs(self._stuckCallbacks) do
                        pcall(cb)
                    end
                    stuckTimer = 0
                    break
                end

                task.wait()
            end

            if reached then
                pathIndex = pathIndex + 1
                jumpTriggered = false
            else
                -- Not reached (stuck or path blocked), break out to recompute path
                break
            end
        end

        blockedConnection:Disconnect()

        -- Check if we reached the final target (the user waypoint)
        if (rootPart.Position - targetCFrame.Position).Magnitude <= 3 then
            return true
        end

        -- If we are still moving but didn't reach, loop will continue (recompute)
        -- If force find is off, we give up after one attempt
        if not self.ForceFindPath then
            return false
        end

        task.wait(0.5)
    end

    return false
end

-- Register callback for when a waypoint is reached
function Pathfinder:OnWaypointReached(callback)
    table.insert(self._waypointReachedCallbacks, callback)
end

-- Register callback for when the entire path is completed (non-looping)
function Pathfinder:OnPathCompleted(callback)
    table.insert(self._pathCompletedCallbacks, callback)
end

-- Register callback for when the character gets stuck
function Pathfinder:OnStuck(callback)
    table.insert(self._stuckCallbacks, callback)
end

-- Clean up all drawing lines and stop movement (call when done)
function Pathfinder:Destroy()
    self:SetWalkingEnabled(false)
    for _, line in ipairs(self.UserPathLines) do
        pcall(function() line:Remove() end)
    end
    for _, line in ipairs(self.ComputedPathLines) do
        pcall(function() line:Remove() end)
    end
    if self.LineRenderConnection then
        self.LineRenderConnection:Disconnect()
        self.LineRenderConnection = nil
    end
    self.UserPathLines = {}
    self.ComputedPathLines = {}
end

return Pathfinder
