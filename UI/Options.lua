-- Kor'kron Roster: options panel (Esc > Options > AddOns > Kor'kron Roster).
local _, KR = ...

local UI = KR.UI
local Options = {}
UI.Options = Options

local panel, category
local refreshers = {}

local function Checkbox(parent, anchor, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine(tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb
end

local function Button(parent, anchor, text, width, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

StaticPopupDialogs["KORKRON_ROSTER_PURGE"] = {
    text = "Delete all stored data for your current guild?\n\nYour own characters are kept, and guildmates' data comes back on the next sync.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        KR.DB:WipeGuild()
        KR.Recipes.InvalidateIndex()
        KR.Roster:Scan()
        KR:Print("Guild data cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Build()
    local s = KR.db.settings
    panel = CreateFrame("Frame")
    panel.name = "Kor'kron Roster"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(KR.TITLE .. " |cffaaaaaav" .. KR.version .. "|r")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Guild roster, professions, recipes and PvP standings shared between guildmates.")

    local last = sub
    last = Checkbox(panel, last, "Automatic sync", "Share your data with the guild when it changes and ask for everyone's data at login.",
        function() return s.autoSync end, function(v) s.autoSync = v end)
    last = Checkbox(panel, last, "Show guild crafters on item tooltips", "Adds the guildmates who can craft an item to its tooltip.",
        function() return s.tooltips end, function(v) s.tooltips = v end)
    last = Checkbox(panel, last, "Show minimap button", "Left-click opens the roster, right-click opens these options.",
        function() return not s.minimap.hide end, function(v) s.minimap.hide = not v UI.MinimapButton:Update() end)
    last = Checkbox(panel, last, "Show offline members", "Include offline guildmates in the roster window.",
        function() return s.showOffline end, function(v) s.showOffline = v UI.Main:Refresh() end)
    last = Checkbox(panel, last, "Debug messages", "Print sync and scan details to chat. Useful when reporting problems.",
        function() return s.debug end, function(v) s.debug = v end)

    local reset = Button(panel, last, "", 220, function(self)
        s.resetDay = (s.resetDay % 7) + 1
        self:SetText("PvP week starts: " .. KR.WEEKDAYS[s.resetDay])
        KR.PvP:Scan()
        UI.Main:Refresh()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Weekly reset day")
        GameTooltip:AddLine("The day your realm's PvP week resets. Weekly HKs and honor restart on this day. Click to change.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refreshers[#refreshers + 1] = function() reset:SetText("PvP week starts: " .. KR.WEEKDAYS[s.resetDay]) end

    local open = Button(panel, reset, "Open roster", 220, function() UI.Main:Show() end)
    local purge = Button(panel, open, "Clear guild data...", 220, function() StaticPopup_Show("KORKRON_ROSTER_PURGE") end)

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", purge, "BOTTOMLEFT", 0, -16)
    help:SetJustifyH("LEFT")
    help:SetText("Type |cffffd100/kr help|r for chat commands.")

    panel:SetScript("OnShow", function()
        for _, fn in ipairs(refreshers) do fn() end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options:Init()
    if not panel then Build() end
end

function Options:Open()
    self:Init()
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- first call only opens the frame on old clients
    end
end
