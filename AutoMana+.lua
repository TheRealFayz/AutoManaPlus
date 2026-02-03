-- Name: AutoMana+
-- License: LGPL v2.1

local success = true
local failure = nil

local function debug_print(text)
    if AutoManaSettings and AutoManaSettings.debug_mode == true then 
      DEFAULT_CHAT_FRAME:AddMessage("|cFFFF9900[AutoMana+ Debug]|r " .. text) 
    end
end

-- Did an oom event fire
local oom = false

-- User Options
local defaults =
{
  enabled = true,
  combat_only = true,
  min_group_size = 1,
  use_tea = true,
  use_potion = false,
  use_rejuv = false,
  use_flask = false,
  use_healthstone = true,
  -- Thresholds (percentages)
  tea_threshold = 25,        -- use when below 25% mana
  potion_threshold = 40,     -- use when below 40% mana
  rejuv_threshold = 30,      -- use when below 30% health
  healthstone_threshold = 30, -- use when below 30% health
  flask_threshold = 10,      -- use when below 10% mana
  debug_mode = false,        -- show debug messages
  disable_on_login = true,   -- automatically disable on fresh login
}

local consumables = {}

-------------------------------------------------
-- Minimap Button
-------------------------------------------------

local MinimapButton = CreateFrame("Button", "AutoManaPlusMinimapButton", Minimap)
MinimapButton:SetWidth(32)
MinimapButton:SetHeight(32)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon
local icon = MinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexture("Interface\\Icons\\INV_Potion_76") -- Major Mana Potion

-- Function to update icon appearance based on enabled state
local function UpdateMinimapIcon()
  if AutoManaSettings and AutoManaSettings.enabled then
    icon:SetDesaturated(false)
  else
    icon:SetDesaturated(true)
  end
end

-- Border
local overlay = MinimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetWidth(53)
overlay:SetHeight(53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT", 0, 0)

-- Position on minimap (will be called after PLAYER_ENTERING_WORLD)
local function UpdateMinimapPosition()
  local angle = math.rad(225) -- convert degrees to radians
  local x = 80 * math.cos(angle)
  local y = 80 * math.sin(angle)
  MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Tooltip
MinimapButton:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText("AutoMana+", 1, 1, 1)
  if AutoManaSettings and AutoManaSettings.enabled then
    GameTooltip:AddLine("Status: |cFF00FF00Enabled|r", 0.8, 0.8, 0.8)
  else
    GameTooltip:AddLine("Status: |cFFFF0000Disabled|r", 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Left-click: Open settings", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right-click: Toggle on/off", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

-------------------------------------------------
-- Settings Frame
-------------------------------------------------

local SettingsFrame = CreateFrame("Frame", "AutoManaPlusSettings", UIParent)
SettingsFrame:SetWidth(400)
SettingsFrame:SetHeight(540)
SettingsFrame:SetPoint("CENTER", UIParent, "CENTER")
SettingsFrame:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
SettingsFrame:SetMovable(true)
SettingsFrame:EnableMouse(true)
SettingsFrame:RegisterForDrag("LeftButton")
SettingsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
SettingsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
SettingsFrame:Hide()

-- Title
local title = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("AutoMana+ Settings")

-- Credits
local credits = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
credits:SetPoint("TOP", 0, -40)
credits:SetText("Originally by MarcelineVQ • Enhanced by Fayz")
credits:SetTextColor(1, 1, 1)

-- Close Button
local closeBtn = CreateFrame("Button", nil, SettingsFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Helper function to create checkboxes
local function CreateCheckbox(parent, label, yOffset, setting)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", 30, yOffset)
  check:SetWidth(24)
  check:SetHeight(24)
  
  local text = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", check, "RIGHT", 5, 0)
  text:SetText(label)
  
  check:SetScript("OnClick", function()
    AutoManaSettings[setting] = not AutoManaSettings[setting]
    check:SetChecked(AutoManaSettings[setting])
    -- Update minimap icon when enabled setting changes
    if setting == "enabled" then
      UpdateMinimapIcon()
    end
  end)
  
  check:SetScript("OnShow", function()
    check:SetChecked(AutoManaSettings[setting])
  end)
  
  return check
end

-- Helper function to create sliders
local function CreateSlider(parent, label, xOffset, yOffset, setting, minVal, maxVal)
  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetPoint("TOPLEFT", xOffset, yOffset)
  slider:SetWidth(100)
  slider:SetHeight(15)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(1)
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 }
  })
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  
  local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
  
  slider:SetScript("OnValueChanged", function()
    local val = this:GetValue()
    AutoManaSettings[setting] = val
    valueText:SetText(val .. "%")
  end)
  
  slider:SetScript("OnShow", function()
    this:SetValue(AutoManaSettings[setting])
    valueText:SetText(AutoManaSettings[setting] .. "%")
  end)
  
  return slider
end

-- Enable/Disable
CreateCheckbox(SettingsFrame, "Enable AutoMana+", -70, "enabled")

-- Combat Only
CreateCheckbox(SettingsFrame, "Active only in combat", -100, "combat_only")

-- Debug Mode
CreateCheckbox(SettingsFrame, "Show debug messages", -130, "debug_mode")

-- Disable on Login
CreateCheckbox(SettingsFrame, "Disable on login (keeps state on /reload)", -160, "disable_on_login")

-- Separator
local sep1 = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
sep1:SetPoint("TOPLEFT", 30, -195)
sep1:SetText("Consumables")

-- Tea
local teaCheck = CreateCheckbox(SettingsFrame, "Use Nordanaar Herbal Tea / Nightfin Soup", -225, "use_tea")
local teaLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
teaLabel:SetPoint("TOPLEFT", 235, -227)
teaLabel:SetText("Mana <")
CreateSlider(SettingsFrame, "Tea Threshold", 280, -232, "tea_threshold", 1, 100)

-- Mana Potion
local potionCheck = CreateCheckbox(SettingsFrame, "Use Major Mana Potion", -260, "use_potion")
local potionLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
potionLabel:SetPoint("TOPLEFT", 235, -262)
potionLabel:SetText("Mana <")
CreateSlider(SettingsFrame, "Potion Threshold", 280, -267, "potion_threshold", 1, 100)

-- Rejuv Potion
local rejuvCheck = CreateCheckbox(SettingsFrame, "Use Major Rejuvenation Potion", -295, "use_rejuv")
local rejuvLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rejuvLabel:SetPoint("TOPLEFT", 235, -297)
rejuvLabel:SetText("Health <")
CreateSlider(SettingsFrame, "Rejuv Threshold", 280, -302, "rejuv_threshold", 1, 100)

-- Healthstone
local healthstoneCheck = CreateCheckbox(SettingsFrame, "Use Healthstone", -330, "use_healthstone")
local healthstoneLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
healthstoneLabel:SetPoint("TOPLEFT", 235, -332)
healthstoneLabel:SetText("Health <")
CreateSlider(SettingsFrame, "Healthstone Threshold", 280, -337, "healthstone_threshold", 1, 100)

-- Flask
local flaskCheck = CreateCheckbox(SettingsFrame, "Use Flask of Distilled Wisdom", -365, "use_flask")
local flaskLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
flaskLabel:SetPoint("TOPLEFT", 235, -367)
flaskLabel:SetText("Mana <")
CreateSlider(SettingsFrame, "Flask Threshold", 280, -372, "flask_threshold", 1, 100)

-- Separator
local sep2 = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
sep2:SetPoint("TOPLEFT", 30, -410)
sep2:SetText("Group Size")

-- Group Size Label
local groupLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
groupLabel:SetPoint("TOPLEFT", 30, -440)
groupLabel:SetText("Minimum group size:")

-- Group Size Input
local groupInput = CreateFrame("EditBox", nil, SettingsFrame, "InputBoxTemplate")
groupInput:SetPoint("TOPLEFT", 160, -437)
groupInput:SetWidth(50)
groupInput:SetHeight(20)
groupInput:SetAutoFocus(false)
groupInput:SetMaxLetters(2)
groupInput:SetNumeric(true)

groupInput:SetScript("OnShow", function()
  this:SetText(AutoManaSettings.min_group_size)
end)

groupInput:SetScript("OnEnterPressed", function()
  local val = tonumber(this:GetText())
  if val and val >= 0 and val <= 40 then
    AutoManaSettings.min_group_size = val
  else
    this:SetText(AutoManaSettings.min_group_size)
  end
  this:ClearFocus()
end)

groupInput:SetScript("OnEscapePressed", function()
  this:SetText(AutoManaSettings.min_group_size)
  this:ClearFocus()
end)

-- Info text
local infoText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoText:SetPoint("BOTTOM", 0, 20)
infoText:SetText("Thresholds show when to use each consumable based on mana/health %")
infoText:SetTextColor(0.7, 0.7, 0.7)

-- Minimap button click handler
MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
MinimapButton:SetScript("OnClick", function()
  if arg1 == "LeftButton" then
    -- Left click: toggle settings window
    if SettingsFrame:IsVisible() then
      SettingsFrame:Hide()
    else
      SettingsFrame:Show()
    end
  elseif arg1 == "RightButton" then
    -- Right click: toggle enabled/disabled
    AutoManaSettings.enabled = not AutoManaSettings.enabled
    UpdateMinimapIcon()
    -- Update the checkbox in settings if it's open
    if SettingsFrame:IsVisible() then
      SettingsFrame:Hide()
      SettingsFrame:Show()
    end
  end
end)

-------------------------------------------------

-- taken from supermacros
local function ItemLinkToName(link)
  if ( link ) then
    return gsub(link,"^.*%[(.*)%].*$","%1");
  end
end

local function hasAlchStone()
  return ItemLinkToName(GetInventoryItemLink("player",13)) == "Alchemists' Stone"
      or ItemLinkToName(GetInventoryItemLink("player",14)) == "Alchemists' Stone" or false
end

-- adapted from supermacros
local function RunLine(...)
  for k=1,arg.n do
    local text=arg[k];
      ChatFrameEditBox:SetText(text);
      ChatEdit_SendText(ChatFrameEditBox);
  end
end

-- adapted from supermacros
local function RunBody(text)
  local body = text;
  local length = strlen(body);
  for w in string.gfind(body, "[^\n]+") do
    RunLine(w);
  end
end

-- Finds an item by either its numeric ID or its name, using string.find
-- @param consume     Optional table: { bag = b, slot = s } to check first
-- @param identifier  Number or string: item ID (e.g. 51916) or item name (e.g. "Healthstone")
-- @param bag         Optional bag index to search first (0â€‘4)
-- @return table { bag = b, slot = s } or nil
function AMFindItem(consume, identifier, bag)
  if not identifier then return end

  local searchID   = tonumber(identifier)
  local searchName = nil
  if not searchID then
    searchName = identifier
  end

  -- Helper: does this item link match our ID or name?
  local function linkMatches(link)
    -- extract item ID via string.find captures
    local _, _, idStr = string.find(link, "item:(%d+)")
    local id = idStr and tonumber(idStr)

    if searchID then
      return id == searchID
    else
      -- extract item name in brackets via string.find captures
      local _, _, name = string.find(link, "%[(.-)%]")
      -- exact match? partial?
      return name == searchName or (name and string.find(name, identifier))
    end
  end

  -- 1) check the consume slot if provided
  if consume and consume.bag and consume.slot then
    local link = GetContainerItemLink(consume.bag, consume.slot)
    if link and linkMatches(link) then
      return consume
    end
  end

  -- 2) scan a single bag
  local function SearchBag(b)
    for slot = 1, GetContainerNumSlots(b) do
      local link = GetContainerItemLink(b, slot)
      if link and linkMatches(link) then
        return { bag = b, slot = slot }
      end
    end
  end

  -- 3) search the specified bag first
  if bag then
    local result = SearchBag(bag)
    if result then return result end
  end

  -- 4) search all other bags
  for b = 0, 4 do
    if b ~= bag then
      local result = SearchBag(b)
      if result then return result end
    end
  end
end

function FindItemById(consume, item_id, bag)
  if not item_id then return end

  if consume then
    local link = GetContainerItemLink(consume.bag, consume.slot)
    if link then
      local _, _, id = string.find(link, "item:(%d+)")
      if id == item_id then
        return consume
      end
    end
  end

  -- Function to search a single bag for the item
  local function SearchBag(b)
    for slot = 1, GetContainerNumSlots(b) do
      local link = GetContainerItemLink(b, slot)
      if link then
        local _, _, id = string.find(link, "item:(%d+)")
        if id == item_id then
          return { bag = b, slot = slot }
        end
      end
    end
  end

  -- Search the specified bag first
  local result = bag and SearchBag(bag)
  if result then return result end

  -- Search other bags if not found
  for b = 0, 4 do
    if b ~= bag then
      result = SearchBag(b)
      if result then return result end
    end
  end
end

function consumeReady(which)
  if not which then return false end
  local start,dur = GetContainerItemCooldown(which.bag,which.slot)
  return GetTime() > start + dur
end

local last_fired = 0
function AutoMana(macro_body,fn)
  local fn = fn or RunBody
  local p = "player"
  local now = GetTime()
  local gcd_done = now > last_fired + 1.5 -- delay after item use before using another one or client gets unhappy, even if items have no gcd
  -- local gcd_done = true

  if AutoManaSettings.enabled and gcd_done
    and (UnitAffectingCombat(p) or not AutoManaSettings.combat_only)
    and (max(1,max(GetNumRaidMembers(),GetNumPartyMembers())) >= AutoManaSettings.min_group_size) then

    local hp = UnitHealth(p)
    local hp_max = UnitHealthMax(p)
    local mana = UnitMana(p)
    local mana_max = UnitManaMax(p)
    local mana_perc = (mana / mana_max) * 100
    local health_perc = (hp / hp_max) * 100

    debug_print(string.format("Mana: %.1f%% Health: %.1f%%", mana_perc, health_perc))

    if AutoManaSettings.use_tea and (mana_perc < AutoManaSettings.tea_threshold) and consumeReady(consumables.tea) then
      debug_print("Trying Tea")
      UseContainerItem(consumables.tea.bag,consumables.tea.slot)
      oom = false
      last_fired = now
    elseif AutoManaSettings.use_tea and (mana_perc < AutoManaSettings.tea_threshold) and not consumeReady(consumables.tea) then
      debug_print("Tea not ready (cooldown)")
    elseif AutoManaSettings.use_tea and (mana_perc < AutoManaSettings.tea_threshold) and not consumables.tea then
      debug_print("Tea not found in bags!")
    elseif AutoManaSettings.use_rejuv and (health_perc < AutoManaSettings.rejuv_threshold) and consumeReady(consumables.rejuv) then
      debug_print("Trying Rejuv")
      UseContainerItem(consumables.rejuv.bag,consumables.rejuv.slot)
      oom = false
      last_fired = now
    elseif AutoManaSettings.use_healthstone and (health_perc < AutoManaSettings.healthstone_threshold) and consumeReady(consumables.healthstone) then
      debug_print("Trying Healthstone")
      UseContainerItem(consumables.healthstone.bag,consumables.healthstone.slot)
      last_fired = now
    elseif AutoManaSettings.use_healthstone and (health_perc < AutoManaSettings.healthstone_threshold) and not consumeReady(consumables.healthstone) then
      debug_print("Healthstone not ready (cooldown)")
    elseif AutoManaSettings.use_healthstone and (health_perc < AutoManaSettings.healthstone_threshold) and not consumables.healthstone then
      debug_print("Healthstone not found in bags!")
    elseif AutoManaSettings.use_healthstone and not (health_perc < AutoManaSettings.healthstone_threshold) then
      debug_print(string.format("Healthstone threshold not met (Health: %.1f%%, Threshold: %d%%)", health_perc, AutoManaSettings.healthstone_threshold))
    elseif AutoManaSettings.use_potion and (mana_perc < AutoManaSettings.potion_threshold) and consumeReady(consumables.potion) then
      debug_print("Trying Potion")
      UseContainerItem(consumables.potion.bag,consumables.potion.slot)
      oom = false
      last_fired = now
    elseif AutoManaSettings.use_flask and (mana_perc < AutoManaSettings.flask_threshold or oom) and consumeReady(consumables.flask) then
      debug_print("Trying Flask")
      UseContainerItem(consumables.flask.bag,consumables.flask.slot)
      oom = false
      last_fired = now
    else
      debug_print("Running body")
      fn(macro_body)
    end
  else
    debug_print("AutoMana+ disabled or conditions not met")
    fn(macro_body)
  end
end

-------------------------------------------------

local AutoManaFrame = CreateFrame("FRAME")

function AM_CastSpellByName(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  AutoMana(spell,function () AutoManaFrame.orig_CastSpellByName(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
end

function AM_CastSpell(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  AutoMana(spell,function () AutoManaFrame.orig_CastSpell(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
end

-- action bar buttons are spells too
function AM_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  if AutoManaFrame.cachedSpells[GetActionTexture(slot)] then
    AutoMana(slot,function () AutoManaFrame.orig_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
  else
    AutoManaFrame.orig_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  end
end

local orig_CastSpell = CastSpell
local orig_CastSpellByName = CastSpellByName
local orig_UseAction = UseAction

local function HookCasts(unhook)
  if unhook then -- not neccesary really
    CastSpell = orig_CastSpell
    CastSpellByName = orig_CastSpellByName
    UseAction = orig_UseAction
  else
    AutoManaFrame.orig_CastSpell = orig_CastSpell
    AutoManaFrame.orig_CastSpellByName = orig_CastSpellByName
    AutoManaFrame.orig_UseAction = orig_UseAction
    CastSpell = AM_CastSpell
    CastSpellByName = AM_CastSpellByName
    UseAction = AM_UseAction
  end
end
HookCasts() -- hook right now in case another addon does further hooks

local function OnEvent()
  if event == "PLAYER_LOGIN" then
    -- Disable addon on fresh login if setting is enabled (not on /reload)
    if AutoManaSettings.disable_on_login then
      AutoManaSettings.enabled = false
      UpdateMinimapIcon()
    end
  elseif event == "UI_ERROR_MESSAGE" and arg1 == "Not enough mana" then
    if AutoManaSettings.use_flask then oom = true end
  elseif event == "ADDON_LOADED" then
    if not AutoManaSettings
      then AutoManaSettings = defaults -- initialize default settings
      else -- or check that we only have the current settings format
        local s = {}
        for k,v in pairs(defaults) do
          s[k] = (AutoManaSettings[k] == nil) and defaults[k] or AutoManaSettings[k]
        end
        AutoManaSettings = s
    end
    UpdateMinimapIcon() -- update icon appearance on load
  elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then -- alch stone
    consumables.has_alchstone = hasAlchStone()
  elseif event == "BAG_UPDATE" then -- consume slot update
    -- this should only actually search for the missing item
    consumables.tea = AMFindItem(consumables.tea, "61675", arg1)
    if not consumables.tea then
      consumables.tea = AMFindItem(consumables.tea, "15723", arg1)
    end
    consumables.potion = AMFindItem(consumables.potion, "13444", arg1)
    consumables.rejuv = AMFindItem(consumables.rejuv, "18253", arg1)
    consumables.healthstone = AMFindItem(consumables.healthstone, "Healthstone", arg1)
    consumables.flask = AMFindItem(consumables.flask, "13511", arg1)
  elseif event == "PLAYER_ENTERING_WORLD" then -- spell cache
    UpdateMinimapPosition() -- position minimap button
    AutoManaFrame.cachedSpells = {}
    -- Loop through the spellbook and cache player spells
    local function CacheSpellTextures(bookType)
      local i = 1
      while true do
        local spellTexture = GetSpellTexture(i, bookType)
        if not spellTexture then break end
        AutoManaFrame.cachedSpells[spellTexture] = true
        i = i + 1
      end
  end

  CacheSpellTextures(BOOKTYPE_SPELL)
  CacheSpellTextures(BOOKTYPE_PET)
  end
end

AutoManaFrame:RegisterEvent("PLAYER_LOGIN")
AutoManaFrame:RegisterEvent("UI_ERROR_MESSAGE")
AutoManaFrame:RegisterEvent("BAG_UPDATE")
AutoManaFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
AutoManaFrame:RegisterEvent("ADDON_LOADED")
AutoManaFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
AutoManaFrame:SetScript("OnEvent", OnEvent)
