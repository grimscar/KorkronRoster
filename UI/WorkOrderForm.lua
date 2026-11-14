-- Kor'kron Roster: the "New Work Order" window. A searchable list of everything the guild can craft
-- (from the shared recipe lists): pick an item, set how many, who provides the materials and a
-- note, and post the order.
local _, KR = ...

local UI = KR.UI
local Form = {}
UI.WorkOrderForm = Form

local ROW_HEIGHT = 20
local MAX_CRAFTERS = 8 -- names shown before "+N"

local MATS_CHOICES = {
    { value = "requester", label = "I'll provide the materials" },
    { value = "crafter", label = "The crafter provides them" },
}

local frame, list, detail
local selected -- an entry of the guild's recipe index
local mats     -- who provides the materials: "requester" or "crafter", nil until the requester picks
local searchText = ""

local function Lower(s)
    return string.lower(s or "")
end

-- every recipe in the guild that matches the search, by name
local function Craftables()
    local out, key = {}, {}
    for _, e in ipairs(KR.Recipes.GetIndex().list) do
        local name = Lower(e.recipe.name)
        if searchText == "" or string.find(name, searchText, 1, true) or string.find(Lower(e.prof), searchText, 1, true) then
            out[#out + 1] = e
            key[e] = name .. "\001" .. e.prof
        end
    end
    table.sort(out, function(a, b) return key[a] < key[b] end)
    return out
end

-- detail pane ------------------------------------------------------------------------------

local function ShowSelected()
    local e = selected
    detail.icon:SetShown(e ~= nil)
    if e and mats then frame.submit:Enable() else frame.submit:Disable() end
    if not e then
        detail.name:SetText("Pick an item")
        if #list.items == 0 and searchText == "" then
            detail.prof:SetText("No recipe lists shared yet. They fill in as guildmates open their profession windows with Kor'kron Roster.")
        else
            detail.prof:SetText("Search for what you need, then click it in the list.")
        end
        detail.crafters:SetText("")
        detail.reagents:SetText("")
        return
    end

    local r = e.recipe
    UI.PrimeItem(r.itemID)
    detail.icon.recipe = r
    detail.icon.texture:SetTexture(KR.Recipes.Icon(r))
    detail.name:SetText(r.name)
    detail.prof:SetText(e.prof)
    detail.crafters:SetText("|cffffd100Crafters:|r " .. UI.CrafterList(e, MAX_CRAFTERS))
    local lines = UI.ReagentLines(r, 1)
    detail.reagents:SetText(#lines > 0 and ("|cffffd100Reagents for one:|r\n" .. table.concat(lines, "\n")) or "")
end

local function ChooseMats(value)
    mats = value
    for v, box in pairs(frame.mats) do box:SetChecked(v == mats) end
    ShowSelected()
end

local function Submit()
    if not selected then return end
    local qty = tonumber(frame.qty:GetText())
    if not qty or qty < 1 or qty > KR.WorkOrders.MAX_QTY then
        KR:Print("The quantity has to be 1 to %s.", KR.WorkOrders.MAX_QTY)
        return
    end
    if KR.WorkOrders.Create(selected, qty, mats, frame.note:GetText()) then
        frame:Hide()
        UI.Main:Show("ORDERS")
    end
end

-- item list --------------------------------------------------------------------------------

local function RowOnClick(row)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        UI.InsertLink(KR.Recipes.Link(row.item.recipe))
        return
    end
    selected = row.item
    ShowSelected()
    list:Redraw()
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
    row.icon:SetPoint("LEFT", 4, 0)
    row.prof = row:CreateFontString(nil, "OVERLAY", "KorkronRosterFontDisableSmall")
    row.prof:SetPoint("RIGHT", -4, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "KorkronRosterFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.prof, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", RowOnClick)
    return row
end

local function UpdateRow(row, e)
    row.item = e
    local isSelected = selected ~= nil and e.prof == selected.prof and e.recipe.name == selected.recipe.name
    row.bg:SetColorTexture(0.7, 0.5, 0.1, isSelected and 0.45 or 0)
    row.icon:SetTexture(KR.Recipes.Icon(e.recipe))
    row.text:SetText(e.recipe.name)
    row.prof:SetText(e.prof)
end

-- frame ------------------------------------------------------------------------------------

local function EditBox(name, parent, width, maxLetters)
    local box = UI.EditBox(parent, width, name)
    box:SetMaxLetters(maxLetters)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function Label(parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function BuildDetail(left)
    detail = CreateFrame("Frame", nil, frame)
    detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", -12, 12)
    detail.bg = detail:CreateTexture(nil, "BACKGROUND")
    detail.bg:SetAllPoints()
    detail.bg:SetColorTexture(0.06, 0.05, 0.04, 0.85)

    local icon = CreateFrame("Button", nil, detail)
    icon:SetSize(42, 42)
    icon:SetPoint("TOPLEFT", 16, -16)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon:SetScript("OnEnter", function(self) UI.ItemTooltip(self, self.recipe) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", function(self)
        if IsModifiedClick and IsModifiedClick("CHATLINK") then UI.InsertLink(KR.Recipes.Link(self.recipe)) end
    end)
    detail.icon = icon

    detail.name = Label(detail, "KorkronRosterFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    detail.name:SetPoint("RIGHT", -10, 0)
    detail.name:SetWordWrap(false)

    detail.prof = Label(detail, "KorkronRosterFontHighlightSmall")
    detail.prof:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.prof:SetPoint("RIGHT", -10, 0)
    detail.prof:SetTextColor(0.7, 0.7, 0.7)

    detail.crafters = Label(detail, "KorkronRosterFontHighlightSmall")
    detail.crafters:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16)
    detail.crafters:SetPoint("RIGHT", -10, 0)

    detail.reagents = Label(detail, "KorkronRosterFontHighlightSmall")
    detail.reagents:SetPoint("TOPLEFT", detail.crafters, "BOTTOMLEFT", 0, -12)
    detail.reagents:SetPoint("RIGHT", -10, 0)
    detail.reagents:SetSpacing(2)

    -- no default: every requester says who provides the materials
    local matsLabel = Label(detail, "KorkronRosterFontNormalSmall", "Materials:")
    matsLabel:SetPoint("BOTTOMLEFT", 16, 128)
    frame.mats = {}
    for i, choice in ipairs(MATS_CHOICES) do
        local box = UI.CheckButton(detail)
        box:SetPoint("BOTTOMLEFT", 80, 122 - (i - 1) * 22)
        box.label = Label(box, "KorkronRosterFontHighlightSmall", choice.label)
        box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box:SetScript("OnClick", function() ChooseMats(choice.value) end)
        frame.mats[choice.value] = box
    end

    local qtyLabel = Label(detail, "KorkronRosterFontNormalSmall", "Quantity:")
    qtyLabel:SetPoint("BOTTOMLEFT", 16, 74)
    frame.qty = EditBox("KorkronWorkOrderQty", detail, 34, 2)
    frame.qty:SetPoint("LEFT", qtyLabel, "LEFT", 70, 0)
    frame.qty:SetNumeric(true)

    local noteLabel = Label(detail, "KorkronRosterFontNormalSmall", "Note:")
    noteLabel:SetPoint("BOTTOMLEFT", 16, 46)
    frame.note = EditBox("KorkronWorkOrderNote", detail, 190, KR.WorkOrders.MAX_NOTE)
    frame.note:SetPoint("LEFT", noteLabel, "LEFT", 70, 0)
    frame.note.placeholder = Label(frame.note, "KorkronRosterFontDisableSmall", "e.g. needed by Friday")
    frame.note.placeholder:SetPoint("LEFT", 6, 0)
    frame.note:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end)
    frame.note:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    frame.note:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)

    local submit = UI.Button(detail, 120)
    KR.Style.SetButtonKind(submit, true)
    submit:SetPoint("BOTTOMRIGHT", -10, 10)
    submit:SetText("Post Order")
    submit:SetScript("OnClick", function() KR.Safe(Submit) end)
    frame.submit = submit
end

local function Build()
    frame = CreateFrame("Frame", "KorkronWorkOrderForm", UIParent)
    frame:SetSize(620, 448)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronWorkOrderForm")
    UI.MakePopup(frame)
    KR.Style.Window(frame, "|cffc41f3bKor'kron|r - New Work Order")

    local search = UI.EditBox(frame, 280, "KorkronWorkOrderSearch")
    search:SetPoint("TOPLEFT", 16, KR.Style.TOP - 2)
    search.placeholder = Label(search, "KorkronRosterFontDisableSmall", "Search craftable items or professions")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search:SetScript("OnTextChanged", function(self)
        searchText = Lower(strtrim(self:GetText() or ""))
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if frame:IsShown() then
            list:ScrollToTop()
            Form:Refresh()
        end
    end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT", 12, KR.Style.TOP - 28)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(300)
    left.bg = left:CreateTexture(nil, "BACKGROUND")
    left.bg:SetAllPoints()
    left.bg:SetColorTexture(0.04, 0.04, 0.04, 0.7)

    list = UI.CreateList(left, "KorkronWorkOrderList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 4)

    BuildDetail(left)
    frame:SetScript("OnHide", function() UI.HideMenu() end)
end

function Form:Refresh()
    if not frame or not frame:IsShown() then return end
    -- new recipe data rebuilds the index; keep the same recipe picked
    if selected then selected = KR.Recipes.Find(selected.prof, selected.recipe.name) or selected end
    list:SetItems(Craftables())
    ShowSelected()
end

function Form:Open()
    if not frame then Build() end
    selected = nil
    frame.search:SetText("")
    frame.qty:SetText("1")
    frame.note:SetText("")
    frame:Show()
    frame:Raise()
    ChooseMats(nil)
    self:Refresh()
end

function Form:Hide()
    if frame then frame:Hide() end
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("orderFormRefresh", 0.5, function() Form:Refresh() end)
    end
end)
