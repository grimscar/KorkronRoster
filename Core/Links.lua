local _, KR = ...

local Links = {}
KR.Links = Links

local Comm, Recipes, Ranks = KR.Comm, KR.Recipes, KR.Ranks

local FUTURE = 3600
local Now = GetServerTime or time

local shareStarted = {}
local catchingUp

local function Book()
    local g = KR.DB:GetGuild()
    if not g then return nil end
    g.links = g.links or {}
    return g.links, g
end

local function Encode(cmd, char, link)
    return table.concat({ cmd, char, link.main, link.stamp, link.by }, "^")
end

local function Decode(msg)
    local _, char, main, stamp, by = strsplit("^", msg)
    char, by, stamp = KR.NameKey(char), KR.NameKey(by), tonumber(stamp)
    local mainKey = KR.NameKey(main)
    if not (char and by and stamp) or (main ~= "" and not mainKey) or mainKey == char then return nil end
    return char, { main = mainKey or "", stamp = stamp, by = by }
end

local function Newer(a, b)
    if a.stamp ~= b.stamp then return a.stamp > b.stamp end
    return a.by > b.by
end

local function Merge(char, link)
    local book = Book()
    if not book or link.stamp > Now() + FUTURE then return false end
    local old = book[char]
    if old and not Newer(link, old) then return false end
    book[char] = link
    return true
end

function Links.CanSet(m)
    return m ~= nil and not KR.DB:IsMyCharacter(m.name) and Ranks.AmOfficer()
end

function Links.Choices(m)
    local out = {}
    local g = KR.DB:GetGuild()
    for name, other in KR.DB:IterateMembers() do
        if name ~= m.name and not KR.DB:MainOf(other, g) then out[#out + 1] = other end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Links.Set(m, main)
    if not Links.CanSet(m) or main == m.name then return false end
    local book = Book()
    local old = book[m.name]
    local link = { main = main or "", by = KR.PlayerName(), stamp = math.max(Now(), old and old.stamp + 1 or 0) }
    book[m.name] = link
    Comm:Send(Encode("L", m.name, link), "NORMAL")
    KR:Fire("DATA_UPDATED")
    return true
end

local function Digest()
    local parts = {}
    for char, link in pairs(Book() or {}) do
        parts[#parts + 1] = char .. "=" .. link.main .. "@" .. link.stamp .. link.by
    end
    table.sort(parts)
    return Recipes.Hash(table.concat(parts, ","))
end

local function Share(target)
    local book = Book()
    if not book then return end
    Comm:Send("LS^" .. target, "BULK")
    for char, link in pairs(book) do Comm:Send(Encode("LL", char, link), "BULK") end
    Comm:Send("LE^" .. target, "BULK")
end

function Links.Request()
    if not Book() then return end
    catchingUp = {}
    Comm:Send("LQ^" .. Digest(), "NORMAL")
end

Comm:RegisterHandler("L", function(name, msg)
    local char, link = Decode(msg)
    if not char or link.by ~= name or not Ranks.IsOfficer(name) then return end
    if Merge(char, link) then KR:Fire("DATA_UPDATED") end
end)

Comm:RegisterHandler("LQ", function(name, msg)
    if not Ranks.AmOfficer() or select(2, strsplit("^", msg)) == Digest() then return end
    local asked = GetTime()
    KR:Debounce("linkShare" .. name, 2 + math.random() * 6, function()
        if (shareStarted[name] or -1) >= asked then return end
        Share(name)
    end)
end)

Comm:RegisterHandler("LS", function(name, msg)
    if not Ranks.IsOfficer(name) then return end
    local target = KR.NameKey(select(2, strsplit("^", msg)))
    if target then shareStarted[target] = GetTime() end
end)

Comm:RegisterHandler("LL", function(name, msg)
    local book = Book()
    if not book or not Ranks.IsOfficer(name) then return end
    local char, link = Decode(msg)
    if not char then return end
    if catchingUp and not (book[char] and Newer(book[char], link)) then catchingUp[char] = true end
    if Merge(char, link) then KR:Fire("DATA_UPDATED") end
end)

Comm:RegisterHandler("LE", function(_, msg)
    if not catchingUp or not KR.IsMe(KR.NameKey(select(2, strsplit("^", msg)))) then return end
    local had = catchingUp
    catchingUp = nil
    if not Ranks.AmOfficer() then return end
    for char, link in pairs(Book() or {}) do
        if not had[char] then Comm:Send(Encode("LL", char, link), "BULK") end
    end
end)
