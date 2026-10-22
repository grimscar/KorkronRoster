-- Kor'kron Roster: recipe browser for one member's profession.
local _, KR = ...

local UI = KR.UI
local Inspector = {}
UI.Inspector = Inspector

local ROW_HEIGHT = 20
local MAX_REAGENTS = 8

local frame, list, detail
local member, profName
local selectedName
local pickedByUser = false -- the auto-selected first recipe is not linked in whispers
local collapsed = {}
local searchText = ""

local function CurrentRecipes()
    local data = member and member.recipes and member.recipes[profName]
    return data and data.list or {}, data
end

local function ReagentInfo(rg)
    local name, link = KR.Recipes.ItemInfo(rg.itemID)
    local icon = rg.icon or KR.Recipes.Icon({ itemID = rg.itemID })
    return name or rg.name or (rg.itemID and ("Item #" .. rg.itemID)) or "?", icon, link
end

-- detail pane ------------------------------------------------------------------------------

local function ShowRecipe(r)
    if not r then
        detail.itemBtn:Hide()
        detail.name:SetText("No recipes shared")
        detail.category:SetText("This list fills in once " .. (member and member.name or "they") .. " opens the profession window with Kor'kron Roster installed.")
        detail.reagentHeader:Hide()
        for i = 1, MAX_REAGENTS do detail.reagents[i]:Hide() end
        return
    end

    UI.PrimeItem(r.itemID)
    detail.itemBtn.recipe = r
    detail.itemBtn.icon:SetTexture(KR.Recipes.Icon(r))
    detail.itemBtn:Show()
    detail.name:SetText(r.name)
    detail.category:SetText(r.category or "")

    local reagents = r.reagents or {}
    detail.reagentHeader:SetShown(#reagents > 0)
    for i = 1, MAX_REAGENTS do
        local rf = detail.reagents[i]
        local rg = reagents[i]
        if rg then
            local name, icon = ReagentInfo(rg)
            rf.itemID = rg.itemID
            rf.icon:SetTexture(icon)
            rf.count:SetText(rg.count or 1)
            rf.name:SetText(name)
            rf:Show()
        else
            rf:Hide()
        end
    end
end

-- recipe list ------------------------------------------------------------------------------

local function BuildRows()
    local recipes = CurrentRecipes()
    local categories, order = {}, {}
    for _, r in ipairs(recipes) do
        if searchText == "" or string.find(string.lower(r.name), searchText, 1, true) then
            local cat = r.category or "General"
            if not categories[cat] then
                categories[cat] = {}
                order[#order + 1] = cat
            end
            table.insert(categories[cat], r)
        end
    end
    local rows = {}
    for _, cat in ipairs(order) do
        rows[#rows + 1] = { header = cat, count = #categories[cat] }
        if not collapsed[cat] or searchText ~= "" then
            for _, r in ipairs(categories[cat]) do rows[#rows + 1] = { recipe = r } end
        end
    end
    return rows
end

local function RowOnClick(row)
    local item = row.item
    if item.header then
        collapsed[item.header] = not collapsed[item.header]
        Inspector:Refresh()
    elseif IsModifiedClick and IsModifiedClick("CHATLINK") then
        UI.InsertLink(KR.Recipes.Link(item.recipe))
    else
        selectedName = item.recipe.name
        pickedByUser = true
        ShowRecipe(item.recipe)
        list:Redraw()
    end
end

local function RowOnEnter(row)
    if row.item and row.item.recipe then row.highlight:Show() end
end

local function RowOnLeave(row)
    row.highlight:Hide()
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.bg = row:CreateTexture(nil, "BORDER")
    row.bg:SetAllPoints()
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 14, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row:SetScript("OnClick", RowOnClick)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    return row
end

local function UpdateRow(row, item)
    row.item = item
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", -4, 0)
    if item.header then
        row.bg:SetColorTexture(0.2, 0.16, 0.08, 0.85)
        row.icon:Hide()
        row.text:SetPoint("LEFT", 6, 0)
        local open = searchText ~= "" or not collapsed[item.header]
        row.text:SetText(string.format("|cffffd100%s %s|r |cff888888(%d)|r", open and "[-]" or "[+]", item.header, item.count))
    else
        local selected = item.recipe.name == selectedName
        row.bg:SetColorTexture(0.7, 0.5, 0.1, selected and 0.45 or 0)
        row.icon:SetTexture(KR.Recipes.Icon(item.recipe))
        row.icon:Show()
        row.text:SetPoint("LEFT", 34, 0)
        row.text:SetText("|cffffd100" .. item.recipe.name .. "|r")
    end
end

-- frame ------------------------------------------------------------------------------------

local function ReagentButton(parent, i)
    local rf = CreateFrame("Button", nil, parent)
    rf:SetSize(124, 34)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    rf:SetPoint("TOPLEFT", parent.reagentHeader, "BOTTOMLEFT", col * 130, -8 - row * 38)
    rf.icon = rf:CreateTexture(nil, "ARTWORK")
    rf.icon:SetSize(30, 30)
    rf.icon:SetPoint("LEFT")
    rf.count = rf:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    rf.count:SetPoint("BOTTOMRIGHT", rf.icon, "BOTTOMRIGHT", -2, 2)
    rf.bg = rf:CreateTexture(nil, "BACKGROUND")
    rf.bg:SetPoint("TOPLEFT", rf.icon, "TOPRIGHT", 4, 0)
    rf.bg:SetPoint("BOTTOMRIGHT")
    rf.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    rf.name = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rf.name:SetPoint("LEFT", rf.icon, "RIGHT", 8, 0)
    rf.name:SetWidth(84)
    rf.name:SetJustifyH("LEFT")
    rf:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rf:SetScript("OnClick", function(self)
        if self.itemID and IsModifiedClick and IsModifiedClick("CHATLINK") then
            local _, link = KR.Recipes.ItemInfo(self.itemID)
            UI.InsertLink(link)
        end
    end)
    rf:Hide()
    return rf
end

local function Build()
    frame = CreateFrame("Frame", "KorkronTradeSkillInspector", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 440)
    frame:SetPoint("CENTER", 200, 0)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronTradeSkillInspector")
    UI.MakePopup(frame)

    frame.portrait = frame:CreateTexture(nil, "OVERLAY")
    frame.portrait:SetSize(20, 20)
    frame.portrait:SetPoint("TOPLEFT", 6, -2)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame.TitleBg or frame, "TOP", 0, -3)

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetSize(300, 16)
    bar:SetPoint("TOPLEFT", 16, -32)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.1, 0.45, 0.85, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    frame.skillBar = bar

    frame.updated = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.updated:SetPoint("LEFT", bar, "RIGHT", 10, 0)

    local whisper = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    whisper:SetSize(100, 22)
    whisper:SetPoint("TOPRIGHT", -14, -28)
    whisper:SetText("Whisper")
    whisper:SetScript("OnClick", function()
        local r = pickedByUser and detail.itemBtn:IsShown() and detail.itemBtn.recipe or nil
        UI.WhisperRecipe(member, r)
    end)
    whisper:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Whisper " .. (member and member.name or ""))
        local r = pickedByUser and detail.itemBtn:IsShown() and detail.itemBtn.recipe
        if r then
            GameTooltip:AddLine("Asks them to craft " .. r.name .. ", with a link.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Select a recipe first to link it in the whisper.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    whisper:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.whisper = whisper

    local search = CreateFrame("EditBox", "KorkronInspectorSearch", frame, "InputBoxTemplate")
    search:SetSize(230, 20)
    search:SetPoint("TOPLEFT", 20, -56)
    search:SetAutoFocus(false)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 2, 0)
    search.placeholder:SetText("Search recipes")
    search:SetScript("OnTextChanged", function(self)
        searchText = string.lower(strtrim(self:GetText() or ""))
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if frame:IsShown() then
            list:ScrollToTop()
            Inspector:Refresh()
        end
    end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT", 12, -82)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(260)
    left.bg = left:CreateTexture(nil, "BACKGROUND")
    left.bg:SetAllPoints()
    left.bg:SetColorTexture(0.04, 0.04, 0.04, 0.7)

    list = UI.CreateList(left, "KorkronInspectorList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 4)

    detail = CreateFrame("Frame", nil, frame)
    detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", -12, 12)
    detail.bg = detail:CreateTexture(nil, "BACKGROUND")
    detail.bg:SetAllPoints()
    detail.bg:SetColorTexture(0.06, 0.05, 0.04, 0.85)

    local itemBtn = CreateFrame("Button", nil, detail)
    itemBtn:SetSize(42, 42)
    itemBtn:SetPoint("TOPLEFT", 16, -16)
    itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK")
    itemBtn.icon:SetAllPoints()
    itemBtn:SetScript("OnEnter", function(self)
        local r = self.recipe
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if r.itemID then
            GameTooltip:SetItemByID(r.itemID)
        elseif r.spellID and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(r.spellID)
        else
            GameTooltip:AddLine(r.name, 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemBtn:SetScript("OnClick", function(self)
        if self.recipe and IsModifiedClick and IsModifiedClick("CHATLINK") then
            UI.InsertLink(KR.Recipes.Link(self.recipe))
        end
    end)
    detail.itemBtn = itemBtn

    detail.name = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", itemBtn, "TOPRIGHT", 12, -2)
    detail.name:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detail.name:SetJustifyH("LEFT")

    detail.category = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.category:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.category:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detail.category:SetJustifyH("LEFT")
    detail.category:SetTextColor(0.7, 0.7, 0.7)

    detail.reagentHeader = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail.reagentHeader:SetPoint("TOPLEFT", itemBtn, "BOTTOMLEFT", 0, -20)
    detail.reagentHeader:SetText("Reagents:")

    detail.reagents = {}
    for i = 1, MAX_REAGENTS do detail.reagents[i] = ReagentButton(detail, i) end
end

function Inspector:Refresh()
    if not frame or not frame:IsShown() or not member then return end
    local recipes, data = CurrentRecipes()
    local prof
    for _, slot in ipairs(KR.PROF_SLOTS) do
        if member[slot] and member[slot].name == profName then prof = member[slot] end
    end
    local rank, maxRank = prof and prof.rank or 0, prof and prof.max or 0
    frame.skillBar:SetMinMaxValues(0, math.max(1, maxRank))
    frame.skillBar:SetValue(rank)
    frame.skillBar.text:SetText(string.format("%s %d/%d", profName, rank, maxRank))
    frame.updated:SetText(data and (#recipes .. " recipes, updated " .. KR.FormatAgo(data.updated)) or "")

    list:SetItems(BuildRows())

    local selected
    for _, r in ipairs(recipes) do
        if r.name == selectedName then selected = r break end
    end
    if not selected and #list.items > 0 then
        for _, item in ipairs(list.items) do
            if item.recipe then selected = item.recipe break end
        end
        selected = selected or recipes[1]
        selectedName = selected and selected.name
    end
    ShowRecipe(selected)
    list:Redraw()
end

function Inspector:Open(m, prof, recipeName)
    if not frame then Build() end
    local changed = m ~= member or prof ~= profName
    member, profName = m, prof
    if changed then
        collapsed = {}
        selectedName = nil
        pickedByUser = false
        frame.search:SetText("")
    end
    -- opened from the Recipes tab for a specific recipe: that counts as picking it
    if recipeName then
        selectedName = recipeName
        pickedByUser = true
    end

    frame.title:SetText(UI.ColoredName(m) .. " - " .. prof)
    frame.portrait:SetTexture(KR.ProfIcon(prof))
    frame.whisper:SetShown(not KR.IsMe(m.name))
    frame:Show()
    frame:Raise()
    self:Refresh()
end

function Inspector:Hide()
    if frame then frame:Hide() end
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("inspectorRefresh", 0.5, function() Inspector:Refresh() end)
    end
end)
