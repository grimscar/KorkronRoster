-- Kor'kron Roster: guild work orders. A member picks something a guildmate can craft and posts an
-- order; anyone else running the addon can claim it. When the requester provides the materials,
-- they mark them sent and the crafter marks them received. The crafter marks the order sent once
-- the items have been traded or mailed, and the requester confirms they have them. OrderTracking.lua
-- does all four by itself for trades and mail.
--
-- KorkronRosterDB.guilds[guild].orders["Requester#created"] = {
--     id, requester, created, status, claimer, stamp, by, step, how, qty, prof, itemID, spellID, name,
--     note, mats, log, handed }
-- status: "open" -> "claimed" -> "sent" -> "done", or "cancelled" from open or claimed. The
-- requester can also go straight from claimed to done, and a crafter on 2.4.0 (which has no "sent")
-- from claimed to done. A sent order nobody confirms counts as done after CONFIRM_WAIT. stamp and by
-- are the time (server clock) and the author of the last change; step is what that change was (see
-- STEPS) and how, for a handover, whether it was by trade ("t"), mail ("m") or by hand ("h"). mats:
-- who provides the materials, "requester" or "crafter", answered when the order is posted (nil on
-- orders posted with 2.4.0). log: the order's history, every change { at, by, step, how }, oldest
-- first. handed: OrderTracking's count of the materials handed over so far, kept on this PC only.
--
-- Every copy keeps the newest change, and a finished order (done or cancelled) beats any open,
-- claimed or sent copy, so all copies end up the same and an old copy can't bring a finished order
-- back. A handover that loses to a newer change (both sides of one trade at once) still goes in the
-- history. 2.4.0 ignores "sent" changes: it shows the order claimed until the requester confirms.
--
-- Guild addon messages (prefix KRROSTER), fields separated by "^":
--   W^requester^created^status^claimer^stamp^by^qty^prof^itemID^spellID^name^note^mats^step
--                    a change, only accepted from `by` itself. step is the step's letter and how
--                    ("gt": materials received by trade). 2.4.0 sends no mats and reads the note as
--                    the last field; 2.5.0 sends no step, which is then worked out from the status.
--   WQ^hash          "I just logged in; this is a fingerprint of the orders I know"
--   WS^name          someone whose fingerprint differs starts re-sharing their orders for name
--   WL^...           one re-shared order (same fields as W)
--   WH^requester^created^at^by^step   one entry of that order's history, after its WL
--   WE^name          end of that re-share; name then sends whatever the re-share lacked
-- A re-shared order can't be checked against who really made the change, so a modified addon could
-- make orders up. That is acceptable for a guild tool (Kor'kron Loot's ledger has the same gap).
local _, KR = ...

local WorkOrders = {}
KR.WorkOrders = WorkOrders

local Comm, Recipes = KR.Comm, KR.Recipes

local DAY = 86400
local RECENT = 30 * DAY   -- orders changed this recently are re-shared; unfinished ones older than this expire
local HISTORY = 180 * DAY -- finished orders stay in the Completed tab this long
local CONFIRM_WAIT = 7 * DAY -- a sent order the requester never confirms counts as done after this
WorkOrders.MAX_QTY = 99
WorkOrders.MAX_NOTE = 60  -- bytes: a whole order has to fit in one 255-byte message

local STATUSES = { open = true, claimed = true, sent = true, done = true, cancelled = true }
local FINISHED = { done = true, cancelled = true }
local MATS = { requester = true, crafter = true }

-- every change is one step: its letter, and the status it leaves the order in. m and g are the
-- requester's materials, sent and received; they happen while the order is claimed.
local STEPS = { p = "open", c = "claimed", m = "claimed", g = "claimed", s = "sent", d = "done", r = "open", x = "cancelled" }
local STEP_ORDER = { p = 1, c = 2, m = 3, g = 4, s = 5, d = 6, r = 7, x = 8 } -- for steps in the same second
local HANDOVER = { m = true, g = true, s = true, d = true } -- steps that hand something over, by trade, mail or hand
local HOWS = { t = true, m = true, h = true }

local Now = GetServerTime or time

-- this guild's orders (and the guild table), or nil outside a guild
local function Book()
    local g = KR.DB:GetGuild()
    if not g then return nil end
    g.orders = g.orders or {}
    return g.orders, g
end

-- done or cancelled, or sent and never confirmed
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

-- the note is shortened if the rest of the order leaves it too little room
local function Encode(cmd, o)
    local msg = table.concat({ cmd, o.requester, o.created, o.status, o.claimer or "", o.stamp, o.by,
        o.qty, o.prof, o.itemID or "", o.spellID or "", o.name, "" }, "^")
    local tail = "^" .. (o.mats or "") .. "^" .. (o.step or "") .. (o.how or "")
    return msg .. Truncate(o.note or "", 255 - #msg - #tail) .. tail
end

-- "gt" -> "g", "t"; nil for anything else
local function ParseStep(s)
    local step, how = string.match(s or "", "^(%l)(%l?)$")
    if not STEPS[step] then return nil end
    return step, HOWS[how] and how or ""
end

-- the step a change made with 2.5.0 or older (which says none) must have been
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
        if o.step == "m" then -- the requester's materials are on their way, to the crafter they already had
            return by == o.requester and o.claimer ~= nil and (old == nil or old.claimer == o.claimer)
        end
        return o.claimer == by and by ~= o.requester
    elseif o.status == "sent" then
        return o.claimer ~= nil and by == o.claimer
    elseif o.status == "done" then
        return o.claimer ~= nil and (by == o.requester or by == o.claimer)
    end
    return by == o.requester or IsOfficer(by) -- cancelled
end

-- add a change (stamp, by, step, how) to an order's history unless it's there already; true if added
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

-- the materials steps since the order was last claimed: { m = entry, g = entry }, either missing
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

-- take an order heard from the guild; returns true (and the copy it replaced) if ours changed
local function Merge(o)
    local book, g = Book()
    if not book or not KR.DB:GetMember(o.requester, false, g) then return false end
    local now = Now()
    -- (a stamp far in the future would make the order impossible to change again)
    if o.stamp < o.created or o.stamp > now + 3600 or not Keep(o, now) then return false end
    local old = book[o.id]
    local newer = not old or Newer(o, old)
    if not Allowed(o, old) then
        if newer then KR:Debug("Ignored a work order change by %s (not allowed).", o.by) end
        return false
    end
    if not newer then
        -- a handover crossed a newer change (both sides of one trade at once): it still happened
        if HANDOVER[o.step] and Record(old, o) then KR:Fire("DATA_UPDATED") end
        return false
    end
    -- the materials answer is given once, when the order is posted; changes made with 2.4.0 lack it
    o.mats = (old and old.mats) or o.mats
    -- a copy, so `old` still shows the history before this change
    o.log = { unpack(old and old.log or {}) }
    o.handed = old and old.handed
    Record(o, o)
    book[o.id] = o
    return true, old
end

-- chat notices ------------------------------------------------------------------------------

-- the order's item as chat shows it, "[Arcanite Reaper] x2" (link: the item's chat link, if loaded)
function WorkOrders.ItemText(o, link)
    return (link or o.name) .. (o.qty > 1 and (" x" .. o.qty) or "")
end

-- print text with the order's item linked in place of its one %s
local function Tell(o, text)
    KR.UI.GetRecipeLink(o, function(link)
        KR:Print(text, WorkOrders.ItemText(o, link))
    end)
end

-- a name in chat that opens a whisper to them when clicked
local function PlayerLink(name)
    local m = KR.DB:GetMember(name)
    return "|Hplayer:" .. (m and m.whisperTarget or name) .. "|h[" .. name .. "]|h"
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

-- when the crafter sends it, and again at login until the requester confirms
local function TellSent(o)
    Tell(o, PlayerLink(o.claimer) .. " sent your work order for %s. Once you have it, confirm it on the order's card (/kr orders).")
end

local MATS_HANDED = { t = "traded you", m = "mailed you" }

-- for changes made by guildmates while you are online (not for re-shares when you log in)
local function Notify(o, old)
    local mine = KR.DB:IsMyCharacter(o.requester)
    if o.step == "p" and not mine and CanCraft(o) then
        Tell(o, "New work order from " .. PlayerLink(o.requester) .. ": %s. You can craft it; type /kr orders to claim it.")
    elseif mine and o.step == "c" then
        Tell(o, PlayerLink(o.claimer) .. " claimed your work order for %s.")
    elseif o.step == "m" and KR.DB:IsMyCharacter(o.claimer) and old and not WorkOrders.MatsSteps(old).g then
        -- (not if they've already reached you: both sides of one trade)
        Tell(o, PlayerLink(o.requester) .. " " .. (MATS_HANDED[o.how] or "says they sent you") .. " the materials for %s.")
    elseif mine and o.step == "g" then
        Tell(o, PlayerLink(o.claimer) .. " received your materials for %s.")
    elseif mine and o.step == "r" and old and old.claimer and WorkOrders.MatsSteps(old).g then
        local by = o.by == old.claimer and "" or (" by " .. PlayerLink(o.by))
        Tell(o, "Your work order for %s was given back" .. by .. " after " .. PlayerLink(old.claimer)
            .. " received your materials. Make sure you get them back.")
    elseif mine and o.status == "sent" then
        TellSent(o)
    elseif mine and o.status == "done" and o.by == o.claimer then -- a crafter on 2.4.0
        Tell(o, PlayerLink(o.claimer) .. " marked your work order for %s complete.")
    elseif o.status == "done" and o.by == o.requester and KR.DB:IsMyCharacter(o.claimer) then
        Tell(o, PlayerLink(o.requester) .. " confirmed they have %s. The work order is complete.")
    elseif o.status == "cancelled" and old and old.claimer and KR.DB:IsMyCharacter(old.claimer) then
        Tell(o, PlayerLink(o.by) .. " cancelled the work order for %s that you claimed.")
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
local reminded          -- sent orders waiting for you to confirm are mentioned once a session

local function Digest()
    local book, g = Book()
    local parts, now = {}, Now()
    for id, o in pairs(book or {}) do
        if Shareable(o, now, g) then parts[#parts + 1] = id .. "=" .. o.stamp .. o.by end
    end
    table.sort(parts)
    return Recipes.Hash(table.concat(parts, ","))
end

-- one order for a re-share, then its history
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
    if not reminded then
        reminded = true
        KR:After(20, RemindToConfirm) -- after the guild's re-share has caught us up
    end
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

-- your own changes --------------------------------------------------------------------------

local ACTIONS = {
    claim    = { step = "c", from = { open = true }, said = "You claimed the work order for %s." },
    release  = { step = "r", from = { claimed = true }, said = "The work order for %s is open again." },
    matsSent = { step = "m", from = { claimed = true },
                 said = "The materials for %s are marked sent. The crafter's side marks them received." },
    matsGot  = { step = "g", from = { claimed = true }, said = "The materials for %s are marked received." },
    send     = { step = "s", from = { claimed = true },
                 said = "The work order for %s is marked sent. The requester confirms once they have it." },
    -- the rules also let the crafter finish an order (2.4.0 does), but from 2.5.0 only the requester does
    confirm  = { step = "d", from = { claimed = true, sent = true }, requesterOnly = true,
                 said = "You confirmed you have %s. The work order is complete." },
    cancel   = { step = "x", from = { open = true, claimed = true }, said = "The work order for %s is cancelled." },
}

-- the materials steps happen once a claim, and only when the requester provides the materials
local function MatsDone(o, step)
    if o.mats ~= "requester" then return true end
    local steps = WorkOrders.MatsSteps(o)
    return steps.g ~= nil or (step == "m" and steps.m ~= nil) -- received counts as sent too
end

-- the order after you do action to it, or nil if that isn't possible or allowed. how: "t" or "m"
-- when a trade or mail did it (OrderTracking), otherwise by hand
local function Changed(o, action, how)
    local a = ACTIONS[action]
    if not a.from[o.status] or (a.requesterOnly and not KR.IsMe(o.requester)) then return nil end
    if (a.step == "m" or a.step == "g") and MatsDone(o, a.step) then return nil end
    local n = {}
    for k, v in pairs(o) do n[k] = v end
    n.status, n.step = STEPS[a.step], a.step
    n.how = HANDOVER[a.step] and (how or "h") or ""
    n.by = KR.PlayerName()
    n.stamp = math.max(Now(), o.stamp + 1) -- always after the change it replaces
    if action == "claim" then
        n.claimer = n.by
    elseif action == "release" then
        n.claimer = nil
    end
    return Allowed(n, o) and n or nil
end

-- our copy of the order with this id now, or nil
function WorkOrders.Get(id)
    local book = Book()
    return book and book[id]
end

-- our copy of the order now (a window may have been opened before a newer change came in)
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

-- said (optional): the chat message instead of the usual one, with %s for the item; how: see Changed
function WorkOrders.Do(o, action, said, how)
    local n = Changed(Current(o), action, how)
    if not n then return false end
    Send(n)
    Tell(n, said or ACTIONS[action].said)
    return true
end

-- post an order for an entry of the guild's recipe index (Recipes.GetIndex); mats is who provides
-- the materials ("requester" or "crafter"); returns the order or nil
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

-- orders to show: active ones (open, claimed and sent), or finished ones (done, and sent ones nobody
-- confirmed in time; cancelled ones stay hidden)
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
