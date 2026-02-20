## Pathfinder Module – API Documentation

The Pathfinder module provides a robust, dynamic waypoint system for Roblox characters. It uses `PathfindingService` to navigate around obstacles, supports jumping, includes visual tracers (user‑defined and computed paths), and offers a flexible API for control and customisation.

# Installation

```lua
local PF = loadstring(game:HttpGet("https://raw.githubusercontent.com/0xF7A/PathFinderRBX/refs/heads/main/main.luau"))
PF.new()
```

# Constructor

Creates a new Pathfinder instance.

Returns:
- A new Pathfinder object.

# Public Methods

`AddWaypoint([cframe])`
Adds a waypoint at the specified `CFrame`. If no argument is given, the character's current position is used.

Parameters:

- `cframe` (optional, CFrame): The position to add as a waypoint. Defaults to current character position.

Returns:
`true` if successful, `false` if character not found.

`RemoveWaypoint(index)`

Removes the waypoint at the given index (1‑based).

Parameters:

- `index` (number): The index of the waypoint to remove.

Returns:
`true` if successful, `false` if the index is out of range.

`ClearWaypoints()`
Removes all waypoints and stops any ongoing movement.

`GetWaypoints()`
Returns a read‑only copy of the current waypoint list.

Returns:
A table containing all waypoint `CFrame` values.

SetLooping(enabled)
Enables or disables path looping. When `true`, the path restarts from the first waypoint after reaching the last.

Parameters:

`enabled` (boolean): `true` to loop, `false` to stop after final waypoint.

ShowUserPathTracer(enabled, [settings])
Shows or hides the green line connecting user‑defined waypoints.

Parameters:

- `enabled` (boolean): `true` to show, `false` to hide.

- `settings` (optional, table): Custom appearance settings (see Line Settings).

Example:
```lua
myPathfinder:ShowUserPathTracer(true, { Color = Color3.new(1,0,0), Thickness = 3 })
```

`ShowCalculatedTracer(enabled, [settings])`
Shows or hides the blue line representing the actual pathfinding path currently being followed.

Parameters:

- `enabled` (boolean): `true` to show, `false` to hide.

- `settings` (optional, table): Custom appearance settings (see Line Settings).

`SetComputedLine(settings)`
Updates the appearance of the computed path line (blue) without toggling visibility.

Parameters:

- `settings` (table): Table with fields `Color` (Color3), `Thickness` (number), `Transparency` (0–1).

SetUserTracer(settings)
Updates the appearance of the user path line (green) without toggling visibility.

Parameters:

- `settings` (table): Table with fields `Color` (Color3), `Thickness` (number), `Transparency` (0–1).

`GetProgress()`
Returns the current movement progress.

Returns:
A table with the following fields:

- `currentIndex` (number): Index of the waypoint currently being approached (0 if not moving).

- `total` (number): Total number of waypoints.

- `isMoving` (boolean): Whether the character is currently moving.

- `currentWaypoint` (CFrame or nil): The target waypoint CFrame, or nil if not moving.

`SetForceFindPath(enabled)`
Determines whether the pathfinder should retry a waypoint indefinitely if it cannot be reached.

- `true` (default): Keep retrying until the waypoint is reached (never skip).

- `false`: Skip to the next waypoint after a single failure.

Parameters:

- `enabled` (boolean).

`SetCalculationTimeout(seconds)`
Sets the stuck detection timeout. If the character moves less than MoveThreshold (0.2 studs) for this many seconds, a path recalculation is triggered.

Parameters:

- `seconds` (number): Time in seconds (default 5).

`SetWalkingEnabled(enabled)`
Starts or stops the character along the defined path.

Parameters:

`enabled` (boolean): `true` to start moving, `false` to stop.

# Events (Callbacks)
`OnWaypointReached(callback)`
Registers a function to be called each time a waypoint is successfully reached.

Callback signature:
`function(index, cframe)`

- `index` (number): The index of the reached waypoint.

- `cframe` (CFrame): The position of the reached waypoint.

`OnPathCompleted(callback)`
Registers a function to be called when the entire path has been completed (only fires when looping is `false`).

Callback signature:
`function()`

`OnStuck(callback)`
Registers a function to be called when the character is detected as stuck (movement below threshold for the timeout duration).

Callback signature:
`function()`

# Cleanup

`Destroy()`
Stops any ongoing movement, removes all drawing lines, and disconnects the render connection. Call this when the Pathfinder instance is no longer needed (e.g., on script unload).

# Usage Example

```lua
local Pathfinder = require(game.ReplicatedStorage.Pathfinder)
local pf = Pathfinder.new()

-- Add waypoints
pf:AddWaypoint()                     -- current position
pf:AddWaypoint(CFrame.new(10,0,10))  -- specific position
pf:AddWaypoint()

-- Show tracers with custom colors
pf:ShowUserPathTracer(true, { Color = Color3.new(1,1,0) })  -- yellow user line
pf:ShowCalculatedTracer(true, { Color = Color3.new(1,0,1) }) -- magenta computed line

-- Set callbacks
pf:OnWaypointReached(function(idx, pos)
    print("Reached waypoint", idx)
end)
pf:OnPathCompleted(function()
    print("All waypoints visited!")
end)

-- Start moving
pf:SetWalkingEnabled(true)

-- Later, maybe stop
task.wait(10)
pf:SetWalkingEnabled(false)

-- Clean up when done
pf:Destroy()
```

~ build 0.1.3b-22026
