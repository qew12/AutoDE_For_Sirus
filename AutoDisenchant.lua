AutoDE_DB = AutoDE_DB or {
    point = "CENTER",
    x = 0,
    y = 0,
}

local DB = AutoDE_DB

local DE_SPELL_NAMES = {
    ["ruRU"] = "Распыление",
    ["enUS"] = "Disenchant",
    ["enGB"] = "Disenchant",
}

local function GetDESpell()
    local locale = GetLocale()
    local name = DE_SPELL_NAMES[locale] or DE_SPELL_NAMES["enUS"]
    if GetSpellInfo(name) then
        return name
    end
    for i = 1, 500 do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if spellName then
            if spellName:find("Распыл") or spellName:lower():find("disenchant") then
                return spellName
            end
        end
    end
    return name
end

local ITEMS = {}

-- ================= AUTOLOOT (мгновенный подбор пыли после распыления) =================
-- Аддон НЕ трогает лут-окно из Lua (LootSlot защищён). Вместо этого клиентская
-- авто-подборка (autoLootDefault) забирает пыль сразу, без кликов.
local function EnableAutoLoot()
    if not DB.lootBackup then
        DB.lootBackup = GetCVar("autoLootDefault") or "0"
    end
    if GetCVar("autoLootDefault") ~= "1" then
        SetCVar("autoLootDefault", 1)
    end
end

local function RestoreAutoLoot()
    if DB.lootBackup then
        SetCVar("autoLootDefault", DB.lootBackup)
        DB.lootBackup = nil
    end
end

-- ================= FRAME =================
local frame = CreateFrame("Frame", "AutoDisenchantFrame", UIParent)
frame:SetSize(340, 380)
if DB.point then
    frame:SetPoint(DB.point, UIParent, DB.point, DB.x or 0, DB.y or 0)
else
    frame:SetPoint("CENTER")
end
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    DB.point = point
    DB.x = x
    DB.y = y
end)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
frame:Hide()

-- ================= HEADER =================
local headerBar = frame:CreateTexture(nil, "ARTWORK")
headerBar:SetHeight(20)
headerBar:SetPoint("TOPLEFT", 4, -4)
headerBar:SetPoint("TOPRIGHT", -4, -4)
headerBar:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
headerBar:SetVertexColor(0.06, 0.06, 0.06, 0.98)

local headerIcon = frame:CreateTexture(nil, "OVERLAY")
headerIcon:SetSize(16, 16)
headerIcon:SetPoint("LEFT", headerBar, "LEFT", 6, 0)
headerIcon:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant")

local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerText:SetPoint("LEFT", headerIcon, "RIGHT", 5, 0)
headerText:SetText("|cff00ffffAutoDisenchant|r")
headerText:SetJustifyH("LEFT")

-- ================= CLOSE BUTTON =================
local closeBtn = CreateFrame("Button", nil, frame)
closeBtn:SetSize(14, 14)
closeBtn:SetPoint("RIGHT", headerBar, "RIGHT", -4, 0)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")

closeBtn:SetScript("OnClick", function()
    RestoreAutoLoot()
    frame:Hide()
end)

-- ================= BG =================
local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2)
bg:SetPoint("BOTTOMRIGHT", -4, 4)
bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
bg:SetVertexColor(0.12, 0.12, 0.12, 0.8)

-- ================= LIST =================
local scrollFrame = CreateFrame("ScrollFrame", "AutoDEScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 6, -6)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 82)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(290, 200)
scrollFrame:SetScrollChild(scrollChild)

local itemTexts = {}
for i = 1, 150 do
    itemTexts[i] = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemTexts[i]:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i-1)*16))
    itemTexts[i]:SetWidth(290)
    itemTexts[i]:SetJustifyH("LEFT")
    itemTexts[i]:Hide()
end

-- ================= STATUS =================
local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
countText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 66)
countText:SetText("Найдено: 0")

-- Статус: 2 ряда с переносом, выше кнопок (кнопки занимают y=6..30)
local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 36)
statusText:SetWidth(310)
statusText:SetJustifyH("CENTER")
statusText:SetTextColor(0.8, 0.8, 0.8)
statusText:SetText("Фильтр: зелёные + уровень предмета > 0")

-- ================= SECURE DE BUTTON =================
-- ЗАЩИЩЁННАЯ кнопка. Реальный клик мышкой игрока, Lua-кликов нет.
local deBtn = CreateFrame("Button", "AutoDESecureButton", frame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
deBtn:SetSize(150, 24)
deBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
deBtn:SetText("Распылить")
deBtn:SetAttribute("type", "macro")
deBtn:RegisterForClicks("AnyUp")

-- ================= BUTTONS =================
local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
scanBtn:SetSize(150, 24)
scanBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 6)
scanBtn:SetText("Обновить список")

-- ================= UPDATE LIST =================
local function UpdateList()
    for i = 1, 150 do
        itemTexts[i]:Hide()
    end
    countText:SetText("Найдено: |cff00ff00" .. #ITEMS .. "|r")
    if #ITEMS == 0 then
        itemTexts[1]:SetText("|cff999999Список пуст. Подходящих зелёных с уровнем нет.|r")
        itemTexts[1]:Show()
        return
    end
    for i = 1, math.min(#ITEMS, 150) do
        local item = ITEMS[i]
        local name = item.name or GetItemInfo(item.link) or item.link
        itemTexts[i]:SetText(string.format("|cff1eff00%s|r |cffbbbbbb(ур. %s)|r [%d:%d]", name, item.level or "??", item.bag, item.slot))
        itemTexts[i]:Show()
    end
end

-- ================= PREPARE NEXT (подстановка макроса в защищённую кнопку) =================
local function PrepareNext()
    if InCombatLockdown() then
        statusText:SetText("|cffffcc00В бою! Выйди из боя и нажми Обновить список.|r")
        return
    end

    if #ITEMS == 0 then
        deBtn:SetAttribute("macrotext", nil)
        deBtn:Disable()
        statusText:SetText("|cff00ff00Все предметы обработаны|r")
        return
    end

    local spellName = GetDESpell()
    if not GetSpellInfo(spellName) then
        statusText:SetText("|cffff0000Не найдено заклинание Распыление! Научи Автоматическое распыление.|r")
        deBtn:SetAttribute("macrotext", nil)
        deBtn:Disable()
        return
    end

    local item = ITEMS[1]
    if not item then
        deBtn:SetAttribute("macrotext", nil)
        deBtn:Disable()
        return
    end

    local macroText = string.format("/cast %s\n/use %d %d", spellName, item.bag, item.slot)

    deBtn:SetAttribute("macrotext", macroText)
    deBtn:Enable()
    if GetCVar("autoLootDefault") == "1" then
        statusText:SetText(string.format("|cff00ffffГотово:|r распыли %s — пыль заберётся сама (осталось %d)", item.name or "?", #ITEMS))
    else
        statusText:SetText(string.format("|cff00ffffГотово:|r распыли %s (осталось %d)", item.name or "?", #ITEMS))
    end
end

-- ================= POSTCLICK (после реального клика игрока) =================
deBtn:SetScript("PostClick", function(self, button)
    if #ITEMS > 0 then
        local done = table.remove(ITEMS, 1)
        print(string.format("|cff00ffffAutoDE:|r распыляется: %s", done.name or done.link))
    end
    UpdateList()
    PrepareNext()
end)

-- ================= SCAN =================
local function ScanInventory()
    ITEMS = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name, _, quality, iLevel = GetItemInfo(link)
                    if quality == 2 and iLevel and tonumber(iLevel) > 0 then
                        if not link:find("quest") then
                            table.insert(ITEMS, {bag = bag, slot = slot, link = link, name = name, level = iLevel})
                        end
                    end
                end
            end
        end
    end
    UpdateList()
    PrepareNext()
end

-- ================= BUTTONS SCRIPT =================
scanBtn:SetScript("OnClick", function()
    ScanInventory()
end)

-- ================= EVENTS =================
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_SLOT_CLEARED")
frame:RegisterEvent("LOOT_CLOSED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "LOOT_OPENED" then
        if GetCVar("autoLootDefault") == "1" then
            statusText:SetText("|cff00ffffРеагент в лут-окне — забирается автоматически|r")
        else
            statusText:SetText("|cffff8888Авто-лут выключен!|r Кликни по пыли руками или включи авопасчёт.")
        end
    elseif event == "LOOT_SLOT_CLEARED" then
        statusText:SetText("|cff00ff00Пыль забрана!|r Кликай дальше — следующий уже готов")
    elseif event == "LOOT_CLOSED" then
        if #ITEMS > 0 and not InCombatLockdown() then
            PrepareNext()
        end
    end
end)

-- ================= SLASH =================
SLASH_AUTODISENCHANT1 = "/autode"
SLASH_AUTODISENCHANT2 = "/adisen"
SLASH_AUTODISENCHANT3 = "/disen"
SlashCmdList["AUTODISENCHANT"] = function()
    if frame:IsShown() then
        RestoreAutoLoot()
        frame:Hide()
    else
        frame:Show()
        EnableAutoLoot()
        ScanInventory()
    end
end
