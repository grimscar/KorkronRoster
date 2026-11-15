local _, KR = ...

local WorkOrders = {}
KR.WorkOrders = WorkOrders

local Comm, Recipes = KR.Comm, KR.Recipes

local DAY = 86400
local RECENT = 30 * DAY
local HISTORY = 180 * DAY
local CONFIRM_WAIT = 7 * DAY
WorkOrders.MAX_QTY = 99
WorkOrders.MAX_NOTE = 60

local STATUSES = { open = true, claimed = true, sent = true, done = true, cancelled = true }
local FINISHED = { done = true, cancelled = true }
local MATS = { requester = true, crafter = true }

local STEPS = { p = "open", c = "claimed", m = "claimed", g = "claimed", s = "sent", d = "done", r = "open", x = "cancelled" }
local STEP_ORDER = { p = 1, c = 2, m = 3, g = 4, s = 5, d = 6, r = 7, x = 8 }
local HANDOVER = { m = true, g = true, s = true, d = true }
local HOWS = { t = true, m = true, h = true }

local Now = GetServerTime or time

local function Book()
    local g = KR.DB:GetGuild()
    if not g then return nil end
    g.orders = g.orders or {}
    return g.orders, g
end

local function Finished(o, now)
    return FINISHED[o.status] or (o.status == "sent" and o.stamp < now - CONFIRM_WAIT)
end

function WorkOrders.IsFinished(o)
    return Finished(o, Now())
end

local function Keep(o, now)
    return o.stamp >= now - (Finished(o, now) and HISTORY or RECENT)
end

local function Shareable(o, now, g)
    return o.stamp >= now - RECENT and KR.DB:GetMember(o.requester, false, g) ~= nil
end

local function Truncate(s, n)
    if #s <= n then return s end
    while n > 0 and string.byte(s, n + 1) >= 128 and string.byte(s, n + 1) < 192 do n = n - 1 end
    return string.sub(s, 1, n)
end

local function CleanNote(s)
    return strtrim((string.gsub(tostring(s or ""), "[%^|\r\n]", "")))
end

local function Encode(cmd, o)
    local msg = table.concat({ cmd, o.requester, o.created, o.status, o.claimer or "", o.stamp, o.by,
        o.qty, o.prof, o.itemID or "", o.spellID or "", o.name, "" }, "^")
    local tail = "^" .. (o.mats or "") .. "^" .. (o.step or "") .. (o.how or "")
    return msg .. Truncate(o.note or "", 255 - #msg - #tail) .. tail
end

local function ParseStep(s)
    local step, how = string.match(s or "", "^(%l)(%l?)$")
    if not STEPS[step] then return nil end
    return step, HOWS[how] and how or ""
end

local function StepOf(o)
    if o.status == "open" then return o.stamp == o.created and "p" or "r" end
    return ({ claimed = "c", sent = "s", done = "d", cancelled = "x" })[o.status]
end

local function Decode(msg)
    local f = { strsplit("^", msg) }
    if #f < 13 then return nil end
    local o = {
        requester = KR.NameKey(f[2]), created = tonumber(f[3]), status = f[4], claimer = KR.NameKey(f[5]),
        stamp = tonumber(f[6]), by = KR.NameKey(f[7]), qty = tonumber(f[8]), prof = f[9],
        itemID = tonumber(f[10]), spellID = tonumber(f[11]), name = f[12], note = f[13],
        mats = MATS[f[14]] and f[14] or nil,
    }
    if not (o.requester and o.created and STATUSES[o.status] and o.stamp and o.by and o.qty) then return nil end
    if o.qty < 1 or o.qty > WorkOrders.MAX_QTY or o.prof == "" or o.name == "" then return nil end
    o.id = o.requester .. "#" .. o.created
    o.step, o.how = ParseStep(f[15])
    if STEPS[o.step] ~= o.status then o.step, o.how = StepOf(o), "" end
    return o
end

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

local function Allowed(o, old)
    local by = o.by
    if o.status == "open" then
        return o.claimer == nil and (old == nil or old.claimer == nil or by == old.claimer
            or by == o.requester or IsOfficer(by))
    elseif o.status == "claimed" then
        if o.step == "m" then
            return by == o.requester and o.claimer ~= nil and (old == nil or old.claimer == o.claimer)
        end
        return o.claimer == by and by ~= o.requester
    elseif o.status == "sent" then
        return o.claimer ~= nil and by == o.claimer
    elseif o.status == "done" then
        return o.claimer ~= nil and (by == o.requester or by == o.claimer)
    end
    return by == o.requester or IsOfficer(by)
end

local function Record(o, change)
    o.log = o.log or {}
    for _, e in ipairs(o.log) do
        if e.at == change.stamp and e.by == change.by and e.step == change.step then return false end
    end
    table.insert(o.log, { at = change.stamp, by = change.by, step = change.step, how = change.how })
    table.sort(o.log, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return STEP_ORDER[a.step] < STEP_ORDER[b.step]
    end)
    return true
end

function WorkOrders.MatsSteps(o)
    local found = {}
    for _, e in ipairs(o.log or {}) do
        if e.step == "c" or e.step == "r" then
            found = {}
        elseif e.step == "m" or e.step == "g" then
            found[e.step] = e
        end
    end
    return found
end

local function Merge(o)
    local book, g = Book()
    if not book or not KR.DB:GetMember(o.requester, false, g) then return false end
    local now = Now()
    if o.stamp < o.created or o.stamp > now + 3600 or not Keep(o, now) then return false end
    local old = book[o.id]
    local newer = not old or Newer(o, old)
    if not Allowed(o, old) then
        if newer then KR:Debug("Ignored a work order change by %s (not allowed).", o.by) end
        return false
    end
    if not newer then
        if HANDOVER[o.step] and Record(old, o) then KR:Fire("DATA_UPDATED") end
        return false
    end
    o.mats = (old and old.mats) or o.mats
    o.log = { unpack(old and old.log or {}) }
    o.handed = old and old.handed
    Record(o, o)
    book[o.id] = o
    return true, old
end

function WorkOrders.ItemText(o, link)
    return (link or o.name) .. (o.qty > 1 and (" x" .. o.qty) or "")
end

local function Tell(o, text)
    KR.UI.GetRecipeLink(o, function(link)
        KR:Print(text, WorkOrders.ItemText(o, link))
    end)
end

local function PlayerLink(name)
    local m = KR.DB:GetMember(name)
    return "|Hplayer:" .. (m and m.whisperTarget or name) .. "|h[" .. name .. "]|h"
end

local function CanCraft(o)
    local e = Recipes.Find(o.prof, o.name)
    if not e then return false end
    for _, name in ipairs(e.crafters) do
        if KR.DB:IsMyCharacter(name) then return true end
    end
    return false
end

local function TellSent(o)
    Tell(o, PlayerLink(o.claimer) .. " sent your work order for %s. Once you have it, confirm it on the order's card (/kr orders).")
end

local MATS_HANDED = { t = "traded you", m = "mailed you" }

local function Notify(o, old)
    local mine = KR.DB:IsMyCharacter(o.requester)
    if o.step == "p" and not mine and CanCraft(o) then
        Tell(o, "New work order from " .. PlayerLink(o.requester) .. ": %s. You can craft it; type /kr orders to claim it.")
    elseif mine and o.step == "c" then
        Tell(o, PlayerLink(o.claimer) .. " claimed your work order for %s.")
    elseif o.step == "m" and KR.DB:IsMyCharacter(o.claimer) and old and not WorkOrders.MatsSteps(old).g then
        Tell(o, PlayerLink(o.requester) .. " " .. (MATS_HANDED[o.how] or "says they sent you") .. " the materials for %s.")
    elseif mine and o.step == "g" then
        Tell(o, PlayerLink(o.claimer) .. " received your materials for %s.")
    elseif mine and o.step == "r" and old and old.claimer and WorkOrders.MatsSteps(old).g then
        local by = o.by == old.claimer and "" or (" by " .. PlayerLink(o.by))
        Tell(o, "Your work order for %s was given back" .. by .. " after " .. PlayerLink(old.claimer)
            .. " received your materials. Make sure you get them back.")
    elseif mine and o.status == "sent" then
        TellSent(o)
    elseif mine and o.status == "done" and o.by == o.claimer then
        Tell(o, PlayerLink(o.claimer) .. " marked your work order for %s complete.")
    elseif o.status == "done" and o.by == o.requester and KR.DB:IsMyCharacter(o.claimer) then
        Tell(o, PlayerLink(o.requester) .. " confirmed they have %s. The work order is complete.")
    elseif o.status == "cancelled" and old and old.claimer and KR.DB:IsMyCharacter(old.claimer) then
        Tell(o, PlayerLink(o.by) .. " cancelled the work order for %s that you claimed.")
    end
end

Comm:RegisterHandler("W", function(name, msg)
    local o = Decode(msg)
    if not o or o.by ~= name then return end
    local changed, old = Merge(o)
    if not changed then return end
    Notify(o, old)
    KR:Fire("DATA_UPDATED")
end)

local shareStarted = {}
local catchingUp
local reminded

local function Digest()
    local book, g = Book()
    local parts, now = {}, Now()
    for id, o in pairs(book or {}) do
        if Shareable(o, now, g) then parts[#parts + 1] = id .. "=" .. o.stamp .. o.by end
    end
    table.sort(parts)
    return Recipes.Hash(table.concat(parts, ","))
end

local function ShareOrder(o)
    Comm:Send(Encode("WL", o), "BULK")
    for _, e in ipairs(o.log or {}) do
        Comm:Send(table.concat({ "WH", o.requester, o.created, e.at, e.by, e.step .. e.how }, "^"), "BULK")
    end
end

local function Share(target)
    local book, g = Book()
    if not book then return end
    local now = Now()
    Comm:Send("WS^" .. target, "BULK")
    for _, o in pairs(book) do
        if Shareable(o, now, g) then ShareOrder(o) end
    end
    Comm:Send("WE^" .. target, "BULK")
end

local function RemindToConfirm()
    for _, o in ipairs(WorkOrders.List(false)) do
        if o.status == "sent" and KR.IsMe(o.requester) then TellSent(o) end
    end
end

function WorkOrders.Request()
    local book = Book()
    if not book then return end
    local now = Now()
    for id, o in pairs(book) do
        if not Keep(o, now) then book[id] = nil end
    end
    catchingUp = {}
    Comm:Send("WQ^" .. Digest(), "NORMAL")
    if not reminded then
        reminded = true
        KR:After(20, RemindToConfirm)
    end
end

Comm:RegisterHandler("WQ", function(name, msg)
    if select(2, strsplit("^", msg)) == Digest() then return end
    local asked = GetTime()
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

Comm:RegisterHandler("WH", function(_, msg)
    local _, requester, created, at, by, step = strsplit("^", msg)
    local o = WorkOrders.Get(tostring(KR.NameKey(requester)) .. "#" .. tostring(created))
    local e = { stamp = tonumber(at), by = KR.NameKey(by) }
    e.step, e.how = ParseStep(step)
    if not (o and e.stamp and e.by and e.step) or e.stamp < o.created or e.stamp > Now() + 3600 then return end
    if Record(o, e) then KR:Fire("DATA_UPDATED") end
end)

Comm:RegisterHandler("WE", function(_, msg)
    if not catchingUp or not KR.IsMe(KR.NameKey(select(2, strsplit("^", msg)))) then return end
    local had = catchingUp
    catchingUp = nil
    local book, g = Book()
    if not book then return end
    local now = Now()
    for id, o in pairs(book) do
        if not had[id] and Shareable(o, now, g) then ShareOrder(o) end
    end
end)

local ACTIONS = {
    claim    = { step = "c", from = { open = true }, said = "You claimed the work order for %s." },
    release  = { step = "r", from = { claimed = true }, said = "The work order for %s is open again." },
    matsSent = { step = "m", from = { claimed = true },
                 said = "The materials for %s are marked sent. The crafter's side marks them received." },
    matsGot  = { step = "g", from = { claimed = true }, said = "The materials for %s are marked received." },
    send     = { step = "s", from = { claimed = true },
                 said = "The work order for %s is marked sent. The requester confirms once they have it." },
    confirm  = { step = "d", from = { claimed = true, sent = true }, requesterOnly = true,
                 said = "You confirmed you have %s. The work order is complete." },
    cancel   = { step = "x", from = { open = true, claimed = true }, said = "The work order for %s is cancelled." },
}

local function MatsDone(o, step)
    if o.mats ~= "requester" then return true end
    local steps = WorkOrders.MatsSteps(o)
    return steps.g ~= nil or (step == "m" and steps.m ~= nil)
end

local function Changed(o, action, how)
    local a = ACTIONS[action]
    if not a.from[o.status] or (a.requesterOnly and not KR.IsMe(o.requester)) then return nil end
    if (a.step == "m" or a.step == "g") and MatsDone(o, a.step) then return nil end
    local n = {}
    for k, v in pairs(o) do n[k] = v end
    n.status, n.step = STEPS[a.step], a.step
    n.how = HANDOVER[a.step] and (how or "h") or ""
    n.by = KR.PlayerName()
    n.stamp = math.max(Now(), o.stamp + 1)
    if action == "claim" then
        n.claimer = n.by
    elseif action == "release" then
        n.claimer = nil
    end
    return Allowed(n, o) and n or nil
end

function WorkOrders.Get(id)
    local book = Book()
    return book and book[id]
end

local function Current(o)
    return WorkOrders.Get(o.id) or o
end

local function Send(o)
    Record(o, o)
    Book()[o.id] = o
    Comm:Send(Encode("W", o), "NORMAL")
    KR:Fire("DATA_UPDATED")
end

function WorkOrders.Can(o, action)
    return Changed(Current(o), action) ~= nil
end

function WorkOrders.Do(o, action, said, how)
    local n = Changed(Current(o), action, how)
    if not n then return false end
    Send(n)
    Tell(n, said or ACTIONS[action].said)
    return true
end

function WorkOrders.Create(entry, qty, mats, note)
    qty = tonumber(qty)
    if not Book() or not qty or qty < 1 or qty > WorkOrders.MAX_QTY or qty % 1 ~= 0 or not MATS[mats] then return nil end
    if not KR.HasFullPlayerName() then
        KR:Print("Still loading the guild roster; try again in a moment.")
        return nil
    end
    local me, now, r = KR.PlayerName(), Now(), entry.recipe
    local o = {
        id = me .. "#" .. now, requester = me, created = now, status = "open", stamp = now, by = me,
        step = "p", how = "", qty = qty, prof = entry.prof, itemID = r.itemID, spellID = r.spellID, name = r.name,
        note = Truncate(CleanNote(note), WorkOrders.MAX_NOTE), mats = mats,
    }
    Send(o)
    Tell(o, "Work order posted for %s. Guildmates running Kor'kron Roster can now claim it.")
    return o
end

function WorkOrders.List(finished)
    local out = {}
    local book, g = Book()
    if not book then return out end
    local now = Now()
    for _, o in pairs(book) do
        local over = Finished(o, now)
        local wanted = (finished and over and o.status ~= "cancelled") or (not finished and not over)
        if wanted and Keep(o, now) and KR.DB:GetMember(o.requester, false, g) then out[#out + 1] = o end
    end
    return out
end
