-- Kor'kron Roster: addon-message transport with a bandwidth-limited send queue.
local _, KR = ...

local Comm = {}
KR.Comm = Comm

Comm.PREFIX = "KRROSTER" -- shared with 1.0 so old and new versions still see each other

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(Comm.PREFIX)
end

-- token bucket, same budget ChatThrottleLib uses: ~800 bytes/s sustained
local CPS, BURST, OVERHEAD = 800, 2000, 25
local MAX_MESSAGE = 255
local PRIORITIES = { "ALERT", "NORMAL", "BULK" }
local queues = { ALERT = {}, NORMAL = {}, BULK = {} }
local bucket = BURST

-- messages we sent in the last minute; their echo tells us our own full name
Comm.recentlySent = {}

-- Enum.SendAddonMessageResult values that mean "try again later"
local THROTTLED = { [3] = true, [8] = true }

local function RawSend(msg, channel, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage(Comm.PREFIX, msg, channel, target)
    elseif SendAddonMessage then
        return SendAddonMessage(Comm.PREFIX, msg, channel, target)
    end
end

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, elapsed)
    bucket = math.min(BURST, bucket + CPS * elapsed)
    for _, prio in ipairs(PRIORITIES) do
        local q = queues[prio]
        while q[1] do
            local item = q[1]
            local cost = #item.msg + OVERHEAD
            if bucket < cost then return end
            local result = RawSend(item.msg, item.channel, item.target)
            if type(result) == "number" and THROTTLED[result] then
                bucket = 0 -- the server pushed back; retry once the bucket refills
                return
            end
            table.remove(q, 1)
            bucket = bucket - cost
            Comm.recentlySent[item.msg] = GetTime()
        end
    end
    self:Hide()
    local now = GetTime()
    for msg, sentAt in pairs(Comm.recentlySent) do
        if now - sentAt > 60 then Comm.recentlySent[msg] = nil end
    end
end)

function Comm:Send(msg, prio, channel, target)
    channel = channel or "GUILD"
    if channel == "GUILD" and not IsInGuild() then return false end
    if #msg > MAX_MESSAGE then
        KR:Debug("Dropped oversized message (%s bytes).", #msg)
        return false
    end
    table.insert(queues[prio] or queues.NORMAL, { msg = msg, channel = channel, target = target })
    pump:Show()
    return true
end

function Comm:Pending()
    return #queues.ALERT + #queues.NORMAL + #queues.BULK
end

-- receiving --------------------------------------------------------------------

local handlers = {}

-- fn(senderName, message, channel, rawSender); only guild traffic is dispatched.
-- Several modules may listen to the same command.
function Comm:RegisterHandler(cmd, fn)
    handlers[cmd] = handlers[cmd] or {}
    table.insert(handlers[cmd], fn)
end

KR:RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    if prefix ~= Comm.PREFIX or channel ~= "GUILD" or not msg or not sender or not KR.db then return end
    local name = KR.NameKey(sender)
    if not name then return end

    -- our own echo
    local sentAt = Comm.recentlySent[msg]
    if sentAt and GetTime() - sentAt < 60 and KR.FirstName(name) == UnitName("player") then
        if KR.LearnPlayerName(name) then
            KR.DB:SyncSelf()
            KR:Fire("DATA_UPDATED")
        end
        return
    end
    if KR.IsMe(name) then return end
    local cmd = string.match(msg, "^([^%^]+)")
    local list = cmd and handlers[cmd]
    if not list then return end
    for i = 1, #list do
        list[i](name, msg, channel, sender)
    end
end)
