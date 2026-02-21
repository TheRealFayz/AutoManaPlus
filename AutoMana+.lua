-- AutoMana+ by Fayz
-- Automatically use consumables when casting spells

-- Global addon namespace
AutoManaPlus = {}
local AMP = AutoManaPlus

-- Color codes for chat messages
local COLORS = {
    GOLD = "|cffffd100",
    GREEN = "|cff00ff00",
    RED = "|cffff0000",
    BLUE = "|cff4169e1",
    CLOSE = "|r"
}

-- Default settings
local DEFAULT_SETTINGS = {
    enabled = true,
    combatOnly = true,
    minGroupSize = 10,
    useTea = true,
    usePotion = false,
    useRejuv = false,
    useHealthstone = true,
    useFlask = false,
    teaThreshold = 60,
    potionThreshold = 40,
    rejuvThreshold = 50,
    healthstoneThreshold = 30,
    flaskThreshold = 20,
    minimapPos = 180,
    debugMode = false,
    disableOnLogin = true
}

-- Consumable bag/slot cache
local consumableCache = {
    tea = nil,
    potion = nil,
    rejuv = nil,
    healthstone = nil,
    flask = nil
}

-- Player spell texture cache
local spellTextureCache = {}

-- Cooldown tracking
local lastConsumeTime = 0
local CONSUME_COOLDOWN = 1.5

-- Original function references
local Original_CastSpell = nil
local Original_CastSpellByName = nil
local Original_UseAction = nil

-- Print message to chat
local function PrintMessage(msg)
    DEFAULT_CHAT_FRAME:AddMessage(COLORS.GOLD .. "[AutoMana+]" .. COLORS.CLOSE .. " " .. msg)
end

-- Debug print (only when debug mode enabled)
local function DebugMessage(msg)
    if AutoManaPlusDB and AutoManaPlusDB.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage(COLORS.BLUE .. "[AutoMana+ Debug]" .. COLORS.CLOSE .. " " .. msg)
    end
end

-- Search bags for an item by ID or name
local function FindItemInBags(searchTerm)
    local searchByID = type(searchTerm) == "number"
    
    for bagIndex = 0, 4 do
        local numSlots = GetContainerNumSlots(bagIndex)
        for slotIndex = 1, numSlots do
            local itemLink = GetContainerItemLink(bagIndex, slotIndex)
            if itemLink then
                if searchByID then
                    -- Extract item ID from link
                    local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
                    if itemIDStr and tonumber(itemIDStr) == searchTerm then
                        return {bag = bagIndex, slot = slotIndex}
                    end
                else
                    -- Extract item name from link
                    local _, _, itemName = string.find(itemLink, "%[(.-)%]")
                    if itemName and string.find(itemName, searchTerm) then
                        return {bag = bagIndex, slot = slotIndex}
                    end
                end
            end
        end
    end
    
    return nil
end

-- Check if a consumable is off cooldown
local function IsConsumableOffCooldown(consumable)
    if not consumable then
        return false
    end
    
    local startTime, duration = GetContainerItemCooldown(consumable.bag, consumable.slot)
    local currentTime = GetTime()
    return currentTime >= (startTime + duration)
end

-- Update all consumable locations in bags
local function RefreshConsumableLocations()
    DebugMessage("Refreshing consumable locations...")
    
    -- Try Nordanaar Herbal Tea first, fallback to Nightfin Soup
    consumableCache.tea = FindItemInBags(61675)
    if not consumableCache.tea then
        consumableCache.tea = FindItemInBags(15723)
    end
    
    consumableCache.potion = FindItemInBags(13444)
    consumableCache.rejuv = FindItemInBags(18253)
    consumableCache.healthstone = FindItemInBags("Healthstone")
    consumableCache.flask = FindItemInBags(13511)
    
    DebugMessage("Tea: " .. (consumableCache.tea and "FOUND" or "NOT FOUND"))
    DebugMessage("Potion: " .. (consumableCache.potion and "FOUND" or "NOT FOUND"))
    DebugMessage("Rejuv: " .. (consumableCache.rejuv and "FOUND" or "NOT FOUND"))
    DebugMessage("Healthstone: " .. (consumableCache.healthstone and "FOUND" or "NOT FOUND"))
    DebugMessage("Flask: " .. (consumableCache.flask and "FOUND" or "NOT FOUND"))
end

-- Main logic: attempt to use a consumable if needed
-- Returns true if a consumable was used, false otherwise
local function TryUseConsumable()
    DebugMessage("TryUseConsumable called")
    
    -- Check if addon is enabled
    if not AutoManaPlusDB.enabled then
        DebugMessage("Addon is disabled")
        return false
    end
    
    DebugMessage("Addon is enabled")
    
    -- Check global consumable cooldown
    local currentTime = GetTime()
    if currentTime < (lastConsumeTime + CONSUME_COOLDOWN) then
        DebugMessage("Still on global consumable cooldown")
        return false
    end
    
    -- Check combat requirement
    if AutoManaPlusDB.combatOnly and not UnitAffectingCombat("player") then
        DebugMessage("Combat-only mode active and not in combat")
        return false
    end
    
    DebugMessage("Combat check passed")
    
    -- Check group size requirement
    local raidSize = GetNumRaidMembers()
    local partySize = GetNumPartyMembers()
    local groupSize = math.max(1, math.max(raidSize, partySize))
    
    DebugMessage("Group size: " .. groupSize .. " (min required: " .. AutoManaPlusDB.minGroupSize .. ")")
    
    if groupSize < AutoManaPlusDB.minGroupSize then
        DebugMessage("Group too small")
        return false
    end
    
    -- Get player stats
    local currentMana = UnitMana("player")
    local maxMana = UnitManaMax("player")
    local currentHealth = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    
    if maxMana == 0 or maxHealth == 0 then
        DebugMessage("Invalid mana/health values")
        return false
    end
    
    local manaPercent = (currentMana / maxMana) * 100
    local healthPercent = (currentHealth / maxHealth) * 100
    
    DebugMessage("Mana: " .. math.floor(manaPercent) .. "% (" .. currentMana .. "/" .. maxMana .. ")")
    DebugMessage("Health: " .. math.floor(healthPercent) .. "% (" .. currentHealth .. "/" .. maxHealth .. ")")
    
    -- Check consumables in priority order
    
    -- 1. Tea (highest priority for mana)
    if AutoManaPlusDB.useTea and manaPercent < AutoManaPlusDB.teaThreshold then
        DebugMessage("Tea check: useTea=" .. tostring(AutoManaPlusDB.useTea) .. ", manaPercent=" .. math.floor(manaPercent) .. ", threshold=" .. AutoManaPlusDB.teaThreshold)
        if consumableCache.tea then
            DebugMessage("Tea found in bag " .. consumableCache.tea.bag .. " slot " .. consumableCache.tea.slot)
            if IsConsumableOffCooldown(consumableCache.tea) then
                DebugMessage("Using Tea - Mana at " .. math.floor(manaPercent) .. "%")
                UseContainerItem(consumableCache.tea.bag, consumableCache.tea.slot)
                lastConsumeTime = currentTime
                return true
            else
                DebugMessage("Tea is on cooldown")
            end
        else
            DebugMessage("Tea not found in bags")
        end
    end
    
    -- 2. Major Rejuvenation Potion (health)
    if AutoManaPlusDB.useRejuv and healthPercent < AutoManaPlusDB.rejuvThreshold then
        if consumableCache.rejuv and IsConsumableOffCooldown(consumableCache.rejuv) then
            DebugMessage("Using Rejuv Potion - Health at " .. math.floor(healthPercent) .. "%")
            UseContainerItem(consumableCache.rejuv.bag, consumableCache.rejuv.slot)
            lastConsumeTime = currentTime
            return true
        end
    end
    
    -- 3. Healthstone (emergency health)
    if AutoManaPlusDB.useHealthstone and healthPercent < AutoManaPlusDB.healthstoneThreshold then
        if consumableCache.healthstone and IsConsumableOffCooldown(consumableCache.healthstone) then
            DebugMessage("Using Healthstone - Health at " .. math.floor(healthPercent) .. "%")
            UseContainerItem(consumableCache.healthstone.bag, consumableCache.healthstone.slot)
            lastConsumeTime = currentTime
            return true
        end
    end
    
    -- 4. Major Mana Potion
    if AutoManaPlusDB.usePotion and manaPercent < AutoManaPlusDB.potionThreshold then
        if consumableCache.potion and IsConsumableOffCooldown(consumableCache.potion) then
            DebugMessage("Using Mana Potion - Mana at " .. math.floor(manaPercent) .. "%")
            UseContainerItem(consumableCache.potion.bag, consumableCache.potion.slot)
            lastConsumeTime = currentTime
            return true
        end
    end
    
    -- 5. Flask (lowest priority for mana)
    if AutoManaPlusDB.useFlask and manaPercent < AutoManaPlusDB.flaskThreshold then
        if consumableCache.flask and IsConsumableOffCooldown(consumableCache.flask) then
            DebugMessage("Using Flask - Mana at " .. math.floor(manaPercent) .. "%")
            UseContainerItem(consumableCache.flask.bag, consumableCache.flask.slot)
            lastConsumeTime = currentTime
            return true
        end
    end
    
    return false
end

-- Hooked version of CastSpell
function AMP.Hook_CastSpell(spellID, bookType, a3, a4, a5, a6, a7, a8, a9, a10)
    DebugMessage("Hook_CastSpell called: spellID=" .. tostring(spellID) .. ", bookType=" .. tostring(bookType))
    TryUseConsumable()  -- Try to use consumable if needed
    Original_CastSpell(spellID, bookType, a3, a4, a5, a6, a7, a8, a9, a10)  -- Always cast the spell
end

-- Hooked version of CastSpellByName
function AMP.Hook_CastSpellByName(spellName, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    TryUseConsumable()  -- Try to use consumable if needed
    Original_CastSpellByName(spellName, a2, a3, a4, a5, a6, a7, a8, a9, a10)  -- Always cast the spell
end

-- Hooked version of UseAction
function AMP.Hook_UseAction(actionSlot, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    -- Only check consumables if this action is a spell
    local actionTexture = GetActionTexture(actionSlot)
    if actionTexture and spellTextureCache[actionTexture] then
        TryUseConsumable()  -- Try to use consumable if needed
    end
    Original_UseAction(actionSlot, a2, a3, a4, a5, a6, a7, a8, a9, a10)  -- Always execute the action
end

-- Install function hooks
local function InstallFunctionHooks()
    Original_CastSpell = CastSpell
    Original_CastSpellByName = CastSpellByName
    Original_UseAction = UseAction
    
    CastSpell = AMP.Hook_CastSpell
    CastSpellByName = AMP.Hook_CastSpellByName
    UseAction = AMP.Hook_UseAction
    
    DebugMessage("Function hooks installed successfully")
end

-- Cache all player and pet spell textures
local function CachePlayerSpells()
    spellTextureCache = {}
    
    local function CacheSpellbook(bookType)
        local spellIndex = 1
        while true do
            local spellTexture = GetSpellTexture(spellIndex, bookType)
            if not spellTexture then
                break
            end
            spellTextureCache[spellTexture] = true
            spellIndex = spellIndex + 1
        end
    end
    
    CacheSpellbook(BOOKTYPE_SPELL)
    CacheSpellbook(BOOKTYPE_PET)
    
    DebugMessage("Cached " .. table.getn(spellTextureCache) .. " spell textures")
end

-- Initialize settings from saved variables
local function InitializeSettings()
    if not AutoManaPlusDB then
        AutoManaPlusDB = {}
    end
    
    -- Apply defaults for any missing settings
    for settingKey, defaultValue in pairs(DEFAULT_SETTINGS) do
        if AutoManaPlusDB[settingKey] == nil then
            AutoManaPlusDB[settingKey] = defaultValue
        end
    end
end

-- Event handling frame
local eventFrame = CreateFrame("Frame", "AutoManaPlusEventFrame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and (arg1 == "AutoMana+" or arg1 == "AutoManaPlus") then
        InitializeSettings()
        PrintMessage("Loaded! Type " .. COLORS.GREEN .. "/amp" .. COLORS.CLOSE .. " for settings.")
        
    elseif event == "PLAYER_LOGIN" then
        if AutoManaPlusDB.disableOnLogin then
            AutoManaPlusDB.enabled = false
            DebugMessage("Addon disabled on login (disableOnLogin setting)")
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        CachePlayerSpells()
        RefreshConsumableLocations()
        
    elseif event == "BAG_UPDATE" then
        RefreshConsumableLocations()
    end
end)

-- Install hooks immediately on file load
InstallFunctionHooks()

--------------------------------------------------------------------------------
-- UI COMPONENTS
--------------------------------------------------------------------------------

local settingsFrame = nil
local minimapButton = nil

-- Create the main settings frame
local function CreateSettingsFrame()
    if settingsFrame then
        return
    end
    
    local frame = CreateFrame("Frame", "AutoManaPlusSettingsFrame", UIParent)
    frame:SetWidth(355)
    frame:SetHeight(450)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    
    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    
    -- Title text
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", frame, "TOP", 0, -15)
    titleText:SetText("AutoMana+")
    
    -- Subtitle text
    local subtitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOP", titleText, "BOTTOM", 0, -3)
    subtitleText:SetText("By Fayz")
    subtitleText:SetTextColor(0.7, 0.7, 0.7, 1)
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    
    -- Dragging handlers
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)
    
    -- ESC key handling
    table.insert(UISpecialFrames, "AutoManaPlusSettingsFrame")
    
    local yPosition = -60
    
    -- Enable/Disable toggle button
    local enableButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    enableButton:SetWidth(120)
    enableButton:SetHeight(25)
    enableButton:SetPoint("TOP", frame, "TOP", 0, yPosition)
    enableButton:SetText(AutoManaPlusDB.enabled and "Disable" or "Enable")
    enableButton:SetScript("OnClick", function()
        AutoManaPlusDB.enabled = not AutoManaPlusDB.enabled
        this:SetText(AutoManaPlusDB.enabled and "Disable" or "Enable")
        PrintMessage(AutoManaPlusDB.enabled and "Addon enabled" or "Addon disabled")
        
        -- Update minimap button appearance if it exists
        if minimapButton and minimapButton.UpdateAppearance then
            minimapButton.UpdateAppearance()
        end
    end)
    
    -- Store reference to enable button for external updates
    frame.enableButton = enableButton
    
    yPosition = yPosition - 35
    
    -- Combat only checkbox
    local combatCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    combatCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPosition)
    combatCheckbox:SetChecked(AutoManaPlusDB.combatOnly)
    combatCheckbox:SetScript("OnClick", function()
        AutoManaPlusDB.combatOnly = (this:GetChecked() == 1)
    end)
    
    local combatLabel = combatCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatLabel:SetPoint("LEFT", combatCheckbox, "RIGHT", 5, 0)
    combatLabel:SetText("Active only in combat")
    combatLabel:SetTextColor(1, 0.82, 0, 1)
    
    yPosition = yPosition - 30
    
    -- Debug mode checkbox
    local debugCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    debugCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPosition)
    debugCheckbox:SetChecked(AutoManaPlusDB.debugMode)
    debugCheckbox:SetScript("OnClick", function()
        AutoManaPlusDB.debugMode = (this:GetChecked() == 1)
        PrintMessage("Debug mode: " .. (AutoManaPlusDB.debugMode and COLORS.GREEN .. "ON" or COLORS.RED .. "OFF") .. COLORS.CLOSE)
    end)
    
    local debugLabel = debugCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugLabel:SetPoint("LEFT", debugCheckbox, "RIGHT", 5, 0)
    debugLabel:SetText("Debug mode")
    debugLabel:SetTextColor(1, 0.82, 0, 1)
    
    yPosition = yPosition - 30
    
    -- Disable on login checkbox
    local disableOnLoginCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    disableOnLoginCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPosition)
    disableOnLoginCheckbox:SetChecked(AutoManaPlusDB.disableOnLogin)
    disableOnLoginCheckbox:SetScript("OnClick", function()
        AutoManaPlusDB.disableOnLogin = (this:GetChecked() == 1)
    end)
    
    local disableOnLoginLabel = disableOnLoginCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    disableOnLoginLabel:SetPoint("LEFT", disableOnLoginCheckbox, "RIGHT", 5, 0)
    disableOnLoginLabel:SetText("Disable on login")
    disableOnLoginLabel:SetTextColor(1, 0.82, 0, 1)
    
    yPosition = yPosition - 40
    
    -- Min group size label and input
    local groupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPosition)
    groupLabel:SetText("Minimum group size:")
    groupLabel:SetTextColor(1, 0.82, 0, 1)
    
    local groupInput = CreateFrame("EditBox", nil, frame)
    groupInput:SetPoint("LEFT", groupLabel, "RIGHT", 5, 0)
    groupInput:SetWidth(40)
    groupInput:SetHeight(20)
    groupInput:SetAutoFocus(false)
    groupInput:SetMaxLetters(2)
    groupInput:SetFontObject(GameFontHighlight)
    groupInput:SetJustifyH("CENTER")  -- Center align the text
    
    -- Refresh displayed value when settings frame is shown
    groupInput:SetScript("OnShow", function()
        this:SetText(tostring(AutoManaPlusDB.minGroupSize))
    end)
    
    groupInput:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    groupInput:SetBackdropColor(0, 0, 0, 0.9)
    
    groupInput:SetScript("OnTextChanged", function()
        local numericValue = tonumber(this:GetText())
        if numericValue and numericValue >= 0 and numericValue <= 40 then
            AutoManaPlusDB.minGroupSize = numericValue
        end
    end)
    
    groupInput:SetScript("OnEnterPressed", function()
        this:ClearFocus()
    end)
    
    yPosition = yPosition - 35
    
    -- Consumables section header
    local consumablesHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    consumablesHeader:SetPoint("TOP", frame, "TOP", 0, yPosition)
    consumablesHeader:SetText("Consumables")
    consumablesHeader:SetTextColor(1, 0.82, 0, 1)
    
    yPosition = yPosition - 30
    
    -- Helper function to create a consumable configuration row
    local function CreateConsumableRow(displayName, enableKey, thresholdKey, statType)
        local checkbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPosition)
        checkbox:SetChecked(AutoManaPlusDB[enableKey])
        checkbox:SetScript("OnClick", function()
            AutoManaPlusDB[enableKey] = (this:GetChecked() == 1)
        end)
        
        local nameLabel = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        nameLabel:SetText(displayName)
        nameLabel:SetTextColor(1, 0.82, 0, 1)
        
        local thresholdLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        thresholdLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -70, yPosition - 10)
        thresholdLabel:SetText(statType .. " <")
        thresholdLabel:SetTextColor(1, 0.82, 0, 1)
        
        local thresholdInput = CreateFrame("EditBox", nil, frame)
        thresholdInput:SetPoint("LEFT", thresholdLabel, "RIGHT", 5, 0)
        thresholdInput:SetWidth(30)
        thresholdInput:SetHeight(20)
        thresholdInput:SetAutoFocus(false)
        thresholdInput:SetMaxLetters(3)
        thresholdInput:SetFontObject(GameFontHighlight)
        thresholdInput:SetJustifyH("CENTER")  -- Center align the text
        
        -- Refresh displayed value when settings frame is shown
        thresholdInput:SetScript("OnShow", function()
            this:SetText(tostring(AutoManaPlusDB[thresholdKey]))
        end)
        
        thresholdInput:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4}
        })
        thresholdInput:SetBackdropColor(0, 0, 0, 0.9)
        
        thresholdInput:SetScript("OnTextChanged", function()
            local numericValue = tonumber(this:GetText())
            if numericValue and numericValue >= 1 and numericValue <= 100 then
                AutoManaPlusDB[thresholdKey] = numericValue
            end
        end)
        
        thresholdInput:SetScript("OnEnterPressed", function()
            this:ClearFocus()
        end)
        
        local percentSymbol = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        percentSymbol:SetPoint("LEFT", thresholdInput, "RIGHT", 2, 0)
        percentSymbol:SetText("%")
        percentSymbol:SetTextColor(1, 0.82, 0, 1)
        
        yPosition = yPosition - 28
    end
    
    -- Create rows for each consumable
    CreateConsumableRow("Tea", "useTea", "teaThreshold", "Mana")
    CreateConsumableRow("Major Mana Potion", "usePotion", "potionThreshold", "Mana")
    CreateConsumableRow("Major Rejuv Potion", "useRejuv", "rejuvThreshold", "Health")
    CreateConsumableRow("Healthstone", "useHealthstone", "healthstoneThreshold", "Health")
    CreateConsumableRow("Flask of Wisdom", "useFlask", "flaskThreshold", "Mana")
    
    settingsFrame = frame
end

-- Create minimap button
local function CreateMinimapButton()
    if minimapButton then
        return
    end
    
    local button = CreateFrame("Button", "AutoManaPlusMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("RightButton")
    
    -- Icon texture
    local iconTexture = button:CreateTexture(nil, "BACKGROUND")
    iconTexture:SetWidth(20)
    iconTexture:SetHeight(20)
    iconTexture:SetPoint("CENTER", button, "CENTER", 0, 1)
    iconTexture:SetTexture("Interface\\Icons\\INV_Potion_76")
    
    -- Store icon texture for later access
    button.iconTexture = iconTexture
    
    -- Function to update button appearance based on enabled state
    local function UpdateButtonAppearance()
        if AutoManaPlusDB.enabled then
            iconTexture:SetVertexColor(1, 1, 1)  -- Normal color
        else
            iconTexture:SetVertexColor(0.5, 0.5, 0.5)  -- Gray when disabled
        end
    end
    
    -- Store function globally so settings frame can call it
    button.UpdateAppearance = UpdateButtonAppearance
    
    UpdateButtonAppearance()  -- Set initial appearance
    
    -- Border texture
    local borderTexture = button:CreateTexture(nil, "OVERLAY")
    borderTexture:SetWidth(52)
    borderTexture:SetHeight(52)
    borderTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderTexture:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Position update function
    local function UpdateButtonPosition()
        local angleRadians = math.rad(AutoManaPlusDB.minimapPos or 180)
        local xOffset = 80 * math.cos(angleRadians)
        local yOffset = 80 * math.sin(angleRadians)
        button:SetPoint("CENTER", Minimap, "CENTER", xOffset, yOffset)
    end
    
    UpdateButtonPosition()
    
    -- Tooltip
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("AutoMana+", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open settings", 1, 1, 1, 1)
        GameTooltip:AddLine("Right-click: Toggle on/off", 1, 1, 1, 1)
        GameTooltip:AddLine("Right-drag: Move button", 0.7, 0.7, 0.7, 1)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handling
    button:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            if not settingsFrame then
                CreateSettingsFrame()
            end
            
            if settingsFrame:IsShown() then
                settingsFrame:Hide()
            else
                settingsFrame:Show()
            end
            
        elseif arg1 == "RightButton" then
            AutoManaPlusDB.enabled = not AutoManaPlusDB.enabled
            UpdateButtonAppearance()  -- Update visual state
            
            -- Update settings frame enable button text if it exists
            if settingsFrame and settingsFrame.enableButton then
                settingsFrame.enableButton:SetText(AutoManaPlusDB.enabled and "Disable" or "Enable")
            end
            
            local status = AutoManaPlusDB.enabled and "enabled" or "disabled"
            PrintMessage("Addon " .. status)
        end
    end)
    
    -- Dragging functionality
    button:SetScript("OnDragStart", function()
        this.isDragging = true
    end)
    
    button:SetScript("OnDragStop", function()
        this.isDragging = false
    end)
    
    button:SetScript("OnUpdate", function()
        if this.isDragging then
            local mouseX, mouseY = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            local uiScale = Minimap:GetEffectiveScale()
            
            mouseX = mouseX / uiScale
            mouseY = mouseY / uiScale
            
            local angleRadians = math.atan2(mouseY - centerY, mouseX - centerX)
            local angleDegrees = math.deg(angleRadians)
            
            AutoManaPlusDB.minimapPos = angleDegrees
            UpdateButtonPosition()
        end
    end)
    
    minimapButton = button
end

-- Slash command handler
local function HandleSlashCommand(commandText)
    local args = {}
    for word in string.gfind(commandText, "%S+") do
        table.insert(args, string.lower(word))
    end
    
    if args[1] == "status" then
        if AutoManaPlusDB.debugMode then
            PrintMessage("=== Status ===")
            PrintMessage("Enabled: " .. (AutoManaPlusDB.enabled and COLORS.GREEN .. "YES" or COLORS.RED .. "NO") .. COLORS.CLOSE)
            PrintMessage("Combat Only: " .. (AutoManaPlusDB.combatOnly and "YES" or "NO"))
            PrintMessage("Min Group Size: " .. AutoManaPlusDB.minGroupSize)
            PrintMessage("Tea: " .. (AutoManaPlusDB.useTea and "ON" or "OFF") .. " @ " .. AutoManaPlusDB.teaThreshold .. "%")
            PrintMessage("Potion: " .. (AutoManaPlusDB.usePotion and "ON" or "OFF") .. " @ " .. AutoManaPlusDB.potionThreshold .. "%")
            PrintMessage("Rejuv: " .. (AutoManaPlusDB.useRejuv and "ON" or "OFF") .. " @ " .. AutoManaPlusDB.rejuvThreshold .. "%")
            PrintMessage("Healthstone: " .. (AutoManaPlusDB.useHealthstone and "ON" or "OFF") .. " @ " .. AutoManaPlusDB.healthstoneThreshold .. "%")
            PrintMessage("Flask: " .. (AutoManaPlusDB.useFlask and "ON" or "OFF") .. " @ " .. AutoManaPlusDB.flaskThreshold .. "%")
        end
        return
    end
    
    if not settingsFrame then
        CreateSettingsFrame()
    end
    
    if not minimapButton then
        CreateMinimapButton()
    end
    
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
    end
end

-- Register slash commands
SLASH_AUTOMANAPLUS1 = "/automanaplus"
SLASH_AUTOMANAPLUS2 = "/amp"
SlashCmdList["AUTOMANAPLUS"] = HandleSlashCommand

-- Initialize UI on first load
local function InitializeUI()
    CreateMinimapButton()
end

-- Delay UI creation until player enters world
local uiInitFrame = CreateFrame("Frame")
uiInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
uiInitFrame:SetScript("OnEvent", function()
    InitializeUI()
    this:UnregisterAllEvents()
end)
