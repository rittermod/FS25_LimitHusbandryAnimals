-- LimitHusbandryAnimals - Main entry point (loader only)
-- Author: Ritter

local modName = g_currentModName
local modDirectory = g_currentModDirectory

-- Load dependencies
source(modDirectory .. "scripts/RmLogging.lua")
source(modDirectory .. "scripts/RmLimitHusbandryAnimals.lua")
source(modDirectory .. "scripts/events/RmLimitHusbandryAnimalsSyncEvent.lua")
source(modDirectory .. "scripts/gui/RmLimitSetDialog.lua")


--- Validate and inject specialization into husbandry placeable types
local function validateTypes(typeManager)
    if typeManager.typeName == "placeable" then
        local specializationName = RmPlaceableHusbandryLimitAnimals.SPEC_NAME
        local specializationObject = g_placeableSpecializationManager:getSpecializationObjectByName(specializationName)

        if specializationObject ~= nil then
            local numInserted = 0

            for typeName, typeEntry in pairs(typeManager:getTypes()) do
                if specializationObject.prerequisitesPresent(typeEntry.specializations) then
                    typeManager:addSpecialization(typeName, specializationName)
                    numInserted = numInserted + 1
                end
            end

            if numInserted > 0 then
                RmLogging.logInfo("Injected specialization into %d placeable types", numInserted)
            end
        end
    end
end

--- Initialize mod - register specialization and hooks
local function init()
    -- Register the specialization
    g_placeableSpecializationManager:addSpecialization(
        "husbandryLimitAnimals",
        "RmPlaceableHusbandryLimitAnimals",
        modDirectory .. "scripts/placeables/RmPlaceableHusbandryLimitAnimals.lua",
        nil
    )

    -- Hook to inject specialization into husbandry types
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, validateTypes)
end

init()
