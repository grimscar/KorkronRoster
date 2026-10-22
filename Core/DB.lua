-- Kor'kron Roster: saved variables, schema migration and record accessors.
--
-- KorkronRosterDB layout (schema 2):
--   settings            user options
--   chars[Name-Realm]   your own characters (source of truth for what you broadcast)
--   guilds[Guild-Realm] .members[Name] = member record, one table per guild
local _, KR = ...

local DB = {}
KR.DB = DB

local SCHEMA = 3

local DEFAULT_SETTINGS = {
    debug = false,
    showOffline = true,
    tooltips = true,
    autoSync = true,
    resetDay = 3, -- weekday the PvP week starts (1 = Sunday ... 7 = Saturday)
    minimap = { hide = false, angle = 200 },
    tab = "ROSTER",
    mainsOnly = false,
    sort = {},
}

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function NewProfSlot(name)
    return { name = name or "-", rank = 0, max = 0 }
end

function DB.NewPvP()
    return { rankNum = 0, todayHK = 0, weekHK = 0, weekHonor = 0, lifetimeHK = 0 }
end

-- make sure every field the UI and sync code touch exists
local function Sanitize(rec)
    for _, slot in ipairs(KR.PROF_SLOTS) do
        if type(rec[slot]) ~= "table" then rec[slot] = NewProfSlot() end
        rec[slot].recipes = nil -- 1.0 kept recipes on the slot; they now live in rec.recipes
    end
    for slot, name in pairs({ fish = "Fishing", cook = "Cooking", fa = "First Aid" }) do
        if not rec[slot].name or rec[slot].name == "-" then rec[slot].name = name end
    end
    if type(rec.pvp) ~= "table" then rec.pvp = DB.NewPvP() end
    if type(rec.recipes) ~= "table" then rec.recipes = {} end
    rec.level = rec.level or 0
    return rec
end

local function NewMember(name)
    return Sanitize({ name = name, online = false })
end

-- 1.0 stored a flat db.members keyed "FirstName_CLASS"; park it until we know the guild
local function MigrateV1(db)
    if type(db.members) == "table" and next(db.members) then
        db.legacyMembers = db.members
    end
    db.members = nil
    db.settings = db.settings or {}
    if db.debug ~= nil then db.settings.debug = db.debug and true or false end
    db.debug = nil
end

-- 2.0.0 keyed members by whatever name the API returned, so Forever's two-part names
-- could appear as "First", "First Last" and "First-Last". Normalise every key and drop
-- first-name-only records that have a full-name twin.
local function MigrateV2(db)
    for _, g in pairs(db.guilds or {}) do
        local members = {}
        for key, m in pairs(g.members or {}) do
            local name = KR.NameKey(key)
            if name and (not members[name] or (m.lastSync or 0) > (members[name].lastSync or 0)) then
                m.name = name
                members[name] = m
            end
        end
        local firstNames = {}
        for name in pairs(members) do
            if string.find(name, " ", 1, true) then firstNames[KR.FirstName(name)] = true end
        end
        for name in pairs(members) do
            if not string.find(name, " ", 1, true) and firstNames[name] then members[name] = nil end
        end
        g.members = members
    end
end

function DB:Init()
    if type(KorkronRosterDB) ~= "table" then KorkronRosterDB = {} end
    local db = KorkronRosterDB
    if (db.schema or 1) < 2 then MigrateV1(db) end
    if (db.schema or 1) < 3 then MigrateV2(db) end
    db.schema = SCHEMA
    if type(db.settings) ~= "table" then db.settings = {} end
    ApplyDefaults(db.settings, DEFAULT_SETTINGS)
    db.chars = db.chars or {}
    db.guilds = db.guilds or {}
    db.mains = db.mains or {} -- [guildKey] = full name of the account's main in that guild
    KR.db = db
end

-- own character -------------------------------------------------------------

function DB:GetCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

function DB:GetProfile()
    local key = self:GetCharKey()
    local p = KR.db.chars[key]
    if not p then
        p = NewMember(UnitName("player"))
        KR.db.chars[key] = p
    end
    if not p.sanitized then
        Sanitize(p)
        p.sanitized = true
    end
    if type(p.pvpTrack) ~= "table" then p.pvpTrack = {} end
    return p
end

-- guild ----------------------------------------------------------------------

function DB:GetGuildKey()
    if not IsInGuild() then return nil end
    local gName, _, _, gRealm = GetGuildInfo("player")
    if not gName then return nil end
    return gName .. "-" .. (gRealm or GetRealmName() or "")
end

function DB:GetGuild()
    local key = self:GetGuildKey()
    if not key then return nil end
    local g = KR.db.guilds[key]
    if not g then
        g = { name = (GetGuildInfo("player")), members = {} }
        KR.db.guilds[key] = g
    end
    return g, key
end

function DB:GetMember(name, create)
    if not name then return nil end
    local g = self:GetGuild()
    if not g then return nil end
    local m = g.members[name]
    if not m and create then
        m = NewMember(name)
        g.members[name] = m
    elseif m and not m.sanitized then
        Sanitize(m)
        m.sanitized = true
    end
    return m
end

local EMPTY = {}
function DB:IterateMembers()
    local g = self:GetGuild()
    return pairs(g and g.members or EMPTY)
end

function DB:PruneMembers(seen)
    local g = self:GetGuild()
    if not g then return 0 end
    local removed = 0
    for name in pairs(g.members) do
        if not seen[name] then
            g.members[name] = nil
            removed = removed + 1
        end
    end
    return removed
end

function DB:WipeGuild()
    local _, key = self:GetGuild()
    if key then KR.db.guilds[key] = nil end
end

-- point your own guild entry at your character profile so the UI shows live data
function DB:SyncSelf()
    local myName = KR.PlayerName()
    local me = self:GetMember(myName, true)
    if not me then return end
    -- before we knew our full name we may have filed ourselves under the first name
    local firstName = UnitName("player")
    if firstName ~= myName and KR.HasFullPlayerName() then
        local g = self:GetGuild()
        if g.members[firstName] then
            g.members[firstName] = nil
            KR.Recipes.InvalidateIndex()
        end
    end
    me.name = myName
    me.main = self:GetMain()
    local p = self:GetProfile()
    local _, guildKey = self:GetGuild()
    p.guildKey = guildKey
    if KR.HasFullPlayerName() then p.fullName = myName end
    for _, slot in ipairs(KR.PROF_SLOTS) do
        me[slot] = p[slot]
    end
    me.pvp = p.pvp
    me.recipes = p.recipes
    me.class = p.class or me.class
    if (p.level or 0) > 0 then me.level = p.level end
    me.version = KR.version
    me.protocol = KR.PROTOCOL
    me.lastSync = time()
end

-- mains and alts ----------------------------------------------------------------------
-- One main per guild for the whole account (SavedVariables are account-wide). Each of
-- your characters announces it in its profile; guildmates only ever take a character's
-- main from that character itself, so nobody can claim someone else as their alt.

-- the main this character should announce, or nil if it is the main / none is set
function DB:GetMain()
    local _, key = self:GetGuild()
    local main = key and KR.db.mains[key]
    if main and main ~= KR.PlayerName() then return main end
    return nil
end

function DB:GetMainSetting()
    local _, key = self:GetGuild()
    return key and KR.db.mains[key] or nil
end

function DB:SetMain(name)
    local _, key = self:GetGuild()
    if not key then return end
    KR.db.mains[key] = name
    -- our other characters only announce it when they next log in; mark them locally now
    for _, p in ipairs(self:GetMyCharacters()) do
        local m = self:GetMember(p.fullName)
        if m then m.main = (name and name ~= p.fullName) and name or nil end
    end
end

-- your characters (from this account) last seen in the current guild, sorted by name
function DB:GetMyCharacters()
    local _, key = self:GetGuild()
    local out = {}
    if not key then return out end
    for _, p in pairs(KR.db.chars) do
        if p.guildKey == key and p.fullName and self:GetMember(p.fullName) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.fullName < b.fullName end)
    return out
end

function DB:IsMyCharacter(name)
    for _, p in ipairs(self:GetMyCharacters()) do
        if p.fullName == name then return true end
    end
    return KR.IsMe(name)
end

function DB:GetAlts(mainName)
    local alts = {}
    for name, m in self:IterateMembers() do
        if m.main == mainName and name ~= mainName then alts[#alts + 1] = m end
    end
    table.sort(alts, function(a, b) return a.name < b.name end)
    return alts
end

-- copy 1.0 data into the current guild (and your own profile) once
function DB:ImportLegacy()
    local legacy = KR.db.legacyMembers
    if not legacy or not self:GetGuild() then return end
    local firstName, myClass = UnitName("player"), select(2, UnitClass("player"))

    for _, old in pairs(legacy) do
        local name = type(old) == "table" and KR.NameKey(old.displayName or old.name)
        if name then
            local isMe = KR.IsMe(name) or (KR.FirstName(name) == firstName and old.classTag == myClass)
            local target = isMe and self:GetProfile() or self:GetMember(name, true)
            target.class = target.class or old.classTag
            if (target.level or 0) == 0 then target.level = tonumber(old.level) or 0 end

            for _, slot in ipairs(KR.PROF_SLOTS) do
                local o = old[slot]
                if type(o) == "table" and o.name and o.name ~= "-" then
                    if (target[slot].rank or 0) == 0 then
                        target[slot].name = (slot == "prof1" or slot == "prof2") and o.name or target[slot].name
                        target[slot].rank = tonumber(o.rank) or 0
                        target[slot].max = tonumber(o.max) or 0
                    end
                    if type(o.recipes) == "table" and #o.recipes > 0 and not target.recipes[o.name] then
                        KR.Recipes.Store(target, o.name, o.recipes)
                    end
                end
            end

            if type(old.pvp) == "table" then
                for _, field in ipairs({ "rankNum", "todayHK", "weekHK", "weekHonor", "lifetimeHK" }) do
                    target.pvp[field] = math.max(tonumber(target.pvp[field]) or 0, tonumber(old.pvp[field]) or 0)
                end
                if isMe then
                    local t = target.pvpTrack
                    t.dayKey, t.dayStartHK = old.pvp.dayKey, old.pvp.dayStartHK
                    t.weekKey, t.weekStartHK = old.pvp.weekKey, old.pvp.weekStartHK
                end
            end
        end
    end

    KR.db.legacyMembers = nil
    KR:Debug("Imported data from version 1.0.")
end
