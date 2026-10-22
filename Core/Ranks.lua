-- Kor'kron Roster: Kor'kron titles on top of the in-game guild ranks, and rank changes.
--
-- Titles are addon-only: the in-game rank stays Officer/Veteran/..., and everyone running
-- the addon sees the title instead. Titles travel over the addon channel and are only
-- accepted from Officers and the Guild Master:
--   T^target^title^stamp            an officer set (or cleared, "") a member's title
--   L^name=title=stamp;...          an officer re-sharing every known title (answer to Q)
local _, KR = ...

local Ranks = {}
KR.Ranks = Ranks

local Comm = KR.Comm

local function Lower(s)
    return string.lower(s or "")
end

-- in-game ranks -------------------------------------------------------------------------

-- in-game rank index (0 = Guild Master) for a tier, matched by rank name
function Ranks.TierIndex(tier)
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 1, n do
        if Lower(GuildControlGetRankName(i)) == Lower(tier.rank) then return i - 1 end
    end
    return tier.index
end

function Ranks.RankName(index)
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    if index and index + 1 <= n then return GuildControlGetRankName(index + 1) end
    for _, tier in ipairs(KR.RANK_TIERS) do
        if tier.index == index then return tier.rank end
    end
end

function Ranks.TierFor(m)
    if not m then return nil end
    for _, tier in ipairs(KR.RANK_TIERS) do
        if m.guildRank and Lower(m.guildRank) == Lower(tier.rank) then return tier end
    end
    for _, tier in ipairs(KR.RANK_TIERS) do
        if m.guildRankIndex == Ranks.TierIndex(tier) then return tier end
    end
end

local function TitleInTier(tier, title)
    if not tier or not title then return nil end
    for _, t in ipairs(tier.titles) do
        if Lower(t) == Lower(title) then return t end
    end
end

-- what to display: their title if it fits their current in-game rank, the tier's only
-- title, or else the in-game rank name
function Ranks.Title(m)
    local tier = Ranks.TierFor(m)
    if tier then
        local title = TitleInTier(tier, m.title)
        if title then return title end
        if #tier.titles == 1 then return tier.titles[1] end
    end
    return m.guildRank
end

-- permissions ---------------------------------------------------------------------------

local function OfficerIndex()
    return Ranks.TierIndex(KR.RANK_TIERS[2])
end

function Ranks.MyIndex()
    local _, _, index = GetGuildInfo("player")
    return index
end

-- Officers and the Guild Master manage titles
function Ranks.IsManagerIndex(index)
    return index ~= nil and index <= OfficerIndex()
end

-- the game only lets you move people who rank below you
function Ranks.CanEdit(m)
    local mine = Ranks.MyIndex()
    return m ~= nil and not KR.IsMe(m.name) and Ranks.IsManagerIndex(mine)
        and m.guildRankIndex ~= nil and m.guildRankIndex > mine
end

-- every title you may hand out, grouped by tier (only tiers below your own rank)
function Ranks.Options(m)
    local mine = Ranks.MyIndex()
    local options = {}
    for _, tier in ipairs(KR.RANK_TIERS) do
        local index = Ranks.TierIndex(tier)
        if mine and index > mine then
            options[#options + 1] = { header = tier.rank .. " (in-game)" }
            for _, title in ipairs(tier.titles) do
                options[#options + 1] = {
                    label = title,
                    tier = tier,
                    title = title,
                    selected = m and Ranks.Title(m) == title and m.guildRankIndex == index,
                }
            end
        end
    end
    return options
end

-- applying a rank -----------------------------------------------------------------------

local function Broadcast(target, title, stamp)
    Comm:Send(table.concat({ "T", target, title or "", stamp }, "^"), "NORMAL")
end

local function StoreTitle(m, title, stamp, by)
    if (m.titleStamp or 0) > stamp then return false end
    m.title = (title and title ~= "") and title or nil
    m.titleStamp = stamp
    m.titleBy = by
    return true
end

function Ranks.SetTitle(m, title)
    local stamp = (GetServerTime and GetServerTime()) or time()
    StoreTitle(m, title, stamp, KR.PlayerName())
    Broadcast(m.name, title, stamp)
    KR:Print("%s is now |cffffd100%s|r (%s).", m.name, title, m.guildRank or "?")
    KR:Fire("DATA_UPDATED")
end

-- How to get a member to a tier's in-game rank. Addons may not call GuildPromote or
-- GuildDemote (the game blocks it and offers to disable the addon), so the change runs as
-- /gpromote or /gdemote macro lines on a secure button the officer clicks: see RankConfirm.
-- Returns the plan, or nil and a reason.
function Ranks.Plan(m, tier)
    if not Ranks.CanEdit(m) then
        return nil, "You can only change the rank of members below your own rank."
    end
    local goal = Ranks.TierIndex(tier)
    local steps = (m.guildRankIndex or goal) - goal -- positive = promotions
    if steps == 0 then return { steps = 0, goal = goal } end
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
        promote = promote,
        macro = table.concat(lines, "\n"),
    }
end

-- the officer clicked Confirm and the macro ran: record the new rank and title
function Ranks.Applied(m, tier, title, plan)
    m.guildRankIndex = plan.goal
    m.guildRank = Ranks.RankName(plan.goal) or tier.rank
    KR.Roster:Request()
    Ranks.SetTitle(m, title)
end

-- picked from the rank menu
function Ranks.Choose(m, tier, title)
    local plan, reason = Ranks.Plan(m, tier)
    if not plan then
        KR:Print(reason)
    elseif plan.steps == 0 then
        Ranks.SetTitle(m, title)
    else
        KR.UI.RankConfirm:Open(m, tier, title, plan)
    end
end

-- sync ------------------------------------------------------------------------------------

local function SenderIsManager(name)
    local s = KR.DB:GetMember(name)
    return s and Ranks.IsManagerIndex(s.guildRankIndex)
end

Comm:RegisterHandler("T", function(name, msg)
    local _, target, title, stamp = strsplit("^", msg)
    stamp = tonumber(stamp)
    local s, m = KR.DB:GetMember(name), KR.DB:GetMember(KR.NameKey(target))
    if not (s and m and stamp) then return end
    -- same rule as the game: officers and the GM, and only for members below them
    if not Ranks.IsManagerIndex(s.guildRankIndex) or (m.guildRankIndex or 99) <= s.guildRankIndex then
        KR:Debug("Ignored title for %s from %s (not allowed).", target, name)
        return
    end
    if StoreTitle(m, title, stamp, name) then KR:Fire("DATA_UPDATED") end
end)

local lastListSeen = -999

Comm:RegisterHandler("L", function(name, msg)
    lastListSeen = GetTime()
    if not SenderIsManager(name) then return end
    local changed = false
    for entry in string.gmatch(string.sub(msg, 3), "[^;]+") do
        local target, title, stamp = string.match(entry, "^(.-)=(.-)=(%d+)$")
        local m = target and KR.DB:GetMember(target)
        if m and StoreTitle(m, title, tonumber(stamp), name) then changed = true end
    end
    if changed then KR:Fire("DATA_UPDATED") end
end)

-- when someone logs in and asks for data, one online officer re-shares the titles
function Ranks.SendList()
    local entries = {}
    for name, m in KR.DB:IterateMembers() do
        if m.titleStamp then entries[#entries + 1] = name .. "=" .. (m.title or "") .. "=" .. m.titleStamp end
    end
    local msg = "L^"
    for _, e in ipairs(entries) do
        if #msg + #e + 1 > 250 then
            Comm:Send(msg, "BULK")
            msg = "L^"
        end
        msg = msg .. e .. ";"
    end
    if #msg > 2 then Comm:Send(msg, "BULK") end
end

Comm:RegisterHandler("Q", function()
    if not Ranks.IsManagerIndex(Ranks.MyIndex()) then return end
    local asked = GetTime()
    KR:Debounce("titleList", 3 + math.random() * 7, function()
        if lastListSeen > asked then return end -- another officer already answered
        Ranks.SendList()
    end)
end)

-- public API for other addons in the pack -------------------------------------------------
-- KorkronRoster:GetTitle("First Last")  -> "Quartermaster", in-game rank name, tier rank name
function KR:GetTitle(name)
    local m = KR.DB and KR.db and KR.DB:GetMember(KR.NameKey(name))
    if not m then return nil end
    local tier = Ranks.TierFor(m)
    return Ranks.Title(m), m.guildRank, tier and tier.rank
end
