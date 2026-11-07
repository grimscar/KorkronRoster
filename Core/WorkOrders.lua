-- Kor'kron Roster: guild work orders. A member picks something a guildmate can craft and posts an
-- order; anyone else running the addon can claim it, and the requester or the crafter marks it
-- complete once the items have been traded or mailed.
--
-- KorkronRosterDB.guilds[guild].orders["Requester#created"] = {
--     id, requester, created, status, claimer, stamp, by, qty, prof, itemID, spellID, name, note }
-- status: "open" -> "claimed" -> "done", or "cancelled" from open or claimed. stamp and by are the
-- time (server clock) and the author of the last change.
--
-- Every copy keeps the newest change, and a finished order (done or cancelled) beats any open or
-- claimed copy, so all copies end up the same and an old copy can't bring a finished order back.
--
-- Guild addon messages (prefix KRROSTER), fields separated by "^":
--   W^requester^created^status^claimer^stamp^by^qty^prof^itemID^spellID^name^note
--                    a change, only accepted from `by` itself
--   WQ^hash          "I just logged in; this is a fingerprint of the orders I know"
--   WS^name          someone whose fingerprint differs starts re-sharing their orders for name
--   WL^...           one re-shared order (same fields as W)
--   WE^name          end of that re-share; name then sends whatever the re-share lacked
-- A re-shared order can't be checked against who really made the change, so a modified addon could
-- make orders up. That is acceptable for a guild tool (Kor'kron Loot's ledger has the same gap).
local _, KR = ...

local WorkOrders = {}
KR.WorkOrders = WorkOrders

local Comm, Recipes = KR.Comm, KR.Recipes

local DAY = 86400
local RECENT = 30 * DAY   -- orders changed this recently are re-shared; open or claimed ones older than this expire
local HISTORY = 180 * DAY -- finished orders stay in the Completed tab this long
WorkOrders.MAX_QTY = 99
WorkOrders.MAX_NOTE = 60  -- bytes: a whole order has to fit in one 255-byte message

local STATUSES = { open = true, claimed = true, done = true, cancelled = true }
local FINISHED = { done = true, cancelled = true }

local Now = GetServerTime or time

-- this guild's orders (and the guild table), or nil outside a guild
local function Book()
    local g = KR.DB:GetGuild()
    if not g then return nil end
    g.orders = g.orders or {}
    return g.orders, g
end

local function Keep(o, now)
    return o.stamp >= now - (FINISHED[o.status] and HISTORY or RECENT)
end

local function Shareable(o, now, g)
    return o.stamp >= now - RECENT and KR.DB:GetMember(o.requester, false, g) ~= nil
end

-- wire format ------------------------------------------------------------------------------

-- the first n bytes of s, without cutting a character in half
local function Truncate(s, n)
    if #s <= n then return s end
    while n > 0 and string.byte(s, n + 1) >= 128 and string.byte(s, n + 1) < 192 do n = n - 1 end
    return string.sub(s, 1, n)
end

-- a player's note: no field separators or chat escape codes
local function CleanNote(s)
    return strtrim((string.gsub(tostring(s or ""), "[%^|\r\n]", "")))
end

-- the note goes last and is shortened if the rest of the order leaves it too little room
local function Encode(cmd, o)
    local msg = table.concat({ cmd, o.requester, o.created, o.status, o.claimer or "", o.stamp, o.by,
        o.qty, o.prof, o.itemID or "", o.spellID or "", o.name, "" }, "^")
    return msg .. Truncate(o.note or "", 255 - #msg)
end

local function Decode(msg)
    local f = { strsplit("^", msg) }
    if #f < 13 then return nil end
    local o = {
        requester = KR.NameKey(f[2]), created = tonumber(f[3]), status = f[4], claimer = KR.NameKey(f[5]),
        stamp = tonumber(f[6]), by = KR.NameKey(f[7]), qty = tonumber(f[8]), prof = f[9],
        itemID = tonumber(f[10]), spellID = tonumber(f[11]), name = f[12], note = f[13],
    }
    if not (o.requester and o.created and STATUSES[o.status] and o.stamp and o.by and o.qty) then return nil end
    if o.qty < 1 or o.qty > WorkOrders.MAX_QTY or o.prof == "" or o.name == "" then return nil end
    o.id = o.requester .. "#" .. o.created
    return o
end

-- rules ---------------------------------------------------------------------------------------

-- does change a come after change b? Every client answers the same way.
local function Newer(a, b)
    local fa, fb = FINISHED[a.status] or false, FINISHED[b.status] or false
    if fa ~= fb then return fa end
    if a.stamp ~= b.stamp then return a.stamp > b.stamp end
    return a.by > b.by
end

local function IsOfficer(name)
    local m = KR.DB:GetMember(name)
    return m ~= nil and KR.Ranks.IsManagerIndex(m.guildRankIndex)
end

-- may o.by leave the order as o, given our copy before the change (old, or nil if we had none)?
local function Allowed(o, old)
    local by = o.by
    if o.status == "open" then
        -- a new order, or a claim given back by the crafter, the requester or an officer (someone
        -- who never saw the claim can't check who gave it back)
        return o.claimer == nil and (old == nil or old.claimer == nil or by == old.claimer
            or by == o.requester or IsOfficer(by))
    elseif o.status == "claimed" then
        return o.claimer == by and by ~= o.requester
    elseif o.status == "done" then
        return o.claimer ~= nil and (by == o.requester or by == o.claimer)
    end
    return by == o.requester or IsOfficer(by) -- cancelled
end

-- take an order heard from the guild; returns true (and the copy it replaced) if ours changed
local function Merge(o)
    local book, g = Book()
    if not book or not KR.DB:GetMember(o.requester, false, g) then return false end
    local now = Now()
    -- (a stamp far in the future would make the order impossible to change again)
    if o.stamp < o.created or o.stamp > now + 3600 or not Keep(o, now) then return false end
    local old = book[o.id]
    if old and not Newer(o, old) then return false end
    if not Allowed(o, old) then
        KR:Debug("Ignored a work order change by %s (not allowed).", o.by)
        return false
    end
    book[o.id] = o
    return true, old
end

-- chat notices ------------------------------------------------------------------------------

-- print text with the order's item linked in place of its one %s
local function Tell(o, text)
    KR.UI.GetRecipeLink(o, function(link)
        KR:Print(text, (link or o.name) .. (o.qty > 1 and (" x" .. o.qty) or ""))
    end)
end

-- one of your characters knows the recipe
local function CanCraft(o)
    local e = Recipes.Find(o.prof, o.name)
    if not e then return false end
    for _, name in ipairs(e.crafters) do
        if KR.DB:IsMyCharacter(name) then return true end
    end
    return false
end

-- for changes made by guildmates while you are online (not for re-shares when you log in)
local function Notify(o, old)
    local mine = KR.DB:IsMyCharacter(o.requester)
    if not old and o.status == "open" and not mine and CanCraft(o) then
        Tell(o, "New work order from " .. o.requester .. ": %s. You can craft it; type /kr orders to claim it.")
    elseif mine and o.status == "claimed" then
        Tell(o, o.claimer .. " claimed your work order for %s.")
    elseif mine and o.status == "done" then
        Tell(o, o.claimer .. " marked your work order for %s complete.")
    elseif o.status == "cancelled" and old and old.claimer and KR.DB:IsMyCharacter(old.claimer) then
        Tell(o, o.by .. " cancelled the work order for %s that you claimed.")
    end
end

-- live changes ----------------------------------------------------------------------------

Comm:RegisterHandler("W", function(name, msg)
    local o = Decode(msg)
    if not o or o.by ~= name then return end -- a change is only taken from the person who made it
    local changed, old = Merge(o)
    if not changed then return end
    Notify(o, old)
    KR:Fire("DATA_UPDATED")
end)

-- catching up after logging in --------------------------------------------------------------

local shareStarted = {} -- [name] = when we saw someone start re-sharing for name
local catchingUp        -- after our own WQ: [id] = true for orders the re-share had at least as new as ours

local function Digest()
    local book, g = Book()
    local parts, now = {}, Now()
    for id, o in pairs(book or {}) do
        if Shareable(o, now, g) then parts[#parts + 1] = id .. "=" .. o.stamp .. o.by end
    end
    table.sort(parts)
    return Recipes.Hash(table.concat(parts, ","))
end

local function Share(target)
    local book, g = Book()
    if not book then return end
    local now = Now()
    Comm:Send("WS^" .. target, "BULK")
    for _, o in pairs(book) do
        if Shareable(o, now, g) then Comm:Send(Encode("WL", o), "BULK") end
    end
    Comm:Send("WE^" .. target, "BULK")
end

-- after logging in (and on Sync Guild): drop expired orders and compare notes with the guild
function WorkOrders.Request()
    local book = Book()
    if not book then return end
    local now = Now()
    for id, o in pairs(book) do
        if not Keep(o, now) then book[id] = nil end
    end
    catchingUp = {}
    Comm:Send("WQ^" .. Digest(), "NORMAL")
end

Comm:RegisterHandler("WQ", function(name, msg)
    if select(2, strsplit("^", msg)) == Digest() then return end
    local asked = GetTime()
    -- wait a moment so only one of us answers; everyone else overhears the answer
    KR:Debounce("orderShare" .. name, 2 + math.random() * 6, function()
        if (shareStarted[name] or -1) >= asked then return end
        Share(name)
    end)
end)

Comm:RegisterHandler("WS", function(_, msg)
    local target = KR.NameKey(select(2, strsplit("^", msg)))
    if target then shareStarted[target] = GetTime() end
end)

Comm:RegisterHandler("WL", function(_, msg)
    local o = Decode(msg)
    if not o then return end
    if catchingUp then
        local book = Book()
        local mine = book and book[o.id]
        if not (mine and Newer(mine, o)) then catchingUp[o.id] = true end
    end
    if Merge(o) then KR:Fire("DATA_UPDATED") end
end)

Comm:RegisterHandler("WE", function(_, msg)
    if not catchingUp or not KR.IsMe(KR.NameKey(select(2, strsplit("^", msg)))) then return end
    local had = catchingUp
    catchingUp = nil
    local book, g = Book()
    if not book then return end
    local now = Now()
    for id, o in pairs(book) do
        if not had[id] and Shareable(o, now, g) then Comm:Send(Encode("WL", o), "BULK") end
    end
end)

-- your own changes --------------------------------------------------------------------------

local ACTIONS = {
    claim    = { from = { open = true }, status = "claimed", said = "You claimed the work order for %s." },
    release  = { from = { claimed = true }, status = "open", said = "The work order for %s is open again." },
    complete = { from = { claimed = true }, status = "done", said = "The work order for %s is complete." },
    cancel   = { from = { open = true, claimed = true }, status = "cancelled", said = "The work order for %s is cancelled." },
}

-- the order after you do action to it, or nil if that isn't possible or allowed
local function Changed(o, action)
    local a = ACTIONS[action]
    if not a.from[o.status] then return nil end
    local n = {}
    for k, v in pairs(o) do n[k] = v end
    n.status = a.status
    n.by = KR.PlayerName()
    n.stamp = math.max(Now(), o.stamp + 1) -- always after the change it replaces
    if action == "claim" then
        n.claimer = n.by
    elseif action == "release" then
        n.claimer = nil
    end
    return Allowed(n, o) and n or nil
end

-- our copy of the order now (a menu may have been opened before a newer change came in)
local function Current(o)
    local book = Book()
    return book and book[o.id] or o
end

local function Send(o)
    Book()[o.id] = o
    Comm:Send(Encode("W", o), "NORMAL")
    KR:Fire("DATA_UPDATED")
end

function WorkOrders.Can(o, action)
    return Changed(Current(o), action) ~= nil
end

function WorkOrders.Do(o, action)
    local n = Changed(Current(o), action)
    if not n then return false end
    Send(n)
    Tell(n, ACTIONS[action].said)
    return true
end

-- post an order for an entry of the guild's recipe index (Recipes.GetIndex); returns it or nil
function WorkOrders.Create(entry, qty, note)
    qty = tonumber(qty)
    if not Book() or not qty or qty < 1 or qty > WorkOrders.MAX_QTY or qty % 1 ~= 0 then return nil end
    if not KR.HasFullPlayerName() then
        KR:Print("Still loading the guild roster; try again in a moment.")
        return nil
    end
    local me, now, r = KR.PlayerName(), Now(), entry.recipe
    local o = {
        id = me .. "#" .. now, requester = me, created = now, status = "open", stamp = now, by = me,
        qty = qty, prof = entry.prof, itemID = r.itemID, spellID = r.spellID, name = r.name,
        note = Truncate(CleanNote(note), WorkOrders.MAX_NOTE),
    }
    Send(o)
    Tell(o, "Work order posted for %s. Guildmates running Kor'kron Roster can now claim it.")
    return o
end

-- orders to show: active ones (open and claimed), or finished ones (done; cancelled stay hidden)
function WorkOrders.List(finished)
    local out = {}
    local book, g = Book()
    if not book then return out end
    local now = Now()
    for _, o in pairs(book) do
        local wanted = (finished and o.status == "done") or (not finished and not FINISHED[o.status])
        if wanted and Keep(o, now) and KR.DB:GetMember(o.requester, false, g) then out[#out + 1] = o end
    end
    return out
end
