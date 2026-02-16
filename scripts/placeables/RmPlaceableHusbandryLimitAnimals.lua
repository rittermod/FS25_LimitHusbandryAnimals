-- RmPlaceableHusbandryLimitAnimals - Specialization for adding limit keybind to husbandry triggers
-- Author: Ritter

RmPlaceableHusbandryLimitAnimals = {}

RmPlaceableHusbandryLimitAnimals.MOD_NAME = g_currentModName
RmPlaceableHusbandryLimitAnimals.SPEC_NAME = string.format("%s.husbandryLimitAnimals", g_currentModName)
RmPlaceableHusbandryLimitAnimals.SPEC_TABLE_NAME = string.format("spec_%s", RmPlaceableHusbandryLimitAnimals.SPEC_NAME)

--- Check if this specialization can be added (requires PlaceableHusbandryAnimals)
function RmPlaceableHusbandryLimitAnimals.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableHusbandryAnimals, specializations)
end

--- Register event listeners
function RmPlaceableHusbandryLimitAnimals.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onPostLoad", RmPlaceableHusbandryLimitAnimals)
    SpecializationUtil.registerEventListener(placeableType, "onHusbandryAnimalsCreated", RmPlaceableHusbandryLimitAnimals)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", RmPlaceableHusbandryLimitAnimals)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", RmPlaceableHusbandryLimitAnimals)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", RmPlaceableHusbandryLimitAnimals)
end

--- Called after placeable loads - patch activatable to add our keybind
--- Uses non-destructive method wrapping to preserve compatibility with other mods
--- (e.g., MoveHusbandryAnimals) that also extend the activatable
function RmPlaceableHusbandryLimitAnimals:onPostLoad(savegame)
    local husbandryAnimalsSpec = self.spec_husbandryAnimals
    local animalLoadingTrigger = husbandryAnimalsSpec.animalLoadingTrigger

    -- Patch activatable to add our input binding (only for non-dealer husbandries)
    if animalLoadingTrigger ~= nil and animalLoadingTrigger.activatable ~= nil then
        if not animalLoadingTrigger.isDealer and animalLoadingTrigger.husbandry == self then
            local activatable = animalLoadingTrigger.activatable

            -- Store original methods (may be nil for base class, defined for custom activatables like MoveHusbandryAnimals)
            local origRegister = activatable.registerCustomInput
            local origRemove = activatable.removeCustomInput

            -- Wrap registerCustomInput to add our keybinding while preserving other mods' keybindings
            activatable.registerCustomInput = function(act, inputContext)
                -- Call original first (preserves other mods' keybindings)
                if origRegister then
                    origRegister(act, inputContext)
                end
                -- Add our limit keybinding (player on foot only)
                if inputContext == PlayerInputComponent.INPUT_CONTEXT_NAME then
                    local _, actionEventId = g_inputBinding:registerActionEvent(
                        InputAction.RM_LIMIT_HUSBANDRY_ANIMALS,
                        act,
                        RmPlaceableHusbandryLimitAnimals.actionEventLimitAnimals,
                        false, true, false, true)
                    g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("rm_lha_action_setLimit"))
                    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
                    g_inputBinding:setActionEventTextVisibility(actionEventId, true)
                    act.rmLimitAnimalsActionEventId = actionEventId
                end
            end

            -- Wrap removeCustomInput to clean up our keybinding
            activatable.removeCustomInput = function(act, inputContext)
                -- Call original first
                if origRemove then
                    origRemove(act, inputContext)
                end
                -- Remove our keybinding
                if act.rmLimitAnimalsActionEventId then
                    g_inputBinding:removeActionEvent(act.rmLimitAnimalsActionEventId)
                    act.rmLimitAnimalsActionEventId = nil
                end
            end

            -- Store reference to husbandry for action handler
            activatable.rmHusbandry = self

            self[RmPlaceableHusbandryLimitAnimals.SPEC_TABLE_NAME].activatablePatched = true
            Log:debug("Patched activatable for %s (preserves other mods)", self:getName())
        end
    end
end

--- Handle limit action event (static function called with activatable as first arg)
---@param activatable table The activatable instance
---@param actionName string Action name
---@param inputValue number Input value
---@param callbackState any Callback state
---@param isAnalog boolean Whether input is analog
function RmPlaceableHusbandryLimitAnimals.actionEventLimitAnimals(activatable, actionName, inputValue, callbackState, isAnalog)
    local husbandry = activatable.rmHusbandry
    if husbandry == nil or activatable.owner == nil then
        InfoDialog.show(g_i18n:getText("rm_lha_error_notAvailable"))
        return
    end

    -- Check permission (handles both SP and MP cases)
    local canModify, errorKey = RmLimitHusbandryAnimals:canModifyLimit(husbandry)
    if not canModify then
        InfoDialog.show(g_i18n:getText(errorKey))
        return
    end

    -- Show limit dialog
    RmLimitHusbandryAnimals:showLimitDialog(husbandry)
end

--- Called when husbandry animals system is created (fires after navigation mesh is created/recreated)
--- IMPORTANT: For fenced pastures, this event fires MULTIPLE times on BOTH server AND client:
---   1. First during initial placement (capacity = initial nav mesh, e.g., 19)
---   2. Again after fence customization finishes (capacity = fence area, e.g., 72)
--- We ALWAYS update originalLimit here, so the last call has the correct capacity.
--- Both server and client track this - server for validation, client for display.
--- Only exception: if a custom limit has been set, we don't overwrite the original.
---@param husbandryId number The husbandry ID (unused, but part of event signature)
function RmPlaceableHusbandryLimitAnimals:onHusbandryAnimalsCreated(husbandryId)
    local uniqueId = self.uniqueId
    local spec = self.spec_husbandryAnimals

    if spec ~= nil and uniqueId ~= nil then
        local currentMax = spec.maxNumAnimals or spec.baseMaxNumAnimals or 0
        local previousOriginal = RmLimitHusbandryAnimals.originalLimits[uniqueId]
        local hasCustomLimit = RmLimitHusbandryAnimals.customLimits[uniqueId] ~= nil

        -- Don't update if custom limit is set (preserve original for validation/reset)
        if hasCustomLimit then
            Log:debug(
                "onHusbandryAnimalsCreated: %s (maxNumAnimals=%d) - keeping original %d (has custom limit)",
                self:getName(), currentMax, previousOriginal or 0)
            return
        end

        -- Update originalLimit (may fire multiple times, last call has correct value)
        RmLimitHusbandryAnimals.originalLimits[uniqueId] = currentMax

        if previousOriginal ~= nil and previousOriginal ~= currentMax then
            Log:debug("onHusbandryAnimalsCreated: %s updated original %d -> %d (fence area changed)",
                self:getName(), previousOriginal, currentMax)
        else
            Log:debug("onHusbandryAnimalsCreated: %s captured original limit %d",
                self:getName(), currentMax)
        end
    end
end

--- Called when placeable is deleted/sold
--- Cleans up customLimits and originalLimits to prevent stale data
function RmPlaceableHusbandryLimitAnimals:onDelete()
    local uniqueId = self.uniqueId

    if uniqueId ~= nil then
        local hadCustomLimit = RmLimitHusbandryAnimals.customLimits[uniqueId] ~= nil
        local hadOriginalLimit = RmLimitHusbandryAnimals.originalLimits[uniqueId] ~= nil

        -- Clean up on both server and client
        RmLimitHusbandryAnimals.customLimits[uniqueId] = nil
        RmLimitHusbandryAnimals.originalLimits[uniqueId] = nil

        if hadCustomLimit or hadOriginalLimit then
            Log:debug("Cleaned up limits for deleted husbandry: %s", self:getName() or uniqueId)
        end
    end
end

--- Called on server side when syncing placeable to a new client
--- Writes original and custom limit data to the network stream
---@param streamId number Network stream ID
---@param connection table Network connection
function RmPlaceableHusbandryLimitAnimals:onWriteStream(streamId, connection)
    local uniqueId = self.uniqueId
    local originalLimit = RmLimitHusbandryAnimals.originalLimits[uniqueId]
    local customLimit = RmLimitHusbandryAnimals.customLimits[uniqueId]

    -- Send original limit (may be nil for new pens where nav mesh hasn't loaded yet)
    if streamWriteBool(streamId, originalLimit ~= nil) then
        streamWriteInt32(streamId, originalLimit)
        Log:debug("WriteStream: Sending original limit %d for %s", originalLimit, self:getName())
    end

    -- Send custom limit
    if streamWriteBool(streamId, customLimit ~= nil) then
        streamWriteInt32(streamId, customLimit)
        Log:debug("WriteStream: Sending custom limit %d for %s", customLimit, self:getName())
    end
end

--- Called on client side when receiving placeable sync from server
--- Reads and applies original and custom limit data from the network stream
---@param streamId number Network stream ID
---@param connection table Network connection
function RmPlaceableHusbandryLimitAnimals:onReadStream(streamId, connection)
    local uniqueId = self.uniqueId
    local spec = self.spec_husbandryAnimals

    -- Read original limit
    if streamReadBool(streamId) then
        local originalLimit = streamReadInt32(streamId)
        if uniqueId ~= nil then
            RmLimitHusbandryAnimals.originalLimits[uniqueId] = originalLimit
            Log:debug("ReadStream: Received original limit %d for %s", originalLimit, self:getName())
        end
    end

    -- Read custom limit
    if streamReadBool(streamId) then
        local customLimit = streamReadInt32(streamId)
        if spec ~= nil and uniqueId ~= nil then
            spec.maxNumAnimals = customLimit
            RmLimitHusbandryAnimals.customLimits[uniqueId] = customLimit
            Log:debug("ReadStream: Applied custom limit %d for %s", customLimit, self:getName())
        end
    end
end
