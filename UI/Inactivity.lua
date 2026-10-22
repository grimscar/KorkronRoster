-- Kor'kron Roster: inactivity report. Purely informational: players (a main and all of
-- their alts together) grouped by how long since any of their characters was online.
local _, KR = ...

local UI = KR.UI
local Inactivity = {}
UI.Inactivity = Inactivity

local ROW_HEIGHT = 18
local DAY = 86400

local BRACKETS = {
    { label = "Seen this week", min = 0, max = 7 * DAY, color = "40ff40" },
    { label = "1 to 4 weeks", min = 7 * DAY, max = 30 * DAY, color = "ffffff" },
    { label = "1 to 3 months", min = 30 * DAY, max = 90 * DAY, color = "ffd100" },
    { label = "3 months or more", min = 90 * DAY, max = math.huge, color = "ff8040" },
}

local frame, list
local collapsed = { [1] = true } -- the active bracket is usually the big boring one

local function BuildRows()
    local now = time()
    local buckets = {}
    for i = 1, #BRACKETS do buckets[i] = {} end
    for _, p in ipairs(KR.Roster:GetPlayers()) do
        if p.lead then
            local away = p.online and 0 or (now - (p.lastOnline or 0))
            for i, b in ipairs(BRACKETS) do
                if away >= b.min and away < b.max then
                    table.insert(buckets[i], { player = p, away = away })
                    break
                end
            end
        end
    end
    local rows = {}
    for i, b in ipairs(BRACKETS) do
        local entries = buckets[i]
        table.sort(entries, function(x, y)
            if x.away ~= y.away then return x.away > y.away end
            return x.player.lead.name < y.player.lead.name
        end)
        rows[#rows + 1] = { header = i, count = #entries }
        if not collapsed[i] then
            for _, e in ipairs(entries) do rows[#rows + 1] = e end
        end
    end
    return rows
end

local function RowOnClick(row)
    local item = row.item
    if item.header then
        collapsed[item.header] = not collapsed[item.header]
        Inactivity:Refresh()
    elseif item.player then
        UI.MemberCard:Open(item.player.lead)
    end
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.bg = row:CreateTexture(nil, "BORDER")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", 6, 0)
    row.left:SetPoint("RIGHT", -110, 0)
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetWidth(100)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnClick", RowOnClick)
    return row
end

local function UpdateRow(row, item)
    row.item = item
    if item.header then
        local b = BRACKETS[item.header]
        row.bg:SetColorTexture(0.2, 0.16, 0.08, 0.85)
        row.left:SetText(string.format("|cff%s%s %s|r", b.color, collapsed[item.header] and "[+]" or "[-]", b.label))
        row.right:SetText(string.format("|cff%s%d player%s|r", b.color, item.count, item.count == 1 and "" or "s"))
    else
        local p = item.player
        local m = p.lead
        row.bg:SetColorTexture(0, 0, 0, 0)
        local extra = #p.chars - 1
        local name = "|cff" .. KR.ClassColorHex(m.class) .. m.name .. "|r"
        if extra > 0 then name = name .. " |cff9d9d9d(+" .. extra .. (extra == 1 and " alt" or " alts") .. ")|r" end
        local title = KR.Ranks.Title(m)
        if title then name = name .. "  |cff777777" .. title .. "|r" end
        row.left:SetText(name)
        row.right:SetText(p.online and "|cff40ff40Online|r" or ("|cffaaaaaa" .. KR.FormatAgo(p.lastOnline) .. "|r"))
    end
end

local function Build()
    frame = CreateFrame("Frame", "KorkronInactivityReport", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 460)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronInactivityReport")
    UI.MakePopup(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg or frame, "TOP", 0, -3)
    frame.title:SetText("Inactivity Report")

    local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Each player counts once, using whichever of their characters was online most recently. Click a name for their player card.")
    intro:SetTextColor(0.8, 0.8, 0.8)

    list = UI.CreateList(frame, "KorkronInactivityList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 12, -66)
    list:SetPoint("BOTTOMRIGHT", -12, 12)
end

function Inactivity:Refresh()
    if frame and frame:IsShown() then list:SetItems(BuildRows()) end
end

function Inactivity:Toggle()
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
    self:Refresh()
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("inactivityRefresh", 1, function() Inactivity:Refresh() end)
    end
end)
