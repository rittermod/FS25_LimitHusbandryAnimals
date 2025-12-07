-- RmLimitHusbandryAnimals - Main module for LimitHusbandryAnimals
-- Author: Ritter
--
-- Description: Limits the maximum number of animals in animal pens

RmLimitHusbandryAnimals = {}
RmLimitHusbandryAnimals.modDirectory = g_currentModDirectory
RmLimitHusbandryAnimals.modName = g_currentModName

-- Storage for limits
-- Key = uniqueId, Value = limit
RmLimitHusbandryAnimals.customLimits = {}   -- User-configured limits (persisted to savegame)
RmLimitHusbandryAnimals.originalLimits = {} -- Original limits captured on first load (for validation)

-- Console error messages (hardcoded English - console is developer-facing)
local CONSOLE_ERRORS = {
    rm_lha_error_notOwner = "You don't own this husbandry",
    rm_lha_error_notManager = "You must be farm manager to change limits",
    rm_lha_error_notFound = "Husbandry not found",
    rm_lha_error_invalidLimit = "Invalid limit value",
    rm_lha_error_unknown = "An unknown error occurred"
}

-- Initialize logging (prefix updated in setLoggingContext after mission starts)
RmLogging.setLogPrefix("[RmLimitHusbandryAnimals]")
RmLogging.setLogLevel(RmLogging.LOG_LEVEL.DEBUG)

--- Detects server/client context and updates logging prefix accordingly
--- Called during initialization to distinguish between dedicated server, listen server, and client
local function setLoggingContext()
    local prefix = "[RmLimitHusbandryAnimals"
    local contextName = ""

    if g_dedicatedServer ~= nil then
        prefix = prefix .. "|SERVER-DEDICATED]"
        contextName = "Dedicated Server"
    elseif g_server ~= nil and g_client ~= nil then
        prefix = prefix .. "|SERVER-LISTEN]"
        contextName = "Listen Server (Host)"
    elseif g_client ~= nil and g_server == nil then
        prefix = prefix .. "|CLIENT]"
        contextName = "Pure Client"
    else
        prefix = prefix .. "|UNKNOWN]"
        contextName = "Unknown (no g_server or g_client)"
    end

    RmLogging.setLogPrefix(prefix)
    RmLogging.logInfo("Context detected: %s", contextName)

    -- Debug: Log detection variables
    RmLogging.logDebug("g_server=%s, g_client=%s, g_dedicatedServer=%s, isMultiplayer=%s",
        tostring(g_server ~= nil),
        tostring(g_client ~= nil),
        tostring(g_dedicatedServer ~= nil),
        tostring(g_currentMission.missionDynamicInfo.isMultiplayer))
end

--- Called when map is loaded
function RmLimitHusbandryAnimals:loadMap()
    RmLogging.logInfo("Mod loaded successfully (v%s)", g_modManager:getModByName(self.modName).version)

    -- Register console commands
    addConsoleCommand("lhaList", "Lists all husbandries with current limits", "consoleCommandList", self)
    addConsoleCommand("lhaSet", "Sets limit: lhaSet <index> <limit> (e.g. lhaSet 1 20)", "consoleCommandSet", self)
    addConsoleCommand("lhaReset", "Resets limit to original: lhaReset <index>", "consoleCommandReset", self)
end

--- Called when mission starts (via hook) - placeables are populated at this point
function RmLimitHusbandryAnimals.onMissionStarted()
    -- Set logging context based on server/client role
    setLoggingContext()

    RmLogging.logInfo("Mission started, initializing...")

    -- NOTE: Original limits are captured via onHusbandryAnimalsCreated in the specialization
    -- (RmPlaceableHusbandryLimitAnimals.lua). This event fires when nav mesh is created/recreated.
    -- For fenced pastures, it fires MULTIPLE times - we always update originalLimit so the last
    -- call (after fence customization) has the correct capacity.
    --
    -- For savegame loads: applyAllLimits captures original BEFORE applying custom limits.
    -- For new placements: onHusbandryAnimalsCreated updates on both server AND client.

    -- Load custom limits from savegame (server only - clients get limits from server)
    RmLimitHusbandryAnimals:loadFromSavegame()

    -- Apply loaded limits (also captures original limits for savegame-loaded husbandries)
    RmLimitHusbandryAnimals:applyAllLimits()

    -- Log current state
    RmLimitHusbandryAnimals:logAllHusbandries()
end

--- Ensure originalLimit is captured for a husbandry (fallback/safety measure)
--- Primary capture is via onHusbandryAnimalsCreated in the specialization.
--- This function serves as a fallback for edge cases where the event didn't fire
--- (e.g., older savegames, mods loaded mid-game, validation before event fires).
---@param husbandry table The husbandry placeable
---@return number originalLimit The original limit for this husbandry
function RmLimitHusbandryAnimals:ensureOriginalLimit(husbandry)
    local uniqueId = husbandry.uniqueId
    local spec = husbandry.spec_husbandryAnimals

    -- Already captured?
    if self.originalLimits[uniqueId] ~= nil then
        return self.originalLimits[uniqueId]
    end

    -- Capture current maxNumAnimals as the original
    -- For fenced pastures: this is the fence-calculated capacity
    -- For fixed buildings: this is the building's capacity
    local currentMax = spec.maxNumAnimals or spec.baseMaxNumAnimals or 0
    self.originalLimits[uniqueId] = currentMax

    RmLogging.logDebug("Captured original limit %d for %s (lazy)", currentMax, husbandry:getName())

    return currentMax
end

--- Validate a new limit value
---@param husbandry table The husbandry placeable
---@param newLimit number The proposed new limit
---@return boolean valid Whether the limit is valid
---@return string|nil error Error message if invalid
function RmLimitHusbandryAnimals:validateLimit(husbandry, newLimit)
    local currentAnimals = husbandry:getNumOfAnimals() or 0

    -- Ensure original limit is captured (lazy capture)
    local originalMax = self:ensureOriginalLimit(husbandry)

    if newLimit < currentAnimals then
        return false, string.format("Limit (%d) cannot be lower than current animals (%d)", newLimit, currentAnimals)
    end

    if newLimit > originalMax then
        return false, string.format("Limit (%d) cannot exceed original capacity (%d)", newLimit, originalMax)
    end

    return true, nil
end

--- Check if current player can modify a husbandry's limit
--- Admins can modify any husbandry
--- Non-admins must own the husbandry and be farm manager (in MP)
---@param husbandry table The husbandry placeable
---@return boolean canModify Whether the player can modify the limit
---@return string|nil errorKey Localization key for error message if not allowed
function RmLimitHusbandryAnimals:canModifyLimit(husbandry)
    if husbandry == nil then
        return false, "rm_lha_error_notAvailable"
    end

    local ownerFarmId = husbandry:getOwnerFarmId()
    local playerFarmId = g_currentMission:getFarmId()
    local isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer

    -- Check admin/server status first (can modify ANY husbandry)
    if isMultiplayer then
        -- Server/host can modify any husbandry
        if g_currentMission:getIsServer() then
            return true, nil
        end

        -- Admin (master user) can modify any husbandry
        if g_currentMission.isMasterUser then
            return true, nil
        end
    end

    -- Non-admin: must own the husbandry
    if ownerFarmId ~= playerFarmId then
        return false, "rm_lha_error_notOwner"
    end

    -- Single player: ownership is sufficient
    if not isMultiplayer then
        return true, nil
    end

    -- Multiplayer non-admin: must be farm manager
    local farm = g_farmManager:getFarmById(playerFarmId)
    if farm ~= nil and farm:isUserFarmManager(g_currentMission.playerUserId) then
        return true, nil
    end

    -- Not authorized
    return false, "rm_lha_error_notManager"
end

--- Apply all custom limits to husbandries
--- Important: captures original limits BEFORE applying custom limits
function RmLimitHusbandryAnimals:applyAllLimits()
    local husbandrySystem = g_currentMission.husbandrySystem
    if husbandrySystem == nil or husbandrySystem.placeables == nil then
        return
    end

    local applied = 0
    for _, husbandry in ipairs(husbandrySystem.placeables) do
        local uniqueId = husbandry.uniqueId
        local limit = self.customLimits[uniqueId]

        if limit ~= nil then
            local spec = husbandry.spec_husbandryAnimals
            if spec then
                -- IMPORTANT: Capture original limit BEFORE applying custom limit
                -- This ensures we know the true original for validation/reset
                if self.originalLimits[uniqueId] == nil then
                    self.originalLimits[uniqueId] = spec.maxNumAnimals or spec.baseMaxNumAnimals or 0
                    RmLogging.logDebug("Captured original limit %d for %s (before applying custom)",
                        self.originalLimits[uniqueId], husbandry:getName())
                end

                spec.maxNumAnimals = limit
                applied = applied + 1
            end
        end
    end

    if applied > 0 then
        RmLogging.logInfo("Applied %d custom limit(s)", applied)
    end
end

--- Set a custom limit for a husbandry
---@param identifier string Index (1,2,3) or unique ID
---@param limit number The new limit
---@return boolean success Whether the limit was set
---@return string|nil error Error message if failed
function RmLimitHusbandryAnimals:setLimit(identifier, limit)
    local husbandry = self:getHusbandryByIdentifier(identifier)
    if husbandry == nil then
        return false, "Husbandry not found (use lhaList to see valid indexes)"
    end

    -- Validate
    local valid, err = self:validateLimit(husbandry, limit)
    if not valid then
        return false, err
    end

    -- Apply
    local spec = husbandry.spec_husbandryAnimals
    local oldLimit = spec.maxNumAnimals or 0
    spec.maxNumAnimals = limit
    self.customLimits[husbandry.uniqueId] = limit -- Always store by uniqueId for persistence

    RmLogging.logInfo("Set limit for %s: %d -> %d", husbandry:getName(), oldLimit, limit)
    return true, nil
end

--- Reset a husbandry to its original limit
---@param identifier string Index (1,2,3) or unique ID
---@return boolean success Whether the limit was reset
---@return string|nil error Error message if failed
function RmLimitHusbandryAnimals:resetLimit(identifier)
    local husbandry = self:getHusbandryByIdentifier(identifier)
    if husbandry == nil then
        return false, "Husbandry not found (use lhaList to see valid indexes)"
    end

    local uniqueId = husbandry.uniqueId
    local originalLimit = self.originalLimits[uniqueId]
    if originalLimit == nil then
        return false, "Original limit not found"
    end

    local spec = husbandry.spec_husbandryAnimals
    local oldLimit = spec.maxNumAnimals or 0
    spec.maxNumAnimals = originalLimit
    self.customLimits[uniqueId] = nil -- Remove from custom limits

    RmLogging.logInfo("Reset limit for %s: %d -> %d (original)", husbandry:getName(), oldLimit, originalLimit)
    return true, nil
end

--- Get a husbandry by index or unique ID
--- Accepts: "1", "2", "3" (index) or full uniqueId string
---@param identifier string Index number or unique ID
---@return table|nil husbandry The husbandry or nil if not found
function RmLimitHusbandryAnimals:getHusbandryByIdentifier(identifier)
    local husbandrySystem = g_currentMission.husbandrySystem
    if husbandrySystem == nil or husbandrySystem.placeables == nil then
        return nil
    end

    -- Try as index first (short form: 1, 2, 3...)
    local index = tonumber(identifier)
    if index ~= nil then
        local placeables = husbandrySystem.placeables
        if index >= 1 and index <= #placeables then
            return placeables[index]
        end
        return nil
    end

    -- Otherwise search by uniqueId
    for _, husbandry in ipairs(husbandrySystem.placeables) do
        if husbandry.uniqueId == identifier then
            return husbandry
        end
    end

    return nil
end

--- Load custom limits from savegame XML
function RmLimitHusbandryAnimals:loadFromSavegame()
    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then
        RmLogging.logDebug("No savegame directory (new game?)")
        return
    end

    local xmlPath = savegameDir .. "/limitHusbandryAnimals.xml"
    if not fileExists(xmlPath) then
        RmLogging.logDebug("No saved limits found")
        return
    end

    local xmlFile = loadXMLFile("limitHusbandryAnimals", xmlPath)
    if xmlFile == 0 then
        RmLogging.logWarning("Failed to load limits file: %s", xmlPath)
        return
    end

    self.customLimits = {}
    local i = 0
    while true do
        local key = string.format("limitHusbandryAnimals.limits.limit(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local uniqueId = getXMLString(xmlFile, key .. "#uniqueId")
        local limit = getXMLInt(xmlFile, key .. "#maxAnimals")

        if uniqueId and limit then
            self.customLimits[uniqueId] = limit
        end

        i = i + 1
    end

    delete(xmlFile)
    RmLogging.logInfo("Loaded %d custom limit(s) from savegame", i)
end

--- Save custom limits to savegame XML
function RmLimitHusbandryAnimals.saveToSavegame()
    local self = RmLimitHusbandryAnimals

    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then
        RmLogging.logWarning("Cannot save: no savegame directory")
        return
    end

    local xmlPath = savegameDir .. "/limitHusbandryAnimals.xml"

    -- Count limits
    local count = self:countTable(self.customLimits)
    if count == 0 then
        -- No custom limits, delete file if exists
        if fileExists(xmlPath) then
            deleteFile(xmlPath)
            RmLogging.logDebug("Removed empty limits file")
        end
        return
    end

    local xmlFile = createXMLFile("limitHusbandryAnimals", xmlPath, "limitHusbandryAnimals")
    if xmlFile == 0 then
        RmLogging.logWarning("Failed to create limits file: %s", xmlPath)
        return
    end

    local i = 0
    for uniqueId, limit in pairs(self.customLimits) do
        local key = string.format("limitHusbandryAnimals.limits.limit(%d)", i)
        setXMLString(xmlFile, key .. "#uniqueId", uniqueId)
        setXMLInt(xmlFile, key .. "#maxAnimals", limit)
        i = i + 1
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
    RmLogging.logInfo("Saved %d custom limit(s) to savegame", count)
end

--- Console command: List all husbandries with limits
function RmLimitHusbandryAnimals:consoleCommandList()
    local husbandrySystem = g_currentMission.husbandrySystem
    if husbandrySystem == nil or husbandrySystem.placeables == nil then
        return "No husbandry system found"
    end

    local placeables = husbandrySystem.placeables
    if #placeables == 0 then
        return "No husbandries found"
    end

    RmLogging.logInfo("=== Husbandry Animal Limits ===")

    for i, husbandry in ipairs(placeables) do
        local uniqueId = husbandry.uniqueId or "N/A"
        local name = husbandry:getName() or "Unknown"
        local spec = husbandry.spec_husbandryAnimals
        local currentAnimals = husbandry:getNumOfAnimals() or 0
        local currentMax = spec.maxNumAnimals or 0
        local originalMax = self.originalLimits[uniqueId] or currentMax
        local ownerFarmId = husbandry:getOwnerFarmId() or 0

        local customMarker = ""
        if self.customLimits[uniqueId] then
            customMarker = " [CUSTOM]"
        end

        RmLogging.logInfo(string.format("#%d: %s (Farm %d)%s", i, name, ownerFarmId, customMarker))
        RmLogging.logInfo(string.format("    Animals: %d / %d (original: %d)", currentAnimals, currentMax, originalMax))
        RmLogging.logInfo(string.format("    UniqueId: %s", uniqueId))
    end

    return string.format("Listed %d husbandries. Use 'lhaSet <index> <limit>' to set a limit.", #placeables)
end

--- Console command: Set limit for a husbandry
function RmLimitHusbandryAnimals:consoleCommandSet(identifier, limitStr)
    if identifier == nil or identifier == "" then
        return "Usage: lhaSet <index> <limit> (e.g. lhaSet 1 20)"
    end

    if limitStr == nil or limitStr == "" then
        return "Usage: lhaSet <index> <limit> (e.g. lhaSet 1 20)"
    end

    local limit = tonumber(limitStr)
    if limit == nil then
        RmLogging.logWarning("lhaSet: Invalid limit '%s' - must be a number", limitStr)
        return "Invalid limit: must be a number"
    end

    local husbandry = self:getHusbandryByIdentifier(identifier)
    if husbandry == nil then
        RmLogging.logWarning("lhaSet: Husbandry not found for identifier '%s'", identifier)
        return "Husbandry not found (use lhaList to see valid indexes)"
    end

    -- Check permission
    local canModify, errorKey = self:canModifyLimit(husbandry)
    if not canModify then
        RmLogging.logWarning("lhaSet: Permission denied - %s", errorKey)
        return "Error: " .. (CONSOLE_ERRORS[errorKey] or errorKey)
    end

    -- Use sync event for MP support (NetworkUtil handles object references)
    RmLogging.logDebug("lhaSet: Requesting limit change for %s to %d", husbandry:getName(), limit)
    RmLimitHusbandryAnimalsSyncEvent.sendSetLimit(husbandry, limit)
    return "Limit change requested..."
end

--- Console command: Reset limit to original
function RmLimitHusbandryAnimals:consoleCommandReset(identifier)
    if identifier == nil or identifier == "" then
        return "Usage: lhaReset <index>"
    end

    local husbandry = self:getHusbandryByIdentifier(identifier)
    if husbandry == nil then
        RmLogging.logWarning("lhaReset: Husbandry not found for identifier '%s'", identifier)
        return "Husbandry not found (use lhaList to see valid indexes)"
    end

    -- Check permission
    local canModify, errorKey = self:canModifyLimit(husbandry)
    if not canModify then
        RmLogging.logWarning("lhaReset: Permission denied - %s", errorKey)
        return "Error: " .. (CONSOLE_ERRORS[errorKey] or errorKey)
    end

    -- Use sync event for MP support (NetworkUtil handles object references)
    RmLogging.logDebug("lhaReset: Requesting limit reset for %s", husbandry:getName())
    RmLimitHusbandryAnimalsSyncEvent.sendResetLimit(husbandry)
    return "Limit reset requested..."
end

--- Log all husbandries with their properties
function RmLimitHusbandryAnimals:logAllHusbandries()
    local husbandrySystem = g_currentMission.husbandrySystem
    if husbandrySystem == nil or husbandrySystem.placeables == nil then
        return
    end

    local placeables = husbandrySystem.placeables
    RmLogging.logInfo("Found %d husbandries", #placeables)

    for i, husbandry in ipairs(placeables) do
        local spec = husbandry.spec_husbandryAnimals
        if spec ~= nil then
            local uniqueId = husbandry.uniqueId or "N/A"
            local name = husbandry:getName() or "Unknown"
            local ownerFarmId = husbandry:getOwnerFarmId() or 0
            local maxNumAnimals = spec.maxNumAnimals or 0
            local originalMax = self.originalLimits[uniqueId] or maxNumAnimals
            local currentAnimals = husbandry:getNumOfAnimals() or 0

            local customMarker = self.customLimits[uniqueId] and " [CUSTOM]" or ""

            RmLogging.logInfo("  #%d: %s (Farm %d) - %d/%d (orig: %d)%s",
                i, name, ownerFarmId, currentAnimals, maxNumAnimals, originalMax, customMarker)
        end
    end
end

--- Called when map is about to unload
function RmLimitHusbandryAnimals:deleteMap()
    RmLogging.logDebug("Mod unloading")

    -- Remove console commands
    removeConsoleCommand("lhaList")
    removeConsoleCommand("lhaSet")
    removeConsoleCommand("lhaReset")

    -- Clear data
    self.customLimits = {}
    self.originalLimits = {}
end

--- Utility: Count table entries
function RmLimitHusbandryAnimals:countTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--- Get husbandry index in the placeables list
---@param husbandry table The husbandry to find
---@return number|nil index The 1-based index or nil if not found
function RmLimitHusbandryAnimals:getHusbandryIndex(husbandry)
    local husbandrySystem = g_currentMission.husbandrySystem
    if husbandrySystem == nil or husbandrySystem.placeables == nil then
        return nil
    end

    for i, h in ipairs(husbandrySystem.placeables) do
        if h == husbandry then
            return i
        end
    end

    return nil
end

--- Show limit dialog for a husbandry (called from activatable)
---@param husbandry table The husbandry placeable
function RmLimitHusbandryAnimals:showLimitDialog(husbandry)
    if husbandry == nil then
        InfoDialog.show(g_i18n:getText("rm_lha_error_notAvailable"))
        return
    end

    local uniqueId = husbandry.uniqueId
    local name = husbandry:getName() or "Unknown"
    local spec = husbandry.spec_husbandryAnimals
    local currentAnimals = husbandry:getNumOfAnimals() or 0
    local currentMax = spec.maxNumAnimals or 0

    -- Ensure original limit is captured (lazy capture for correct fence capacity)
    local originalMax = self:ensureOriginalLimit(husbandry)

    local index = self:getHusbandryIndex(husbandry) or "?"

    local isCustom = self.customLimits[uniqueId] ~= nil
    local customText = isCustom and g_i18n:getText("rm_lha_dialog_customMarker") or ""

    -- Build info text (console hints use hardcoded English)
    local text = string.format(
        "%s%s\n\n%s\n%s\n%s\n\n%s\n%s\n%s",
        name, customText,
        string.format(g_i18n:getText("rm_lha_dialog_currentAnimals"), currentAnimals),
        string.format(g_i18n:getText("rm_lha_dialog_currentLimit"), currentMax),
        string.format(g_i18n:getText("rm_lha_dialog_originalCapacity"), originalMax),
        "To change limit, use console:",
        string.format("  lhaSet %d <new_limit>", index),
        string.format("  lhaReset %d", index)
    )

    InfoDialog.show(text)
end

-- Hook onStartMission - fires after placeables are populated
FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission,
    RmLimitHusbandryAnimals.onMissionStarted)

-- Hook saveSavegame - save limits when game saves
FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, RmLimitHusbandryAnimals.saveToSavegame)

-- Register mod event listener (calls loadMap/deleteMap)
addModEventListener(RmLimitHusbandryAnimals)
