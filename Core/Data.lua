-- Kor'kron Roster: static lookup tables.
local _, KR = ...

KR.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
KR.CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

KR.CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
    ["WARRIOR"] = { 0, 0.25, 0, 0.25 },
    ["MAGE"]    = { 0.25, 0.49609375, 0, 0.25 },
    ["ROGUE"]   = { 0.49609375, 0.7421875, 0, 0.25 },
    ["DRUID"]   = { 0.7421875, 0.98828125, 0, 0.25 },
    ["HUNTER"]  = { 0, 0.25, 0.25, 0.5 },
    ["SHAMAN"]  = { 0.25, 0.49609375, 0.25, 0.5 },
    ["PRIEST"]  = { 0.49609375, 0.7421875, 0.25, 0.5 },
    ["WARLOCK"] = { 0.7421875, 0.98828125, 0.25, 0.5 },
    ["PALADIN"] = { 0, 0.25, 0.5, 0.75 },
}

-- profession slots stored on every member record, in display order
KR.PROF_SLOTS = { "prof1", "prof2", "fish", "cook", "fa" }

KR.PROF_ICONS = {
    ["Alchemy"]        = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]  = "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]     = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]    = "Interface\\Icons\\Trade_Engineering",
    ["Herbalism"]      = "Interface\\Icons\\Trade_Herbalism",
    ["Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Mining"]         = "Interface\\Icons\\Trade_Mining",
    ["Skinning"]       = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Tailoring"]      = "Interface\\Icons\\Trade_Tailoring",
    ["Jewelcrafting"]  = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Inscription"]    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["Fishing"]        = "Interface\\Icons\\Trade_Fishing",
    ["Cooking"]        = "Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"]      = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}

KR.PRIMARY_PROFS = {
    ["Alchemy"] = true, ["Blacksmithing"] = true, ["Enchanting"] = true,
    ["Engineering"] = true, ["Herbalism"] = true, ["Leatherworking"] = true,
    ["Mining"] = true, ["Skinning"] = true, ["Tailoring"] = true,
    ["Jewelcrafting"] = true, ["Inscription"] = true,
}

-- secondary profession -> member slot
KR.SECONDARY_SLOT = {
    ["Fishing"] = "fish",
    ["Cooking"] = "cook",
    ["First Aid"] = "fa",
}

-- spells that carry each profession's localized name; lets non-English clients map names back
local PROF_SPELLS = {
    ["Alchemy"] = 2259, ["Blacksmithing"] = 2018, ["Enchanting"] = 7411,
    ["Engineering"] = 4036, ["Leatherworking"] = 2108, ["Tailoring"] = 3908,
    ["Mining"] = 2575, ["Skinning"] = 8613, ["Jewelcrafting"] = 25229,
    ["Inscription"] = 45357, ["Fishing"] = 7620, ["Cooking"] = 2550, ["First Aid"] = 3273,
}

function KR.GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name
    elseif GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
end

local localizedToEnglish
-- English profession name for a (possibly localized) one; unknown names pass through
function KR.CanonicalProf(name)
    if not name then return nil end
    if not localizedToEnglish then
        localizedToEnglish = {}
        for english, spellID in pairs(PROF_SPELLS) do
            local localized = KR.GetSpellName(spellID)
            if localized then localizedToEnglish[localized] = english end
        end
    end
    return localizedToEnglish[name] or name
end

function KR.ProfIcon(name)
    return KR.PROF_ICONS[KR.CanonicalProf(name)] or "Interface\\Icons\\INV_Misc_Book_09"
end

KR.PVP_RANK_NAMES = {
    Horde = {
        "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant",
        "Stone Guard", "Blood Guard", "Legionnaire", "Centurion", "Champion",
        "Lieutenant General", "General", "Warlord", "High Warlord",
    },
    Alliance = {
        "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major",
        "Knight", "Knight-Lieutenant", "Knight-Captain", "Knight-Champion", "Lieutenant Commander",
        "Commander", "Marshal", "Field Marshal", "Grand Marshal",
    },
}

-- Kor'kron titles, shown instead of the in-game rank to everyone running the addon.
-- Each tier is matched to an in-game rank by name (falling back to its position, 0 = GM).
-- A tier with a single title applies it automatically; otherwise an officer picks one.
KR.RANK_TIERS = {
    { rank = "Guild Master", index = 0, titles = { "High Overlord" } },
    { rank = "Officer",      index = 1, titles = { "Warmaster", "Blood Guard", "Quartermaster", "Hearth-Caller" } },
    { rank = "Veteran",      index = 2, titles = { "Kor'Kron Vanguard" } },
    { rank = "Member",       index = 3, titles = { "Legionnaire", "Oathbound", "Hearthguard" } },
    { rank = "Initiate",     index = 4, titles = { "Scout" } },
}

KR.WEEKDAYS ={ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
