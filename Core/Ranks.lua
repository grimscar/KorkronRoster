-- Kor'kron Roster: who counts as an officer, and changing a member's guild rank.
-- The ranks and their names come from the game.
local _, KR = ...

local Ranks = {}
KR.Ranks = Ranks

-- the guild's ranks, highest first: names[1] is the Guild Master, position 0 in GetGuildInfo
local function RankNames()
    local names = {}
    local count = GuildControlGetNumRanks()
    if KR.Readable(count) then
        for i = 1, count do names[i] = KR.Text(GuildControlGetRankName(i)) end
    end
    return names
end

-- permissions ---------------------------------------------------------------------------

local function OfficerIndex()
    local lowest = string.lower(KR.LOWEST_OFFICER_RANK)
    for i, name in ipairs(RankNames()) do
        if string.lower(name) == lowest then return i - 1 end
    end
    return 1 -- a guild without that rank (an alt's, say): the rank right below the Guild Master
end

function Ranks.MyIndex()
    local _, _, index = GetGuildInfo("player")
    return index
end

function Ranks.IsManagerIndex(index)
    return index ~= nil and index <= OfficerIndex()
end

-- the game only lets you move people who rank below you
function Ranks.CanEdit(m)
    local mine = Ranks.MyIndex()
    return m ~= nil and not KR.IsMe(m.name) and Ranks.IsManagerIndex(mine)
        and m.guildRankIndex ~= nil and m.guildRankIndex > mine
end

-- every rank you may move someone to: the ones below your own
function Ranks.Options(m)
    local names = RankNames()
    local options = {}
    for i = Ranks.MyIndex() + 2, #names do
        options[#options + 1] = { label = names[i], index = i - 1, selected = m.guildRankIndex == i - 1 }
    end
    return options
end

-- applying a rank -----------------------------------------------------------------------

-- How to get a member to a rank. Addons may not call GuildPromote or GuildDemote (the game
-- blocks it and offers to disable the addon), so the change runs as /gpromote or /gdemote
-- macro lines on a secure button the officer clicks: see RankConfirm.
-- Returns the plan, or nil and a reason.
function Ranks.Plan(m, goal)
    if not Ranks.CanEdit(m) then
        return nil, "You can only change the rank of members below your own rank."
    end
    local steps = m.guildRankIndex - goal -- positive = promotions
    local promote = steps > 0
    local allowed = promote and (CanGuildPromote and CanGuildPromote()) or (not promote and CanGuildDemote and CanGuildDemote())
    if not allowed then
        return nil, "Your guild rank is not allowed to " .. (promote and "promote" or "demote") .. " members."
    end
    local command = promote and (SLASH_GUILD_PROMOTE1 or "/gpromote") or (SLASH_GUILD_DEMOTE1 or "/gdemote")
    local lines = {}
    for i = 1, math.abs(steps) do
        lines[i] = command .. " " .. (m.rosterName or m.name)
    end
    return {
        steps = steps,
        goal = goal,
        goalName = RankNames()[goal + 1],
        promote = promote,
        macro = table.concat(lines, "\n"),
    }
end

-- the officer clicked Confirm and the macro ran: show the new rank until the roster says otherwise
function Ranks.Applied(m, plan)
    m.guildRankIndex = plan.goal
    m.guildRank = plan.goalName
    KR.Roster:Request()
    KR:Fire("DATA_UPDATED")
end

-- picked from the rank menu
function Ranks.Choose(m, goal)
    if goal == m.guildRankIndex then return end
    local plan, reason = Ranks.Plan(m, goal)
    if plan then
        KR.UI.RankConfirm:Open(m, plan)
    else
        KR:Print(reason)
    end
end
