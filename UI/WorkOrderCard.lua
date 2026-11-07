-- Kor'kron Roster: the work order card (click an order on the Work Orders or Completed tab). The whole
-- order, who provides the materials and how many are needed, buttons for what you may do with it, and
-- ready-made whispers between the requester and the crafter.
local _, KR = ...

local UI = KR.UI
local Card = {}
UI.WorkOrderCard = Card

local WIDTH, HEIGHT = 380, 440
local CHAT_MAX = 255 -- longest chat message, in bytes

local frame, order

local STATUS_TEXT = {
    open = "|cff40ff40Open|r", claimed = "|cffffd100Claimed|r", sent = "|cffff9933Sent|r",
    done = "|cff66bbffCompleted|r", cancelled = "|cff9d9d9dCancelled|r",
}

local ACTIONS = {
    { id = "claim", label = "Claim", width = 86 },
    { id = "release", label = "Release", width = 86 },
    { id = "send", label = "Mark Sent", width = 86,
      confirm = "Mark the work order for %s sent?\n\nDo this once the items have been traded or mailed. The requester then confirms they have them." },
    { id = "confirm", label = "Confirm Received", width = 126,
      confirm = "Confirm you have %s?\n\nThe work order moves to Completed." },
    { id = "cancel", label = "Cancel Order", width = 96, confirm = "Cancel the work order for %s?" },
}

-- ready-made whispers for a claimed order, by your side of it and then by who provides the materials
-- (unknown: posted with 2.4.0). {item} becomes the linked item and count, {mats} the materials list.
local QUICK = {
    crafter = { -- to the requester
        requester = { label = "Ask for mats", text = "Hi! I claimed your work order for {item}. Could you mail or trade me the materials{mats}?" },
        crafter = { label = "I'm on it", text = "Hi! I claimed your work order for {item}. I'll get the materials myself and let you know when it's ready." },
        unknown = { label = "Ask about mats", text = "Hi! I claimed your work order for {item}. Will you send me the materials, or should I get them?" },
        always = { label = "It's ready", text = "Your {item} is ready! Should I mail it, or shall we meet up to trade?" },
    },
    requester = { -- to the crafter
        requester = { label = "Sending mats", text = "Thanks for taking my work order for {item}! I'll send you the materials{mats}." },
        crafter = { label = "Thank you", text = "Thanks for taking my work order for {item}! Let me know when it's ready." },
        always = { label = "Any news?", text = "Hi! How is my work order for {item} coming along?" },
    },
}
QUICK.requester.unknown = QUICK.requester.crafter

-- completing and cancelling are final, so they ask first
StaticPopupDialogs["KORKRON_WORK_ORDER"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) KR.Safe(KR.WorkOrders.Do, data.order, data.action) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- what goes into the card ------------------------------------------------------------------------

-- the materials for the whole order ("30x Arcanite Bar"), or nil when nobody in the guild shares the recipe
local function Materials(o)
    local e = KR.Recipes.Find(o.prof, o.name)
    local lines = e and UI.ReagentLines(e.recipe, o.qty)
    return lines and #lines > 0 and lines or nil
end

-- a ready-made whisper; the materials list is left out if it would make the message too long to send
local function Fill(text, item, lines)
    local list = lines and (" (" .. table.concat(lines, ", ") .. ")") or ""
    local full = string.gsub(text, "{(%a+)}", { item = item, mats = list })
    if #full > CHAT_MAX then full = string.gsub(text, "{(%a+)}", { item = item, mats = "" }) end
    return full
end

local function People(o)
    local second
    if o.status == "done" then
        second = "Crafted by " .. UI.PersonText(o.claimer) .. ", completed " .. KR.FormatAgo(o.stamp)
    elseif o.status == "cancelled" then
        second = "Cancelled by " .. UI.PersonText(o.by) .. ", " .. KR.FormatAgo(o.stamp)
    elseif o.status == "sent" then
        second = "Sent by " .. UI.PersonText(o.claimer) .. ", " .. KR.FormatAgo(o.stamp)
            .. (KR.WorkOrders.IsFinished(o) and "; never confirmed" or "; waiting for the requester to confirm")
    elseif o.claimer then
        second = "Claimed by " .. UI.PersonText(o.claimer)
    else
        second = "|cff9d9d9dNot claimed yet|r"
    end
    return "Requested by " .. UI.PersonText(o.requester) .. ", " .. KR.FormatAgo(o.created) .. "\n" .. second
end

local function MatsText(o)
    local who
    if o.mats == "requester" then
        who = UI.PersonText(o.requester) .. " provides them."
    elseif o.mats == "crafter" then
        who = "The crafter provides them."
    else
        who = "|cff9d9d9dNot said (posted with an older version).|r"
    end
    local lines = Materials(o)
    if not lines then return who .. "\n|cff9d9d9dNobody in the guild shares this recipe right now, so the list is unknown.|r" end
    return who .. "\n|cffffffff" .. table.concat(lines, "\n") .. "|r"
end

-- your side of a claimed or sent order ("crafter" or "requester") and the other person, when it's
-- between you and someone else
local function Sides(o)
    if o.status ~= "claimed" and o.status ~= "sent" then return nil end
    local isRequester, isCrafter = KR.DB:IsMyCharacter(o.requester), KR.DB:IsMyCharacter(o.claimer)
    if isRequester == isCrafter then return nil end
    local m = KR.DB:GetMember(isCrafter and o.requester or o.claimer)
    if not m then return nil end
    return isCrafter and "crafter" or "requester", m
end

-- the whisper section's title and buttons: ready-made messages between the two sides of a claimed or
-- sent order, otherwise a plain whisper to the requester and the crafter
local function WhisperOptions(o)
    local side, other = Sides(o)
    if side then
        local q = QUICK[side]
        local first = q[o.mats or "unknown"]
        return "Whisper " .. other.name, {
            { label = first.label, text = first.text, member = other },
            { label = q.always.label, text = q.always.text, member = other },
            { label = "Whisper", member = other },
        }
    end
    local options = {}
    for _, who in ipairs({ { "Requester", o.requester }, { "Crafter", o.claimer } }) do
        local m = who[2] and not KR.DB:IsMyCharacter(who[2]) and KR.DB:GetMember(who[2])
        if m then options[#options + 1] = { label = who[1], member = m } end
    end
    return "Whisper", options
end

-- buttons ----------------------------------------------------------------------------------------

local function WhisperClick(btn)
    local opt, o = btn.option, order
    if not opt.text then
        UI.Whisper(opt.member)
        return
    end
    UI.GetRecipeLink(o, function(link)
        UI.Whisper(opt.member, Fill(opt.text, KR.WorkOrders.ItemText(o, link), Materials(o)))
    end)
end

local function WhisperTooltip(btn)
    local opt = btn.option
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:AddLine("Whisper " .. opt.member.name)
    if opt.text then
        GameTooltip:AddLine(Fill(opt.text, KR.WorkOrders.ItemText(order), Materials(order)), 1, 1, 1, true)
        GameTooltip:AddLine("Goes into your chat box: change it if you like, then press Enter to send.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function ActionClick(btn)
    local a, o = btn.action, order
    if a.confirm then
        StaticPopup_Show("KORKRON_WORK_ORDER", string.format(a.confirm, o.name), nil, { order = o, action = a.id })
    else
        KR.WorkOrders.Do(o, a.id)
    end
end

local function Button(label, width, onClick)
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetText(label)
    btn:SetScript("OnClick", function(self) KR.Safe(onClick, self) end)
    return btn
end

-- frame --------------------------------------------------------------------------------------------

local function Label(template)
    local fs = frame:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    return fs
end

-- a gold section title with a faint line to the right edge; the caller places it
local function Header(text)
    local fs = Label("GameFontNormal")
    fs:SetText(text)
    fs.line = frame:CreateTexture(nil, "ARTWORK")
    fs.line:SetHeight(1)
    fs.line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    fs.line:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    fs.line:SetColorTexture(1, 0.82, 0, 0.25)
    return fs
end

-- text under a header, as wide as the card, growing with what it holds
local function Body(header)
    local fs = Label("GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -6)
    fs:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    fs:SetSpacing(2)
    return fs
end

local function Build()
    frame = CreateFrame("Frame", "KorkronWorkOrderCard", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronWorkOrderCard")
    UI.MakePopup(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg or frame, "TOP", 0, -3)
    frame.title:SetText("|cffc41f3bKor'kron|r - Work Order")

    local icon = CreateFrame("Button", nil, frame)
    icon:SetSize(42, 42)
    icon:SetPoint("TOPLEFT", 16, -32)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon:SetScript("OnEnter", function(self) UI.ItemTooltip(self, order) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", function()
        if IsModifiedClick and IsModifiedClick("CHATLINK") then UI.InsertLink(KR.Recipes.Link(order)) end
    end)
    frame.icon = icon

    frame.name = Label("GameFontNormalLarge")
    frame.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    frame.name:SetPoint("RIGHT", -16, 0)
    frame.name:SetWordWrap(false)
    frame.sub = Label("GameFontHighlightSmall")
    frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
    frame.sub:SetPoint("RIGHT", -16, 0)
    frame.sub:SetWordWrap(false)

    frame.people = Label("GameFontHighlightSmall")
    frame.people:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    frame.people:SetPoint("RIGHT", -16, 0)
    frame.people:SetSpacing(2)

    local matsHeader = Header("Materials")
    matsHeader:SetPoint("TOPLEFT", frame.people, "BOTTOMLEFT", 0, -14)
    frame.mats = Body(matsHeader)
    local noteHeader = Header("Note")
    noteHeader:SetPoint("TOPLEFT", frame.mats, "BOTTOMLEFT", -4, -14)
    frame.note = Body(noteHeader)

    frame.whisperHeader = Header("Whisper")
    frame.whisperHeader:SetPoint("BOTTOMLEFT", 16, 74)
    frame.whispers = {}
    for i = 1, 3 do
        local btn = Button("", 114, WhisperClick)
        btn:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 119, 44)
        btn:SetScript("OnEnter", WhisperTooltip)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.whispers[i] = btn
    end

    frame.actions = {}
    for i, a in ipairs(ACTIONS) do
        frame.actions[i] = Button(a.label, a.width, ActionClick)
        frame.actions[i].action = a
    end
end

local function ShowWhispers(o)
    local title, options = WhisperOptions(o)
    frame.whisperHeader:SetText(title)
    frame.whisperHeader:SetShown(#options > 0)
    frame.whisperHeader.line:SetShown(#options > 0)
    for i, btn in ipairs(frame.whispers) do
        btn.option = options[i]
        btn:SetShown(options[i] ~= nil)
        if options[i] then btn:SetText(options[i].label) end
    end
end

-- the buttons for what you may do now, side by side from the left
local function ShowActions(o)
    local x = 12
    for _, btn in ipairs(frame.actions) do
        local can = KR.WorkOrders.Can(o, btn.action.id)
        btn:SetShown(can)
        if can then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", x, 12)
            x = x + btn:GetWidth() + 4
        end
    end
end

function Card:Refresh()
    if not frame or not frame:IsShown() or not order then return end
    local o = KR.WorkOrders.Get(order.id) or order
    order = o
    UI.PrimeItem(o.itemID)
    frame.icon.texture:SetTexture(KR.Recipes.Icon(o))
    frame.name:SetText(KR.WorkOrders.ItemText(o))
    -- a sent order nobody confirmed in time counts as completed
    local status = (o.status == "sent" and KR.WorkOrders.IsFinished(o)) and "done" or o.status
    frame.sub:SetText(o.prof .. " - " .. STATUS_TEXT[status])
    frame.people:SetText(People(o))
    frame.mats:SetText(MatsText(o))
    frame.note:SetText(o.note ~= "" and o.note or "|cff9d9d9dNo note.|r")
    ShowWhispers(o)
    ShowActions(o)
end

function Card:Open(o)
    if not frame then Build() end
    order = o
    UI.HideMenu()
    if not frame:IsShown() then
        frame:ClearAllPoints()
        if KorkronRosterMainFrame and KorkronRosterMainFrame:IsShown() then
            frame:SetPoint("TOPLEFT", KorkronRosterMainFrame, "TOPRIGHT", 4, 0)
        else
            frame:SetPoint("CENTER")
        end
    end
    frame:Show()
    frame:Raise()
    self:Refresh()
end

function Card:Hide()
    if frame then frame:Hide() end
end

KR:On("DATA_UPDATED", function()
    if frame and frame:IsShown() then
        KR:Throttle("orderCardRefresh", 0.5, function() Card:Refresh() end)
    end
end)
