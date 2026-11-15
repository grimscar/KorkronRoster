local _, KR = ...

local TRADE_SLOTS, ENCHANT_SLOT = 6, 7

local function Handover()
    return { counts = {} }
end

local function Add(h, link, quantity)
    local id = link and tonumber(string.match(link, "item:(%d+)"))
    if id then h.counts[id] = (h.counts[id] or 0) + (quantity or 1) end
end

local function Describe(h)
    local parts = {}
    for id, n in pairs(h.counts) do parts[#parts + 1] = n .. "x item " .. id end
    if h.enchant then parts[#parts + 1] = "enchant " .. h.enchant end
    return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

local function SamePerson(seen, name)
    seen = KR.NameKey(seen)
    if not seen or not name then return false end
    if string.find(seen, " ", 1, true) then return seen == name end
    return seen == KR.FirstName(name)
end

local function Take(o, h)
    if not o.itemID then
        if h.enchant ~= o.name then return false end
        h.enchant = nil
        return true
    end
    local have = h.counts[o.itemID] or 0
    if have < o.qty then return false end
    h.counts[o.itemID] = have - o.qty
    return true
end

local function Needed(o)
    local e = KR.Recipes.Find(o.prof, o.name)
    local reagents = e and e.recipe.reagents
    if not reagents or #reagents == 0 then return nil end
    local need = {}
    for _, rg in ipairs(reagents) do
        if not rg.itemID then return nil end
        need[rg.itemID] = (need[rg.itemID] or 0) + (rg.count or 1) * o.qty
    end
    return need
end

local function TakeMats(o, h, inbox)
    local need = Needed(o)
    if not need then return false end
    if not o.handed or o.handed.claimer ~= o.claimer then o.handed = { claimer = o.claimer, counts = {} } end
    local all, progress = true, {}
    for id, n in pairs(need) do
        local had = o.handed.counts[id] or 0
        local take = math.max(0, math.min(n - had, h.counts[id] or 0))
        if take > 0 then
            h.counts[id] = h.counts[id] - take
            if not inbox then o.handed.counts[id] = had + take end
        end
        all = all and had + take >= n
        progress[#progress + 1] = (had + take) .. "/" .. n .. " item " .. id
    end
    KR:Debug("Materials for %s: %s.", o.name, table.concat(progress, ", "))
    return all
end

local VERB = { t = "traded", m = "mailed" }

local function SettleMats(o, partner, given, got, how, inbox)
    if o.status ~= "claimed" or o.mats ~= "requester" then return end
    local steps = KR.WorkOrders.MatsSteps(o)
    if not (steps.m or steps.g) and KR.IsMe(o.requester) and SamePerson(partner, o.claimer) and TakeMats(o, given) then
        KR.WorkOrders.Do(o, "matsSent", "You " .. VERB[how] .. " the materials for %s to " .. o.claimer .. ", so they're marked sent.", how)
    elseif not steps.g and KR.IsMe(o.claimer) and SamePerson(partner, o.requester) and TakeMats(o, got, inbox) then
        KR.WorkOrders.Do(o, "matsGot", "You got the materials for %s from " .. o.requester .. ", so they're marked received.", how)
    end
end

local function SettleItems(o, partner, given, got, how)
    if o.status == "claimed" and KR.IsMe(o.claimer) and SamePerson(partner, o.requester) and Take(o, given) then
        KR.WorkOrders.Do(o, "send", "You " .. VERB[how] .. " %s to " .. o.requester .. ", so the work order is marked sent.", how)
    elseif (o.status == "claimed" or o.status == "sent") and KR.IsMe(o.requester)
        and SamePerson(partner, o.claimer) and Take(o, got) then
        KR.WorkOrders.Do(o, "confirm", "You got %s from " .. o.claimer .. ", so the work order is complete.", how)
    end
end

local function Settle(partner, given, got, how, inbox)
    local orders = KR.WorkOrders.List(false)
    table.sort(orders, function(a, b) return a.created < b.created end)
    for _, o in ipairs(orders) do
        SettleMats(o, partner, given, got, how, inbox)
        SettleItems(o, partner, given, got, how)
    end
end

local trade

local function NoteTrade()
    if not trade then return end
    local given, got = Handover(), Handover()
    for i = 1, TRADE_SLOTS do
        Add(given, GetTradePlayerItemLink(i), select(3, GetTradePlayerItemInfo(i)))
        Add(got, GetTradeTargetItemLink(i), select(3, GetTradeTargetItemInfo(i)))
    end
    given.enchant = select(6, GetTradeTargetItemInfo(ENCHANT_SLOT))
    got.enchant = select(6, GetTradePlayerItemInfo(ENCHANT_SLOT))
    trade.given, trade.got = given, got
end

KR:RegisterEvent("TRADE_SHOW", function()
    trade = { partner = UnitName("NPC") }
    NoteTrade()
end)
for _, event in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
    KR:RegisterEvent(event, NoteTrade)
end

KR:RegisterEvent("UI_INFO_MESSAGE", function(a, b)
    if (a ~= ERR_TRADE_COMPLETE and b ~= ERR_TRADE_COMPLETE) or not trade then return end
    local done = trade
    trade = nil
    KR:Debug("Trade with %s complete: gave %s; got %s.", done.partner, Describe(done.given), Describe(done.got))
    Settle(done.partner, done.given, done.got, "t")
end)

local outgoing

local function NoteOutgoing(recipient)
    local h = Handover()
    for i = 1, ATTACHMENTS_MAX_SEND do
        Add(h, GetSendMailItemLink(i), select(4, GetSendMailItem(i)))
    end
    outgoing = { to = recipient, items = h }
end

hooksecurefunc("SendMail", function(recipient) KR.Safe(NoteOutgoing, recipient) end)

KR:RegisterEvent("MAIL_SEND_SUCCESS", function()
    local mail = outgoing
    outgoing = nil
    if not mail then return end
    KR:Debug("Mail to %s sent: %s.", mail.to, Describe(mail.items))
    Settle(mail.to, mail.items, Handover(), "m")
end)

KR:RegisterEvent("MAIL_FAILED", function() outgoing = nil end)

KR:RegisterEvent("MAIL_INBOX_UPDATE", function()
    local bySender = {}
    for i = 1, GetInboxNumItems() do
        local _, _, sender, _, _, cod, _, hasItem = GetInboxHeaderInfo(i)
        if sender and hasItem and (cod or 0) == 0 then
            local h = bySender[sender] or Handover()
            bySender[sender] = h
            for a = 1, ATTACHMENTS_MAX_RECEIVE do
                Add(h, GetInboxItemLink(i, a), select(4, GetInboxItem(i, a)))
            end
        end
    end
    for sender, h in pairs(bySender) do
        KR:Debug("Mailbox: %s from %s.", Describe(h), sender)
        Settle(sender, Handover(), h, "m", true)
    end
end)
