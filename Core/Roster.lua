-- Kor'kron Roster: guild roster scanning and pruning of departed members.
local _, KR = ...

local Roster = {}
KR.Roster = Roster

local lastRequest = -60

-- ask the server for a fresh roster; it throttles this itself, so we do too
function Roster:Request()
    if not IsInGuild() or GetTime() - lastRequest < 10 then return end
    lastRequest = GetTime()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function Roster:Scan()
    if not IsInGuild() or not KR.DB:GetGuild() then return end
    KR.DB:ImportLegacy()

    local total = GetNumGuildMembers() or 0
    if total == 0 then return end

    local now = time()
    local seen, listed, foundSelf = {}, 0, false
    local firstName, myClass = UnitName("player"), select(2, UnitClass("player"))
    local selfCandidates = {}
    local canViewOfficer = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote())
        or (CanViewOfficerNote and CanViewOfficerNote()) or false

    for i = 1, total do
        local fullName, rankName, rankIndex, level, _, zone, note, officerNote, online, _, classTag = GetGuildRosterInfo(i)
        local name = KR.NameKey(fullName)
        if name then
            listed = listed + 1
            seen[name] = true
            if KR.IsMe(name) then foundSelf = true end
            if online and classTag == myClass and KR.FirstName(name) == firstName then
                selfCandidates[#selfCandidates + 1] = name
            end

            local m = KR.DB:GetMember(name, true)
            m.class = classTag or m.class
            m.level = level or m.level
            m.online = online and true or false
            m.guildRank = rankName
            m.guildRankIndex = rankIndex
            m.zone = zone
            m.note = note
            m.officerNote = canViewOfficer and officerNote or nil
            m.whisperTarget = fullName
            m.rosterName = fullName -- exact roster spelling, used for /gpromote and /gdemote
            if online then
                m.lastOnline = now
            elseif GetGuildRosterLastOnline then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                if years then
                    m.lastOnline = now - ((((years * 365) + (months * 30) + days) * 24) + hours) * 3600
                end
            end
        end
    end

    -- the client only told us our first name; the roster has the full one
    if not foundSelf and #selfCandidates == 1 and KR.LearnPlayerName(selfCandidates[1]) then
        foundSelf = true
    end

    -- only prune when we are sure we saw the complete roster
    local showsOffline = not GetGuildRosterShowOffline or GetGuildRosterShowOffline()
    if foundSelf and showsOffline and listed == total then
        local removed = KR.DB:PruneMembers(seen)
        if removed > 0 then
            KR.Recipes.InvalidateIndex()
            KR:Debug("Removed %s member(s) no longer in the guild.", removed)
        end
    end

    KR.DB:SyncSelf()
    KR:Fire("DATA_UPDATED")
end

-- members grouped into players: a main plus every character that names it as main.
-- Alts whose main is not in the guild stand on their own.
-- Each player: { lead = member, chars = { members }, online, onlineChar, lastOnline }
function Roster:GetPlayers()
    local groups, list = {}, {}
    for name, m in KR.DB:IterateMembers() do
        local key = (m.main and KR.DB:GetMember(m.main)) and m.main or name
        local p = groups[key]
        if not p then
            p = { lead = KR.DB:GetMember(key), chars = {}, online = false, lastOnline = 0 }
            groups[key] = p
            list[#list + 1] = p
        end
        p.chars[#p.chars + 1] = m
        if m.online then
            p.online = true
            -- prefer reporting the main when both are somehow online
            if not p.onlineChar or name == key then p.onlineChar = m end
        end
        p.lastOnline = math.max(p.lastOnline, m.lastOnline or 0)
    end
    return list, groups
end

function Roster:Counts()
    local total, online, withAddon = 0, 0, 0
    for _, m in KR.DB:IterateMembers() do
        total = total + 1
        if m.online then online = online + 1 end
        if m.version then withAddon = withAddon + 1 end
    end
    local players = self:GetPlayers()
    return total, online, withAddon, #players
end
