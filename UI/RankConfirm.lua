-- Kor'kron Roster: confirm box for in-game rank changes.
--
-- GuildPromote/GuildDemote are protected: an addon calling them gets blocked (and the game
-- offers to disable it). A secure action button running "/gpromote Name" as a macro is
-- allowed, because the officer's own click runs it. Secure attributes can't change in
-- combat, so the box refuses to open then.
local _, KR = ...

local UI = KR.UI
local RankConfirm = {}
UI.RankConfirm = RankConfirm

local frame, confirm
local pending -- { m, tier, title, plan }

local function Build()
    frame = CreateFrame("Frame", "KorkronRankConfirm", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(340, 150)
    frame:SetPoint("CENTER", 0, 120)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronRankConfirm")
    UI.MakePopup(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg or frame, "TOP", 0, -3)
    frame.title:SetText("Change Rank")

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("TOPLEFT", 18, -36)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetSpacing(3)

    confirm = CreateFrame("Button", "KorkronRankConfirmButton", frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    confirm:SetSize(120, 24)
    confirm:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 14)
    confirm:SetText("Confirm")
    -- fire on exactly one of down/up: whichever the client's secure buttons act on
    local onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    confirm:RegisterForClicks(onDown and "AnyDown" or "AnyUp")
    confirm:SetAttribute("type", "macro")
    confirm:HookScript("PostClick", function()
        local p = pending
        pending = nil
        frame:Hide()
        if p then KR.Ranks.Applied(p.m, p.tier, p.title, p.plan) end
    end)

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24)
    cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 14)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnHide", function()
        pending = nil
        if not InCombatLockdown() then confirm:SetAttribute("macrotext", nil) end
    end)
end

function RankConfirm:Open(m, tier, title, plan)
    if InCombatLockdown() then
        KR:Print("Rank changes can't be made in combat.")
        return
    end
    if not frame then Build() end
    pending = { m = m, tier = tier, title = title, plan = plan }
    confirm:SetAttribute("macrotext", plan.macro)

    local steps = math.abs(plan.steps)
    frame.text:SetText(string.format("%s |cffffffff%s|r\nfrom |cffaaaaaa%s|r to |cffaaaaaa%s|r%s\nand make them |cffffd100%s|r?",
        plan.promote and "Promote" or "Demote", m.name, m.guildRank or "?",
        KR.Ranks.RankName(plan.goal) or tier.rank,
        steps > 1 and (" (" .. steps .. " steps)") or "", title))
    frame:Show()
    frame:Raise()
end

-- secure frames can't be hidden by addon code once combat starts, so close it just before
KR:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and frame:IsShown() then frame:Hide() end
end)
