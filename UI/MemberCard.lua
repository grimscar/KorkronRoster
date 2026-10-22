-- Kor'kron Roster: player card (click a name in the roster).
local _, KR = ...

local UI = KR.UI
local Card = {}
UI.MemberCard = Card

local WIDTH = 360
local NO_MAIN = "No main (characters listed separately)"

local frame, member

local function Label(parent, template, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    return fs
end

local function Header(parent, text, y)
    local fs = Label(parent, "GameFontNormal", 16, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    line:SetColorTexture(1, 0.82, 0, 0.25)
    return fs
end

local function ClassName(classTag)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[classTag]) or (classTag and (classTag:sub(1, 1) .. classTag:sub(2):lower())) or ""
end

-- main character picker (only on your own characters' cards) -----------------------------

local function ChooseMain(value)
    KR.DB:SetMain(value or nil)
    KR.DB:SyncSelf()
    KR.Sync:SendProfile(false)
    if value then
        KR:Print("Your main in this guild is now |cffffd100%s|r. Your other characters show it once they log in.", value)
    else
        KR:Print("Main character cleared.")
    end
    KR:Fire("DATA_UPDATED")
end

local function ShowMainMenu(anchor)
    local current = KR.DB:GetMainSetting()
    local options = { { label = NO_MAIN, value = false, selected = current == nil } }
    for _, p in ipairs(KR.DB:GetMyCharacters()) do
        options[#options + 1] = {
            label = "|cff" .. KR.ClassColorHex(p.class) .. p.fullName .. "|r",
            value = p.fullName,
            selected = p.fullName == current,
        }
    end
    UI.ShowMenu(anchor, options, function(opt) ChooseMain(opt.value) end)
end

-- frame ---------------------------------------------------------------------------------

local function ProfLine(parent, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(WIDTH - 40, 18)
    btn:SetPoint("TOPLEFT", 20, y)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(16, 16)
    btn.icon:SetPoint("LEFT")
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
    btn.text:SetPoint("RIGHT")
    btn.text:SetJustifyH("LEFT")
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)
    btn:SetScript("OnClick", function(self)
        if self.prof and member then UI.Inspector:Open(member, self.prof) end
    end)
    return btn
end

local function Build()
    frame = CreateFrame("Frame", "KorkronMemberCard", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, 484)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronMemberCard")
    UI.MakePopup(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg or frame, "TOP", 0, -3)
    frame.title:SetText("Player Card")

    frame.classIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(40, 40)
    frame.classIcon:SetPoint("TOPLEFT", 16, -32)
    frame.classIcon:SetTexture(KR.CLASS_ICON_TEXTURE)

    frame.name = Label(frame, "GameFontNormalLarge", 64, -32, WIDTH - 80)
    frame.info = Label(frame, "GameFontHighlightSmall", 64, -52, WIDTH - 180)
    frame.rank = Label(frame, "GameFontHighlightSmall", 64, -66, WIDTH - 180)
    frame.status = Label(frame, "GameFontHighlightSmall", 64, -80, WIDTH - 80)
    -- one line each: long titles get "..." instead of wrapping over the next line
    for _, fs in ipairs({ frame.name, frame.info, frame.rank, frame.status }) do
        fs:SetWordWrap(false)
    end


    -- officers and the GM: change rank and Kor'kron title
    frame.setRank = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.setRank:SetSize(90, 20)
    frame.setRank:SetPoint("TOPRIGHT", -16, -54)
    frame.setRank:SetText("Set Rank")
    frame.setRank:SetScript("OnClick", function(self) UI.ShowRankMenu(self, member) end)
    frame.setRank:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Set rank")
        GameTooltip:AddLine("Pick a Kor'kron title. Their in-game rank moves to match, and everyone running the addon sees the title.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.setRank:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- main / alts
    Header(frame, "Main & Alts", -104)
    frame.family = Label(frame, "GameFontHighlightSmall", 20, -124, WIDTH - 40)
    frame.family:SetWordWrap(true)

    frame.mainLabel = Label(frame, "GameFontNormalSmall", 20, -154)
    frame.mainLabel:SetText("Your main:")
    local picker = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    picker:SetSize(230, 22)
    picker:SetPoint("LEFT", frame.mainLabel, "RIGHT", 8, 0)
    picker:SetScript("OnClick", function(self) ShowMainMenu(self) end)
    picker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Main character")
        GameTooltip:AddLine("Pick which of your characters is your main. Your other characters in this guild then show up as \"Alt (Main)\" for everyone.", 1, 1, 1, true)
        GameTooltip:AddLine("Only characters you have logged into with Kor'kron Roster are listed.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    picker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.picker = picker

    frame.viewMain = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.viewMain:SetSize(110, 22)
    frame.viewMain:SetPoint("TOPRIGHT", -16, -148)
    frame.viewMain:SetText("View Main")
    frame.viewMain:SetScript("OnClick", function()
        local main = member and member.main and KR.DB:GetMember(member.main)
        if main then Card:Open(main) end
    end)

    -- professions
    Header(frame, "Professions", -186)
    frame.profs = {}
    for i = 1, 5 do frame.profs[i] = ProfLine(frame, -204 - (i - 1) * 19) end

    -- pvp
    Header(frame, "PvP", -306)
    frame.pvp = Label(frame, "GameFontHighlightSmall", 20, -324, WIDTH - 40)
    frame.pvp:SetSpacing(2)

    -- notes
    Header(frame, "Notes", -366)
    frame.notes = Label(frame, "GameFontHighlightSmall", 20, -384, WIDTH - 40)
    frame.notes:SetWordWrap(true)
    frame.notes:SetSpacing(2)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 16, 14)

    frame.whisper = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.whisper:SetSize(90, 22)
    frame.whisper:SetPoint("BOTTOMRIGHT", -12, 10)
    frame.whisper:SetText("Whisper")
    frame.whisper:SetScript("OnClick", function() UI.Whisper(member) end)

    frame:SetScript("OnHide", function() UI.HideMenu() end)
end

function Card:Refresh()
    if not frame or not frame:IsShown() or not member then return end
    local m = member

    local coords = KR.CLASS_ICON_TCOORDS[m.class]
    if coords then
        frame.classIcon:SetTexCoord(unpack(coords))
        frame.classIcon:Show()
    else
        frame.classIcon:Hide()
    end
    frame.classIcon:SetDesaturated(not m.online)
    frame.name:SetText(UI.ColoredName(m))
    local title = KR.Ranks.Title(m)
    frame.info:SetText(string.format("Level %s %s", m.level or "?", ClassName(m.class)))
    if title and title ~= m.guildRank then
        frame.rank:SetText("|cffffd100" .. title .. "|r |cff888888(" .. (m.guildRank or "?") .. ")|r")
    else
        frame.rank:SetText("|cffffd100" .. (m.guildRank or "") .. "|r")
    end
    frame.setRank:SetShown(KR.Ranks.CanEdit(m))
    if m.online then
        frame.status:SetText("|cff40ff40Online|r" .. ((m.zone and m.zone ~= "") and (" - " .. m.zone) or ""))
    else
        frame.status:SetText("|cff9d9d9dOffline, last seen " .. KR.FormatAgo(m.lastOnline) .. "|r")
    end

    -- main / alts
    local alts = KR.DB:GetAlts(m.main or m.name)
    local lines = {}
    if m.main then
        lines[#lines + 1] = "Alt of |cffffd100" .. m.main .. "|r"
        local others = {}
        for _, alt in ipairs(alts) do
            if alt.name ~= m.name then others[#others + 1] = UI.ColoredName(alt) end
        end
        if #others > 0 then lines[#lines + 1] = "Other alts: " .. table.concat(others, ", ") end
    elseif #alts > 0 then
        local names = {}
        for i, alt in ipairs(alts) do names[i] = UI.ColoredName(alt) end
        lines[#lines + 1] = "Main character. Alts: " .. table.concat(names, ", ")
    else
        lines[#lines + 1] = "|cff9d9d9dNo alts linked.|r"
    end
    frame.family:SetText(table.concat(lines, "\n"))

    local mine = KR.DB:IsMyCharacter(m.name)
    frame.mainLabel:SetShown(mine)
    frame.picker:SetShown(mine)
    if mine then
        frame.picker:SetText(KR.DB:GetMainSetting() or "Choose...")
    end
    frame.viewMain:SetShown(not mine and m.main ~= nil and KR.DB:GetMember(m.main) ~= nil)

    -- professions
    local shown = 0
    for _, slot in ipairs(KR.PROF_SLOTS) do
        local p = m[slot]
        if p and (p.rank or 0) > 0 and p.name ~= "-" then
            shown = shown + 1
            local line = frame.profs[shown]
            local data = m.recipes and m.recipes[p.name]
            line.prof = p.name
            line.icon:SetTexture(KR.ProfIcon(p.name))
            line.text:SetText(string.format("%s |cffaaaaaa%d/%d|r%s", p.name, p.rank, p.max or 0,
                data and ("  |cff66bbff" .. data.count .. " recipes|r") or ""))
            line:Show()
        end
    end
    for i = shown + 1, #frame.profs do frame.profs[i]:Hide() end
    if shown == 0 then
        frame.profs[1].prof = nil
        frame.profs[1].icon:SetTexture(nil)
        frame.profs[1].text:SetText("|cff9d9d9dNo professions known.|r")
        frame.profs[1]:Show()
    end

    -- pvp
    local pvp = KR.PvP.Current(m.pvp)
    frame.pvp:SetText(string.format("%s\nHKs today |cff66ff66%d|r   this week |cffffffff%d|r   lifetime |cffff8040%d|r\nHonor this week |cffffd100%d|r",
        KR.PvP.RankName(pvp.rankNum) and ("|cffffd100" .. KR.PvP.RankName(pvp.rankNum) .. "|r (Rank " .. pvp.rankNum .. ")") or "Unranked",
        pvp.todayHK, pvp.weekHK, pvp.lifetimeHK, pvp.weekHonor))

    -- notes; officer notes are only stored when you are allowed to read them
    local notes = {}
    if m.note and m.note ~= "" then notes[#notes + 1] = "Public: |cffffffff" .. m.note .. "|r" end
    if m.officerNote and m.officerNote ~= "" then notes[#notes + 1] = "Officer: |cffff8040" .. m.officerNote .. "|r" end
    frame.notes:SetText(#notes > 0 and table.concat(notes, "\n") or "|cff9d9d9dNo notes.|r")

    frame.footer:SetText(m.version and ("Kor'kron Roster " .. m.version .. ", synced " .. KR.FormatAgo(m.lastSync)) or "Not running Kor'kron Roster")
    frame.whisper:SetShown(not KR.IsMe(m.name))
end

function Card:Open(m)
    if not m then return end
    if not frame then Build() end
    member = m
    UI.HideMenu()
    if not frame:IsShown() then
        frame:ClearAllPoints()
        if KorkronRosterMainFrame and KorkronRosterMainFrame:IsShown() then
            frame:SetPoint("TOPLEFT", KorkronRosterMainFrame, "TOPRIGHT", 4, 0)
        else
            frame:SetPoint("CENTER")
        end
    end
    frame:Show()
    frame:Raise()
    self:Refresh()
end

function Card:Hide()
    if frame then frame:Hide() end
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("cardRefresh", 0.5, function() Card:Refresh() end)
    end
end)
