-- Kor'kron Roster: honor and PvP rank tracking with daily and weekly baselines.
local _, KR = ...

local PvP = {}
KR.PvP = PvP

-- date keys for today and the start of the current PvP week ("YYYY-MM-DD")
function PvP.GetKeys()
    local resetDay = (KR.db and KR.db.settings.resetDay) or 3
    local now = (GetServerTime and GetServerTime()) or time()
    local d = date("*t", now)
    -- anchor on noon so daylight-saving shifts never move the date
    local noon = now - (d.hour * 3600 + d.min * 60 + d.sec) + 43200
    local daysSinceReset = (d.wday - resetDay) % 7
    return date("%Y-%m-%d", noon), date("%Y-%m-%d", noon - daysSinceReset * 86400)
end

local function Num(v)
    return tonumber(v) or 0
end

-- returns true if any shared stat changed
function PvP:Scan()
    if not KR.db then return false end
    local p = KR.DB:GetProfile()
    local pvp, track = p.pvp, p.pvpTrack
    local before = table.concat({ pvp.rankNum, pvp.todayHK, pvp.weekHK, pvp.weekHonor, pvp.lifetimeHK }, ":")
    local dayKey, weekKey = PvP.GetKeys()

    local lifetime, highestRank = 0, 0
    if GetPVPLifetimeStats then
        local hk, _, highest = GetPVPLifetimeStats()
        lifetime, highestRank = Num(hk), Num(highest)
    end
    lifetime = math.max(lifetime, Num(pvp.lifetimeHK))

    if track.dayKey ~= dayKey then
        track.dayKey, track.dayStartHK = dayKey, lifetime
    elseif not track.dayStartHK or track.dayStartHK > lifetime then
        track.dayStartHK = lifetime
    end
    if track.weekKey ~= weekKey then
        track.weekKey, track.weekStartHK, track.weekHonor = weekKey, lifetime, 0
    elseif not track.weekStartHK or track.weekStartHK > lifetime then
        track.weekStartHK = lifetime
    end

    -- the server's "this week" numbers exclude today, so today's session is added on top
    local sessionHK, sessionHonor, weekHK, weekHonor = 0, 0, 0, 0
    if GetPVPSessionStats then
        local a, b = GetPVPSessionStats()
        sessionHK, sessionHonor = Num(a), Num(b)
    end
    if GetPVPThisWeekStats then
        local a, b = GetPVPThisWeekStats()
        weekHK, weekHonor = Num(a), Num(b)
    end

    pvp.lifetimeHK = lifetime
    pvp.todayHK = math.max(sessionHK, lifetime - track.dayStartHK)
    pvp.weekHK = math.max(weekHK + sessionHK, lifetime - track.weekStartHK, pvp.todayHK)
    track.weekHonor = math.max(weekHonor + sessionHonor, Num(track.weekHonor))
    pvp.weekHonor = track.weekHonor
    pvp.dayKey, pvp.weekKey = dayKey, weekKey

    -- current rank; fall back to the highest rank held if the client reports none
    local rankNum = 0
    if GetPVPRankInfo then
        local rankID = UnitPVPRank and UnitPVPRank("player") or 0
        if (not rankID or rankID == 0) and highestRank > 0 then rankID = highestRank end
        if rankID and rankID > 0 then
            local _, number = GetPVPRankInfo(rankID)
            rankNum = math.max(0, Num(number))
        end
    end
    pvp.rankNum = rankNum

    return before ~= table.concat({ pvp.rankNum, pvp.todayHK, pvp.weekHK, pvp.weekHonor, pvp.lifetimeHK }, ":")
end

-- manual corrections from /kr settoday and /kr setweek
function PvP:SetToday(count)
    local p = KR.DB:GetProfile()
    self:Scan()
    p.pvpTrack.dayStartHK = math.max(0, p.pvp.lifetimeHK - count)
    if (p.pvpTrack.weekStartHK or 0) > p.pvpTrack.dayStartHK then
        p.pvpTrack.weekStartHK = p.pvpTrack.dayStartHK
    end
    self:Scan()
    return p.pvp.todayHK
end

function PvP:SetWeek(count)
    local p = KR.DB:GetProfile()
    self:Scan()
    p.pvpTrack.weekStartHK = math.max(0, p.pvp.lifetimeHK - count)
    self:Scan()
    return p.pvp.weekHK
end

-- a member's stats with stale daily/weekly numbers zeroed (they last synced before a reset)
function PvP.Current(pvp)
    local dayKey, weekKey = PvP.GetKeys()
    local today = (pvp.dayKey == nil or pvp.dayKey == dayKey) and Num(pvp.todayHK) or 0
    local fresh = pvp.weekKey == nil or pvp.weekKey == weekKey
    return {
        rankNum = Num(pvp.rankNum),
        todayHK = today,
        weekHK = fresh and Num(pvp.weekHK) or 0,
        weekHonor = fresh and Num(pvp.weekHonor) or 0,
        lifetimeHK = Num(pvp.lifetimeHK),
    }
end

function PvP.RankName(rankNum)
    if not rankNum or rankNum <= 0 then return nil end
    local faction = UnitFactionGroup("player")
    local names = KR.PVP_RANK_NAMES[faction] or KR.PVP_RANK_NAMES.Horde
    return names[rankNum] or ("Rank " .. rankNum)
end
