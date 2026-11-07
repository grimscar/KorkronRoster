-- Kor'kron Roster: notices trades and mail that hand over a work order's items and moves the order on
-- by itself. On the crafter's side the order is marked sent; on the requester's side it's confirmed.
--   Trade: what each side has put in the trade window is noted as it changes (an enchant shows on the
--          item in the "Will not be traded" slot); it counts once the game says the trade is complete.
--   Mail:  the crafter's attachments count once the game says the mail went out. The requester's side
--          counts mail from the crafter as soon as it shows in their mailbox, except cash on delivery.
-- One trade or mail (or the mailbox, for each sender) has to hold the whole order; anything less is
-- left to the order card's buttons.
local _, KR = ...

local TRADE_SLOTS, ENCHANT_SLOT = 6, 7 -- the trade window's item slots, and its "Will not be traded" slot

-- what changed hands: counts[itemID] = how many, and the enchant put on an item, if any
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

-- is a name the game gave us (perhaps only "First") this guildmate ("First Last")?
local function SamePerson(seen, name)
    seen = KR.NameKey(seen)
    if not seen or not name then return false end
    if string.find(seen, " ", 1, true) then return seen == name end
    return seen == KR.FirstName(name)
end

-- does the handover hold this order's items? Those it does are used up, so each counts for one order.
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

-- partner: who we traded or mailed with; given/got: what went to them and what came from them;
-- verb: "traded" or "mailed". Oldest orders first.
local function Settle(partner, given, got, verb)
    local orders = KR.WorkOrders.List(false)
    table.sort(orders, function(a, b) return a.created < b.created end)
    for _, o in ipairs(orders) do
        if o.status == "claimed" and KR.IsMe(o.claimer) and SamePerson(partner, o.requester) and Take(o, given) then
            KR.WorkOrders.Do(o, "send", "You " .. verb .. " %s to " .. o.requester .. ", so the work order is marked sent.")
        elseif (o.status == "claimed" or o.status == "sent") and KR.IsMe(o.requester)
            and SamePerson(partner, o.claimer) and Take(o, got) then
            KR.WorkOrders.Do(o, "confirm", "You got %s from " .. o.claimer .. ", so the work order is complete.")
        end
    end
end

-- trade ----------------------------------------------------------------------------------------------

local trade -- the trade in the window: partner, and what each side has put in so far

local function NoteTrade()
    if not trade then return end
    local given, got = Handover(), Handover()
    for i = 1, TRADE_SLOTS do
        Add(given, GetTradePlayerItemLink(i), select(3, GetTradePlayerItemInfo(i)))
        Add(got, GetTradeTargetItemLink(i), select(3, GetTradeTargetItemInfo(i)))
    end
    -- an enchanter enchants the item the other side puts in its "Will not be traded" slot
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

-- the window empties as the trade goes through, so what was noted last is what changed hands
KR:RegisterEvent("UI_INFO_MESSAGE", function(a, b)
    if (a ~= ERR_TRADE_COMPLETE and b ~= ERR_TRADE_COMPLETE) or not trade then return end
    local done = trade
    trade = nil
    KR:Debug("Trade with %s complete: gave %s; got %s.", done.partner, Describe(done.given), Describe(done.got))
    Settle(done.partner, done.given, done.got, "traded")
end)

-- mail -------------------------------------------------------------------------------------------------

local outgoing -- the mail being sent: recipient and attachments, until the game says it went

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
    Settle(mail.to, mail.items, Handover(), "mailed")
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
        Settle(sender, Handover(), h, "mailed")
    end
end)
