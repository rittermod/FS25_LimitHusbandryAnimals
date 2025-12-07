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

--- Called after placeable loads - replace activatable to add our keybind
function RmPlaceableHusbandryLimitAnimals:onPostLoad(savegame)
    local husbandryAnimalsSpec = self.spec_husbandryAnimals
    local animalLoadingTrigger = husbandryAnimalsSpec.animalLoadingTrigger

    -- Replace activatable to add our input binding (only for non-dealer husbandries)
    if animalLoadingTrigger ~= nil and animalLoadingTrigger.activatable ~= nil then
        if not animalLoadingTrigger.isDealer and animalLoadingTrigger.husbandry == self then
            g_currentMission.activatableObjectsSystem:removeActivatable(animalLoadingTrigger.activatable)

            animalLoadingTrigger.activatable = RmAnimalLoadingTriggerLimitActivatable.new(animalLoadingTrigger)
            self[RmPlaceableHusbandryLimitAnimals.SPEC_TABLE_NAME].activatableAdded = true

            RmLogging.logDebug("Replaced activatable for %s", self:getName())
        end
    end
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
            RmLogging.logDebug(
                "onHusbandryAnimalsCreated: %s (maxNumAnimals=%d) - keeping original %d (has custom limit)",
                self:getName(), currentMax, previousOriginal or 0)
            return
        end

        -- Update originalLimit (may fire multiple times, last call has correct value)
        RmLimitHusbandryAnimals.originalLimits[uniqueId] = currentMax

        if previousOriginal ~= nil and previousOriginal ~= currentMax then
            RmLogging.logDebug("onHusbandryAnimalsCreated: %s updated original %d -> %d (fence area changed)",
                self:getName(), previousOriginal, currentMax)
        else
            RmLogging.logDebug("onHusbandryAnimalsCreated: %s captured original limit %d",
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
            RmLogging.logDebug("Cleaned up limits for deleted husbandry: %s", self:getName() or uniqueId)
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
        RmLogging.logDebug("WriteStream: Sending original limit %d for %s", originalLimit, self:getName())
    end

    -- Send custom limit
    if streamWriteBool(streamId, customLimit ~= nil) then
        streamWriteInt32(streamId, customLimit)
        RmLogging.logDebug("WriteStream: Sending custom limit %d for %s", customLimit, self:getName())
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
            RmLogging.logDebug("ReadStream: Received original limit %d for %s", originalLimit, self:getName())
        end
    end

    -- Read custom limit
    if streamReadBool(streamId) then
        local customLimit = streamReadInt32(streamId)
        if spec ~= nil and uniqueId ~= nil then
            spec.maxNumAnimals = customLimit
            RmLimitHusbandryAnimals.customLimits[uniqueId] = customLimit
            RmLogging.logDebug("ReadStream: Applied custom limit %d for %s", customLimit, self:getName())
        end
    end
end

-- Custom activatable that adds our limit keybind
RmAnimalLoadingTriggerLimitActivatable = {}
RmAnimalLoadingTriggerLimitActivatable.MOD_NAME = g_currentModName

local RmAnimalLoadingTriggerLimitActivatable_mt = Class(RmAnimalLoadingTriggerLimitActivatable,
    AnimalLoadingTriggerActivatable)

--- Create new activatable
function RmAnimalLoadingTriggerLimitActivatable.new(owningTrigger)
    local self = setmetatable({}, RmAnimalLoadingTriggerLimitActivatable_mt)

    self.owner = owningTrigger
    self.activateText = g_i18n:getText("animals_openAnimalScreen", owningTrigger.customEnvironment)

    self.activateActionEventId = nil
    self.limitAnimalsActionEventId = nil

    return self
end

--- Register input actions when player enters trigger
function RmAnimalLoadingTriggerLimitActivatable:registerCustomInput(inputContext)
    -- Register original activate action (opens animal screen)
    local _, actionEventId = g_inputBinding:registerActionEvent(InputAction.ACTIVATE_OBJECT, self,
        self.actionEventActivate, false, true, false, true)

    g_inputBinding:setActionEventText(actionEventId, self.activateText)
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventTextVisibility(actionEventId, true)

    self.activateActionEventId = actionEventId

    -- Add our limit action (only for player on foot, not in vehicle)
    if inputContext == PlayerInputComponent.INPUT_CONTEXT_NAME then
        _, actionEventId = g_inputBinding:registerActionEvent(InputAction.RM_LIMIT_HUSBANDRY_ANIMALS, self,
            self.actionEventLimitAnimals, false, true, false, true)

        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("rm_lha_action_setLimit"))
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)

        self.limitAnimalsActionEventId = actionEventId
    end
end

--- Remove input actions when player leaves trigger
function RmAnimalLoadingTriggerLimitActivatable:removeCustomInput(inputContext)
    g_inputBinding:removeActionEventsByTarget(self)

    self.activateActionEventId = nil
    self.limitAnimalsActionEventId = nil
end

--- Handle original activate action (opens animal screen)
function RmAnimalLoadingTriggerLimitActivatable:actionEventActivate(actionName, inputValue, callbackState, isAnalog)
    self:run()
end

--- Handle our limit action (opens limit dialog)
function RmAnimalLoadingTriggerLimitActivatable:actionEventLimitAnimals(actionName, inputValue, callbackState, isAnalog)
    if self.owner == nil or self.owner.husbandry == nil then
        InfoDialog.show(g_i18n:getText("rm_lha_error_notAvailable"))
        return
    end

    local husbandry = self.owner.husbandry

    -- Check permission (handles both SP and MP cases)
    local canModify, errorKey = RmLimitHusbandryAnimals:canModifyLimit(husbandry)
    if not canModify then
        InfoDialog.show(g_i18n:getText(errorKey))
        return
    end

    -- Show limit dialog
    RmLimitHusbandryAnimals:showLimitDialog(husbandry)
end
