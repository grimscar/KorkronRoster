-- Kor'kron Roster: namespace, utilities, event dispatch and timers.
local ADDON_NAME, KR = ...

KorkronRoster = KR -- global handle for debugging (/dump KorkronRoster.version)

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

KR.name = ADDON_NAME
KR.version = (GetMetadata and GetMetadata(ADDON_NAME, "Version")) or "dev"
KR.PROTOCOL = 2
KR.COLOR = "c41f3b"
KR.TITLE = "|cffc41f3bKor'kron|r Roster"

local CHAT_TAG = "|cffc41f3bKor'kron Roster:|r "

local function Format(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return tostring(fmt) end
    local args = { ... }
    for i = 1, n do args[i] = tostring(args[i]) end
    return string.format(fmt, unpack(args, 1, n))
end

-- all format arguments are tostring()'d, so only use %s in messages
function KR:Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_TAG .. Format(fmt, ...))
end

function KR:Debug(fmt, ...)
    if not (self.db and self.db.settings and self.db.settings.debug) then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[KR debug]|r " .. Format(fmt, ...))
end

-- game events --------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- returns false if the client does not know the event
function KR:RegisterEvent(event, handler)
    if not eventHandlers[event] then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], handler)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

-- internal message bus (DATA_UPDATED, ...) ---------------------------------

local callbacks = {}

function KR:On(message, fn)
    callbacks[message] = callbacks[message] or {}
    table.insert(callbacks[message], fn)
end

function KR:Fire(message, ...)
    local list = callbacks[message]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-- timers -------------------------------------------------------------------

function KR:After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end

-- run fn once things have been quiet for `delay` seconds
local debounceTokens = {}
function KR:Debounce(key, delay, fn)
    local token = (debounceTokens[key] or 0) + 1
    debounceTokens[key] = token
    self:After(delay, function()
        if debounceTokens[key] == token then fn() end
    end)
end

-- run fn at most once per `interval` seconds; the latest fn always runs eventually
local throttleState = {}
function KR:Throttle(key, interval, fn)
    local st = throttleState[key]
    if not st then
        st = {}
        throttleState[key] = st
    end
    st.fn = fn
    if st.pending then return end
    st.pending = true
    local wait = math.max(0, (st.last or -interval) + interval - GetTime())
    self:After(wait, function()
        st.pending = false
        st.last = GetTime()
        st.fn()
    end)
end

-- helpers ------------------------------------------------------------------

-- names -------------------------------------------------------------------------
-- Forever characters have a first and last name. Depending on the API the pair comes
-- back as "First Last", "First-Last" or with "-Realm" appended, and UnitName("player")
-- only returns "First". Every record is keyed by NameKey(): realm removed, separator
-- normalised to a single space.

local function RealmSuffix()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = string.gsub(GetRealmName() or "", "[%s%-']", "")
    end
    return realm
end

function KR.NameKey(name)
    if type(name) ~= "string" then return nil end
    name = strtrim(name)
    local realm = RealmSuffix()
    if realm ~= "" then
        local suffix = "-" .. realm
        if #name > #suffix and string.sub(name, -#suffix) == suffix then
            name = string.sub(name, 1, -#suffix - 1)
        end
    end
    name = string.gsub(name, "[%s%-]+", " ")
    return name ~= "" and name or nil
end

function KR.FirstName(name)
    return name and (string.match(name, "^([^%s%-]+)") or name)
end

local playerKey

-- your own full name; falls back to the first name until the roster or our own
-- addon traffic tells us the rest
function KR.PlayerName()
    if playerKey then return playerKey end
    local candidates = {}
    if GetUnitName then
        local ok, n = pcall(GetUnitName, "player", true)
        if ok then candidates[#candidates + 1] = n end
    end
    if UnitNameUnmodified then candidates[#candidates + 1] = UnitNameUnmodified("player") end
    if UnitFullName then candidates[#candidates + 1] = (UnitFullName("player")) end
    for _, n in ipairs(candidates) do
        local key = KR.NameKey(n)
        if key and string.find(key, " ", 1, true) then
            playerKey = key
            return key
        end
    end
    return KR.NameKey(UnitName("player"))
end

function KR.HasFullPlayerName()
    return playerKey ~= nil or string.find(KR.PlayerName() or "", " ", 1, true) ~= nil
end

function KR.LearnPlayerName(key)
    if key and not playerKey and string.find(key, " ", 1, true) and KR.FirstName(key) == UnitName("player") then
        playerKey = key
        KR:Debug("Your full name is %s.", key)
        return true
    end
    return false
end

function KR.IsMe(name)
    return name ~= nil and name == KR.PlayerName()
end

-- -1 if a < b, 0 if equal, 1 if a > b ("1.2.10" > "1.2.9")
function KR.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in string.gmatch(tostring(a or ""), "%d+") do pa[#pa + 1] = tonumber(n) end
    for n in string.gmatch(tostring(b or ""), "%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

function KR.ClassColorHex(classTag)
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classTag]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag])
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

function KR.FormatAgo(timestamp)
    if not timestamp or timestamp <= 0 then return "never" end
    local diff = math.max(0, time() - timestamp)
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end
