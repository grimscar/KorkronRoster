local _, KR = ...

local Comm = {}
KR.Comm = Comm

Comm.PREFIX = "KRROSTER"

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(Comm.PREFIX)
end

local CPS, BURST, OVERHEAD = 800, 2000, 25
local MAX_MESSAGE = 255
local PRIORITIES = { "ALERT", "NORMAL", "BULK" }
local queues = { ALERT = {}, NORMAL = {}, BULK = {} }
local bucket = BURST

Comm.recentlySent = {}

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
                bucket = 0
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

function Comm.Split(s, size)
    local chunks, pos, len = {}, 1, #s
    while pos <= len do
        local stop = pos + size - 1
        if stop >= len then
            stop = len
        else
            local cut
            for i = stop, pos + math.floor(size / 2), -1 do
                if string.byte(s, i) == 126 then cut = i break end
            end
            if cut then
                stop = cut
            else
                while stop > pos do
                    local nextByte = string.byte(s, stop + 1)
                    local inChar = nextByte >= 128 and nextByte < 192
                    if not inChar and string.byte(s, stop) ~= 32 then break end
                    stop = stop - 1
                end
            end
        end
        chunks[#chunks + 1] = string.sub(s, pos, stop)
        pos = stop + 1
    end
    return chunks
end

local handlers = {}

function Comm:RegisterHandler(cmd, fn)
    handlers[cmd] = handlers[cmd] or {}
    table.insert(handlers[cmd], fn)
end

KR:RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    prefix, msg, channel, sender = KR.Text(prefix), KR.Text(msg), KR.Text(channel), KR.Text(sender)
    if prefix ~= Comm.PREFIX or channel ~= "GUILD" or not msg or not sender or not KR.db then return end
    local name = KR.NameKey(sender)
    if not name then return end

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
        KR.Safe(list[i], name, msg, channel, sender)
    end
end)
