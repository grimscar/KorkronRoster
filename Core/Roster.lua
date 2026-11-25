local _, KR = ...

local Roster = {}
KR.Roster = Roster

local lastRequest = -60

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
    local g = IsInGuild() and KR.DB:GetGuild()
    if not g then return end
    KR.DB:ImportLegacy()

    local total = GetNumGuildMembers() or 0
    if total == 0 then return end

    local now = time()
    local seen, listed, foundSelf = {}, 0, false
    local firstName, myClass = UnitName("player"), select(2, UnitClass("player"))
    local selfCandidates = {}
    local canViewOfficer = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote())
        or (CanViewOfficerNote and CanViewOfficerNote()) or false

    local function Read(value, old)
        if KR.Readable(value) then return value end
        return old
    end

    for i = 1, total do
        local fullName, rankName, rankIndex, level, _, zone, note, officerNote, online, _, classTag = GetGuildRosterInfo(i)
        local name = KR.NameKey(fullName)
        if name then
            listed = listed + 1
            seen[name] = true
            local m = KR.DB:GetMember(name, true, g)
            classTag, online = Read(classTag, m.class), Read(online, m.online)
            if KR.IsMe(name) then foundSelf = true end
            if online and classTag == myClass and KR.FirstName(name) == firstName then
                selfCandidates[#selfCandidates + 1] = name
            end

            m.class = classTag or m.class
            m.level = Read(level, m.level) or m.level
            m.online = online and true or false
            m.guildRank = Read(rankName, m.guildRank)
            m.guildRankIndex = Read(rankIndex, m.guildRankIndex)
            m.zone = Read(zone, m.zone)
            m.note = Read(note, m.note)
            m.officerNote = canViewOfficer and Read(officerNote, m.officerNote) or nil
            m.whisperTarget = fullName
            m.rosterName = fullName
            if online then
                m.lastOnline = now
            elseif GetGuildRosterLastOnline then
                local away = KR.ElapsedSeconds(GetGuildRosterLastOnline(i))
                if away then m.lastOnline = now - away end
            end
        end
    end

    if not foundSelf and #selfCandidates == 1 and KR.LearnPlayerName(selfCandidates[1]) then
        foundSelf = true
    end

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

function Roster:GetPlayers()
    local groups, list = {}, {}
    local g = KR.DB:GetGuild()
    if not g then return list, groups end
    for name, m in pairs(g.members) do
        local main = KR.DB:MainOf(m, g)
        local key = (main and KR.DB:GetMember(main, false, g)) and main or name
        local p = groups[key]
        if not p then
            p = { lead = KR.DB:GetMember(key, false, g), chars = {}, online = false, lastOnline = 0 }
            groups[key] = p
            list[#list + 1] = p
        end
        p.chars[#p.chars + 1] = m
        if m.online then
            p.online = true
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
