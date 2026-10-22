-- Kor'kron Roster: scanning your own profession levels and recipe lists.
local _, KR = ...

local Prof = {}
KR.Professions = Prof

local function SlotSignature(p)
    local parts = {}
    for _, slot in ipairs(KR.PROF_SLOTS) do
        local s = p[slot]
        parts[#parts + 1] = (s.name or "-") .. ":" .. (s.rank or 0) .. ":" .. (s.max or 0)
    end
    return table.concat(parts, ";")
end

local function IsPrimary(name)
    local canonical = KR.CanonicalProf(name)
    if KR.SECONDARY_SLOT[canonical] then return false end
    return KR.PRIMARY_PROFS[canonical] or canonical ~= "Archaeology"
end

-- keep each primary profession in the slot it already occupies
local function AssignPrimaries(p, found)
    local slots = { "prof1", "prof2" }
    local used, remaining = {}, {}
    for _, f in ipairs(found) do
        local placed = false
        for _, s in ipairs(slots) do
            if not used[s] and p[s].name == f.name then
                p[s].rank, p[s].max = f.rank, f.max
                used[s], placed = true, true
                break
            end
        end
        if not placed then remaining[#remaining + 1] = f end
    end
    for _, s in ipairs(slots) do
        if not used[s] then
            local f = table.remove(remaining, 1)
            if f then
                p[s].name, p[s].rank, p[s].max = f.name, f.rank, f.max
            else
                p[s].name, p[s].rank, p[s].max = "-", 0, 0
            end
        end
    end
end

local function ReadProfessionsAPI(primaries, secondaries)
    if not (GetProfessions and GetProfessionInfo) then return end
    local indices = { GetProfessions() }
    for i = 1, 6 do
        local idx = indices[i]
        if idx then
            local name, _, rank, maxRank = GetProfessionInfo(idx)
            if name then
                local entry = { name = name, rank = rank or 0, max = maxRank or 0 }
                local slot = KR.SECONDARY_SLOT[KR.CanonicalProf(name)]
                if slot then
                    secondaries[slot] = entry
                elseif IsPrimary(name) then
                    primaries[#primaries + 1] = entry
                end
            end
        end
    end
end

-- Classic skill tab; expands collapsed headers and puts them back afterwards
local function ReadSkillLines(primaries, secondaries)
    if not (GetNumSkillLines and GetSkillLineInfo) then return end
    local collapsed = {}
    if ExpandSkillHeader then
        for i = GetNumSkillLines(), 1, -1 do
            local name, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded then
                collapsed[name] = true
                ExpandSkillHeader(i)
            end
        end
    end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if name and not isHeader then
            local canonical = KR.CanonicalProf(name)
            local slot = KR.SECONDARY_SLOT[canonical]
            local entry = { name = name, rank = rank or 0, max = maxRank or 0 }
            if slot then
                secondaries[slot] = entry
            elseif KR.PRIMARY_PROFS[canonical] then
                primaries[#primaries + 1] = entry
            end
        end
    end
    if next(collapsed) and CollapseSkillHeader then
        for i = GetNumSkillLines(), 1, -1 do
            local name, isHeader = GetSkillLineInfo(i)
            if isHeader and collapsed[name] then CollapseSkillHeader(i) end
        end
    end
end

-- refresh level, class and profession levels; returns true if anything changed
function Prof:ScanSkills()
    if not KR.db then return false end
    local p = KR.DB:GetProfile()
    local before = SlotSignature(p) .. (p.level or 0)

    p.level = UnitLevel("player") or p.level
    p.class = select(2, UnitClass("player")) or p.class

    local primaries, secondaries = {}, {}
    ReadProfessionsAPI(primaries, secondaries)
    if #primaries == 0 and not next(secondaries) then
        ReadSkillLines(primaries, secondaries)
    end

    -- an empty read usually means the client has not loaded skills yet; leave data alone
    if #primaries > 0 or next(secondaries) then
        AssignPrimaries(p, primaries)
        for slot in pairs({ fish = true, cook = true, fa = true }) do
            local s = secondaries[slot]
            if s then p[slot].name = s.name end
            p[slot].rank = s and s.rank or 0
            p[slot].max = s and s.max or 0
        end

        -- forget recipe lists for professions that were unlearned
        local known = {}
        for _, slot in ipairs(KR.PROF_SLOTS) do
            if (p[slot].rank or 0) > 0 then known[p[slot].name] = true end
        end
        for profName in pairs(p.recipes) do
            if not known[profName] then
                p.recipes[profName] = nil
                KR.Recipes.InvalidateIndex()
            end
        end
    end

    return before ~= (SlotSignature(p) .. (p.level or 0))
end

-- trade skill window ---------------------------------------------------------------

local function ItemIDFromLink(link)
    return link and tonumber(string.match(link, "item:(%d+)")) or nil
end

local function SpellIDFromLink(link)
    return link and tonumber(string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)")) or nil
end

-- a linked, guild or NPC trade skill window shows someone else's recipes
local function IsForeignTradeSkill()
    if IsTradeSkillLinked and IsTradeSkillLinked() then return true end
    if IsTradeSkillGuild and IsTradeSkillGuild() then return true end
    local api = C_TradeSkillUI
    if api then
        if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then return true end
        if api.IsTradeSkillGuild and api.IsTradeSkillGuild() then return true end
        if api.IsNPCCrafting and api.IsNPCCrafting() then return true end
    end
    return false
end

-- Classic trade skill API. Headers are expanded for the scan and collapsed again after.
local function ScanClassicTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return end
    local skillName, rank, maxRank = GetTradeSkillLine()
    if not skillName or skillName == "UNKNOWN" or GetNumTradeSkills() == 0 then return end

    local collapsed = {}
    if ExpandTradeSkillSubClass then
        for i = GetNumTradeSkills(), 1, -1 do
            local name, kind, _, isExpanded = GetTradeSkillInfo(i)
            if (kind == "header" or kind == "subheader") and not isExpanded then
                collapsed[name] = true
                ExpandTradeSkillSubClass(i)
            end
        end
    end

    local recipes, category = {}, "General"
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name then
            if kind == "header" or kind == "subheader" then
                category = name
            else
                local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
                local reagents = {}
                for r = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
                    local rgName, rgIcon, rgCount = GetTradeSkillReagentInfo(i, r)
                    local rgLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, r)
                    reagents[#reagents + 1] = { itemID = ItemIDFromLink(rgLink), name = rgName, icon = rgIcon, count = rgCount or 1 }
                end
                recipes[#recipes + 1] = {
                    name = name,
                    category = category,
                    itemID = ItemIDFromLink(itemLink),
                    spellID = SpellIDFromLink(recipeLink),
                    icon = GetTradeSkillIcon and GetTradeSkillIcon(i),
                    link = itemLink or recipeLink,
                    reagents = reagents,
                }
            end
        end
    end

    -- close the headers we opened; walking bottom-up keeps indices above valid
    if next(collapsed) and CollapseTradeSkillSubClass then
        for i = GetNumTradeSkills(), 1, -1 do
            local name, kind = GetTradeSkillInfo(i)
            if (kind == "header" or kind == "subheader") and collapsed[name] then
                CollapseTradeSkillSubClass(i)
            end
        end
    end

    return skillName, rank, maxRank, recipes
end

-- Modern C_TradeSkillUI
local function ScanModernTradeSkill()
    local api = C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return end
    local info = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
    if not info or not info.professionName or info.professionName == "UNKNOWN" then return end

    local recipes = {}
    for _, recipeID in ipairs(api.GetAllRecipeIDs() or {}) do
        local r = api.GetRecipeInfo(recipeID)
        if r and r.learned and r.name then
            local category = "General"
            if r.categoryID and api.GetCategoryInfo then
                local c = api.GetCategoryInfo(r.categoryID)
                if c and c.name and c.name ~= "" then category = c.name end
            end
            local schematic = api.GetRecipeSchematic and api.GetRecipeSchematic(recipeID, false)
            local itemLink = api.GetRecipeItemLink and api.GetRecipeItemLink(recipeID)
            local reagents = {}
            if schematic and schematic.reagentSlotSchematics then
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    local rgID = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
                    if rgID then
                        reagents[#reagents + 1] = { itemID = rgID, count = slot.quantityRequired or 1 }
                    end
                end
            end
            recipes[#recipes + 1] = {
                name = r.name,
                category = category,
                itemID = (schematic and schematic.outputItemID) or ItemIDFromLink(itemLink),
                spellID = recipeID,
                icon = r.icon,
                link = itemLink,
                reagents = reagents,
            }
        end
    end
    return info.professionName, info.skillLevel or 0, info.maxSkillLevel or 0, recipes
end

-- Classic craft window (Enchanting); hunters' Beast Training has no skill line and is skipped
local function ScanCraft()
    if not (GetCraftDisplaySkillLine and GetNumCrafts and GetCraftInfo) then return end
    local skillName, rank, maxRank = GetCraftDisplaySkillLine()
    if not skillName or GetNumCrafts() == 0 then return end

    local recipes, category = {}, "General"
    for i = 1, GetNumCrafts() do
        local name, _, kind = GetCraftInfo(i)
        if name then
            if kind == "header" then
                category = name
            else
                local link = GetCraftItemLink and GetCraftItemLink(i)
                local reagents = {}
                for r = 1, (GetCraftNumReagents and GetCraftNumReagents(i) or 0) do
                    local rgName, rgIcon, rgCount = GetCraftReagentInfo(i, r)
                    local rgLink = GetCraftReagentItemLink and GetCraftReagentItemLink(i, r)
                    reagents[#reagents + 1] = { itemID = ItemIDFromLink(rgLink), name = rgName, icon = rgIcon, count = rgCount or 1 }
                end
                recipes[#recipes + 1] = {
                    name = name,
                    category = category,
                    itemID = ItemIDFromLink(link),
                    spellID = SpellIDFromLink(link),
                    icon = GetCraftIcon and GetCraftIcon(i),
                    link = link,
                    reagents = reagents,
                }
            end
        end
    end
    return skillName, rank, maxRank, recipes
end

local function Record(skillName, rank, maxRank, recipes)
    if not skillName or not recipes or #recipes == 0 then
        KR:Debug("No profession window to scan.")
        return false
    end
    local p = KR.DB:GetProfile()
    local slot
    for _, s in ipairs(KR.PROF_SLOTS) do
        if p[s].name == skillName then slot = p[s] break end
    end
    if not slot then
        local sec = KR.SECONDARY_SLOT[KR.CanonicalProf(skillName)]
        slot = sec and p[sec]
    end
    if slot then
        if (rank or 0) > 0 then slot.rank = rank end
        if (maxRank or 0) > 0 then slot.max = maxRank end
    end
    local changed = KR.Recipes.Store(p, skillName, recipes, true)
    KR:Debug("Scanned %s: %s recipes%s.", skillName, #recipes, changed and " (changed)" or "")
    return changed
end

-- expanding/collapsing headers fires update events; callers ignore those for a moment
Prof.lastWindowScan = 0

-- kind is "CRAFT" for the Classic craft frame, anything else for trade skills
function Prof:ScanOpenWindow(kind)
    if not KR.db or IsForeignTradeSkill() then return false end
    self.lastWindowScan = GetTime()
    if kind == "CRAFT" then
        return Record(ScanCraft())
    end
    local name, rank, maxRank, recipes = ScanClassicTradeSkill()
    if not recipes or #recipes == 0 then
        name, rank, maxRank, recipes = ScanModernTradeSkill()
    end
    return Record(name, rank, maxRank, recipes)
end
