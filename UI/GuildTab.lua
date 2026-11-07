-- Kor'kron Roster: a Kor'kron tab on the side of the game's own guild window (J), so the roster is
-- one click away from where people already look. The guild may be shown in the Guild & Communities
-- window or in the Social window's Guild tab, so the tab goes on whichever of them exists. Both may
-- only load the first time they're opened, hence the ADDON_LOADED check.
local _, KR = ...

local UI = KR.UI

local WINDOWS = { "CommunitiesFrame", "GuildFrame" }
local added = {}

local function AddTab(name, parent)
    -- the spellbook's side-tab look, low on the window's right edge (the Communities window keeps
    -- its own side tabs at the top)
    local tab = CreateFrame("Button", "KorkronRoster" .. name .. "Tab", parent)
    tab:SetSize(32, 32)
    tab:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 0, 40)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab:SetNormalTexture("Interface\\Icons\\INV_BannerPVP_01")
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetScript("OnClick", function() KR.Safe(UI.Main.Toggle, UI.Main) end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(KR.TITLE)
        GameTooltip:AddLine("Roster, professions, recipes and work orders", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function AddTabs()
    for _, name in ipairs(WINDOWS) do
        local parent = _G[name]
        if parent and not added[name] then
            added[name] = true
            AddTab(name, parent)
        end
    end
end

KR:RegisterEvent("PLAYER_LOGIN", AddTabs)
KR:RegisterEvent("ADDON_LOADED", AddTabs)
