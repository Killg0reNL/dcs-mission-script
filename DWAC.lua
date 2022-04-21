--[[
    Selectable mission features
        - SMOKE: Map targeted (Idea stolen from Tupper of Rotorheads)
            Usage: On the F10 map, place a comment circle with text of "-smoke;<color>" (red|orange|green|white|blue) and minimize
        - ILLUMINATION: Map targeted
            Usage: On the F10 map, place a comment circle with text of "-flare" and minimize
        - VERSION: Map activated
            Usage: On the F10 map, place a comment circle with text of "-version" to see the current version of DWAC

    The MIT License (MIT)
    Copyright © 2022 gakksimian@gmail.com
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), 
    to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
    and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
    IN THE SOFTWARE.
]]
os = require "os"
io = require "io"
lfs = require "lfs" -- lfs.writedir() provided by DCS and points to the DCS 'SavedGames' folder

local dwac = {}
local baseName = "DWAC"
local version = "0.1.4"

--#region Configuration

-- ##########################
-- CONFIGURATION PROPERTIES - Tie them to this table so calling scopes can reference
-- ##########################
dwac.enableLogging = true

-- To enable/disable features set their state here
dwac.enableMapSmoke = true
dwac.enableMapIllumination = true
dwac.mapIlluminationAltitude = 700 -- Altitude(meters) the illumination bomb appears determines duration (300sec max)/effectiveness
dwac.illuminationPower = 1000000 -- 1 to 1000000 brightness

--#endregion


--#region UTIL
local function getGroupId(_unit)
    if _unit then
        local _group = _unit:getGroup()
        return _group:getID()
    end
end
dwac.getGroupId = getGroupId

-- useful for debugging
local function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end
 dwac.dump = dump
--#endregion


--#region FAC-A

-- ##########################
-- Meta Classes
-- ##########################
FacTarget = {}
function FacTarget:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.position = {} -- vec3
    o.unit = {}

    return o
end

FacUnit = {}
function FacUnit:new (baseUnit, smokeColor, laserCode)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    if baseUnit == nil then
        error("Nil Unit provided to FacUnit constructor")
    end
    o.base = baseUnit
    o.smokeColor = smokeColor or dwac.smokeColors[trigger.smokeColor.Red]
    o.laserCode = laserCode or dwac.laserCodes.One
    o.onStation = false
    o.currentTarget = {}
    o.targets = {}

    return o
end
function FacUnit:goOnStation(o)
    dwac.writeDebug("Go ON station")
    self.onStation = true
    dwac.updateFACUnit(self)
end
function FacUnit:goOffStation(o)
    dwac.writeDebug("Go OFF station")
    self.onStation = false
    dwac.updateFACUnit(self)
end


-- ##########################
-- Properties
-- ##########################

dwac.messageDuration = 5

-- Unit types capable of FAC-A that will receive the F10 menu option
dwac.facCapableUnits = {
    "SA342M",
    "SA342L",
    "SA342Mistral",
    "SA342Minigun"
}

-- reverse of trigger.smokeColor
dwac.smokeColors = {
    [0] = "Green",
    [1] = "Red",
    [2] = "White",
    [3] = "Orange",
    [4] = "Blue"
}

dwac.laserCodes = {
    One = 1688,
    Two = 1588,
    Three = 1488,
    Four = 1337
}

-- collection of FAC-A capable units operating in-game
dwac.facUnits = {}
-- add method of removing fac units no longer in use by a player
local function pruneFACUnits()
    local _facPlayers = dwac.getCurrentFACUnits()
    local _newFacUnits = {}
    for _, _facPlayer in pairs(_facPlayers) do
        for _, _facUnit in pairs(dwac.facUnits) do
            if _facPlayer:getUnitID() == _facUnit:getUnitID() then
                table.insert(_newFacUnits, _facUnit)
                break
            end
        end
    end
    dwac.facUnits = _newFacUnits
end
dwac.pruneFACUnits = pruneFACUnits

dwac.facMenuDB = {}

-- ##########################
-- Methods
-- ##########################

local function addFACMenuFeatures(_unit)
    -- Add the unit for tracking if needed
    if not _unit then
        return
    end
    local _unitId = _unit:getID()
    if not dwac.facUnits[_unitId] then
        dwac.facUnits[_unitId] = FacUnit:new(_unit)
    end
    local _groupId = dwac.getGroupId(dwac.facUnits[_unitId].base)
    if not dwac.facMenuDB[_groupId] then
        dwac.facMenuDB[_groupId] = {}
    end

    dwac.writeDebug("addFACMenuFeatures: " .. dwac.dump(dwac.facUnits[_unitId]))

    local _FACA = "FAC-A"
    local _onStation = "Go ON Station"
    local _offStation = "Go OFF Station"

    -- local _unitMenu = dwac.facMenuDB[_groupId]
    -- if not _unitMenu then
    --     _unitMenu = {}
    --     dwac.facMenuDB[_groupId] = _unitMenu
    -- end

    dwac.writeDebug("Existing: " .. dwac.dump(dwac.facMenuDB[_groupId]))
    if dwac.facMenuDB[_groupId]["StationPath"] then
        missionCommands.removeItemForGroup(_groupId, dwac.facMenuDB[_groupId]["StationPath"])
        if dwac.facUnits[_unitId].onStation then
            dwac.facMenuDB[_groupId]["StationPath"] = missionCommands.addCommandForGroup(_groupId, _offStation, dwac.facMenuDB[_groupId]["FacPath"], dwac.facUnits[_unitId].goOffStation, dwac.facUnits[_unitId])
            -- missionCommands.addSubMenuForGroup(_groupid, "List targets",  _existing.facMenuPath)
            -- missionCommands.addCommandForGroup(_groupId, "Smoke target",  _existing.facMenuPath, _existing.smokeTarget)
            -- missionCommands.addCommandForGroup(_groupId, "Laze target",  _existing.facMenuPath, _existing.lazeTarget)
            -- missionCommands.addCommandForGroup(_groupId, "Call artillery",  _existing.facMenuPath, _existing.callArty)
        else
            dwac.writeDebug("OffStation: " .. dwac.dump(dwac.facUnits[_unitId]))
            dwac.facMenuDB[_groupId]["StationPath"] = missionCommands.addCommandForGroup(_groupId, _onStation,  dwac.facMenuDB[_groupId]["FacPath"], dwac.facUnits[_unitId].goOnStation, dwac.facUnits[_unitId])
        end
        --dwac.updateFACUnit(_existing)
    else
        --dwac.updateFACUnit(_facUnit)
        --missionCommands.removeItemForGroup(_groupId, {"FAC-A"}) -- clears menu at root for this feature
        dwac.facMenuDB[_groupId]["FacPath"] = missionCommands.addSubMenuForGroup(_groupId, "FAC-A")

        -- Laser Codes
        local _laserPath = missionCommands.addSubMenuForGroup(_groupId, "Set laser code", dwac.facMenuDB[_groupId]["FacPath"])
        missionCommands.addCommandForGroup(_groupId, dwac.laserCodes.One, _laserPath, dwac.setLaserCode, {dwac.facUnits[_unitId], dwac.laserCodes.One})
        missionCommands.addCommandForGroup(_groupId, dwac.laserCodes.Two, _laserPath, dwac.setLaserCode, {dwac.facUnits[_unitId], dwac.laserCodes.Two})
        missionCommands.addCommandForGroup(_groupId, dwac.laserCodes.Three, _laserPath, dwac.setLaserCode, {dwac.facUnits[_unitId], dwac.laserCodes.Three})
        missionCommands.addCommandForGroup(_groupId, dwac.laserCodes.Four, _laserPath, dwac.setLaserCode, {dwac.facUnits[_unitId], dwac.laserCodes.Four})

        -- Smoke Color
        local _smokePath = missionCommands.addSubMenuForGroup(_groupId, "Set smoke color", dwac.facMenuDB[_groupId]["FacPath"])
        missionCommands.addCommandForGroup(_groupId, "Red", _smokePath, dwac.setFACSmokeColor, {dwac.facUnits[_unitId], dwac.smokeColors[trigger.smokeColor.Red]})
        missionCommands.addCommandForGroup(_groupId, "Orange", _smokePath, dwac.setFACSmokeColor, {dwac.facUnits[_unitId], dwac.smokeColors[trigger.smokeColor.Orange]})
        missionCommands.addCommandForGroup(_groupId, "White", _smokePath, dwac.setFACSmokeColor, {dwac.facUnits[_unitId], dwac.smokeColors[trigger.smokeColor.White]})

        -- Current Settings
        local _settings = missionCommands.addCommandForGroup(_groupId, "Current settings", dwac.facMenuDB[_groupId]["FacPath"], dwac.getCurrentSettings, {dwac.facUnits[_unitId]})

        -- Station
        dwac.facMenuDB[_groupId]["StationPath"] = missionCommands.addCommandForGroup(_groupId, "Go ON Station", dwac.facMenuDB[_groupId]["FacPath"], dwac.facUnits[_unitId].goOnStation)
        --_facUnit.facMenuPath = _facPath
        --_facUnit.stationMenuPath = _onStationPath
        --dwac.updateFACUnit(_facUnit)
    end
end
dwac.addFACMenuFeatures = addFACMenuFeatures

local function getCurrentSettings(args)
    dwac.writeDebug("getCurrentSettings()")
    local _facUnit = args[1]
    dwac.writeDebug("getCurrentSettings()_facUnit: " .. dwac.dump(_facUnit))
    local _groupId = dwac.getGroupId(_facUnit.base)
    trigger.action.outTextForGroup(_groupId, "Laser code: " .. _facUnit.laserCode .. ", Smoke Color: " .. _facUnit.smokeColor, dwac.messageDuration, true)
end
dwac.getCurrentSettings = getCurrentSettings

local function setLaserCode(args) -- args: {facUnit, code}
    dwac.writeDebug("setLaserCode()")
    args[1].laserCode = args[2]
    dwac.updateFACUnit(args[1])
end
dwac.setLaserCode = setLaserCode


local function setFACSmokeColor(args) -- args: {facUnit, color}
    dwac.writeDebug("setFACSmokeColor()")
    args[1].smokeColor = args[2]
    dwac.updateFACUnit(args[1])
end
dwac.setFACSmokeColor = setFACSmokeColor

local function isFACCapable(_unit)
    if _unit ~= nil then
        for _, _unitName in pairs(dwac.facCapableUnits) do
            if _unit:getTypeName() == _unitName then
                return true
            end
        end
    end
    return false
end
dwac.isFACCapable = isFACCapable

-- Extracts all current player units that are FAC-A capable
local function getCurrentFACCapableUnits()
    local reply = {}
    for _coalition = coalition.side.RED, coalition.side.BLUE do
        local _players = coalition.getPlayers(_coalition) -- returns array of units run by players
        if _players ~= nil then
            for i = 1, #_players do
                local _unit = _players[i]
                if _unit ~= nil then
                    if dwac.isFACCapable(_unit) then
                        table.insert(reply, _unit)
                    end
                end
            end
        end
    end
    return reply
end
dwac.getCurrentFACCapableUnits = getCurrentFACCapableUnits

local function updateFACUnit(_facUnit)
    dwac.writeDebug("updateFACUnit()")
    dwac.writeDebug("Incoming facUnit: " .. dwac.dump(_facUnit))
    if _facUnit then
        if _facUnit.base then
            dwac.writeDebug("UpdateFACUnit: " .. dwac.dump(_facUnit))
            dwac.facUnits[_facUnit.base:getID()] = _facUnit
        end
    end
    dwac.writeDebug("facUnits: " .. dwac.dump(dwac.facUnits))
end
dwac.updateFACUnit = updateFACUnit

local function doFoo()
    trigger.action.outText("DWAC loaded", dwac.messageDuration, false)
end
dwac.doFoo = doFoo

--#endregion


--#region DWAC

-- ##########################
-- Properties
-- ##########################
if dwac.enableLogging then
    local _date = os.date("*t")
    dwac.logger =
        io.open(
        lfs.writedir() .. "Logs/" .. baseName .. "_" .. _date.year .. "_" .. _date.month .. "_" .. _date.day .. ".log",
        "a+"
    )
end
dwac.messageDuration = 20 -- seconds
dwac.messageDuration = dwac.messageDuration -- pass the display time to FACA script
dwac.f10MenuUpdateFrequency = 4 -- F10 menu refresh rate

dwac.MapRequest = {SMOKE = 1, ILLUMINATION = 2, VERSION = 3}

-- ##########################
-- Methods
-- ##########################
-- *** Logging ***
local function writeDebug(debugLog)
    if dwac.enableLogging then
        dwac.logger:write(dwac.getLogTimeStamp() .. debugLog .. "\n")
    end
end
dwac.writeDebug = writeDebug

local function getMarkerRequest(requestText)
    local isSmokeRequest = requestText:match("^-smoke")
    if isSmokeRequest then
        return dwac.MapRequest.SMOKE
    end

    local isIllumination = requestText:match("^-flare%s*$")
    if isIllumination then
        return dwac.MapRequest.ILLUMINATION
    end

    local isVersionRequest = requestText:match("^-version")
    if isVersionRequest then
        return dwac.MapRequest.VERSION
    end
end
dwac.getMarkerRequest = getMarkerRequest

local function setMapSmoke(requestText, vector)
    smokeColor = requestText:match("^-smoke;(%a+)")
    local lat, lon, alt = coord.LOtoLL(vector)
    if smokeColor then
        dwac.writeDebug(
            "Smoke color requested: " .. smokeColor .. " -> Lat: " .. lat .. " Lon: " .. lon .. " Alt: " .. alt
        )
        color = string.lower(smokeColor)
        if color == "green" then
            trigger.action.smoke(vector, trigger.smokeColor.Green)
            return true
        elseif color == "red" then
            trigger.action.smoke(vector, trigger.smokeColor.Red)
            return true
        elseif color == "white" then
            trigger.action.smoke(vector, trigger.smokeColor.White)
            return true
        elseif color == "orange" then
            trigger.action.smoke(vector, trigger.smokeColor.Orange)
            return true
        elseif color == "blue" then
            trigger.action.smoke(vector, trigger.smokeColor.Blue)
            return true
        end
    end
    return false
end
dwac.setMapSmoke = setMapSmoke

local function setMapIllumination(vector)
    if vector then
        local lat, lon, alt = coord.LOtoLL(vector)
        dwac.writeDebug("Illumination requested: Lat: " .. lat .. " Lon: " .. lon .. " Alt: " .. alt)
        trigger.action.illuminationBomb(vector, dwac.illuminationPower)
        return true
    end
    return false
end
dwac.setMapIllumination = setMapIllumination

local function showVersion()
    trigger.action.outText(baseName .. " version: " .. version, dwac.messageDuration, false)
end
dwac.showVersion = showVersion

local function getLogTimeStamp()
    return os.date("%H:%M:%S") .. " - " .. baseName .. ": "
end
dwac.getLogTimeStamp = getLogTimeStamp

-- highest level DWAC F10 menu addition
--   add calls to functions which add specific menu features here to keep it clean
--   REMEMBER to add clean-up to removeF10MenuOptions()
local function addF10MenuOptions()
    timer.scheduleFunction(dwac.addF10MenuOptions, nil, timer.getTime() + dwac.f10MenuUpdateFrequency)
    -- FAC-A
    local _units = dwac.getCurrentFACCapableUnits()
    if _units then
        for _, _unit in pairs(_units) do
            dwac.addFACMenuFeatures(_unit)
        end
    end
end
dwac.addF10MenuOptions = addF10MenuOptions

local function missionStopHandler(event)
    dwac.writeDebug("Closing event handlers")
    if mapIlluminationRequestHandler then
        world.removeEventHandler(mapIlluminationRequestHandler)
    end
    if dwac.mapSmokeRequestHandler then
        world.removeEventHandler(mapSmokeRequestHandler)
    end
    if dwac.logger then
        dwac.logger:write(dwac.getLogTimeStamp() .. "Mission End.  Closing logger.\n")
        dwac.logger:flush()
        dwac.logger:close()
        dwac.logger = nil
    end
end
dwac.missionStopHandler = missionStopHandler

-- ##########################
-- EVENT HANDLING
-- ##########################
dwac.dwacEventHandler = {}
function dwac.dwacEventHandler:onEvent(event)
    -- *** Close Logger on Mission Stop***
    if event.id == world.event.S_EVENT_MISSION_END then
        dwac.missionStopHandler(event)
    end

    -- *** Map Request ***
    if event.id == world.event.S_EVENT_MARK_CHANGE then
        local markerPanels = world.getMarkPanels()
        for i, panel in ipairs(markerPanels) do
            if event.idx == panel.idx then
                local markType = dwac.getMarkerRequest(panel.text)
                if dwac.enableMapSmoke and markType == dwac.MapRequest.SMOKE then
                    if dwac.setMapSmoke(panel.text, panel.pos) then
                        timer.scheduleFunction(trigger.action.removeMark, panel.idx, timer.getTime() + 2)
                    end
                    break
                elseif dwac.enableMapIllumination and markType == dwac.MapRequest.ILLUMINATION then
                    panel.pos.y = dwac.mapIlluminationAltitude
                    if dwac.setMapIllumination(panel.pos) then
                        timer.scheduleFunction(trigger.action.removeMark, panel.idx, timer.getTime() + 2)
                    end
                    break
                elseif markType == dwac.MapRequest.VERSION then
                    dwac.showVersion()
                    timer.scheduleFunction(trigger.action.removeMark, panel.idx, timer.getTime() + 2)
                    break
                end
            end
        end
    end
end
world.addEventHandler(dwac.dwacEventHandler)

trigger.action.outText(baseName .. " version: " .. version, dwac.messageDuration, false)
dwac.addF10MenuOptions()

--#endregion

dwac.writeDebug("DWAC Active")
return dwac
