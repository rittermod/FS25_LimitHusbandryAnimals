-- RmLimitHusbandryAnimalsSyncEvent - Multiplayer sync event for LimitHusbandryAnimals
-- Author: Ritter
--
-- Description: Synchronizes animal limit changes between server and clients

RmLimitHusbandryAnimalsSyncEvent = {}

-- Action types
RmLimitHusbandryAnimalsSyncEvent.ACTION_SET_LIMIT = 0
RmLimitHusbandryAnimalsSyncEvent.ACTION_RESET_LIMIT = 1

-- Result codes
RmLimitHusbandryAnimalsSyncEvent.RESULT_OK = 0
RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_FOUND = 1
RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_OWNER = 2
RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_MANAGER = 3
RmLimitHusbandryAnimalsSyncEvent.ERROR_INVALID_LIMIT = 4
RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN = 255

local RmLimitHusbandryAnimalsSyncEvent_mt = Class(RmLimitHusbandryAnimalsSyncEvent, Event)
InitEventClass(RmLimitHusbandryAnimalsSyncEvent, "RmLimitHusbandryAnimalsSyncEvent")

--- Create empty event instance
function RmLimitHusbandryAnimalsSyncEvent.emptyNew()
    return Event.new(RmLimitHusbandryAnimalsSyncEvent_mt)
end

--- Create new event for client -> server request
---@param husbandry table The husbandry placeable object
---@param newLimit number New limit value (ignored for RESET action)
---@param actionType number ACTION_SET_LIMIT or ACTION_RESET_LIMIT
function RmLimitHusbandryAnimalsSyncEvent.new(husbandry, newLimit, actionType)
    local self = RmLimitHusbandryAnimalsSyncEvent.emptyNew()

    self.husbandry = husbandry
    self.newLimit = newLimit or 0
    self.actionType = actionType or RmLimitHusbandryAnimalsSyncEvent.ACTION_SET_LIMIT

    return self
end

--- Create event for server -> client response/broadcast
---@param errorCode number Error code (0 = success)
---@param husbandry table The husbandry placeable object
---@param appliedLimit number The limit that was applied (for confirmation)
---@param originalLimit number|nil The original limit (optional, for syncing to clients)
---@param isSyncOriginal boolean|nil Whether this is just syncing original limit (no limit change)
function RmLimitHusbandryAnimalsSyncEvent.newServerToClient(errorCode, husbandry, appliedLimit, originalLimit,
                                                            isSyncOriginal)
    local self = RmLimitHusbandryAnimalsSyncEvent.emptyNew()

    self.errorCode = errorCode or RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN
    self.husbandry = husbandry
    self.appliedLimit = appliedLimit or 0
    self.originalLimit = originalLimit -- May be nil
    self.isSyncOriginal = isSyncOriginal or false
    self.isResponse = true

    return self
end

--- Read event data from network stream
---@param streamId number Network stream ID
---@param connection table Network connection
function RmLimitHusbandryAnimalsSyncEvent:readStream(streamId, connection)
    if not connection:getIsServer() then
        -- SERVER receiving from CLIENT (request)
        self.husbandry = NetworkUtil.readNodeObject(streamId)
        self.newLimit = streamReadInt32(streamId)
        self.actionType = streamReadUIntN(streamId, 2)
        self.isResponse = false
    else
        -- CLIENT receiving from SERVER (response/broadcast)
        self.errorCode = streamReadUIntN(streamId, 8)
        self.husbandry = NetworkUtil.readNodeObject(streamId)
        self.appliedLimit = streamReadInt32(streamId)
        self.isSyncOriginal = streamReadBool(streamId)
        -- Read original limit if present
        if streamReadBool(streamId) then
            self.originalLimit = streamReadInt32(streamId)
        end
        self.isResponse = true
    end

    self:run(connection)
end

--- Write event data to network stream
---@param streamId number Network stream ID
---@param connection table Network connection
function RmLimitHusbandryAnimalsSyncEvent:writeStream(streamId, connection)
    if connection:getIsServer() then
        -- CLIENT sending to SERVER (request)
        NetworkUtil.writeNodeObject(streamId, self.husbandry)
        streamWriteInt32(streamId, self.newLimit or 0)
        streamWriteUIntN(streamId, self.actionType or 0, 2)
    else
        -- SERVER sending to CLIENT (response/broadcast)
        streamWriteUIntN(streamId, self.errorCode or RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN, 8)
        NetworkUtil.writeNodeObject(streamId, self.husbandry)
        streamWriteInt32(streamId, self.appliedLimit or 0)
        streamWriteBool(streamId, self.isSyncOriginal or false)
        -- Write original limit if present
        if streamWriteBool(streamId, self.originalLimit ~= nil) then
            streamWriteInt32(streamId, self.originalLimit)
        end
    end
end

--- Execute the event
---@param connection table Network connection
function RmLimitHusbandryAnimalsSyncEvent:run(connection)
    if not connection:getIsServer() then
        -- SERVER processing CLIENT request
        self:runOnServer(connection)
    else
        -- CLIENT processing SERVER response
        self:runOnClient()
    end
end

--- Server-side processing of limit change request
---@param connection table Network connection from requesting client
function RmLimitHusbandryAnimalsSyncEvent:runOnServer(connection)
    local actionName = self.actionType == RmLimitHusbandryAnimalsSyncEvent.ACTION_RESET_LIMIT and "RESET" or "SET"

    local errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN
    local appliedLimit = 0

    -- Get the husbandry directly from network object
    local husbandry = self.husbandry

    if husbandry == nil then
        errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_FOUND
        RmLogging.logWarning("Server received %s request but husbandry is nil", actionName)
    else
        RmLogging.logDebug("Server received %s request for husbandry %s (newLimit=%d)",
            actionName, husbandry:getName(), self.newLimit)
        -- Get the requesting user (for admin check and name)
        local user = g_currentMission.userManager:getUserByConnection(connection)
        local player = g_currentMission:getPlayerByConnection(connection)

        if user == nil then
            RmLogging.logWarning("Could not find user for connection")
            errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN
        elseif player == nil then
            RmLogging.logWarning("Could not find player for connection")
            errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN
        else
            -- Debug: log user object details
            -- Note: user:getUniqueUserId() returns a hash string, but farm uses numeric userId
            local userUniqueId = user:getUniqueUserId() -- Hash string for admin check
            local userId = user.userId or user:getId()  -- Numeric ID for farm manager check
            local playerName = user:getNickname() or user.nickname or "Unknown"
            local playerFarmId = player.farmId

            RmLogging.logDebug("User details: uniqueId=%s, numericId=%s, nickname=%s, playerFarmId=%s",
                tostring(userUniqueId), tostring(userId), tostring(playerName), tostring(playerFarmId))

            if playerFarmId == nil or playerFarmId == FarmManager.SPECTATOR_FARM_ID then
                RmLogging.logWarning("Player %s has no farm or is spectator (farmId=%s)",
                    playerName, tostring(playerFarmId))
                errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_OWNER
            else
                local ownerFarmId = husbandry:getOwnerFarmId()
                local hasPermission = false

                -- Check admin FIRST (can modify ANY husbandry)
                if user:getIsMasterUser() then
                    hasPermission = true
                    RmLogging.logDebug("Player %s is admin (can modify any husbandry)", playerName)
                end

                -- Non-admin: check ownership
                if not hasPermission then
                    if ownerFarmId ~= playerFarmId then
                        errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_OWNER
                        RmLogging.logWarning("Player %s (farm %d) tried to modify husbandry owned by farm %d",
                            playerName, playerFarmId, ownerFarmId)
                    else
                        -- Check if player is farm manager
                        local farm = g_farmManager:getFarmById(playerFarmId)
                        if farm ~= nil then
                            -- Debug: log farm manager info
                            RmLogging.logDebug("Checking farm manager: farm=%s, userId=%s",
                                farm.name or "Unknown", tostring(userId))

                            -- Log all farm managers for debugging
                            if farm.userIdToPlayer ~= nil then
                                for farmUserId, farmPlayer in pairs(farm.userIdToPlayer) do
                                    RmLogging.logDebug("  Farm user: id=%s, isFarmManager=%s",
                                        tostring(farmUserId), tostring(farm:isUserFarmManager(farmUserId)))
                                end
                            end

                            -- Use numeric userId for farm manager check
                            if farm:isUserFarmManager(userId) then
                                hasPermission = true
                                RmLogging.logDebug("Player %s is farm manager", playerName)
                            end
                        else
                            RmLogging.logWarning("Farm not found for farmId=%d", playerFarmId)
                        end
                    end
                end

                if not hasPermission and errorCode == RmLimitHusbandryAnimalsSyncEvent.ERROR_UNKNOWN then
                    errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_MANAGER
                    RmLogging.logWarning("Player %s is not admin or farm manager for farm %d",
                        playerName, playerFarmId)
                end

                -- Permission granted, process the action
                if hasPermission then
                    local uniqueId = husbandry.uniqueId

                    if self.actionType == RmLimitHusbandryAnimalsSyncEvent.ACTION_RESET_LIMIT then
                        -- Reset to original
                        local originalLimit = RmLimitHusbandryAnimals.originalLimits[uniqueId]
                        if originalLimit ~= nil then
                            local spec = husbandry.spec_husbandryAnimals
                            spec.maxNumAnimals = originalLimit
                            RmLimitHusbandryAnimals.customLimits[uniqueId] = nil

                            appliedLimit = originalLimit
                            errorCode = RmLimitHusbandryAnimalsSyncEvent.RESULT_OK

                            RmLogging.logInfo("MP: Reset limit for %s to %d (by %s)",
                                husbandry:getName(), originalLimit, playerName)
                        else
                            RmLogging.logWarning("Original limit not found for %s", uniqueId)
                            errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_FOUND
                        end
                    else
                        -- Set new limit
                        local valid, err = RmLimitHusbandryAnimals:validateLimit(husbandry, self.newLimit)
                        if not valid then
                            errorCode = RmLimitHusbandryAnimalsSyncEvent.ERROR_INVALID_LIMIT
                            RmLogging.logWarning("Invalid limit %d for %s: %s",
                                self.newLimit, husbandry:getName(), err or "unknown")
                        else
                            local spec = husbandry.spec_husbandryAnimals
                            spec.maxNumAnimals = self.newLimit
                            RmLimitHusbandryAnimals.customLimits[uniqueId] = self.newLimit

                            appliedLimit = self.newLimit
                            errorCode = RmLimitHusbandryAnimalsSyncEvent.RESULT_OK

                            RmLogging.logInfo("MP: Set limit for %s to %d (by %s)",
                                husbandry:getName(), self.newLimit, playerName)
                        end
                    end
                end
            end
        end
    end

    -- Send response back to requesting client
    RmLogging.logDebug("Server sending response: errorCode=%d, appliedLimit=%d", errorCode, appliedLimit)
    connection:sendEvent(RmLimitHusbandryAnimalsSyncEvent.newServerToClient(errorCode, husbandry, appliedLimit))

    -- If successful, broadcast to all OTHER clients so they update their local state
    if errorCode == RmLimitHusbandryAnimalsSyncEvent.RESULT_OK then
        RmLogging.logDebug("Broadcasting success to other clients")
        g_server:broadcastEvent(RmLimitHusbandryAnimalsSyncEvent.newServerToClient(errorCode, husbandry, appliedLimit),
            false, connection)
    end
end

--- Client-side processing of server response
function RmLimitHusbandryAnimalsSyncEvent:runOnClient()
    local husbandry = self.husbandry
    local husbandryName = husbandry and husbandry:getName() or "Unknown"

    RmLogging.logDebug(
        "Client received response: errorCode=%d, husbandry=%s, appliedLimit=%d, originalLimit=%s, isSyncOriginal=%s",
        self.errorCode, husbandryName, self.appliedLimit,
        tostring(self.originalLimit), tostring(self.isSyncOriginal))

    if self.errorCode == RmLimitHusbandryAnimalsSyncEvent.RESULT_OK then
        -- Update local state
        if husbandry ~= nil then
            local uniqueId = husbandry.uniqueId

            -- Ensure uniqueId is valid before using as table key
            if uniqueId == nil then
                RmLogging.logWarning("Client: Husbandry %s has nil uniqueId", husbandryName)
                return
            end

            -- Update original limit if provided
            if self.originalLimit ~= nil then
                RmLimitHusbandryAnimals.originalLimits[uniqueId] = self.originalLimit
                RmLogging.logDebug("MP: Stored original limit %d for %s", self.originalLimit, husbandryName)
            end

            -- If this is just syncing original limit, don't apply limit change or show notification
            if self.isSyncOriginal then
                RmLogging.logDebug("MP: Received original limit sync for %s (orig=%d)", husbandryName,
                    self.originalLimit or 0)
                return
            end

            local spec = husbandry.spec_husbandryAnimals
            spec.maxNumAnimals = self.appliedLimit

            -- Update custom limits tracking
            local originalLimit = RmLimitHusbandryAnimals.originalLimits[uniqueId]
            if self.appliedLimit == originalLimit then
                RmLimitHusbandryAnimals.customLimits[uniqueId] = nil
            else
                RmLimitHusbandryAnimals.customLimits[uniqueId] = self.appliedLimit
            end

            RmLogging.logDebug("MP: Updated local limit for %s to %d", husbandryName, self.appliedLimit)

            -- Show success message
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
                string.format(g_i18n:getText("rm_lha_mp_success"), husbandryName, self.appliedLimit))
        else
            RmLogging.logWarning("Client: Husbandry not found in response")
        end
    else
        -- Show error message (only for actual limit change attempts, not sync)
        if not self.isSyncOriginal then
            local errorKey = self:getErrorMessageKey()
            RmLogging.logWarning("Client received error: %s (code=%d)", errorKey, self.errorCode)
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText(errorKey))
        end
    end
end

--- Get localization key for error message
---@return string errorKey Localization key
function RmLimitHusbandryAnimalsSyncEvent:getErrorMessageKey()
    if self.errorCode == RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_FOUND then
        return "rm_lha_error_notFound"
    elseif self.errorCode == RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_OWNER then
        return "rm_lha_error_notOwner"
    elseif self.errorCode == RmLimitHusbandryAnimalsSyncEvent.ERROR_NOT_MANAGER then
        return "rm_lha_error_notManager"
    elseif self.errorCode == RmLimitHusbandryAnimalsSyncEvent.ERROR_INVALID_LIMIT then
        return "rm_lha_error_invalidLimit"
    else
        return "rm_lha_error_unknown"
    end
end

--- Send a limit change request to server (called from client)
---@param husbandry table The husbandry placeable object
---@param newLimit number New limit value
function RmLimitHusbandryAnimalsSyncEvent.sendSetLimit(husbandry, newLimit)
    if husbandry == nil then
        RmLogging.logWarning("sendSetLimit: husbandry is nil")
        return
    end

    RmLogging.logDebug("sendSetLimit called: husbandry=%s, newLimit=%d", husbandry:getName(), newLimit)

    local isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer
    local isServer = g_currentMission:getIsServer()

    -- In SP or as server/host: apply directly. As MP client: send to server
    if not isMultiplayer or isServer then
        -- Single player or server/host can apply directly
        RmLogging.logDebug("Applying SET directly (isMultiplayer=%s, isServer=%s)", tostring(isMultiplayer),
            tostring(isServer))
        local valid, err = RmLimitHusbandryAnimals:validateLimit(husbandry, newLimit)
        if valid then
            local uniqueId = husbandry.uniqueId
            local spec = husbandry.spec_husbandryAnimals
            spec.maxNumAnimals = newLimit
            RmLimitHusbandryAnimals.customLimits[uniqueId] = newLimit

            RmLogging.logInfo("Set limit for %s to %d", husbandry:getName(), newLimit)

            -- Broadcast to all clients (only if MP)
            if isMultiplayer then
                g_server:broadcastEvent(
                    RmLimitHusbandryAnimalsSyncEvent.newServerToClient(
                        RmLimitHusbandryAnimalsSyncEvent.RESULT_OK, husbandry, newLimit
                    )
                )
            end

            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
                string.format(g_i18n:getText("rm_lha_mp_success"), husbandry:getName(), newLimit))
        else
            RmLogging.logWarning("Invalid limit %d for %s: %s", newLimit, husbandry:getName(), err or "unknown")
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("rm_lha_error_invalidLimit"))
        end
    else
        -- Multiplayer client: send request to server using NetworkUtil
        RmLogging.logDebug("Client sending SET request to server")
        g_client:getServerConnection():sendEvent(
            RmLimitHusbandryAnimalsSyncEvent.new(husbandry, newLimit, RmLimitHusbandryAnimalsSyncEvent.ACTION_SET_LIMIT)
        )
    end
end

--- Send a limit reset request to server (called from client)
---@param husbandry table The husbandry placeable object
function RmLimitHusbandryAnimalsSyncEvent.sendResetLimit(husbandry)
    if husbandry == nil then
        RmLogging.logWarning("sendResetLimit: husbandry is nil")
        return
    end

    RmLogging.logDebug("sendResetLimit called: husbandry=%s", husbandry:getName())

    local isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer
    local isServer = g_currentMission:getIsServer()

    -- In SP or as server/host: apply directly. As MP client: send to server
    if not isMultiplayer or isServer then
        -- Single player or server/host can apply directly
        RmLogging.logDebug("Applying RESET directly (isMultiplayer=%s, isServer=%s)", tostring(isMultiplayer),
            tostring(isServer))
        local uniqueId = husbandry.uniqueId
        local originalLimit = RmLimitHusbandryAnimals.originalLimits[uniqueId]
        if originalLimit ~= nil then
            local spec = husbandry.spec_husbandryAnimals
            spec.maxNumAnimals = originalLimit
            RmLimitHusbandryAnimals.customLimits[uniqueId] = nil

            RmLogging.logInfo("Reset limit for %s to %d (original)", husbandry:getName(), originalLimit)

            -- Broadcast to all clients (only if MP)
            if isMultiplayer then
                g_server:broadcastEvent(
                    RmLimitHusbandryAnimalsSyncEvent.newServerToClient(
                        RmLimitHusbandryAnimalsSyncEvent.RESULT_OK, husbandry, originalLimit
                    )
                )
            end

            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
                string.format(g_i18n:getText("rm_lha_mp_success"), husbandry:getName(), originalLimit))
        else
            RmLogging.logWarning("Original limit not found for %s", uniqueId)
        end
    else
        -- Multiplayer client: send request to server using NetworkUtil
        RmLogging.logDebug("Client sending RESET request to server")
        g_client:getServerConnection():sendEvent(
            RmLimitHusbandryAnimalsSyncEvent.new(husbandry, 0, RmLimitHusbandryAnimalsSyncEvent.ACTION_RESET_LIMIT)
        )
    end
end
