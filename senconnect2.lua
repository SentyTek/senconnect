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
    simulator:setProperty("Unit Name", "Aita")
    simulator:setProperty("Sweep Step", 2)

    -- Runs every tick just before onTick; allows you to simulate the inputs changing
    ---@param simulator Simulator Use simulator:<function>() to set inputs etc.
    ---@param ticks     number Number of ticks since simulator started
    function onLBSimulatorTick(simulator, ticks)

        s = simulator:getTouchScreen(1)
        simulator:setInputNumber(26, s.touchX) -- touch x
        simulator:setInputNumber(27, s.touchY) -- touch y

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
            simulator:setInputNumber(3, math.sin(ticks / 20) * 100) -- x
            simulator:setInputNumber(4, math.cos(ticks / 20) * 100)                    -- y
            simulator:setInputNumber(5, (ticks / 20) % (math.pi * 2))                    -- heading
            simulator:setInputNumber(6, math.floor(simulator:getSlider(4) * 7))        -- colorIndex
            -- simulate name "BOB" being sent over
            simulator:setInputNumber(7, 66 * 256 + 79) -- "BO" in bytes
            simulator:setInputNumber(8, 66 * 256) -- "B" in bytes
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
local unitName = property.getText("Unit Name"):upper()
local sweepStep = math.max(1, math.floor(property.getNumber("Sweep Step")))

local bytes = {}
local startChannelName = 7
for i = 1, math.min(#unitName, 36) do
    local char = unitName:sub(i, i)
    local byte = string.byte(char)
    bytes[#bytes + 1] = byte
end

local startingFreq = 95
local maxFreq = 206
local scannerFreq = startingFreq
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
    return (math.floor((value and (value > 0 and value or 1) or 1)) % (#mapColors + 1))
end

local ticks = 0
local state = 0 -- 0 = unready 1 = starting 2 = ready 3 = scanning for players 4 = looping players
local touchX, touchY, ltouchX, ltouchY, ticksSinceTouch = 0, 0, 0, 0, 0
local sweepOffset = 0 -- current offset in sweep pattern (0 to sweepStep-1), rotates through all offsets

local function getSweepStartFreq()
    local startFreq = startingFreq
    local remainder = startFreq % sweepStep
    local needed = (sweepOffset - remainder) % sweepStep
    return startFreq + needed
end

local function clamp(v, m, n)
    return math.max(m, math.min(n, v))
end

local function txName()
    -- translates string to bytes and sends over outputs
    -- since we only use values (30..39, 65..90) we can send 2 chars per channel
    for i = 1, #bytes, 2 do
        local byte1 = bytes[i] or 0
        local byte2 = bytes[i + 1] or 0
        local combined = byte1 * 256 + byte2
        output.setNumber(startChannelName + math.floor((i - 1) / 2), combined)
    end
end

local function rxName()
    -- receives bytes from inputs and translates back to string
    local receivedBytes = {}
    for i = startChannelName, 25 do
        local combined = input.getNumber(i)
        if combined == 0 then goto continue end
        local byte1 = math.floor(combined / 256)
        local byte2 = combined % 256
        if byte1 ~= 0 then table.insert(receivedBytes, byte1) end
        if byte2 ~= 0 then table.insert(receivedBytes, byte2) end
        ::continue::
    end

    local chars = {}
    for _, byte in pairs(receivedBytes) do
        table.insert(chars, string.char(byte))
    end

    return table.concat(chars):upper()
end

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

        if scannerFreq >= maxFreq then
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
        mapPlayerData = {}
        trackedPlayers = {}
        sweepOffset = 0
    end

    local zoom = input.getNumber(31)
    if zoom ~= 0 then mapProperties.zoom = zoom else mapProperties.zoom = 1 end

    local px, py, ph, col = input.getNumber(28), input.getNumber(29), input.getNumber(30)*(math.pi*2)*-1, clamp(input.getNumber(32), 1, 7)
    if col ~= 0 then
        mapProperties.colorIndex = toColorIndex(col)
        mapProperties.color = mapColors[mapProperties.colorIndex] or mapColors[1]
    end
    if px ~= 0 and py ~= 0 and ph ~= 0 then
        mapProperties.x = px
        mapProperties.y = py
        mapProperties.heading = ph
    end

    touchX, touchY = input.getNumber(26), input.getNumber(27)

    -- loop through all frequencies to see where players exist and note their transmitter freqs
    if state == 2 or state == 3 then
        if state == 2 then
            scannerFreq = getSweepStartFreq()
        end
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

        scannerFreq = scannerFreq + sweepStep
        if scannerFreq >= maxFreq then
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
            sweepOffset = (sweepOffset + 1) % sweepStep
            enteredLoopState = true
        end
    end

    if state == 4 and not enteredLoopState then
        -- loop over known players and log their info
        if #playerFreqs == 0 then
            currentPlayerIndex = 1
            scannerFreq = getSweepStartFreq()
            state = 3 -- no players found, go back to scanning
        elseif ticks % refreshInterval == 0 and sweepOffset == 0 then
            scannerFreq = getSweepStartFreq()
            playerFreqs = {}
            currentPlayerIndex = 1
            state = 3 -- go back to scanning
        else
            local playerIndex = currentPlayerIndex
            local playerFreq = playerFreqs[playerIndex]
            scannerFreq = playerFreq

            local alive = input.getBool(1)
            if alive then
                trackedPlayers[playerFreq] = trackedPlayers[playerFreq] or { missedRefreshes = 0 }
                trackedPlayers[playerFreq].x = input.getNumber(3)
                trackedPlayers[playerFreq].y = input.getNumber(4)
                trackedPlayers[playerFreq].heading = input.getNumber(5)
                trackedPlayers[playerFreq].color = input.getNumber(6)
                trackedPlayers[playerFreq].name = rxName()
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
    output.setNumber(6, clamp(mapProperties.colorIndex or 1, 1, 7))

    txName()

    output.setBool(1, state > 1)

    ticksSinceTouch = (touchX ~= ltouchX or touchY ~= ltouchY) and 0 or ticksSinceTouch + 1
    ltouchX, ltouchY = touchX, touchY

    if scannerFreq > maxFreq + 100 then
        scannerFreq = startingFreq
    end
end

function onDraw()
    local nameToDisplay = { x = 0, y = 0, name = "" }
    local w, h = screen.getWidth(), screen.getHeight()
    screen.drawMap(mapProperties.x, mapProperties.y, mapProperties.zoom)

    -- draw other players first so our pointer gets overlaid on top
    for _, player in pairs(mapPlayerData) do
        if player and player.x then
            local playerColor = mapColors[toColorIndex(player.color)] or mapColors[1]
            c(
                playerColor[1],
                playerColor[2],
                playerColor[3]
            )
            local px, py = map.mapToScreen(mapProperties.x, mapProperties.y, mapProperties.zoom, w, h, player.x, player.y)
            drawPointer(px, py, 6, player.heading)
            
            -- create small touch zones for each player to display their name on the screen when touched
            if ticksSinceTouch < 300 and isPointInRectangle(px - 2, py - 4, 4, 4) then
                nameToDisplay = { x = px + 2, y = py - 4, name = player.name or "" }
            end
        end
    end
    
    c(mapProperties.color[1], mapProperties.color[2], mapProperties.color[3])
    drawPointer(w / 2, h / 2, 8, mapProperties.heading)
    c(255, 255, 255)

    if nameToDisplay.name ~= "" then
        c(50, 50, 50, 200)
        screen.drawRectF(nameToDisplay.x, nameToDisplay.y, #nameToDisplay.name * 4 + 1, 7)
        c(255, 255, 255)
        dst(nameToDisplay.x + 1, nameToDisplay.y + 1, nameToDisplay.name or "")
    end
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

function isPointInRectangle(rectX, rectY, rectW, rectH)
    return touchX >= rectX and touchY >= rectY and touchX <= rectX + rectW and touchY <= rectY + rectH
end

--dst(x,y,text,size=1,rotation=1,is_monospace=false)
--rotation can be between 1 and 4
f=screen.drawRectF
--magic willy font
h="00019209B400AAAA793CA54A555690015244449415500BA0004903800009254956D4592EC54EC51C53A4F31C5354E52455545594104110490A201C7008A04504FFFE57DAD75C7246D6DCF34EF3487256B7DAE92E64D4975A924EBEDAF6DAF6DED74856B2D75A711CE924B6D4B6A4B6FAB55AB524E54ED24C911264965400000E"
i={}j=0
for k in h:gmatch("....")do i[j+1]=tonumber(k,16)j=j+1 end
function dst(l, m, n, b, o, p)
    b = b or 1
    o = o or 1
    if o > 2 then n = n:reverse() end
    n = n:upper()
    for q in n:gmatch(".") do
        r = q:byte() - 31
        if 0 < r and r <= j then
            for s = 1, 15 do
                if o > 2 then t = 2 ^ s else t = 2 ^ (16 - s) end
                if i[r] & t == t then
                    u, v = ((s - 1) % 3) * b, ((s - 1) // 3) * b
                    if o % 2 == 1 then f(l + u, m + v, b, b) else f(l + 5 - v, m + u, b, b) end
                end
            end
            if i[r] & 1 == 1 and not p then
                s = 2 * b
            else
                s = 4 * b
            end
            if o % 2 == 1 then l = l + s else m = m + s end
        end
    end
end
