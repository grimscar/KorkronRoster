-- Kor'kron Roster: startup and game event wiring. Loaded last.
local ADDON_NAME, KR = ...

local Prof, PvP, Roster, Sync = KR.Professions, KR.PvP, KR.Roster, KR.Sync

local function RefreshSelf(broadcast)
    KR.DB:SyncSelf()
    if broadcast then Sync:ScheduleBroadcast() end
    KR:Fire("DATA_UPDATED")
end

local function OnSkillsChanged()
    KR:Throttle("skills", 3, function()
        RefreshSelf(Prof:ScanSkills())
    end)
end

local function OnPvPChanged()
    KR:Throttle("pvp", 5, function()
        RefreshSelf(PvP:Scan())
    end)
end

local function OnTradeWindow(kind)
    return function()
        -- our own header expand/collapse fires update events; ignore those
        if GetTime() - Prof.lastWindowScan < 1.5 then return end
        KR:Debounce("tradeScan", 0.5, function()
            if Prof:ScanOpenWindow(kind) then
                RefreshSelf(true)
            end
        end)
    end
end

local function RegisterGameEvents()
    KR:RegisterEvent("GUILD_ROSTER_UPDATE", function()
        KR:Throttle("roster", 2, function() Roster:Scan() end)
    end)
    KR:RegisterEvent("PLAYER_GUILD_UPDATE", function()
        Roster:Request()
        KR:Fire("DATA_UPDATED")
    end)

    KR:RegisterEvent("SKILL_LINES_CHANGED", OnSkillsChanged)
    KR:RegisterEvent("CHAT_MSG_SKILL", OnSkillsChanged)
    KR:RegisterEvent("PLAYER_LEVEL_UP", OnSkillsChanged)

    local tradeHandler = OnTradeWindow("TRADE")
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
        KR:RegisterEvent(event, tradeHandler)
    end
    local craftHandler = OnTradeWindow("CRAFT")
    KR:RegisterEvent("CRAFT_SHOW", craftHandler)
    KR:RegisterEvent("CRAFT_UPDATE", craftHandler)

    for _, event in ipairs({ "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED", "HONOR_CURRENCY_UPDATE" }) do
        KR:RegisterEvent(event, OnPvPChanged)
    end

    -- item names arrive asynchronously; redraw so "Item #1234" becomes a real name
    KR:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        KR:Throttle("itemInfo", 1, function() KR:Fire("DATA_UPDATED") end)
    end)
end

local function OnFirstWorldEntry()
    Roster:Request()
    KR:After(3, function()
        Prof:ScanSkills()
        PvP:Scan()
        Roster:Scan()
        KR:Fire("DATA_UPDATED")
    end)
    -- give the roster and chat channels a moment, then sync with a bit of jitter
    KR:After(8 + math.random() * 7, function()
        if KR.db.settings.autoSync then Sync:RequestAll() end
    end)

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(60, function()
            Roster:Request()
            Sync:ScheduleBroadcast()
        end)
    end
end

KR:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    KR.DB:Init()
end)

KR:RegisterEvent("PLAYER_LOGIN", function()
    RegisterGameEvents()
    KR.Tooltip:Init()
    KR.UI.Options:Init()
    KR.UI.MinimapButton:Update()
end)

local entered = false
KR:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if entered then return end
    entered = true
    OnFirstWorldEntry()
end)
