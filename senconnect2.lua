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

local groupID = property.getNumber("Group ID")
local refreshInterval = property.getNumber("Refresh Interval (sec)") * 60
local playerTimeout = property.getNumber("Player Timeout (num refreshes)")

local scannerFreq = 100
local maxFreq = 200
local transmitterFreq = 0
local ready = false

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

local playerFreqs = {}
local startupFoundFreqs = {}

local rollingScannerFreqs = {}

local function contains(t, v)
    for _, value in pairs(t) do
        if value == v then return true end
    end
    return false
end

local ticks = 0

function onTick()
    if ticks < 5 then
        ticks = ticks + 1
    end
    local enabled = not input.getBool(2)

    -- select frequency if not ready by scanning through all frequencies,
    -- noting whats taken, and then picking an open one once the scanner
    -- has gone through them all
    if ticks >= 5 and not ready and enabled then
        if input.getBool(1) then -- found
            local datedScannerFreq = rollingScannerFreqs[1] or 100
            local f = datedScannerFreq
            if f ~= 0 and not contains(startupFoundFreqs, f) then
                startupFoundFreqs[#startupFoundFreqs + 1] = f
            end
        end
        scannerFreq = scannerFreq + 1

        if scannerFreq >= 200 then
            -- select from the open frequencies
            -- min freq is 100, max is 200
            local freq = 100
            while freq <= maxFreq do
                if not contains(startupFoundFreqs, freq) then
                    break
                end
                freq = freq + 1
            end

            transmitterFreq = freq
            ready = true
        end
    end

    -- map inputs and such
    output.setNumber(1, #startupFoundFreqs)
    output.setNumber(28, scannerFreq)
    output.setNumber(29, transmitterFreq)
    output.setBool(1, ready)
    rollingScannerFreqs[#rollingScannerFreqs + 1] = scannerFreq
    if #rollingScannerFreqs > 6 then table.remove(rollingScannerFreqs, 1) end
    if not enabled then
        scannerFreq = 100
        transmitterFreq = 0
        ready = false
        startupFoundFreqs = {}
        playerFreqs = {}
        return
    end

    local zoom = input.getNumber(31)
    if zoom ~= 0 then mapProperties.zoom = zoom else mapProperties.zoom = 1 end

    local px, py, ph, c = input.getNumber(28), input.getNumber(29), input.getNumber(30)*(math.pi*2)*-1, input.getNumber(32)
    if c ~= 0 then mapProperties.color = mapColors[math.floor(c) % #mapColors + 1] end
    if px ~= 0 and py ~= 0 and ph ~= 0 then
        mapProperties.x = px
        mapProperties.y = py
        mapProperties.heading = ph
    end

    -- get inputs from the receiver
    -- important to note the receiver is scanning frequencies set several ticks ago (5 tick to be precise)
    local alive = input.getBool(1)
    local rgroupID = input.getNumber(1)
    if alive and rgroupID == groupID then
        playerFreqs[#playerFreqs + 1] = rollingScannerFreqs[1]
    end
end

function onDraw()
    local w, h = screen.getWidth(), screen.getHeight()
    screen.drawMap(mapProperties.x, mapProperties.y, mapProperties.zoom)
    screen.setColor(mapProperties.color[1], mapProperties.color[2], mapProperties.color[3])
    drawPointer(w / 2, h / 2, 8, mapProperties.heading)
    
    for _, f in pairs(startupFoundFreqs) do
        screen.drawText(0, _ * 7, f)
    end
end

function drawPointer(x,y,s,r,...)
	a=...
	a=(a or 30)*math.pi/360
	x=x+s/2*math.sin(r)
	y=y-s/2*math.cos(r)

	screen.drawTriangleF(x,y,x-s*math.sin(r+a),y+s*math.cos(r+a),x-s*math.sin(r-a),y+s*math.cos(r-a))
end
