local _, KR = ...

local UI, Style = KR.UI, KR.Style
local Picker = {}
UI.MainPicker = Picker

local ROW_HEIGHT = 18

local frame, list, member
local searchText = ""

local function Lower(s)
    return string.lower(s or "")
end

local function Choose(main)
    local m = member
    frame:Hide()
    if not KR.Links.Set(m, main) then return end
    if main then
        KR:Print("|cffffd100%s|r is now an alt of |cffffd100%s|r for everyone with Kor'kron Roster.", m.name, main)
    else
        KR:Print("|cffffd100%s|r has no main set by an officer now.", m.name)
    end
end

local function Items()
    local out = {}
    for _, m in ipairs(KR.Links.Choices(member)) do
        if searchText == "" or string.find(Lower(m.name), searchText, 1, true) then out[#out + 1] = m end
    end
    return out
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.text = row:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self) Choose(self.member.name) end)
    return row
end

local function UpdateRow(row, m)
    row.member = m
    row.text:SetText(UI.ColoredName(m) .. "  |cff9d9d9d" .. (m.level or "?") .. "|r")
end

local function Build()
    frame = CreateFrame("Frame", "KorkronMainPicker", UIParent)
    frame:SetSize(300, 420)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronMainPicker")
    UI.MakePopup(frame)
    Style.Window(frame, "Choose a Main")

    frame.question = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    frame.question:SetPoint("TOPLEFT", 16, Style.TOP - 2)
    frame.question:SetPoint("RIGHT", -16, 0)
    frame.question:SetJustifyH("LEFT")
    frame.question:SetWordWrap(true)

    local search = UI.EditBox(frame, 268, "KorkronMainPickerSearch")
    search:SetPoint("TOPLEFT", 16, Style.TOP - 36)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "KorkronRosterFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search.placeholder:SetText("Search names")
    search:SetScript("OnTextChanged", function(self)
        searchText = Lower(strtrim(self:GetText() or ""))
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if frame:IsShown() then
            list:ScrollToTop()
            Picker:Refresh()
        end
    end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    list = UI.CreateList(frame, "KorkronMainPickerList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 12, Style.TOP - 62)
    list:SetPoint("BOTTOMRIGHT", -12, 44)

    frame.none = UI.Button(frame, 120)
    frame.none:SetPoint("BOTTOMLEFT", 12, 12)
    frame.none:SetText("No main")
    frame.none:SetScript("OnClick", function() Choose(nil) end)

    frame.cancel = UI.Button(frame, 90)
    frame.cancel:SetPoint("BOTTOMRIGHT", -12, 12)
    frame.cancel:SetText("Cancel")
    frame.cancel:SetScript("OnClick", function() frame:Hide() end)
end

function Picker:Refresh()
    if not frame or not frame:IsShown() or not member then return end
    list:SetItems(Items())
end

function Picker:Open(m)
    if not m or not KR.Links.CanSet(m) then return end
    if not frame then Build() end
    member = m
    frame.question:SetText("Which character is |cffffd100" .. m.name .. "|r an alt of? Only characters that aren't alts themselves are listed.")
    frame:ClearAllPoints()
    if KorkronMemberCard and KorkronMemberCard:IsShown() then
        frame:SetPoint("TOPLEFT", KorkronMemberCard, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame.search:SetText("")
    frame:Show()
    frame:Raise()
    self:Refresh()
end

function Picker:Hide()
    if frame then frame:Hide() end
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("mainPickerRefresh", 0.5, function() Picker:Refresh() end)
    end
end)
