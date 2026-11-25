local _, KR = ...

local UI, Style = KR.UI, KR.Style
local RaidPlans = KR.RaidPlans
local Planner = {}
UI.RaidPlanner = Planner

local ROW = 18
local POOL_W = 190
local COL_W = 162
local COL_GAP = 6
local BENCH_H = ROW * 5
local HEAD_Y = -32
local LIST_TOP = -50
local POOL_TOP = -122

local pane, ghost
local zones = {}
local plan
local clashes = {}
local drag
local poolSearch = ""

local function Lower(s)
    return string.lower(s or "")
end

local function Label(parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function Tip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTip()
    GameTooltip:Hide()
end

local function Select(p)
    KR.db.settings.raidPlan = p and p.id or nil
    Planner:Refresh()
end

local function ZoneUnderCursor()
    for _, z in ipairs(zones) do
        if z.list:IsMouseOver() then return z end
    end
end

local function NameUnderCursor(list)
    for _, row in ipairs(list.rows) do
        if row:IsShown() and row:IsMouseOver() then return row.name end
    end
end

local function EndDrag()
    drag = nil
    ghost:Hide()
    for _, z in ipairs(zones) do z.list.glow:Hide() end
end

local function Drop()
    local name = drag
    if not name then return end
    local z = ZoneUnderCursor()
    local before = z and not z.pool and NameUnderCursor(z.list)
    EndDrag()
    if not z or not plan then return end
    if z.pool then
        RaidPlans.Remove(plan, name)
    else
        RaidPlans.Place(plan, name, z.role, z.bench, before or nil)
    end
end

local function ShowMoveMenu(row)
    local name = row.name
    local spot = RaidPlans.Spot(plan, name)
    local options = { { header = name } }
    for _, r in ipairs(RaidPlans.ROLES) do
        for _, bench in ipairs({ false, true }) do
            options[#options + 1] = {
                label = r.label .. (bench and " (bench)" or ""), role = r.key, bench = bench,
                selected = spot ~= nil and spot.role == r.key and spot.bench == bench,
            }
        end
    end
    if spot then options[#options + 1] = { label = "Take off the plan", remove = true } end
    UI.ShowMenu(row, options, function(opt)
        if opt.remove then
            RaidPlans.Remove(plan, name)
        elseif not opt.selected then
            RaidPlans.Place(plan, name, opt.role, opt.bench)
        end
    end, 170)
end

local function CardTooltip(row)
    local m = KR.DB:GetMember(row.name)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if m then
        GameTooltip:AddLine("|cff" .. KR.ClassColorHex(m.class) .. m.name .. "|r")
        GameTooltip:AddLine("Level " .. (m.level or "?") .. " " .. UI.ClassName(m.class), 1, 1, 1)
        local main = KR.DB:MainOf(m)
        if main then GameTooltip:AddLine("Alt of " .. main, 0.8, 0.8, 0.8) end
        if m.online then
            GameTooltip:AddLine("Online", 0.4, 1, 0.4)
        else
            GameTooltip:AddLine("Offline, last seen " .. KR.FormatAgo(m.lastOnline), 0.6, 0.6, 0.6)
        end
    else
        GameTooltip:AddLine(row.name, 0.6, 0.6, 0.6)
        GameTooltip:AddLine("No longer in the guild", 0.88, 0.38, 0.31)
    end
    if clashes[row.name] then
        GameTooltip:AddLine("The same player as " .. clashes[row.name] .. ", also in this raid", 0.88, 0.38, 0.31, true)
    end
    if plan and RaidPlans.CanEdit() then GameTooltip:AddLine("Drag to a role, or right-click to move", 0, 1, 0) end
    if m then GameTooltip:AddLine("Click for player card", 0, 1, 0) end
    GameTooltip:Show()
end

local function CardClick(row, button)
    if row.dragged then return end
    if button == "RightButton" then
        if plan and RaidPlans.CanEdit() then ShowMoveMenu(row) end
    else
        local m = KR.DB:GetMember(row.name)
        if m then UI.MemberCard:Open(m) end
    end
end

local function CreateCard(list)
    local row = CreateFrame("Button", nil, list)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.1)
    row.warn = Label(row, "KorkronRosterFontNormalSmall", "|cffe0604f!|r")
    row.warn:SetPoint("RIGHT", -4, 0)
    row.warn:SetWidth(8)
    row.level = Label(row, "KorkronRosterFontDisableSmall")
    row.level:SetPoint("RIGHT", row.warn, "LEFT", -2, 0)
    row.level:SetJustifyH("RIGHT")
    row.text = Label(row, "KorkronRosterFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
    row.text:SetWordWrap(false)
    row:SetScript("OnMouseDown", function(self) self.dragged = false end)
    row:SetScript("OnDragStart", function(self)
        if not plan or not RaidPlans.CanEdit() then return end
        self.dragged = true
        drag = self.name
        GameTooltip:Hide()
        ghost.text:SetText(self.text:GetText())
        ghost:Show()
    end)
    row:SetScript("OnDragStop", function() KR.Safe(Drop) end)
    row:SetScript("OnClick", function(self, button) KR.Safe(CardClick, self, button) end)
    row:SetScript("OnEnter", CardTooltip)
    row:SetScript("OnLeave", HideTip)
    return row
end

local function UpdateCard(row, name)
    local m = KR.DB:GetMember(name)
    row.name = name
    row.text:SetText(m and ("|cff" .. KR.ClassColorHex(m.class) .. name .. "|r") or ("|cff808080" .. name .. "|r"))
    row.level:SetText(m and (m.level or 0) > 0 and m.level or "")
    row.warn:SetShown(clashes[name] ~= nil)
    row:SetAlpha((m and m.online) and 1 or 0.55)
end

local function Zone(name, role, bench, pool)
    local list = UI.CreateList(pane, name, ROW, CreateCard, UpdateCard)
    list.bg = list:CreateTexture(nil, "BACKGROUND")
    list.bg:SetAllPoints()
    list.bg:SetColorTexture(0.04, 0.04, 0.04, 0.7)
    local gold = Style.COLOR.gold
    list.glow = list:CreateTexture(nil, "BORDER")
    list.glow:SetAllPoints()
    list.glow:SetColorTexture(gold[1], gold[2], gold[3], 0.15)
    list.glow:Hide()
    local z = { list = list, role = role, bench = bench, pool = pool }
    zones[#zones + 1] = z
    return z
end

local function PoolItems(placed)
    local f = KR.db.settings.raidFilter
    local g = KR.DB:GetGuild()
    local out = {}
    for name, m in KR.DB:IterateMembers() do
        if not placed[name]
            and (poolSearch == "" or string.find(Lower(name), poolSearch, 1, true))
            and (not f.class or m.class == f.class)
            and (not f.online or m.online)
            and (not f.mains or not KR.DB:MainOf(m, g)) then
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b)
        if a.class ~= b.class then return UI.ClassName(a.class) < UI.ClassName(b.class) end
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la > lb end
        return a.name < b.name
    end)
    for i, m in ipairs(out) do out[i] = m.name end
    return out
end

local function ShowPlanMenu(anchor)
    local options = {}
    for _, p in ipairs(RaidPlans.List()) do
        options[#options + 1] = { label = p.name .. " |cff9d9d9d(" .. p.size .. ")|r", id = p.id, selected = p == plan }
    end
    if #options == 0 then options[1] = { header = "No raid plans yet" } end
    UI.ShowMenu(anchor, options, function(opt) Select(RaidPlans.Get(opt.id)) end, 220)
end

local function ShowClassMenu(anchor)
    local f = KR.db.settings.raidFilter
    local seen, classes = {}, {}
    for _, m in KR.DB:IterateMembers() do
        if m.class and not seen[m.class] then
            seen[m.class] = true
            classes[#classes + 1] = m.class
        end
    end
    table.sort(classes, function(a, b) return UI.ClassName(a) < UI.ClassName(b) end)
    local options = { { label = "All classes", selected = f.class == nil } }
    for _, c in ipairs(classes) do
        options[#options + 1] = { label = "|cff" .. KR.ClassColorHex(c) .. UI.ClassName(c) .. "|r", class = c, selected = f.class == c }
    end
    UI.ShowMenu(anchor, options, function(opt)
        f.class = opt.class
        Planner:Refresh()
    end, POOL_W - 12)
end

local function StartRename()
    if not plan then return end
    pane.planBtn:Hide()
    pane.nameBox:SetText(plan.name)
    pane.nameBox:Show()
    pane.nameBox:SetFocus()
    pane.nameBox:HighlightText()
end

local function EndRename()
    pane.nameBox:Hide()
    pane.planBtn:Show()
end

local function NewPlan()
    local p = RaidPlans.Create("Raid plan " .. (#RaidPlans.List() + 1), plan and plan.size or 40)
    if not p then return end
    Select(p)
    StartRename()
end

local function CopyPlan()
    local p = plan and RaidPlans.Copy(plan)
    if p then Select(p) end
end

local function DeletePlan()
    if plan then StaticPopup_Show("KORKRON_RAID_PLAN_DELETE", plan.name, nil, plan) end
end

StaticPopupDialogs["KORKRON_RAID_PLAN_DELETE"] = {
    text = "Delete the raid plan %s? It's removed for everyone in the guild.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) KR.Safe(RaidPlans.Delete, data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local EDIT_BUTTONS = {
    { key = "new", text = "New", width = 56, fn = NewPlan, tip = "Start a new, empty raid plan." },
    { key = "copy", text = "Copy", width = 56, fn = CopyPlan, tip = "Make a new plan from this one, for example a 20-man version of a 40-man plan." },
    { key = "rename", text = "Rename", width = 66, fn = StartRename, tip = "Type a new name, then press Enter." },
    { key = "delete", text = "Delete", width = 62, fn = DeletePlan, tip = "Delete this plan, for you and everyone in the guild. Asks first." },
}

local function BuildTop()
    local planBtn = UI.Button(pane, 220)
    planBtn:SetPoint("TOPLEFT", 0, 0)
    planBtn:SetScript("OnClick", function(self) ShowPlanMenu(self) end)
    planBtn:SetScript("OnEnter", function(self) Tip(self, "Raid plans", "Pick which plan to show.") end)
    planBtn:SetScript("OnLeave", HideTip)
    pane.planBtn = planBtn

    local nameBox = UI.EditBox(pane, 220, "KorkronRaidPlanName")
    nameBox:SetPoint("TOPLEFT", 0, -1)
    nameBox:SetMaxLetters(RaidPlans.MAX_NAME)
    nameBox:Hide()
    nameBox:SetScript("OnEnterPressed", function(self)
        if plan then KR.Safe(RaidPlans.Rename, plan, self:GetText()) end
        EndRename()
    end)
    nameBox:SetScript("OnEscapePressed", EndRename)
    nameBox:SetScript("OnEditFocusLost", EndRename)
    pane.nameBox = nameBox

    pane.edit = {}
    local prev = planBtn
    for _, b in ipairs(EDIT_BUTTONS) do
        local btn = UI.Button(pane, b.width)
        btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        btn:SetText(b.text)
        btn:SetScript("OnClick", function() KR.Safe(b.fn) end)
        btn:SetScript("OnEnter", function(self) Tip(self, b.text, b.tip) end)
        btn:SetScript("OnLeave", HideTip)
        pane.edit[b.key] = btn
        prev = btn
    end

    pane.sizeLabel = Label(pane, "KorkronRosterFontNormalSmall", "Size:")
    pane.sizes = {}
    prev = pane.sizeLabel
    for _, size in ipairs(RaidPlans.SIZES) do
        local btn = UI.Button(pane, 38)
        btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        btn:SetText(size)
        btn.size = size
        btn:SetScript("OnClick", function() if plan then KR.Safe(RaidPlans.SetSize, plan, size) end end)
        pane.sizes[#pane.sizes + 1] = btn
        prev = btn
    end
    pane.count = Label(pane, "KorkronRosterFontHighlightSmall")
    pane.count:SetPoint("LEFT", prev, "RIGHT", 12, 0)

    pane.note = Label(pane, "KorkronRosterFontDisableSmall")
    pane.note:SetPoint("RIGHT", pane, "TOPRIGHT", -4, -11)
    pane.note:SetJustifyH("RIGHT")
end

local function FilterCheck(key, text, x, tip)
    local check = UI.CheckButton(pane)
    check:SetPoint("TOPLEFT", x, -96)
    check.label = Label(check, "KorkronRosterFontNormalSmall", text)
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check:SetScript("OnClick", function(self)
        KR.db.settings.raidFilter[key] = self:GetChecked() and true or false
        Planner:Refresh()
    end)
    check:SetScript("OnEnter", function(self) Tip(self, text, tip) end)
    check:SetScript("OnLeave", HideTip)
    return check
end

local function BuildPool()
    pane.poolTitle = Label(pane, "KorkronRosterFontNormal")
    pane.poolTitle:SetPoint("TOPLEFT", 2, HEAD_Y)

    local search = UI.EditBox(pane, POOL_W, "KorkronRaidPoolSearch")
    search:SetPoint("TOPLEFT", 0, LIST_TOP)
    search.placeholder = Label(search, "KorkronRosterFontDisableSmall", "Search names")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search:SetScript("OnTextChanged", function(self)
        poolSearch = Lower(strtrim(self:GetText() or ""))
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        Planner:Refresh()
    end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    pane.classBtn = UI.Button(pane, POOL_W)
    pane.classBtn:SetPoint("TOPLEFT", 0, LIST_TOP - 24)
    pane.classBtn:SetScript("OnClick", function(self) ShowClassMenu(self) end)

    pane.online = FilterCheck("online", "Online", -2, "Only list guild members who are online now.")
    pane.mains = FilterCheck("mains", "Mains only", 92, "Leave out characters that are someone's alt.")

    local pool = Zone("KorkronRaidPool", nil, nil, true)
    pool.list:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, POOL_TOP)
    pool.list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", POOL_W, 0)
end

local function BuildColumns()
    for i, r in ipairs(RaidPlans.ROLES) do
        local x = POOL_W + 10 + (i - 1) * (COL_W + COL_GAP)
        local raid = Zone("KorkronRaid_" .. r.key, r.key, false)
        raid.list:SetPoint("TOPLEFT", pane, "TOPLEFT", x, LIST_TOP)
        raid.list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", x + COL_W, BENCH_H + 20)
        raid.head = Label(pane, "KorkronRosterFontNormal")
        raid.head:SetPoint("TOPLEFT", x + 2, HEAD_Y)
        raid.label = r.label

        local bench = Zone("KorkronRaid_" .. r.key .. "_bench", r.key, true)
        bench.list:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", x, 0)
        bench.list:SetSize(COL_W, BENCH_H)
        bench.head = Label(pane, "KorkronRosterFontNormalSmall")
        bench.head:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", x + 2, BENCH_H + 4)
        bench.label = "Bench"
    end
end

local function BuildGhost()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(COL_W - 22, ROW)
    ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.bg:SetAllPoints()
    ghost.bg:SetColorTexture(0.1, 0.08, 0.07, 0.9)
    ghost.text = Label(ghost, "KorkronRosterFontHighlightSmall")
    ghost.text:SetPoint("LEFT", 6, 0)
    ghost:Hide()
    ghost:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then
            KR.Safe(Drop)
            return
        end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        local over = ZoneUnderCursor()
        for _, z in ipairs(zones) do z.list.glow:SetShown(z == over) end
    end)
end

function Planner:Attach(parent)
    pane = CreateFrame("Frame", "KorkronRaidPlanner", parent)
    pane:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, Style.TOP - 30)
    pane:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 30)
    pane:Hide()
    BuildTop()
    BuildPool()
    BuildColumns()
    BuildGhost()
    pane:SetScript("OnHide", function() if drag then EndDrag() end end)
end

function Planner:SetShown(shown)
    if pane then pane:SetShown(shown) end
end

local function RefreshTop(edit)
    pane.planBtn:SetText(plan and plan.name or "No raid plans yet")
    for key, btn in pairs(pane.edit) do
        btn:SetShown(edit)
        btn:SetEnabled(key == "new" or plan ~= nil)
    end
    pane.sizeLabel:ClearAllPoints()
    pane.sizeLabel:SetPoint("LEFT", edit and pane.edit.delete or pane.planBtn, "RIGHT", 16, 0)
    for _, btn in ipairs(pane.sizes) do
        Style.SetButtonKind(btn, plan ~= nil and plan.size == btn.size)
        btn:SetEnabled(edit and plan ~= nil)
    end
    if plan then
        local raid, bench = RaidPlans.Counts(plan)
        local color = raid > plan.size and "|cffe0604f" or "|cffffffff"
        pane.count:SetText(color .. raid .. " / " .. plan.size .. "|r in the raid, " .. bench .. " on the bench")
    else
        pane.count:SetText(edit and "Press New to make your first raid plan." or "")
    end
    if edit then
        pane.note:SetText("")
    else
        pane.note:SetText("Read only: planned by " .. (RaidPlans.GuildMaster() or "the Guild Master"))
    end
end

function Planner:Refresh()
    if not pane or not pane:IsShown() then return end
    plan = RaidPlans.Get(KR.db.settings.raidPlan) or RaidPlans.List()[1]
    clashes = plan and RaidPlans.Clashes(plan) or {}
    RefreshTop(RaidPlans.CanEdit())

    local f = KR.db.settings.raidFilter
    pane.classBtn:SetText(f.class and UI.ClassName(f.class) or "All classes")
    pane.online:SetChecked(f.online)
    pane.mains:SetChecked(f.mains)

    local placed = {}
    for _, s in ipairs(plan and plan.spots or {}) do placed[s.name] = true end
    for _, z in ipairs(zones) do
        if z.pool then
            local items = PoolItems(placed)
            z.list:SetItems(items)
            pane.poolTitle:SetText("Guild members |cff9d9d9d(" .. #items .. ")|r")
        else
            local names = plan and RaidPlans.Column(plan, z.role, z.bench) or {}
            z.list:SetItems(names)
            z.head:SetText(z.label .. " |cff9d9d9d(" .. #names .. ")|r")
        end
    end
end
