-- Kor'kron Roster: the guild log window, for officers: who joined, left or changed rank, newest first.
local _, KR = ...

local UI = KR.UI
local Window = {}
UI.GuildLog = Window

local ROW_HEIGHT = 18

local ACTION = {
    join = "|cff40ff40joined|r",
    quit = "|cffff8040left|r",
    remove = "|cffff4040was kicked|r",
    promote = "|cff40ff40was promoted|r",
    demote = "|cffffd100was demoted|r",
}

local frame, list

-- "~" because the game only gives an event's age in whole hours
local function When(at)
    return (string.gsub(string.lower(date("%m/%d/%y ~%I%p", at)), "~0", "~"))
end

local function Describe(e)
    local text = UI.PersonText(e.name) .. " " .. ACTION[e.kind]
    if e.rank then text = text .. " to |cffffffff" .. e.rank .. "|r" end
    if e.by then text = text .. " by " .. UI.PersonText(e.by) end
    return text
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)
    row.when = row:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    row.when:SetPoint("LEFT", 6, 0)
    row.when:SetWidth(90)
    row.when:SetJustifyH("LEFT")
    row.when:SetTextColor(0.67, 0.67, 0.67)
    row.text = row:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    row.text:SetPoint("LEFT", row.when, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    -- no card for someone who has left: Open ignores a member we don't have
    row:SetScript("OnClick", function(self) UI.MemberCard:Open(KR.DB:GetMember(self.item.name)) end)
    return row
end

local function UpdateRow(row, item)
    row.item = item
    row.when:SetText(When(item.at))
    row.text:SetText(Describe(item))
end

local function Build()
    frame = CreateFrame("Frame", "KorkronGuildLog", UIParent)
    frame:SetSize(560, 468)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronGuildLog")
    UI.MakePopup(frame)
    KR.Style.Window(frame, "Guild Log")

    local intro = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, KR.Style.TOP - 2)
    intro:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Copied from the game's guild log and kept here after the game drops it. Times are to the nearest hour. Click a line for that player's card.")
    intro:SetTextColor(0.8, 0.8, 0.8)

    list = UI.CreateList(frame, "KorkronGuildLogList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 12, KR.Style.TOP - 36)
    list:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontDisable")
    frame.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
    frame.empty:SetText("Nothing in the guild log yet.")
end

function Window:Refresh()
    if not (frame and frame:IsShown()) then return end
    local entries = KR.GuildLog.Entries()
    local rows = {}
    for i = #entries, 1, -1 do rows[#rows + 1] = entries[i] end
    frame.empty:SetShown(#rows == 0)
    list:SetItems(rows)
end

function Window:Toggle()
    if not KR.GuildLog.CanView() then
        KR:Print("The guild log is for officers.")
        return
    end
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:ClearAllPoints()
    if KorkronRosterMainFrame and KorkronRosterMainFrame:IsShown() then
        frame:SetPoint("TOPLEFT", KorkronRosterMainFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    KR.GuildLog.Request()
    self:Refresh()
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("guildLogRefresh", 1, function() Window:Refresh() end)
    end
end)
