-- Kor'kron Roster: recipe normalization, wire format, hashing and the guild crafter index.
--
-- A recipe is { name, category, spellID, itemID, icon, link, reagents = { { itemID, name, count } } }.
-- icon and link are only kept locally; the wire format carries ids and lets each client resolve them.
--
-- Wire format: records joined by "~". "#Category" starts a category, every other record is
--   name`spellID`itemID`reagents     with reagents = "itemID*count,itemID*count" (or name*count)
local _, KR = ...

local Recipes = {}
KR.Recipes = Recipes

-- strip characters reserved by the wire format and chat escapes
local function Clean(s)
    if s == nil then return "" end
    return (string.gsub(tostring(s), "[~`%^%*,#|]", ""))
end
Recipes.Clean = Clean

function Recipes.Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function RecipeKey(r)
    return r.name
end

local function NormalizeOne(r)
    if type(r) == "string" then
        r = { name = r }
    end
    if type(r) ~= "table" then return nil end
    local name, category = Clean(r.name), Clean(r.category)
    if name == "" then return nil end
    local out = {
        name = name,
        category = category ~= "" and category or "General",
        spellID = tonumber(r.spellID),
        itemID = tonumber(r.itemID),
        icon = r.icon,
        link = r.link,
        reagents = {},
    }
    if type(r.reagents) == "table" then
        for _, rg in ipairs(r.reagents) do
            if type(rg) == "table" and (rg.itemID or rg.name) then
                table.insert(out.reagents, {
                    itemID = tonumber(rg.itemID),
                    name = rg.name,
                    icon = rg.icon,
                    count = tonumber(rg.count) or 1,
                })
            end
        end
    end
    return out
end

local function SortRecipes(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.name < b.name
end

-- dedupe and sort so equal recipe sets always serialize (and hash) identically
function Recipes.Normalize(list)
    local seen, out = {}, {}
    for _, r in ipairs(list or {}) do
        local n = NormalizeOne(r)
        if n then
            local key = RecipeKey(n)
            local idx = seen[key]
            if idx then
                out[idx] = n
            else
                out[#out + 1] = n
                seen[key] = #out
            end
        end
    end
    table.sort(out, SortRecipes)
    return out
end

function Recipes.Serialize(list)
    local out, lastCat = {}, nil
    for _, r in ipairs(list) do
        local cat = Clean(r.category)
        if cat == "" then cat = "General" end
        if cat ~= lastCat then
            out[#out + 1] = "#" .. cat
            lastCat = cat
        end
        local reags = {}
        for _, rg in ipairs(r.reagents or {}) do
            local id = rg.itemID and tostring(rg.itemID) or Clean(rg.name)
            if id ~= "" then
                reags[#reags + 1] = id .. "*" .. (tonumber(rg.count) or 1)
            end
        end
        out[#out + 1] = Clean(r.name) .. "`" .. (r.spellID or "") .. "`" .. (r.itemID or "") .. "`" .. table.concat(reags, ",")
    end
    return table.concat(out, "~")
end

function Recipes.Deserialize(str)
    local list, cat = {}, "General"
    for rec in string.gmatch(str or "", "[^~]+") do
        if string.sub(rec, 1, 1) == "#" then
            cat = string.sub(rec, 2)
            if cat == "" then cat = "General" end
        else
            local name, spell, item, reags = strsplit("`", rec)
            if name and name ~= "" then
                local r = { name = name, category = cat, spellID = tonumber(spell), itemID = tonumber(item), reagents = {} }
                for token in string.gmatch(reags or "", "[^,]+") do
                    local id, count = string.match(token, "^(.-)%*(%d+)$")
                    if id and id ~= "" then
                        local itemID = tonumber(id)
                        table.insert(r.reagents, { itemID = itemID, name = (not itemID) and id or nil, count = tonumber(count) or 1 })
                    end
                end
                list[#list + 1] = r
            end
        end
    end
    return list
end

-- save a scanned recipe list on a record; with merge, recipes already known are kept
-- (recipes are never unlearned, so a filtered or partial scan must not drop any)
-- returns true if the stored set changed
function Recipes.Store(rec, profName, rawList, merge)
    rec.recipes = rec.recipes or {}
    local existing = rec.recipes[profName]
    local combined = rawList
    if merge and existing and existing.list then
        combined = {}
        for _, r in ipairs(existing.list) do combined[#combined + 1] = r end
        for _, r in ipairs(rawList) do combined[#combined + 1] = r end
    end
    local list = Recipes.Normalize(combined)
    if #list == 0 then return false end
    local hash = Recipes.Hash(Recipes.Serialize(list))
    if existing and existing.hash == hash then
        existing.list = list -- keep fresher icons/links without counting as a change
        return false
    end
    rec.recipes[profName] = { hash = hash, count = #list, updated = time(), list = list }
    Recipes.InvalidateIndex()
    return true
end

-- save a list received from a guildmate; returns false if the payload fails its hash
function Recipes.StoreSerialized(rec, profName, payload, hash)
    if Recipes.Hash(payload) ~= hash then return false end
    local list = Recipes.Deserialize(payload)
    rec.recipes = rec.recipes or {}
    rec.recipes[profName] = { hash = hash, count = #list, updated = time(), list = list }
    Recipes.InvalidateIndex()
    return true
end

-- resolve a display icon without needing the item cache
function Recipes.Icon(r)
    if r.icon and r.icon ~= KR.QUESTION_ICON and r.icon ~= 134400 then return r.icon end
    local icon
    if r.itemID then
        icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID)) or (GetItemIcon and GetItemIcon(r.itemID))
    end
    if not icon and r.spellID then
        icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(r.spellID)) or (GetSpellTexture and GetSpellTexture(r.spellID))
    end
    return icon or KR.QUESTION_ICON
end

-- name and link for an item id; name is nil until the item is cached
function Recipes.ItemInfo(itemID)
    if not itemID then return nil end
    local name, link
    if C_Item and C_Item.GetItemInfo then
        name, link = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        name, link = GetItemInfo(itemID)
    end
    return name, link
end

function Recipes.Link(r)
    if r.link then return r.link end
    if r.itemID then
        local _, link = Recipes.ItemInfo(r.itemID)
        if link then return link end
    end
    if r.spellID and GetSpellLink then
        return GetSpellLink(r.spellID)
    end
end

-- crafter index: every recipe known in the guild and who can make it ----------

local index

function Recipes.InvalidateIndex()
    index = nil
end

function Recipes.GetIndex()
    if index then return index end
    index = { list = {}, byItem = {} }
    local byKey = {}
    for name, m in KR.DB:IterateMembers() do
        for prof, data in pairs(m.recipes or {}) do
            for _, r in ipairs(data.list or {}) do
                local key = prof .. "\001" .. r.name
                local e = byKey[key]
                if not e then
                    e = { recipe = r, prof = prof, crafters = {} }
                    byKey[key] = e
                    index.list[#index.list + 1] = e
                    if r.itemID and not index.byItem[r.itemID] then index.byItem[r.itemID] = e end
                end
                e.crafters[#e.crafters + 1] = name
            end
        end
    end
    for _, e in ipairs(index.list) do
        table.sort(e.crafters)
    end
    return index
end
