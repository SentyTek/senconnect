--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey


--[====[ HOTKEYS ]====]
-- Press F6 to simulate this file
-- Press F7 to build the project, copy the output from /_build/out/ into the game to use
-- Remember to set your Author name etc. in the settings: CTRL+COMMA


--[====[ EDITABLE SIMULATOR CONFIG - *automatically removed from the F7 build output ]====]
---@section __LB_SIMULATOR_ONLY__
do
    ---@type Simulator -- Set properties and screen sizes here - will run once when the script is loaded
    simulator = simulator
    simulator:setScreen(1, "2x2")
    simulator:setScreen(2, "3x1")
    
    simulator:setProperty("Group ID", 1522)
    simulator:setProperty("Refresh Interval (sec)", 3)
    simulator:setProperty("Player Timeout (num refreshes)", 2)

    -- Runs every tick just before onTick; allows you to simulate the inputs changing
    ---@param simulator Simulator Use simulator:<function>() to set inputs etc.
    ---@param ticks     number Number of ticks since simulator started
    function onLBSimulatorTick(simulator, ticks)

        -- map settings
        simulator:setInputNumber(28, 0) -- x
        simulator:setInputNumber(29, 0) -- y
        simulator:setInputNumber(30, 0) -- heading
        simulator:setInputNumber(31, simulator:getSlider(1) * 30) -- zoom
        simulator:setInputNumber(32, simulator:getSlider(2) * 7) -- color

        simulator:setInputBool(1, simulator:getIsToggled(1))      -- enabled

        -- pseudo receiver
    end;
end
---@endsection


--[====[ IN-GAME CODE ]====]

-- try require("Folder.Filename") to include code from another file in this, so you can store code in libraries
-- the "LifeBoatAPI" is included by default in /_build/libs/ - you can use require("LifeBoatAPI") to get this, and use all the LifeBoatAPI.<functions>!

local lb = require("LifeBoatAPI")

local groupID = property.getNumber("Group ID")
local refreshInterval = property.getNumber("Refresh Interval (sec)") * 60
local playerTimeout = property.getNumber("Player Timeout (num refreshes)")

local mapColors = { -- From SenCar
    { 47, 51, 78 },
    { 17, 15, 107 },
    { 74, 27, 99 },
    { 35, 54, 41 },
    { 69, 1,  10 },
    { 38, 38, 38 },
    { 92, 50, 1 }
}

local mapProperties = {
    x = 0,
    y = 0,
    zoom = 1,
    heading = 0,
    color = mapColors[1]
}

function onTick()
    local enabled = not input.getBool(1)
    if not enabled then return end

    local zoom = input.getNumber(31)
    if zoom ~= 0 then mapProperties.zoom = zoom else mapProperties.zoom = 1 end

    local px, py, ph, c = input.getNumber(28), input.getNumber(29), input.getNumber(30)*(math.pi*2)*-1, input.getNumber(32)
    if c ~= 0 then mapProperties.color = mapColors[math.floor(c) % #mapColors + 1] end
    if px ~= 0 and py ~= 0 and ph ~= 0 then
        mapProperties.x = px
        mapProperties.y = py
        mapProperties.heading = ph
    end
end

function onDraw()
    local w, h = screen.getWidth(), screen.getHeight()
    screen.drawMap(mapProperties.x, mapProperties.y, mapProperties.zoom)
    screen.setColor(mapProperties.color[1], mapProperties.color[2], mapProperties.color[3])
    drawPointer(w/2, h/2, 8, mapProperties.heading)
end

function drawPointer(x,y,s,r,...)
	a=...
	a=(a or 30)*math.pi/360
	x=x+s/2*math.sin(r)
	y=y-s/2*math.cos(r)

	screen.drawTriangleF(x,y,x-s*math.sin(r+a),y+s*math.cos(r+a),x-s*math.sin(r-a),y+s*math.cos(r-a))
end
