-- RmLimitSetDialog - GUI dialog for setting animal limit
-- Author: Ritter

RmLimitSetDialog = {}
local RmLimitSetDialog_mt = Class(RmLimitSetDialog, DialogElement)

--- Create new dialog instance
function RmLimitSetDialog.new(target, customMt)
    local self = DialogElement.new(target, customMt or RmLimitSetDialog_mt)

    self.isBackAllowed = true
    self.inputDelay = 250

    -- Dialog state
    self.husbandry = nil
    self.currentLimit = 0
    self.originalLimit = 0
    self.minLimit = 0
    self.newLimit = 0

    return self
end

--- Called when dialog opens
function RmLimitSetDialog:onOpen()
    RmLimitSetDialog:superClass().onOpen(self)
    self.inputDelay = self.time + 250
    self:updateDisplay()
end

--- Handle Enter pressed in text input - confirm and close
function RmLimitSetDialog:onEnterPressed()
    self:applyAndClose()
end

--- Handle text changed in input field
function RmLimitSetDialog:onTextChanged(element, text)
    local value = tonumber(text)
    if value ~= nil then
        -- Clamp to bounds
        if value < self.minLimit then
            value = self.minLimit
        elseif value > self.originalLimit then
            value = self.originalLimit
        end
        self.newLimit = value
    end
end

--- Handle OK button click
function RmLimitSetDialog:onClickOK()
    self:applyAndClose()
end

--- Update the display
function RmLimitSetDialog:updateDisplay()
    -- Update text input field
    if self.limitInput ~= nil then
        self.limitInput:setText(tostring(self.newLimit))
    end

    -- Update info text with bounds
    if self.infoTextElement ~= nil then
        local infoText = string.format(g_i18n:getText("rm_lha_dialog_bounds"), self.minLimit, self.originalLimit)
        self.infoTextElement:setText(infoText)
    end
end

--- Apply the limit and close dialog
function RmLimitSetDialog:applyAndClose()
    if self.inputDelay < self.time then
        if self.newLimit ~= self.currentLimit and self.husbandry ~= nil then
            RmLogging.logInfo("RmLimitSetDialog: Setting limit to %d", self.newLimit)

            if RmLimitHusbandryAnimalsSyncEvent ~= nil then
                RmLimitHusbandryAnimalsSyncEvent.sendSetLimit(self.husbandry, self.newLimit)
            else
                RmLogging.logError("RmLimitSetDialog: Sync event not available")
            end
        end

        self:close()
    end
end

--- Handle Cancel button click
function RmLimitSetDialog:onClickCancel()
    if self.inputDelay < self.time then
        self:close()
    end
end

--- Handle back action (ESC)
function RmLimitSetDialog:onClickBack()
    self:onClickCancel()
end

--- Called when dialog closes
function RmLimitSetDialog:onClose()
    RmLimitSetDialog:superClass().onClose(self)
    self.husbandry = nil
    self.currentLimit = 0
    self.originalLimit = 0
    self.minLimit = 0
    self.newLimit = 0
end

--- Set dialog context before showing
function RmLimitSetDialog:setContext(husbandry, currentLimit, originalLimit, currentAnimals)
    self.husbandry = husbandry
    self.currentLimit = currentLimit
    self.originalLimit = originalLimit
    self.minLimit = currentAnimals
    self.newLimit = currentLimit

    if self.dialogTitleElement ~= nil and husbandry ~= nil then
        self.dialogTitleElement:setText(husbandry:getName() or g_i18n:getText("rm_lha_dialog_title"))
    end
end

--- Static: Show the dialog
function RmLimitSetDialog.show(husbandry, currentLimit, originalLimit, currentAnimals)
    local dialogEntry = g_gui.guis["RmLimitSetDialog"]
    if dialogEntry == nil or dialogEntry.target == nil then
        RmLogging.logWarning("RmLimitSetDialog: Dialog not registered")
        return
    end

    dialogEntry.target:setContext(husbandry, currentLimit, originalLimit, currentAnimals)
    g_gui:showDialog("RmLimitSetDialog")
end

--- Static: Register the dialog with GUI system
function RmLimitSetDialog.register()
    local modDirectory = RmLimitHusbandryAnimals.modDirectory
    local dialog = RmLimitSetDialog.new()

    g_gui:loadGui(modDirectory .. "gui/RmLimitSetDialog.xml", "RmLimitSetDialog", dialog)

    RmLogging.logInfo("RmLimitSetDialog registered")
end
