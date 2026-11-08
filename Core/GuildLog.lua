-- Kor'kron Roster: a lasting copy of the game's guild log, for officers. The game only keeps the
-- most recent events, so each read adds whatever is new to the saved list.
local _, KR = ...

local GuildLog = {}
KR.GuildLog = GuildLog

-- The events we keep (the game's "invite" isn't one). True: player1 did it to player2.
-- False: it happened to player1.
local DONE_TO_PLAYER2 = { promote = true, demote = true, remove = true, join = false, quit = false }

function GuildLog.CanView()
    return KR.Ranks.IsManagerIndex(KR.Ranks.MyIndex())
end

-- the current guild's saved events, oldest first
function GuildLog.Entries()
    local _, key = KR.DB:GetGuild()
    if not key then return {} end
    local logs = KR.db.guildLogs
    logs[key] = logs[key] or {}
    return logs[key]
end

-- Keeps a list oldest first. Events with the same time stay in the order they were added.
local function Insert(list, e)
    local pos = #list + 1
    while pos > 1 and list[pos - 1].at > e.at do pos = pos - 1 end
    table.insert(list, pos, e)
end

-- One event from the game as we'd save it, or nil if we don't keep it or can't read it yet:
-- names may arrive from the server later, and a later read picks the event up then.
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

-- Not the rank: the game may show today's name for a rank even on an old event, and the saved
-- entry should keep the name it had.
local function EventKey(e)
    return e.kind .. "^" .. e.name .. "^" .. (e.by or "")
end

-- Takes the saved copy of an event out of `candidates` (saved events with the same key). The game
-- only gives an event's age, rounded down to the hour and only roughly in months and years, so the
-- same event comes out at a slightly different time on each read.
local function TakeSavedCopy(candidates, e, now)
    local slack = math.max(2 * 3600, (now - e.at) / 10)
    local best, bestGap
    for i, saved in ipairs(candidates) do
        local gap = math.abs(saved.at - e.at)
        if gap <= slack and (not bestGap or gap < bestGap) then best, bestGap = i, gap end
    end
    return best and table.remove(candidates, best)
end

-- Runs on the game's GUILD_EVENT_LOG_UPDATE, the answer to Request.
function GuildLog.Read()
    if not GuildLog.CanView() then return end
    local total = GetNumGuildEvents()
    if not KR.Readable(total) then return end

    local now = time()
    local events = {}
    for i = total, 1, -1 do -- the game lists the newest first
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

    -- Oldest first: new events are the newest, so the older ones claim the saved copies first
    -- and a new event can't be mistaken for an older one just like it.
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
