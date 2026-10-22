-- Kor'kron Roster: guild sync protocol.
--
-- All traffic goes over the GUILD addon channel, fields separated by "^":
--   P^proto^version^class^level^prof1^r^max^prof2^r^max^fishR^max^cookR^max^faR^max^pvpRank^todayHK^weekHK^weekHonor^lifetimeHK^dayKey^weekKey^main
--   Q^proto                         "everyone please send your profile"
--   M^prof^hash^count               "my recipe list for prof has this hash"
--   F^target^prof^hash              "target, please send that recipe list"
--   R^prof^hash^index^total^data    one chunk of a recipe list (see Recipes.lua)
-- Version 1.0 messages (REQ, SYNC) are still understood and answered.
local _, KR = ...

local Sync = {}
KR.Sync = Sync

local Comm, Recipes = KR.Comm, KR.Recipes
local Clean = Recipes.Clean

local PROFILE_COOLDOWN = 15  -- seconds between full answers to Q
local REQUEST_COOLDOWN = 30  -- seconds between our own Q broadcasts
local RECIPE_COOLDOWN = 30   -- seconds before resending the same recipe list
local BUFFER_TIMEOUT = 120   -- drop half-received recipe lists after this

local lastProfileMsg, lastProfileTime = nil, -999
local lastManifestSig
local lastRequest = -999
local notifiedVersion

local function Num(v)
    return tonumber(v) or 0
end

-- outgoing -----------------------------------------------------------------------

local function BuildProfile()
    local p = KR.DB:GetProfile()
    local v = p.pvp
    local f = { "P", KR.PROTOCOL, KR.version, p.class or "", p.level or 0 }
    for _, slot in ipairs({ "prof1", "prof2" }) do
        f[#f + 1] = Clean(p[slot].name)
        f[#f + 1] = p[slot].rank or 0
        f[#f + 1] = p[slot].max or 0
    end
    for _, slot in ipairs({ "fish", "cook", "fa" }) do
        f[#f + 1] = p[slot].rank or 0
        f[#f + 1] = p[slot].max or 0
    end
    f[#f + 1] = v.rankNum or 0
    f[#f + 1] = v.todayHK or 0
    f[#f + 1] = v.weekHK or 0
    f[#f + 1] = v.weekHonor or 0
    f[#f + 1] = v.lifetimeHK or 0
    f[#f + 1] = v.dayKey or ""
    f[#f + 1] = v.weekKey or ""
    f[#f + 1] = Clean(KR.DB:GetMain() or "")
    return table.concat(f, "^")
end

local function ManifestSignature(p)
    local parts = {}
    for prof, data in pairs(p.recipes) do parts[#parts + 1] = prof .. data.hash end
    table.sort(parts)
    return table.concat(parts)
end

function Sync:SendManifest()
    local p = KR.DB:GetProfile()
    for prof, data in pairs(p.recipes) do
        if data.hash and (data.count or 0) > 0 then
            Comm:Send(table.concat({ "M", Clean(prof), data.hash, data.count }, "^"), "NORMAL")
        end
    end
    lastManifestSig = ManifestSignature(p)
end

-- broadcast our profile; unchanged profiles are skipped unless forced
function Sync:SendProfile(force)
    if not KR.db or not IsInGuild() then return end
    KR.Professions:ScanSkills()
    KR.PvP:Scan()
    KR.DB:SyncSelf()

    local msg = BuildProfile()
    if force or msg ~= lastProfileMsg then
        lastProfileMsg, lastProfileTime = msg, GetTime()
        Comm:Send(msg, "NORMAL")
    end
    if force or ManifestSignature(KR.DB:GetProfile()) ~= lastManifestSig then
        self:SendManifest()
    end
end

-- coalesce bursts of changes (every honorable kill, every skill-up) into one broadcast
function Sync:ScheduleBroadcast()
    if not KR.db or not KR.db.settings.autoSync then return end
    KR:Throttle("broadcast", 20, function() Sync:SendProfile(false) end)
end

-- ask the guild for everyone's data; returns false while on cooldown
function Sync:RequestAll()
    if not IsInGuild() or GetTime() - lastRequest < REQUEST_COOLDOWN then return false end
    lastRequest = GetTime()
    Comm:Send("Q^" .. KR.PROTOCOL, "ALERT")
    Comm:Send("REQ", "ALERT") -- lets 1.0 users answer too
    self:SendProfile(true)
    return true
end

-- recipe transfer ------------------------------------------------------------------

-- split on record boundaries; never cut a UTF-8 character or end a chunk on a space
local function SplitPayload(s, size)
    local chunks, pos, len = {}, 1, #s
    while pos <= len do
        local stop = pos + size - 1
        if stop >= len then
            stop = len
        else
            local cut
            for i = stop, pos + math.floor(size / 2), -1 do
                if string.byte(s, i) == 126 then cut = i break end -- '~'
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

local lastRecipeSend = {}

function Sync:SendRecipes(prof)
    local data = KR.DB:GetProfile().recipes[prof]
    if not data or not data.list then return end
    local stamp = prof .. data.hash
    if GetTime() - (lastRecipeSend[stamp] or -999) < RECIPE_COOLDOWN then return end
    lastRecipeSend[stamp] = GetTime()

    local cleanProf = Clean(prof)
    local header = "R^" .. cleanProf .. "^" .. data.hash .. "^"
    local chunks = SplitPayload(Recipes.Serialize(data.list), 255 - #header - 10)
    for i, chunk in ipairs(chunks) do
        Comm:Send(header .. i .. "^" .. #chunks .. "^" .. chunk, "BULK")
    end
    KR:Debug("Sending %s recipes in %s messages.", prof, #chunks)
end

-- someone advertised a list we don't have: ask for it after a short random wait, so
-- that when many of us need it only one request goes out and everyone overhears the reply
local pendingFetch = {}

local function QueueFetch(name, prof, hash)
    local key = name .. "\001" .. prof
    if pendingFetch[key] == hash then return end
    pendingFetch[key] = hash
    KR:After(1 + math.random() * 4, function()
        if pendingFetch[key] ~= hash then return end
        pendingFetch[key] = nil
        local m = KR.DB:GetMember(name)
        local have = m and m.recipes[prof]
        if m and not (have and have.hash == hash) then
            Comm:Send(table.concat({ "F", name, prof, hash }, "^"), "NORMAL")
        end
    end)
end

-- incoming -------------------------------------------------------------------------

local function ApplyProfile(m, f)
    m.class = (f[4] ~= "" and f[4]) or m.class
    if Num(f[5]) > 0 then m.level = Num(f[5]) end
    m.prof1.name, m.prof1.rank, m.prof1.max = f[6] ~= "" and f[6] or "-", Num(f[7]), Num(f[8])
    m.prof2.name, m.prof2.rank, m.prof2.max = f[9] ~= "" and f[9] or "-", Num(f[10]), Num(f[11])
    m.fish.rank, m.fish.max = Num(f[12]), Num(f[13])
    m.cook.rank, m.cook.max = Num(f[14]), Num(f[15])
    m.fa.rank, m.fa.max = Num(f[16]), Num(f[17])
    local pvp = m.pvp
    pvp.rankNum, pvp.todayHK, pvp.weekHK = Num(f[18]), Num(f[19]), Num(f[20])
    pvp.weekHonor, pvp.lifetimeHK = Num(f[21]), Num(f[22])
    pvp.dayKey = (f[23] and f[23] ~= "") and f[23] or nil
    pvp.weekKey = (f[24] and f[24] ~= "") and f[24] or nil

    -- 2.1+: the main character this one belongs to ("" = none / is the main)
    if f[25] ~= nil then
        local main = KR.NameKey(f[25])
        m.main = (main and main ~= m.name) and main or nil
    end

    -- recipe lists for professions they no longer have
    local known = {}
    for _, slot in ipairs(KR.PROF_SLOTS) do
        if m[slot].rank > 0 then known[m[slot].name] = true end
    end
    for prof in pairs(m.recipes) do
        if not known[prof] then
            m.recipes[prof] = nil
            Recipes.InvalidateIndex()
        end
    end
end

Comm:RegisterHandler("P", function(name, msg, _, sender)
    local m = KR.DB:GetMember(name, true)
    if not m then return end
    m.whisperTarget = sender
    local f = { strsplit("^", msg) }
    if #f < 22 then return end
    m.protocol = Num(f[2])
    m.version = f[3]
    m.lastSync = time()
    ApplyProfile(m, f)

    if not notifiedVersion and KR.CompareVersions(m.version, KR.version) > 0 then
        notifiedVersion = m.version
        KR:Print("A newer version (|cffffd100%s|r) is in use by your guild. You have %s.", m.version, KR.version)
    end
    KR:Fire("DATA_UPDATED")
end)

Comm:RegisterHandler("Q", function(name, msg)
    local m = KR.DB:GetMember(name, true)
    if m then m.protocol = Num(select(2, strsplit("^", msg))) end
    if GetTime() - lastProfileTime < PROFILE_COOLDOWN then return end
    -- spread replies out so a login doesn't make the whole guild answer in the same frame
    KR:Debounce("answerQuery", 2 + math.random() * 6, function()
        if GetTime() - lastProfileTime >= PROFILE_COOLDOWN then Sync:SendProfile(true) end
    end)
end)

Comm:RegisterHandler("M", function(name, msg)
    local _, prof, hash, count = strsplit("^", msg)
    if not prof or prof == "" or not hash or Num(count) <= 0 then return end
    local m = KR.DB:GetMember(name, true)
    local have = m and m.recipes[prof]
    if m and not (have and have.hash == hash) then
        QueueFetch(name, prof, hash)
    end
end)

Comm:RegisterHandler("F", function(name, msg)
    local _, target, prof, hash = strsplit("^", msg)
    if not target or not prof then return end
    if KR.IsMe(KR.NameKey(target)) then
        KR:Debounce("sendRecipes" .. prof, 3, function() Sync:SendRecipes(prof) end)
    else
        -- someone else already asked; we'll overhear the answer
        local key = (KR.NameKey(target) or target) .. "\001" .. prof
        if pendingFetch[key] == hash then pendingFetch[key] = nil end
    end
end)

local buffers = {}

Comm:RegisterHandler("R", function(name, msg)
    local prof, hash, i, n, data = string.match(msg, "^R%^([^%^]*)%^(%x+)%^(%d+)%^(%d+)%^(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not prof or not i or not n or n < 1 or n > 500 or i < 1 or i > n then return end
    local m = KR.DB:GetMember(name, true)
    if not m then return end
    local key = name .. "\001" .. prof
    pendingFetch[key] = nil
    if m.recipes[prof] and m.recipes[prof].hash == hash then return end

    local now = GetTime()
    for k, b in pairs(buffers) do
        if now - b.time > BUFFER_TIMEOUT then buffers[k] = nil end
    end

    local buf = buffers[key]
    if not buf or buf.hash ~= hash or buf.total ~= n then
        buf = { hash = hash, total = n, got = 0, parts = {} }
        buffers[key] = buf
    end
    buf.time = now
    if not buf.parts[i] then
        buf.parts[i] = data
        buf.got = buf.got + 1
    end
    if buf.got < n then return end

    buffers[key] = nil
    if Recipes.StoreSerialized(m, prof, table.concat(buf.parts, "", 1, n), hash) then
        KR:Debug("Received %s's %s recipes (%s).", name, prof, m.recipes[prof].count)
        KR:Fire("DATA_UPDATED")
    else
        KR:Debug("Discarded %s's %s recipes: checksum mismatch.", name, prof)
    end
end)

-- version 1.0 compatibility ----------------------------------------------------------

local lastLegacyReply = -999

Comm:RegisterHandler("REQ", function(name)
    local m = KR.DB:GetMember(name)
    if m and Num(m.protocol) >= 2 then return end -- a current client; it also sent Q
    if GetTime() - lastLegacyReply < 60 then return end
    lastLegacyReply = GetTime()
    KR:After(1 + math.random() * 4, function()
        local p = KR.DB:GetProfile()
        local v = p.pvp
        local msg = table.concat({
            "SYNC", UnitName("player"), p.class or "WARRIOR",
            Clean(p.prof1.name), p.prof1.rank, p.prof1.max,
            Clean(p.prof2.name), p.prof2.rank, p.prof2.max,
            p.fish.rank, p.fish.max, p.cook.rank, p.cook.max, p.fa.rank, p.fa.max,
            v.rankNum or 0, KR.PvP.RankName(v.rankNum) or "None",
            v.todayHK or 0, v.weekHK or 0, v.weekHonor or 0, v.lifetimeHK or 0,
        }, "^")
        Comm:Send(msg, "NORMAL")
    end)
end)

Comm:RegisterHandler("SYNC", function(name, msg)
    local f = { strsplit("^", msg) }
    if #f < 15 then return end
    local m = KR.DB:GetMember(name, true) -- trust the sender, not the name inside the message
    if not m or Num(m.protocol) >= 2 then return end
    m.class = f[3] ~= "" and f[3] or m.class
    m.prof1.name, m.prof1.rank, m.prof1.max = f[4] ~= "" and f[4] or "-", Num(f[5]), Num(f[6])
    m.prof2.name, m.prof2.rank, m.prof2.max = f[7] ~= "" and f[7] or "-", Num(f[8]), Num(f[9])
    m.fish.rank, m.fish.max = Num(f[10]), Num(f[11])
    m.cook.rank, m.cook.max = Num(f[12]), Num(f[13])
    m.fa.rank, m.fa.max = Num(f[14]), Num(f[15])
    if f[16] then
        m.pvp.rankNum = Num(f[16])
        m.pvp.todayHK, m.pvp.weekHK = Num(f[18]), Num(f[19])
        m.pvp.weekHonor, m.pvp.lifetimeHK = Num(f[20]), Num(f[21])
    end
    m.version = m.version or "1.0"
    m.protocol = 1
    m.lastSync = time()
    KR:Fire("DATA_UPDATED")
end)
