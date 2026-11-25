local _, KR = ...

local RaidPlans = {}
KR.RaidPlans = RaidPlans

local Comm, Recipes = KR.Comm, KR.Recipes

RaidPlans.ROLES = {
    { key = "tank", code = "t", label = "Tank" },
    { key = "offtank", code = "o", label = "Off Tank" },
    { key = "melee", code = "m", label = "Melee DPS" },
    { key = "ranged", code = "r", label = "Ranged DPS" },
    { key = "healer", code = "h", label = "Healer" },
}
RaidPlans.SIZES = { 10, 20, 40 }
RaidPlans.MAX_NAME = 40

local BY_KEY, BY_CODE = {}, {}
for _, r in ipairs(RaidPlans.ROLES) do BY_KEY[r.key], BY_CODE[r.code] = r, r end
local SIZE_OK = { [10] = true, [20] = true, [40] = true }

local CHUNK = 200
local MAX_PARTS = 100
local SEND_DELAY = 3
local FETCH_WAIT = 6
local BUFFER_TIMEOUT = 120
local FUTURE = 3600
local Now = GetServerTime or time

local dirty, buffers, pendingFetch = {}, {}, {}

local function Book()
    local key = KR.DB:GetGuildKey()
    if not key then return nil end
    local all = KR.db.raidPlans
    all[key] = all[key] or { stamp = 0, plans = {} }
    return all[key]
end

function RaidPlans.CanEdit()
    return KR.Ranks.MyIndex() == 0
end

local function FromGuildMaster(name)
    local m = KR.DB:GetMember(name)
    return m ~= nil and m.guildRankIndex == 0
end

function RaidPlans.GuildMaster()
    for name, m in KR.DB:IterateMembers() do
        if m.guildRankIndex == 0 then return name end
    end
end

function RaidPlans.List()
    local out = {}
    local book = Book()
    for _, p in pairs(book and book.plans or {}) do out[#out + 1] = p end
    table.sort(out, function(a, b)
        local la, lb = string.lower(a.name), string.lower(b.name)
        if la ~= lb then return la < lb end
        return a.id < b.id
    end)
    return out
end

function RaidPlans.Get(id)
    local book = Book()
    return book and id and book.plans[id] or nil
end

local function CleanName(s)
    return strtrim((string.gsub(tostring(s or ""), "[%^~|,=\r\n]", "")))
end

local function Manifest(book)
    local parts = {}
    for id, p in pairs(book.plans) do parts[#parts + 1] = id .. "=" .. p.stamp end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function Encode(plan)
    local parts = {}
    for i, s in ipairs(plan.spots) do parts[i] = s.name .. "=" .. BY_KEY[s.role].code .. (s.bench and "b" or "") end
    return plan.name .. "~" .. plan.size .. "~" .. table.concat(parts, ",")
end

local function Decode(id, stamp, text)
    local name, size, list = string.match(text, "^([^~]*)~(%d+)~(.*)$")
    size = tonumber(size)
    if not name or not SIZE_OK[size] then return nil end
    local plan = { id = id, name = name, size = size, stamp = stamp, spots = {} }
    for entry in string.gmatch(list, "[^,]+") do
        local who, code, bench = string.match(entry, "^(.+)=(%l)(b?)$")
        local role = BY_CODE[code]
        who = KR.NameKey(who)
        if not (who and role) then return nil end
        plan.spots[#plan.spots + 1] = { name = who, role = role.key, bench = bench == "b" }
    end
    return plan
end

local function SendDoc(kind, key, stamp, text)
    local header = table.concat({ "RD", kind, key, stamp }, "^") .. "^"
    local chunks = Comm.Split(text, CHUNK)
    if #chunks == 0 then chunks = { "" } end
    for i, chunk in ipairs(chunks) do
        Comm:Send(header .. i .. "^" .. #chunks .. "^" .. chunk, "BULK")
    end
end

local function SendManifest()
    local book = Book()
    if book then SendDoc("M", "-", book.stamp, Manifest(book)) end
end

local function SendPlan(id)
    local plan = RaidPlans.Get(id)
    if plan then SendDoc("P", id, plan.stamp, Encode(plan)) end
end

local function SendChanges()
    if not RaidPlans.CanEdit() then return end
    SendManifest()
    for id in pairs(dirty) do SendPlan(id) end
    wipe(dirty)
end

local function Changed(plan)
    local book = Book()
    local now = Now()
    if plan then
        plan.stamp = math.max(now, plan.stamp + 1)
        dirty[plan.id] = true
    end
    book.stamp = math.max(now, book.stamp + 1)
    KR:Debounce("raidSend", SEND_DELAY, SendChanges)
    KR:Fire("DATA_UPDATED")
end

local function NewId(book)
    local id = Now()
    while book.plans[tostring(id)] do id = id + 1 end
    return tostring(id)
end

function RaidPlans.Create(name, size, spots)
    local book = Book()
    if not book or not RaidPlans.CanEdit() then return nil end
    name = CleanName(name)
    local plan = { id = NewId(book), name = name ~= "" and name or "Raid plan", size = SIZE_OK[size] and size or 40,
        stamp = 0, spots = spots or {} }
    book.plans[plan.id] = plan
    Changed(plan)
    return plan
end

function RaidPlans.Copy(plan)
    local spots = {}
    for i, s in ipairs(plan.spots) do spots[i] = { name = s.name, role = s.role, bench = s.bench } end
    return RaidPlans.Create(plan.name .. " (copy)", plan.size, spots)
end

function RaidPlans.Rename(plan, name)
    name = CleanName(name)
    if not RaidPlans.CanEdit() or name == "" or name == plan.name then return false end
    plan.name = name
    Changed(plan)
    return true
end

function RaidPlans.Delete(plan)
    local book = Book()
    if not book or not RaidPlans.CanEdit() or book.plans[plan.id] ~= plan then return false end
    book.plans[plan.id] = nil
    dirty[plan.id] = nil
    Changed(nil)
    return true
end

function RaidPlans.SetSize(plan, size)
    if not RaidPlans.CanEdit() or not SIZE_OK[size] or plan.size == size then return false end
    plan.size = size
    Changed(plan)
    return true
end

local function IndexOf(plan, name)
    for i, s in ipairs(plan.spots) do
        if s.name == name then return i end
    end
end

function RaidPlans.Spot(plan, name)
    local i = IndexOf(plan, name)
    return i and plan.spots[i] or nil
end

function RaidPlans.Place(plan, name, role, bench, before)
    if not RaidPlans.CanEdit() or not BY_KEY[role] or before == name then return false end
    local i = IndexOf(plan, name)
    if i then table.remove(plan.spots, i) end
    local at = before and IndexOf(plan, before) or #plan.spots + 1
    table.insert(plan.spots, at, { name = name, role = role, bench = bench and true or false })
    Changed(plan)
    return true
end

function RaidPlans.Remove(plan, name)
    local i = IndexOf(plan, name)
    if not RaidPlans.CanEdit() or not i then return false end
    table.remove(plan.spots, i)
    Changed(plan)
    return true
end

function RaidPlans.Column(plan, role, bench)
    local out = {}
    for _, s in ipairs(plan.spots) do
        if s.role == role and s.bench == bench then out[#out + 1] = s.name end
    end
    return out
end

function RaidPlans.Counts(plan)
    local raid, bench = 0, 0
    for _, s in ipairs(plan.spots) do
        if s.bench then bench = bench + 1 else raid = raid + 1 end
    end
    return raid, bench
end

function RaidPlans.Clashes(plan)
    local g = KR.DB:GetGuild()
    local first, clash = {}, {}
    for _, s in ipairs(plan.spots) do
        if not s.bench then
            local m = KR.DB:GetMember(s.name, false, g)
            local player = (m and KR.DB:MainOf(m, g)) or s.name
            local other = first[player]
            if other then
                clash[s.name] = other
                clash[other] = clash[other] or s.name
            else
                first[player] = s.name
            end
        end
    end
    return clash
end

local function Digest(book)
    return Recipes.Hash(Manifest(book))
end

function RaidPlans.Request()
    local book = Book()
    if not book or RaidPlans.CanEdit() then return end
    Comm:Send("RQ^" .. Digest(book), "NORMAL")
end

local function QueueFetch(id, stamp)
    pendingFetch[id] = stamp
    KR:After(FETCH_WAIT + math.random() * 4, function()
        if pendingFetch[id] ~= stamp then return end
        local plan = RaidPlans.Get(id)
        if plan and plan.stamp >= stamp then
            pendingFetch[id] = nil
        elseif buffers["P" .. id] then
            QueueFetch(id, stamp)
        else
            pendingFetch[id] = nil
            Comm:Send("RF^" .. id, "NORMAL")
        end
    end)
end

local function ApplyManifest(book, stamp, text)
    if stamp < book.stamp then return end
    local listed = {}
    for id, s in string.gmatch(text, "(%d+)=(%d+)") do listed[id] = tonumber(s) end
    local removed = false
    for id in pairs(book.plans) do
        if not listed[id] then
            book.plans[id] = nil
            removed = true
        end
    end
    for id, s in pairs(listed) do
        local p = book.plans[id]
        if not p or p.stamp < s then QueueFetch(id, s) end
    end
    book.stamp = stamp
    if removed then KR:Fire("DATA_UPDATED") end
end

local function ApplyPlan(book, id, stamp, text)
    local old = book.plans[id]
    if old and old.stamp >= stamp then return end
    local plan = Decode(id, stamp, text)
    if not plan then return end
    book.plans[id] = plan
    if pendingFetch[id] and pendingFetch[id] <= stamp then pendingFetch[id] = nil end
    KR:Fire("DATA_UPDATED")
end

Comm:RegisterHandler("RD", function(name, msg)
    if not FromGuildMaster(name) then return end
    local kind, key, stamp, i, n, data = string.match(msg, "^RD%^([MP])%^([%d%-]+)%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    stamp, i, n = tonumber(stamp), tonumber(i), tonumber(n)
    if not kind or n < 1 or n > MAX_PARTS or i < 1 or i > n or stamp > Now() + FUTURE then return end
    local book = Book()
    if not book then return end
    local now = GetTime()
    for k, b in pairs(buffers) do
        if now - b.time > BUFFER_TIMEOUT then buffers[k] = nil end
    end
    local bkey = kind .. key
    local buf = buffers[bkey]
    if not buf or buf.stamp ~= stamp or buf.total ~= n then
        buf = { stamp = stamp, total = n, got = 0, parts = {} }
        buffers[bkey] = buf
    end
    buf.time = now
    if not buf.parts[i] then
        buf.parts[i] = data
        buf.got = buf.got + 1
    end
    if buf.got < n then return end
    buffers[bkey] = nil
    local text = table.concat(buf.parts, "", 1, n)
    if kind == "M" then
        ApplyManifest(book, stamp, text)
    else
        ApplyPlan(book, key, stamp, text)
    end
end)

Comm:RegisterHandler("RQ", function(_, msg)
    local book = Book()
    if not book or not RaidPlans.CanEdit() or select(2, strsplit("^", msg)) == Digest(book) then return end
    KR:Debounce("raidManifest", 2 + math.random() * 4, SendManifest)
end)

Comm:RegisterHandler("RF", function(_, msg)
    local id = select(2, strsplit("^", msg))
    if not id then return end
    pendingFetch[id] = nil
    if RaidPlans.CanEdit() and RaidPlans.Get(id) then
        KR:Debounce("raidPlan" .. id, 2 + math.random() * 3, function() SendPlan(id) end)
    end
end)
