-- Kor'kron Roster: shared UI building blocks.
local _, KR = ...

local UI = {}
KR.UI = UI

-- A scrolling list that only builds enough rows to fill its height, so a 500-member
-- guild costs the same as a 20-member one.
--   createRow(list) -> row          updateRow(row, item, index)
function UI.CreateList(parent, name, rowHeight, createRow, updateRow)
    local list = CreateFrame("Frame", name, parent)
    list.rowHeight = rowHeight
    list.items = {}
    list.rows = {}

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    list.scroll = scroll

    function list:VisibleCount()
        return math.max(1, math.floor(scroll:GetHeight() / rowHeight))
    end

    function list:Redraw()
        local first = math.floor(scroll:GetVerticalScroll() / rowHeight + 0.5)
        local visible = self:VisibleCount()
        for i = 1, visible do
            local row = self.rows[i]
            if not row then
                row = createRow(self)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
                row.stripe = row:CreateTexture(nil, "BACKGROUND")
                row.stripe:SetAllPoints()
                row:EnableMouseWheel(true)
                row:SetScript("OnMouseWheel", function(_, delta) self:Scroll(delta) end)
                self.rows[i] = row
            end
            local index = first + i
            local item = self.items[index]
            if item then
                if index % 2 == 0 then
                    row.stripe:SetColorTexture(1, 1, 1, 0.03)
                else
                    row.stripe:SetColorTexture(0, 0, 0, 0.2)
                end
                updateRow(row, item, index)
                row:Show()
            else
                row:Hide()
            end
        end
        for i = visible + 1, #self.rows do
            self.rows[i]:Hide()
        end
    end

    -- the scroll range is sized so the last item lands exactly on the last visible row
    function list:Layout()
        child:SetWidth(math.max(1, scroll:GetWidth()))
        local hidden = math.max(0, #self.items - self:VisibleCount())
        child:SetHeight(scroll:GetHeight() + hidden * rowHeight)
        if scroll:GetVerticalScroll() > hidden * rowHeight then
            scroll:SetVerticalScroll(hidden * rowHeight)
        end
        self:Redraw()
    end

    function list:SetItems(items)
        self.items = items
        self:Layout()
    end

    function list:ScrollToTop()
        scroll:SetVerticalScroll(0)
    end

    -- rows sit above the scroll frame, so they forward the mouse wheel to it
    function list:Scroll(delta)
        local bar = scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
        if bar then bar:SetValue(bar:GetValue() - delta * rowHeight * 3) end
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) list:Scroll(delta) end)

    scroll:HookScript("OnVerticalScroll", function() list:Redraw() end)
    list:SetScript("OnSizeChanged", function() list:Layout() end)
    return list
end

-- Pop-up windows share a strata. Without their own frame levels, two overlapping windows
-- interleave draw layers and each one's text shows through the other. Toplevel frames are
-- raised when clicked; we also raise them whenever they are shown or reused.
function UI.MakePopup(frame)
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
end

-- dropdown menu --------------------------------------------------------------------------
-- options: { label, value, selected, header } ; onPick(option) runs when one is clicked.
-- One shared menu; Escape or clicking the same anchor again closes it.

local menu
local MENU_ROW = 16
local MENU_PAD = 15 -- room for the dialog border, like Blizzard's dropdown lists

-- same look as the game's own dropdown lists: dark dialog background, grey dialog border
local MENU_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function BuildMenu()
    menu = CreateFrame("Frame", "KorkronDropDownMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    if menu.SetBackdrop then
        menu:SetBackdrop(MENU_BACKDROP)
    else
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 11, -12)
        bg:SetPoint("BOTTOMRIGHT", -12, 11)
        bg:SetColorTexture(0, 0, 0, 0.9)
    end
    menu.buttons = {}
    menu:Hide()
    tinsert(UISpecialFrames, "KorkronDropDownMenu")
end

local function MenuButton(i)
    local btn = menu.buttons[i]
    if btn then return btn end
    btn = CreateFrame("Button", nil, menu)
    btn:SetHeight(MENU_ROW)
    btn:SetPoint("TOPLEFT", MENU_PAD, -MENU_PAD - (i - 1) * MENU_ROW)
    btn:SetPoint("RIGHT", menu, "RIGHT", -MENU_PAD, 0)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    btn.hl:SetBlendMode("ADD")
    btn.check = btn:CreateTexture(nil, "ARTWORK")
    btn.check:SetSize(16, 16)
    btn.check:SetPoint("LEFT", 0, 0)
    btn.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("RIGHT", 0, 0)
    btn.text:SetJustifyH("LEFT")
    btn:SetScript("OnClick", function(self)
        local opt, pick = self.option, menu.onPick
        menu:Hide()
        if opt and not opt.header and pick then pick(opt) end
    end)
    menu.buttons[i] = btn
    return btn
end

function UI.ShowMenu(anchor, options, onPick, width)
    if not menu then BuildMenu() end
    if menu:IsShown() and menu.anchor == anchor then
        menu:Hide()
        return
    end
    menu.anchor, menu.onPick = anchor, onPick
    for i, opt in ipairs(options) do
        local btn = MenuButton(i)
        btn.option = opt
        btn.text:ClearAllPoints()
        btn.text:SetPoint("RIGHT", 0, 0)
        if opt.header then
            -- section titles: gold, flush left, not clickable (like Blizzard's menu titles)
            btn.text:SetFontObject("GameFontNormalSmall")
            btn.text:SetPoint("LEFT", 0, 0)
            btn.text:SetText(opt.header)
            btn.check:Hide()
            btn:EnableMouse(false)
        else
            btn.text:SetFontObject("GameFontHighlightSmall")
            btn.text:SetPoint("LEFT", 18, 0)
            btn.text:SetText(opt.label)
            btn.check:SetShown(opt.selected and true or false)
            btn:EnableMouse(true)
        end
        btn:Show()
    end
    for i = #options + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -MENU_PAD + 4, 4)
    menu:SetSize((width or math.max(160, anchor:GetWidth())) + MENU_PAD * 2, #options * MENU_ROW + MENU_PAD * 2)
    menu:Show()
    menu:Raise()
end

function UI.HideMenu()
    if menu then menu:Hide() end
end

-- the Kor'kron rank picker, shared by the player card and the Roster tab
function UI.ShowRankMenu(anchor, m)
    UI.ShowMenu(anchor, KR.Ranks.Options(m), function(opt)
        KR.Ranks.Choose(m, opt.tier, opt.title)
    end, 200)
end

-- a clickable table cell with an optional icon
function UI.CreateCell(parent, height)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetHeight(height)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(16, 16)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if cell.text.SetWordWrap then cell.text:SetWordWrap(false) end
    return cell
end

-- text and/or icon; coords crop the icon (class sheet), iconOnly centres it
function UI.SetCell(cell, align, text, icon, coords)
    cell.text:ClearAllPoints()
    cell.icon:ClearAllPoints()
    if icon then
        cell.icon:SetTexture(icon)
        if coords then
            cell.icon:SetTexCoord(unpack(coords))
        else
            cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        cell.icon:Show()
        if text then
            cell.icon:SetPoint("LEFT", 4, 0)
            cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 4, 0)
        else
            cell.icon:SetPoint("CENTER")
        end
    else
        cell.icon:Hide()
        cell.text:SetPoint("LEFT", 4, 0)
    end
    cell.text:SetPoint("RIGHT", -4, 0)
    cell.text:SetJustifyH(align or "LEFT")
    cell.text:SetText(text or "")
end

function UI.ColoredName(m)
    local name = m.name or "?"
    if not m.online then return "|cff808080" .. name .. "|r" end
    return "|cff" .. KR.ClassColorHex(m.class) .. name .. "|r"
end

-- roster label: "Alt Name (Main Name)" for alts that have announced a main
function UI.DisplayName(m)
    local text = UI.ColoredName(m)
    if m.main then text = text .. " |cff9d9d9d(" .. m.main .. ")|r" end
    return text
end

-- m is a member record; whispers go to the exact name the game gave us for them
function UI.Whisper(m, text)
    local name = m and (m.whisperTarget or m.name)
    if not name then return end
    if not ChatFrame_SendTell then return end
    ChatFrame_SendTell(name)
    if not text then return end

    -- SendTell types "/w Name " into the chat box, and the box only switches to
    -- whisper mode a frame later; anything inserted before that is wiped. Wait for it.
    local tries = 0
    local function TryInsert()
        tries = tries + 1
        local editBox = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
            or (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend())
        if not editBox then
            if tries < 20 then KR:After(0.05, TryInsert) end
            return
        end
        local pending = string.find(editBox:GetText() or "", "^/") ~= nil
        local whispering = not editBox.GetAttribute or editBox:GetAttribute("chatType") == "WHISPER"
        if (pending or not whispering) and tries < 20 then
            KR:After(0.05, TryInsert)
            return
        end
        editBox:Insert(text)
    end
    KR:After(0, TryInsert)
end

-- ask the client to load an item so its link is ready by the time we need it
function UI.PrimeItem(itemID)
    if not itemID then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    else
        KR.Recipes.ItemInfo(itemID)
    end
end

-- call back with a chat link for a recipe; items the client hasn't seen yet are loaded
-- first (up to a second), then it falls back to nil and callers use the plain name
function UI.GetRecipeLink(r, callback)
    local link = KR.Recipes.Link(r)
    if link or not r.itemID then
        callback(link)
        return
    end
    UI.PrimeItem(r.itemID)
    local tries = 0
    local function Poll()
        tries = tries + 1
        link = KR.Recipes.Link(r)
        if link or tries >= 10 then
            callback(link)
        else
            KR:After(0.1, Poll)
        end
    end
    KR:After(0.1, Poll)
end

-- whisper a crafter, linking the recipe when there is one
function UI.WhisperRecipe(m, r)
    if not r then
        UI.Whisper(m)
        return
    end
    UI.GetRecipeLink(r, function(link)
        UI.Whisper(m, "Could you craft " .. (link or r.name) .. " for me?")
    end)
end

-- insert a link into the open chat box (shift-click behaviour)
function UI.InsertLink(link)
    if not link then return false end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    return false
end

-- standard member tooltip, used by the roster and the inspector
function UI.MemberTooltip(owner, m)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(UI.ColoredName(m))
    if m.main then
        GameTooltip:AddLine("Alt of " .. m.main, 0.8, 0.8, 0.8)
    else
        local alts = KR.DB:GetAlts(m.name)
        if #alts > 0 then
            local names = {}
            for i, alt in ipairs(alts) do names[i] = alt.name end
            GameTooltip:AddLine("Alts: " .. table.concat(names, ", "), 0.8, 0.8, 0.8, true)
        end
    end
    local classLine = "Level " .. (m.level or "?")
    local title = KR.Ranks.Title(m)
    if title then classLine = classLine .. "  |cffffd100" .. title .. "|r" end
    GameTooltip:AddLine(classLine, 1, 1, 1)
    if m.online then
        if m.zone and m.zone ~= "" then GameTooltip:AddLine(m.zone, 0.4, 1, 0.4) end
    else
        GameTooltip:AddLine("Offline - last seen " .. KR.FormatAgo(m.lastOnline), 0.6, 0.6, 0.6)
    end
    if m.note and m.note ~= "" then GameTooltip:AddLine("Note: " .. m.note, 0.9, 0.9, 0.7, true) end
    if m.version then
        GameTooltip:AddLine("Kor'kron Roster " .. m.version .. ", synced " .. KR.FormatAgo(m.lastSync), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Not running Kor'kron Roster", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Click for player card, right-click to whisper", 0, 1, 0)
    GameTooltip:Show()
end
