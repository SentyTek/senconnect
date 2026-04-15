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
        if simulator:getIsToggled(2) then
            simulator:setInputBool(1, true) -- alive
            simulator:setInputNumber(1, 1522) -- group ID
            simulator:setInputNumber(2, 150 + math.floor(simulator:getSlider(3) * 50)) -- transmitter freq
        else
            simulator:setInputBool(1, false) -- alive
            simulator:setInputNumber(1, 0) -- group ID
            simulator:setInputNumber(2, 0) -- transmitter freq
        end
    end;
end
---@endsection


--[====[ IN-GAME CODE ]====]

-- try require("Folder.Filename") to include code from another file in this, so you can store code in libraries
-- the "LifeBoatAPI" is included by default in /_build/libs/ - you can use require("LifeBoatAPI") to get this, and use all the LifeBoatAPI.<functions>!

local groupID = property.getNumber("Group ID")
local refreshInterval = math.max(60, property.getNumber("Refresh Interval (sec)") * 60)
local playerTimeout = math.max(0, math.floor(property.getNumber("Player Timeout (num refreshes)")))

local startingFreq = 95
local scannerFreq = startingFreq
local maxFreq = 200
local transmitterFreq = 0
local currentPlayerIndex = 1

local mapColors = { -- From SenCar
    { 128, 95, 164  },
    { 48, 208, 217 },
    { 182, 29, 224 },
    { 12, 133, 26 },
    { 160, 9, 9 },
    { 140, 140, 140 },
    { 201, 119, 24 }
}

local mapProperties = {
    x = 0,
    y = 0,
    zoom = 1,
    heading = 0,
    colorIndex = 1,
    color = mapColors[1]
}

-- each entry is a table with x, y, heading, color
local playerData = {}
local mapPlayerData = {}
local trackedPlayers = {} -- keyed by transmitter frequency, persists across refresh scans

local playerFreqs = {}
local startupFoundFreqs = {}

local function contains(t, v)
    if type(v) == "table" then
        for _, value in pairs(t) do
            if type(value) == "table" and value[1] == v[1] and value[2] == v[2] and value[3] == v[3] and value[4] == v[4] then
                return true
            end
        end
    end
    for _, value in pairs(t) do
        if value == v then return true end
    end
    return false
end

local function toColorIndex(value)
    return (math.floor((value and (value > 0 and value or 1) or 1)) % #mapColors)
end

local ticks = 0
local state = 0 -- 0 = unready 1 = starting 2 = ready 3 = scanning for players 4 = looping players

function onTick()
    ticks = ticks + 1
    local enabled = not input.getBool(2)
    local enteredLoopState = false

    -- select frequency if not ready by scanning through all frequencies,
    -- noting whats taken, and then picking an open one once the scanner
    -- has gone through them all
    if ticks >= 5 and (state == 0 or state == 1) and enabled then
        state = 1
        if input.getBool(1) then -- found
            local f = input.getNumber(2) -- transmitter freq of the found signal
            if f ~= 0 and not contains(startupFoundFreqs, f) then
                startupFoundFreqs[#startupFoundFreqs + 1] = f
            end
        end
        scannerFreq = scannerFreq + 1

        if scannerFreq >= 206 then
            -- select a random frequency from the open ones
            local freq = math.random(startingFreq, maxFreq)
            while contains(startupFoundFreqs, freq) do
                freq = math.random(startingFreq, maxFreq)
            end
            
            transmitterFreq = freq
            state = 2 -- ready
            scannerFreq = startingFreq -- Go a few lower to give some time before the first scan starts at 100
        end
    end

    -- map inputs and such
    if not enabled then
        scannerFreq = startingFreq
        transmitterFreq = 0
        state = 0
        startupFoundFreqs = {}
        playerFreqs = {}
        playerData = {}
        mapPlayerData = {}
        trackedPlayers = {}
    end

    local zoom = input.getNumber(31)
    if zoom ~= 0 then mapProperties.zoom = zoom else mapProperties.zoom = 0.01 end

    local px, py, ph, col = input.getNumber(28), input.getNumber(29), input.getNumber(30)*(math.pi*2)*-1, input.getNumber(32)
    if col ~= 0 then
        mapProperties.colorIndex = toColorIndex(col)
        mapProperties.color = mapColors[mapProperties.colorIndex]
    end
    if px ~= 0 and py ~= 0 and ph ~= 0 then
        mapProperties.x = px
        mapProperties.y = py
        mapProperties.heading = ph
    end

    -- loop through all frequencies to see where players exist and note their transmitter freqs
    if state == 2 or state == 3 then
        playerData = {}
        currentPlayerIndex = 1
        state = 3 -- scanning for players
        
        local alive = input.getBool(1)
        local incomingTransmitterFreq = input.getNumber(2)
        if alive and incomingTransmitterFreq ~= transmitterFreq then
            local rgroupID = input.getNumber(1)
            
            if rgroupID == groupID and not contains(playerFreqs, incomingTransmitterFreq) then
                playerFreqs[#playerFreqs + 1] = incomingTransmitterFreq -- transmitter freq of the found signal
            end
        end
        
        scannerFreq = scannerFreq + 1
        if scannerFreq >= 206 then
            local detectedThisRefresh = {}
            for _, freq in pairs(playerFreqs) do
                detectedThisRefresh[freq] = true
            end

            for freq, trackedPlayer in pairs(trackedPlayers) do
                if detectedThisRefresh[freq] then
                    trackedPlayer.missedRefreshes = 0
                else
                    trackedPlayer.missedRefreshes = (trackedPlayer.missedRefreshes or 0) + 1
                    if trackedPlayer.missedRefreshes >= playerTimeout then
                        trackedPlayers[freq] = nil
                    end
                end
            end

            for _, freq in pairs(playerFreqs) do
                if trackedPlayers[freq] == nil then
                    trackedPlayers[freq] = { missedRefreshes = 0 }
                end
            end

            mapPlayerData = trackedPlayers
            currentPlayerIndex = 1
            state = 4 -- looping players
            enteredLoopState = true
        end
    end

    if state == 4 and not enteredLoopState then
        -- loop over known players and log their info
        if #playerFreqs == 0 then
            currentPlayerIndex = 1
            scannerFreq = startingFreq
            state = 3 -- no players found, go back to scanning
        elseif ticks % refreshInterval == 0 then
            scannerFreq = startingFreq
            playerFreqs = {}
            currentPlayerIndex = 1
            state = 3 -- go back to scanning
        else
            local playerIndex = currentPlayerIndex
            local playerFreq = playerFreqs[playerIndex]
            scannerFreq = playerFreq

            if input.getBool(1) then
                trackedPlayers[playerFreq] = trackedPlayers[playerFreq] or { missedRefreshes = 0 }
                trackedPlayers[playerFreq].x = input.getNumber(3)
                trackedPlayers[playerFreq].y = input.getNumber(4)
                trackedPlayers[playerFreq].heading = input.getNumber(5)
                trackedPlayers[playerFreq].color = input.getNumber(6)

                playerData[playerIndex] = {
                    x = input.getNumber(3),
                    y = input.getNumber(4),
                    heading = input.getNumber(5),
                    color = input.getNumber(6)
                }
            end

            currentPlayerIndex = currentPlayerIndex + 1
            if currentPlayerIndex > #playerFreqs then
                currentPlayerIndex = 1
                mapPlayerData = trackedPlayers
            end
        end
    end


    -- local outputs
    output.setNumber(28, scannerFreq)
    output.setNumber(29, transmitterFreq)

    -- transmitter outputs
    output.setNumber(1, groupID)
    output.setNumber(2, transmitterFreq)
    output.setNumber(3, mapProperties.x)
    output.setNumber(4, mapProperties.y)
    output.setNumber(5, mapProperties.heading)
    output.setNumber(6, mapProperties.colorIndex or 1)
    
    output.setBool(1, state > 1)

    output.setNumber(31, state)
    output.setNumber(32, #playerData)

    if scannerFreq > 300 then
        scannerFreq = startingFreq
    end
end

function onDraw()
    local w, h = screen.getWidth(), screen.getHeight()
    screen.drawMap(mapProperties.x, mapProperties.y, mapProperties.zoom)

    -- draw other players first so our pointer gets overlaid on top
    for _, player in pairs(mapPlayerData) do
        if player ~= nil and player.x ~= nil and player.y ~= nil and player.heading ~= nil and player.color ~= nil then
            local playerColor = mapColors[toColorIndex(player.color)] or mapColors[1]
            c(
                playerColor[1],
                playerColor[2],
                playerColor[3]
            )
            local px, py = map.mapToScreen(mapProperties.x, mapProperties.y, mapProperties.zoom, w, h, player.x, player.y)
            drawPointer(px, py, 6, player.heading)
        end
    end

    c(mapProperties.color[1], mapProperties.color[2], mapProperties.color[3])
    drawPointer(w / 2, h / 2, 8, mapProperties.heading)
end

function drawPointer(x,y,s,r,...)
	a=...
	a=(a or 30)*math.pi/360
	x=x+s/2*math.sin(r)
	y=y-s/2*math.cos(r)

	screen.drawTriangleF(x,y,x-s*math.sin(r+a),y+s*math.cos(r+a),x-s*math.sin(r-a),y+s*math.cos(r-a))
end

function c(...)
    local _ = { ... }
    for i, v in pairs(_) do
        _[i] = _[i] ^ 2.2 / 255 ^ 2.2 * _[i]
    end
    screen.setColor(table.unpack(_))
end
