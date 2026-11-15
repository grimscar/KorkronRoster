local _, KR = ...

local GuildLog = {}
KR.GuildLog = GuildLog

local DONE_TO_PLAYER2 = { promote = true, demote = true, remove = true, join = false, quit = false }

function GuildLog.CanView()
    return KR.Ranks.IsManagerIndex(KR.Ranks.MyIndex())
end

function GuildLog.Entries()
    local _, key = KR.DB:GetGuild()
    if not key then return {} end
    local logs = KR.db.guildLogs
    logs[key] = logs[key] or {}
    return logs[key]
end

local function Insert(list, e)
    local pos = #list + 1
    while pos > 1 and list[pos - 1].at > e.at do pos = pos - 1 end
    table.insert(list, pos, e)
end

local function ReadEvent(i, now)
    local kind, player1, player2, rank, years, months, days, hours = GetGuildEventInfo(i)
    kind = KR.Text(kind)
    local doneToPlayer2 = DONE_TO_PLAYER2[kind]
    if doneToPlayer2 == nil then return nil end
    local name, by = KR.NameKey(player1), nil
    if doneToPlayer2 then name, by = KR.NameKey(player2), name end
    local age = KR.ElapsedSeconds(years, months, days, hours)
    if not name or (doneToPlayer2 and not by) or not age then return nil end
    return {
        at = now - age,
        kind = kind,
        name = name,
        by = by,
        rank = (kind == "promote" or kind == "demote") and KR.Text(rank) or nil,
    }
end

local function EventKey(e)
    return e.kind .. "^" .. e.name .. "^" .. (e.by or "")
end

local function TakeSavedCopy(candidates, e, now)
    local slack = math.max(2 * 3600, (now - e.at) / 10)
    local best, bestGap
    for i, saved in ipairs(candidates) do
        local gap = math.abs(saved.at - e.at)
        if gap <= slack and (not bestGap or gap < bestGap) then best, bestGap = i, gap end
    end
    return best and table.remove(candidates, best)
end

function GuildLog.Read()
    if not GuildLog.CanView() then return end
    local total = GetNumGuildEvents()
    if not KR.Readable(total) then return end

    local now = time()
    local events = {}
    for i = total, 1, -1 do
        local e = ReadEvent(i, now)
        if e then Insert(events, e) end
    end

    local entries = GuildLog.Entries()
    local saved = {}
    for _, e in ipairs(entries) do
        local key = EventKey(e)
        saved[key] = saved[key] or {}
        table.insert(saved[key], e)
    end

    local added = 0
    for _, e in ipairs(events) do
        local candidates = saved[EventKey(e)]
        if not (candidates and TakeSavedCopy(candidates, e, now)) then
            Insert(entries, e)
            added = added + 1
        end
    end

    KR:Debug("Guild log: the game has %s events, %s we keep, %s new.", total, #events, added)
    if added > 0 then KR:Fire("DATA_UPDATED") end
end

function GuildLog.Request()
    if GuildLog.CanView() then QueryGuildEventLog() end
end
