local _, KR = ...

local UI = KR.UI
local RankConfirm = {}
UI.RankConfirm = RankConfirm

local frame, confirm
local pending

local function Build()
    frame = CreateFrame("Frame", "KorkronRankConfirm", UIParent)
    frame:SetSize(340, 158)
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
    KR.Style.Window(frame, "Change Rank")

    frame.text = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlight")
    frame.text:SetPoint("TOPLEFT", 18, KR.Style.TOP - 6)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetSpacing(3)

    confirm = CreateFrame("Button", "KorkronRankConfirmButton", frame, "SecureActionButtonTemplate")
    confirm:SetSize(120, 24)
    KR.Style.Button(confirm)
    KR.Style.SetButtonKind(confirm, true)
    confirm:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 14)
    confirm:SetText("Confirm")
    local onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    confirm:RegisterForClicks(onDown and "AnyDown" or "AnyUp")
    confirm:SetAttribute("type", "macro")
    confirm:HookScript("PostClick", function()
        local p = pending
        pending = nil
        frame:Hide()
        if p then KR.Ranks.Applied(p.m, p.plan) end
    end)

    local cancel = UI.Button(frame, 120, 24)
    cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 14)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnHide", function()
        pending = nil
        if not InCombatLockdown() then confirm:SetAttribute("macrotext", nil) end
    end)
end

function RankConfirm:Open(m, plan)
    if InCombatLockdown() then
        KR:Print("Rank changes can't be made in combat.")
        return
    end
    if not frame then Build() end
    pending = { m = m, plan = plan }
    confirm:SetAttribute("macrotext", plan.macro)

    local steps = math.abs(plan.steps)
    frame.text:SetText(string.format("%s |cffffffff%s|r\nfrom |cffaaaaaa%s|r to |cffffd100%s|r%s?",
        plan.promote and "Promote" or "Demote", m.name, m.guildRank or "?",
        plan.goalName, steps > 1 and (" (" .. steps .. " steps)") or ""))
    frame:Show()
    frame:Raise()
end

KR:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and frame:IsShown() then frame:Hide() end
end)
