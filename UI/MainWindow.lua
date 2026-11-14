-- Kor'kron Roster: the main roster window (Roster, Professions, PvP, Recipes and Work Orders tabs).
local _, KR = ...

local UI, Style = KR.UI, KR.Style
local Main = {}
UI.Main = Main

local TOP = Style.TOP -- the tab row
local ROW_HEIGHT = 20
local MAX_COLUMNS = 8
local FRAME_WIDTH = 980
local TAB_WIDTH = 90
local CLASS_COORDS = KR.CLASS_ICON_TCOORDS

local frame, list
local headerButtons, tabButtons = {}, {}
local searchText = ""

-- looked up once per redraw (Main:Refresh), not for every member, recipe and number shown: the
-- guild table (each lookup asks the game for the guild name) and the PvP day and week
local guild, pvpDay, pvpWeek

-- shared columns ----------------------------------------------------------------------

local function Lower(s)
    return string.lower(s or "")
end

local LEVEL_COLUMN = {
    id = "level", title = "Lvl", width = 34, align = "CENTER",
    sortValue = function(m) return m.level or 0 end,
    render = function(cell, m)
        UI.SetCell(cell, "CENTER", (m.online and "|cffffffff" or "|cff808080") .. (m.level or 0) .. "|r")
    end,
}

local CLASS_COLUMN = {
    id = "class", title = "Class", width = 36, align = "CENTER", asc = true,
    sortValue = function(m) return m.class or "" end,
    render = function(cell, m)
        local coords = CLASS_COORDS[m.class]
        if coords then
            UI.SetCell(cell, "CENTER", nil, KR.CLASS_ICON_TEXTURE, coords)
            cell.icon:SetDesaturated(not m.online)
        else
            UI.SetCell(cell, "CENTER", "|cff555555?|r")
        end
    end,
}

local NAME_COLUMN = {
    id = "name", title = "Name", width = 200, asc = true,
    sortValue = function(m) return Lower(m.name) end,
    render = function(cell, m) UI.SetCell(cell, "LEFT", UI.DisplayName(m)) end,
    tooltip = function(cell, m) UI.MemberTooltip(cell, m) end,
    click = function(cell, m, button)
        if button == "RightButton" then
            if not KR.IsMe(m.name) then UI.Whisper(m) end
        else
            UI.MemberCard:Open(m)
        end
    end,
}

-- professions tab --------------------------------------------------------------------

local function HasRecipes(m, prof)
    local data = m.recipes and m.recipes[prof.name]
    return data and (data.count or 0) > 0, data
end

local function ProfText(m, prof, compact)
    if not prof or (prof.rank or 0) == 0 or prof.name == "-" then return "|cff555555-|r" end
    local color = HasRecipes(m, prof) and "|cff66bbff" or "|cffffffff"
    if compact then
        return string.format("%s%d|r|cff777777/%d|r", color, prof.rank, prof.max or 0)
    end
    return string.format("%s%s|r |cffaaaaaa(%d/%d)|r", color, prof.name, prof.rank, prof.max or 0)
end

local function ProfTooltip(cell, m, prof)
    if not prof or (prof.rank or 0) == 0 then return end
    local has, data = HasRecipes(m, prof)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name .. " - " .. prof.name, 1, 0.82, 0)
    GameTooltip:AddLine("Skill: " .. prof.rank .. " / " .. (prof.max or 0), 1, 1, 1)
    if has then
        GameTooltip:AddLine(data.count .. " recipes, updated " .. KR.FormatAgo(data.updated), 0.6, 0.8, 1)
        GameTooltip:AddLine("Click to browse recipes", 0, 1, 0)
    else
        GameTooltip:AddLine("No recipe list shared yet", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function ProfColumn(slot, title, width, compact)
    return {
        id = slot, title = title, width = width, align = compact and "CENTER" or "LEFT",
        sortValue = function(m) return m[slot] and m[slot].rank or 0 end,
        render = function(cell, m) UI.SetCell(cell, compact and "CENTER" or "LEFT", ProfText(m, m[slot], compact)) end,
        tooltip = function(cell, m) ProfTooltip(cell, m, m[slot]) end,
        click = function(cell, m)
            local prof = m[slot]
            if prof and (prof.rank or 0) > 0 and prof.name ~= "-" then UI.Inspector:Open(m, prof.name) end
        end,
    }
end

-- pvp tab ------------------------------------------------------------------------------

local function PvPTooltip(cell, m)
    local p = KR.PvP.Current(m.pvp)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name .. " - PvP", 0.77, 0.12, 0.23)
    GameTooltip:AddLine("Rank: " .. (KR.PvP.RankName(p.rankNum) and (KR.PvP.RankName(p.rankNum) .. " (Rank " .. p.rankNum .. ")") or "Unranked"), 1, 0.82, 0)
    GameTooltip:AddLine("Today's HKs: " .. p.todayHK, 0.4, 1, 0.4)
    GameTooltip:AddLine("Weekly HKs: " .. p.weekHK, 1, 1, 1)
    GameTooltip:AddLine("Weekly Honor: " .. p.weekHonor, 1, 0.82, 0)
    GameTooltip:AddLine("Lifetime HKs: " .. p.lifetimeHK, 1, 0.5, 0.25)
    if m.lastSync then GameTooltip:AddLine("Updated " .. KR.FormatAgo(m.lastSync), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- a member's PvP numbers for the day and week this redraw shows
local function PvPNow(m)
    return KR.PvP.Current(m.pvp, pvpDay, pvpWeek)
end

local function PvPNumberColumn(field, title, width, color)
    return {
        id = field, title = title, width = width, align = "CENTER",
        sortValue = function(m) return PvPNow(m)[field] end,
        render = function(cell, m)
            local v = PvPNow(m)[field]
            UI.SetCell(cell, "CENTER", v > 0 and (color .. v .. "|r") or "|cff5555550|r")
        end,
        tooltip = PvPTooltip,
    }
end

local RANK_COLUMN = {
    id = "rankNum", title = "PvP Rank", width = 160,
    sortValue = function(m) return PvPNow(m).rankNum end,
    render = function(cell, m)
        local num = PvPNow(m).rankNum
        if num <= 0 then
            UI.SetCell(cell, "LEFT", "|cff666666Unranked|r")
        else
            local badge = string.format("Interface\\PvPRankBadges\\PvPRank%02d", num)
            UI.SetCell(cell, "LEFT", string.format("|cffffd100%s|r |cffaaaaaa(R%d)|r", KR.PvP.RankName(num), num), badge)
            cell.icon:SetTexCoord(0, 1, 0, 1)
        end
    end,
    tooltip = PvPTooltip,
}

-- recipes tab --------------------------------------------------------------------------

local CraftersSorted = UI.CraftersSorted

local function RecipeLink(e)
    return KR.Recipes.Link(e.recipe)
end

local RECIPE_COLUMNS = {
    {
        id = "recipe", title = "Recipe", width = 300, asc = true,
        sortValue = function(e) return Lower(e.recipe.name) end,
        render = function(cell, e)
            UI.SetCell(cell, "LEFT", "|cffffd100" .. e.recipe.name .. "|r", KR.Recipes.Icon(e.recipe))
        end,
        tooltip = function(cell, e) UI.ItemTooltip(cell, e.recipe) end,
        click = function(cell, e)
            if IsModifiedClick and IsModifiedClick("CHATLINK") then UI.InsertLink(RecipeLink(e)) end
        end,
    },
    {
        id = "prof", title = "Profession", width = 150, asc = true,
        sortValue = function(e) return Lower(e.prof) end,
        render = function(cell, e) UI.SetCell(cell, "LEFT", e.prof, KR.ProfIcon(e.prof)) end,
    },
    {
        id = "crafters", title = "Crafters", width = 370,
        sortValue = function(e)
            local online = CraftersSorted(e, guild)
            return #online * 1000 + #e.crafters
        end,
        render = function(cell, e)
            local online, offline = CraftersSorted(e, guild)
            local names = {}
            for _, m in ipairs(online) do names[#names + 1] = UI.DisplayName(m) end
            for i = 1, math.min(#offline, math.max(0, 4 - #names)) do names[#names + 1] = "|cff808080" .. offline[i].name .. "|r" end
            local shown = #names
            local text = table.concat(names, ", ")
            if #e.crafters > shown then text = text .. " |cffaaaaaa+" .. (#e.crafters - shown) .. "|r" end
            UI.SetCell(cell, "LEFT", text)
        end,
        tooltip = function(cell, e)
            local online, offline = CraftersSorted(e)
            GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
            GameTooltip:AddLine(e.recipe.name, 1, 0.82, 0)
            for _, m in ipairs(online) do GameTooltip:AddLine(UI.DisplayName(m) .. " |cff40ff40(online)|r") end
            for _, m in ipairs(offline) do GameTooltip:AddLine("|cff808080" .. m.name .. "|r") end
            if #online > 0 then GameTooltip:AddLine("Click to whisper " .. online[1].name, 0, 1, 0) end
            GameTooltip:AddLine("Right-click to open the recipe list", 0, 1, 0)
            GameTooltip:Show()
        end,
        click = function(cell, e, button)
            local online, offline = CraftersSorted(e)
            if button == "RightButton" then
                local m = KR.DB:GetMember((online[1] or offline[1] or {}).name)
                if m then UI.Inspector:Open(m, e.prof, e.recipe.name) end
            elseif online[1] and not KR.IsMe(online[1].name) then
                UI.WhisperRecipe(online[1], e.recipe)
            end
        end,
    },
}

-- work orders and completed tabs --------------------------------------------------------------

local MATS_TEXT = { requester = "|cff40ff40Requester|r", crafter = "|cffff9933Crafter|r" }

local function OrderClick(_, o)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        UI.InsertLink(KR.Recipes.Link(o))
    else
        UI.WorkOrderCard:Open(o)
    end
end

local function OrderTooltip(cell, o)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(o.name .. " x" .. o.qty, 1, 0.82, 0)
    GameTooltip:AddLine(o.prof, 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Requested by " .. o.requester .. ", " .. KR.FormatAgo(o.created), 1, 1, 1)
    local finished = KR.WorkOrders.IsFinished(o)
    if finished then
        GameTooltip:AddLine("Crafted by " .. o.claimer .. ", completed " .. KR.FormatAgo(o.stamp), 1, 1, 1)
    elseif o.status == "sent" then
        GameTooltip:AddLine("Sent by " .. o.claimer .. ", waiting for the requester to confirm", 1, 0.6, 0.2, true)
    elseif o.claimer then
        GameTooltip:AddLine("Claimed by " .. o.claimer, 1, 0.82, 0)
    end
    if o.mats then GameTooltip:AddLine("Materials from the " .. o.mats, 0.9, 0.9, 0.7) end
    if o.note ~= "" then GameTooltip:AddLine("Note: " .. o.note, 0.9, 0.9, 0.7, true) end
    local e = not finished and KR.Recipes.Find(o.prof, o.name)
    if e then GameTooltip:AddLine("Crafters: " .. UI.CrafterList(e), 0.6, 0.8, 1, true) end
    GameTooltip:AddLine("Click to open the order, shift-click to link in chat", 0, 1, 0)
    GameTooltip:Show()
end

local ORDER_ITEM_COLUMN = {
    id = "item", title = "Item", width = 200, asc = true,
    sortValue = function(o) return Lower(o.name) end,
    render = function(cell, o) UI.SetCell(cell, "LEFT", "|cffffd100" .. o.name .. "|r", KR.Recipes.Icon(o)) end,
    tooltip = UI.ItemTooltip,
    click = OrderClick,
}

local ORDER_QTY_COLUMN = {
    id = "qty", title = "Qty", width = 32, align = "CENTER",
    sortValue = function(o) return o.qty end,
    render = function(cell, o) UI.SetCell(cell, "CENTER", tostring(o.qty)) end,
    tooltip = OrderTooltip,
    click = OrderClick,
}

local ORDER_PROF_COLUMN = {
    id = "prof", title = "Profession", width = 110, asc = true,
    sortValue = function(o) return Lower(o.prof) end,
    render = function(cell, o) UI.SetCell(cell, "LEFT", o.prof, KR.ProfIcon(o.prof)) end,
    tooltip = OrderTooltip,
    click = OrderClick,
}

local ORDER_MATS_COLUMN = {
    id = "mats", title = "Mats by", width = 70, asc = true,
    sortValue = function(o) return o.mats or "" end,
    render = function(cell, o) UI.SetCell(cell, "LEFT", MATS_TEXT[o.mats] or "|cff555555-|r") end,
    tooltip = OrderTooltip,
    click = OrderClick,
}

local function PersonColumn(field, title)
    return {
        id = field, title = title, width = 140, asc = true,
        sortValue = function(o) return Lower(o[field]) end,
        render = function(cell, o) UI.SetCell(cell, "LEFT", UI.PersonText(o[field], guild)) end,
        tooltip = OrderTooltip,
        click = OrderClick,
    }
end

local ORDER_STATUS_COLUMN = {
    id = "status", title = "Status", width = 170, asc = true,
    sortValue = function(o) return o.status .. Lower(o.claimer) end,
    render = function(cell, o)
        if o.status == "sent" then
            UI.SetCell(cell, "LEFT", "|cffff9933Sent|r by " .. UI.PersonText(o.claimer, guild))
        elseif o.claimer then
            UI.SetCell(cell, "LEFT", "|cffffd100Claimed|r by " .. UI.PersonText(o.claimer, guild))
        else
            UI.SetCell(cell, "LEFT", "|cff40ff40Open|r")
        end
    end,
    tooltip = OrderTooltip,
    click = OrderClick,
}

local function TimeColumn(field, title)
    return {
        id = field, title = title, width = 70, align = "CENTER",
        sortValue = function(o) return o[field] end,
        render = function(cell, o) UI.SetCell(cell, "CENTER", "|cffaaaaaa" .. KR.FormatAgo(o[field]) .. "|r") end,
        tooltip = OrderTooltip,
        click = OrderClick,
    }
end

local ORDER_NOTE_COLUMN = {
    id = "note", title = "Note", width = 112, asc = true,
    sortValue = function(o) return Lower(o.note) end,
    render = function(cell, o) UI.SetCell(cell, "LEFT", "|cffdddddd" .. o.note .. "|r") end,
    tooltip = OrderTooltip,
    click = OrderClick,
}

local function OrderMatches(o)
    if searchText == "" then return true end
    for _, text in ipairs({ o.name, o.prof, o.requester, o.claimer or "", o.note }) do
        if string.find(Lower(text), searchText, 1, true) then return true end
    end
    return false
end

local function OrderItems(finished)
    local out = {}
    for _, o in ipairs(KR.WorkOrders.List(finished)) do
        if OrderMatches(o) then out[#out + 1] = o end
    end
    return out
end

local function OrderTiebreak(a, b)
    return a.id < b.id
end

-- tab definitions ----------------------------------------------------------------------

local function MemberMatches(m)
    if searchText == "" then return true end
    if string.find(Lower(m.name), searchText, 1, true) then return true end
    if m.main and string.find(Lower(m.main), searchText, 1, true) then return true end
    for _, slot in ipairs(KR.PROF_SLOTS) do
        local p = m[slot]
        if p and (p.rank or 0) > 0 and string.find(Lower(p.name), searchText, 1, true) then return true end
    end
    return false
end

local function MemberItems()
    local out, showOffline = {}, KR.db.settings.showOffline
    for _, m in KR.DB:IterateMembers() do
        if (showOffline or m.online) and MemberMatches(m) then out[#out + 1] = m end
    end
    return out
end

local function MemberTiebreak(a, b)
    if a.online ~= b.online then return a.online and true or false end
    return Lower(a.name) < Lower(b.name)
end

-- roster tab ---------------------------------------------------------------------------------
-- With "Mains only" on, each row is a player: the main (or a lone character) stands in for
-- all of their characters, and playerOf holds the group so columns can use it.

local playerOf = {}

local function GroupOf(m)
    return playerOf[m.name]
end

local function OnlineChar(m)
    local p = GroupOf(m)
    if p then return p.onlineChar end
    return m.online and m or nil
end

local function RosterItems()
    wipe(playerOf)
    if not KR.db.settings.mainsOnly then return MemberItems() end
    local out, showOffline = {}, KR.db.settings.showOffline
    for _, p in ipairs(KR.Roster:GetPlayers()) do
        if p.lead and (showOffline or p.online) then
            local match = false
            for _, c in ipairs(p.chars) do
                if MemberMatches(c) then match = true break end
            end
            if match then
                playerOf[p.lead.name] = p
                out[#out + 1] = p.lead
            end
        end
    end
    return out
end

local function RosterTiebreak(a, b)
    local ao, bo = OnlineChar(a) ~= nil, OnlineChar(b) ~= nil
    if ao ~= bo then return ao end
    return Lower(a.name) < Lower(b.name)
end

local ROSTER_NAME_COLUMN = {
    id = "name", title = "Name", width = 200, asc = true,
    sortValue = NAME_COLUMN.sortValue,
    render = function(cell, m)
        local p = GroupOf(m)
        if not p then
            UI.SetCell(cell, "LEFT", UI.DisplayName(m))
            return
        end
        local name = p.online and ("|cff" .. KR.ClassColorHex(m.class) .. m.name .. "|r") or UI.ColoredName(m)
        local extra = #p.chars - 1
        if extra > 0 then
            name = name .. " |cff9d9d9d(+" .. extra .. (extra == 1 and " alt" or " alts") .. ")|r"
        end
        UI.SetCell(cell, "LEFT", name)
    end,
    tooltip = NAME_COLUMN.tooltip,
    click = NAME_COLUMN.click,
}

local GUILD_RANK_COLUMN = {
    id = "guildRank", title = "Rank", width = 110, asc = true,
    sortValue = function(m) return m.guildRankIndex or 99 end,
    render = function(cell, m)
        UI.SetCell(cell, "LEFT", m.guildRank and ("|cffdddddd" .. m.guildRank .. "|r") or "|cff555555-|r")
    end,
    tooltip = function(cell, m)
        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        GameTooltip:AddLine(m.guildRank or "?", 1, 0.82, 0)
        if KR.Ranks.CanEdit(m) then GameTooltip:AddLine("Click to change rank", 0, 1, 0) end
        GameTooltip:Show()
    end,
    click = function(cell, m)
        if KR.Ranks.CanEdit(m) then UI.ShowRankMenu(cell, m) end
    end,
}

local LOCATION_COLUMN = {
    id = "zone", title = "Location", width = 160, asc = true,
    sortValue = function(m)
        local on = OnlineChar(m)
        return on and Lower(on.zone) or "~" -- offline sorts after every zone
    end,
    render = function(cell, m)
        local on = OnlineChar(m)
        if not on then
            UI.SetCell(cell, "LEFT", "|cff555555Offline|r")
        elseif on ~= m then
            UI.SetCell(cell, "LEFT", (on.zone or "?") .. " |cff9d9d9don " .. on.name .. "|r")
        else
            UI.SetCell(cell, "LEFT", on.zone or "?")
        end
    end,
    tooltip = function(cell, m)
        local on = OnlineChar(m)
        if not on then return end
        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        GameTooltip:AddLine(on.zone or "?", 1, 1, 1)
        if on ~= m then GameTooltip:AddLine("Playing " .. on.name, 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end,
}

local LAST_SEEN_COLUMN = {
    id = "lastOnline", title = "Last Seen", width = 90, align = "CENTER",
    sortValue = function(m)
        local p = GroupOf(m)
        if p then return p.online and math.huge or p.lastOnline end
        return m.online and math.huge or (m.lastOnline or 0)
    end,
    render = function(cell, m)
        local p = GroupOf(m)
        local online = p and p.online or (not p and m.online)
        if online then
            UI.SetCell(cell, "CENTER", "|cff40ff40Online|r")
        else
            UI.SetCell(cell, "CENTER", "|cffaaaaaa" .. KR.FormatAgo(p and p.lastOnline or m.lastOnline) .. "|r")
        end
    end,
}

local NOTE_COLUMN = {
    id = "note", title = "Note", width = 150, asc = true,
    sortValue = function(m) return Lower(m.note) end,
    render = function(cell, m)
        local text = (m.note and m.note ~= "") and ("|cffdddddd" .. m.note .. "|r") or ""
        if m.officerNote and m.officerNote ~= "" then text = text .. " |cffff8040*|r" end
        UI.SetCell(cell, "LEFT", text)
    end,
    tooltip = function(cell, m)
        local hasNote, hasOfficer = m.note and m.note ~= "", m.officerNote and m.officerNote ~= ""
        if not hasNote and not hasOfficer then return end
        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        if hasNote then GameTooltip:AddLine(m.note, 1, 1, 1, true) end
        if hasOfficer then GameTooltip:AddLine("Officer: " .. m.officerNote, 1, 0.5, 0.25, true) end
        GameTooltip:Show()
    end,
}

local TABS = {
    {
        id = "ROSTER", label = "Roster", title = "Guild Roster",
        columns = {
            LEVEL_COLUMN, CLASS_COLUMN, ROSTER_NAME_COLUMN, GUILD_RANK_COLUMN,
            LOCATION_COLUMN, LAST_SEEN_COLUMN, NOTE_COLUMN,
        },
        defaultSort = { key = "guildRank", asc = true },
        items = RosterItems,
        tiebreak = RosterTiebreak,
        rosterTools = true,
    },
    {
        id = "PROFESSIONS", label = "Professions", title = "Guild Professions",
        columns = {
            LEVEL_COLUMN, CLASS_COLUMN, NAME_COLUMN,
            ProfColumn("prof1", "Profession 1", 150),
            ProfColumn("prof2", "Profession 2", 150),
            ProfColumn("fish", "Fishing", 80, true),
            ProfColumn("cook", "Cooking", 80, true),
            ProfColumn("fa", "First Aid", 80, true),
        },
        defaultSort = { key = "level", asc = false },
        items = MemberItems,
        tiebreak = MemberTiebreak,
    },
    {
        id = "PVP", label = "PvP Standings", title = "Guild PvP Standings",
        columns = {
            LEVEL_COLUMN, CLASS_COLUMN, NAME_COLUMN, RANK_COLUMN,
            PvPNumberColumn("todayHK", "Today HKs", 85, "|cff66ff66"),
            PvPNumberColumn("weekHK", "Weekly HKs", 90, "|cffffffff"),
            PvPNumberColumn("weekHonor", "Weekly Honor", 95, "|cffffd100"),
            PvPNumberColumn("lifetimeHK", "Lifetime HKs", 100, "|cffff8040"),
        },
        defaultSort = { key = "lifetimeHK", asc = false },
        items = MemberItems,
        tiebreak = MemberTiebreak,
    },
    {
        id = "RECIPES", label = "Recipes", title = "Guild Recipes",
        columns = RECIPE_COLUMNS,
        defaultSort = { key = "recipe", asc = true },
        items = function()
            local out, showOffline = {}, KR.db.settings.showOffline
            for _, e in ipairs(KR.Recipes.GetIndex().list) do
                local match = searchText == ""
                    or string.find(Lower(e.recipe.name), searchText, 1, true)
                    or string.find(Lower(e.prof), searchText, 1, true)
                if match and (showOffline or #(CraftersSorted(e, guild)) > 0) then out[#out + 1] = e end
            end
            return out
        end,
        tiebreak = function(a, b) return Lower(a.recipe.name) < Lower(b.recipe.name) end,
    },
    {
        id = "ORDERS", label = "Work Orders", title = "Guild Work Orders",
        columns = {
            ORDER_ITEM_COLUMN, ORDER_QTY_COLUMN, ORDER_PROF_COLUMN, PersonColumn("requester", "Requested by"),
            ORDER_MATS_COLUMN, ORDER_STATUS_COLUMN, TimeColumn("created", "Posted"), ORDER_NOTE_COLUMN,
        },
        defaultSort = { key = "created", asc = false },
        items = function() return OrderItems(false) end,
        tiebreak = OrderTiebreak,
        orderTools = true,
    },
    {
        id = "COMPLETED", label = "Completed", title = "Completed Work Orders",
        columns = {
            ORDER_ITEM_COLUMN, ORDER_QTY_COLUMN, ORDER_PROF_COLUMN, PersonColumn("requester", "Requested by"),
            PersonColumn("claimer", "Crafted by"), TimeColumn("stamp", "Completed"), ORDER_NOTE_COLUMN,
        },
        defaultSort = { key = "stamp", asc = false },
        items = function() return OrderItems(true) end,
        tiebreak = OrderTiebreak,
    },
}

local function CurrentTab()
    for _, t in ipairs(TABS) do
        if t.id == KR.db.settings.tab then return t end
    end
    return TABS[1]
end

local function SortState(tab)
    local s = KR.db.settings.sort[tab.id]
    if type(s) ~= "table" then
        s = { key = tab.defaultSort.key, asc = tab.defaultSort.asc }
        KR.db.settings.sort[tab.id] = s
    end
    return s
end

local function FindColumn(tab, id)
    for _, col in ipairs(tab.columns) do
        if col.id == id then return col end
    end
end

-- rows ------------------------------------------------------------------------------------

local function CellOnEnter(cell)
    cell:GetParent().highlight:Show()
    if cell.col and cell.col.tooltip and cell.item then KR.Safe(cell.col.tooltip, cell, cell.item) end
end

local function CellOnLeave(cell)
    cell:GetParent().highlight:Hide()
    GameTooltip:Hide()
end

local function CellOnClick(cell, button)
    if cell.col and cell.col.click and cell.item then KR.Safe(cell.col.click, cell, cell.item, button) end
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.highlight = row:CreateTexture(nil, "BORDER")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 0.82, 0, 0.08)
    row.highlight:Hide()
    row.cells = {}
    for i = 1, MAX_COLUMNS do
        local cell = UI.CreateCell(row, ROW_HEIGHT)
        cell:SetScript("OnEnter", CellOnEnter)
        cell:SetScript("OnLeave", CellOnLeave)
        cell:SetScript("OnClick", CellOnClick)
        row.cells[i] = cell
    end
    return row
end

local function UpdateRow(row, item)
    local tab = CurrentTab()
    if row.layout ~= tab.id then
        local x = 0
        for i, cell in ipairs(row.cells) do
            local col = tab.columns[i]
            cell:ClearAllPoints()
            if col then
                cell:SetPoint("LEFT", row, "LEFT", x, 0)
                cell:SetWidth(col.width)
                cell:Show()
                x = x + col.width + 2
            else
                cell:Hide()
            end
        end
        row.layout = tab.id
    end
    for i, col in ipairs(tab.columns) do
        local cell = row.cells[i]
        cell.col, cell.item = col, item
        cell.icon:SetDesaturated(false)
        col.render(cell, item)
    end
end

-- window ------------------------------------------------------------------------------------

local function UpdateHeaders()
    local tab = CurrentTab()
    local sort = SortState(tab)
    local x = 14
    for i, hdr in ipairs(headerButtons) do
        local col = tab.columns[i]
        if col then
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", x, TOP - 32)
            hdr:SetWidth(col.width)
            hdr.col = col
            hdr.text:SetJustifyH(col.align or "LEFT")
            local arrow = ""
            if sort.key == col.id then arrow = sort.asc and " |cffffffff^|r" or " |cffffffffv|r" end
            hdr.text:SetText("|cffffd100" .. col.title .. "|r" .. arrow)
            hdr:Show()
            x = x + col.width + 2
        else
            hdr:Hide()
        end
    end
    for _, btn in ipairs(tabButtons) do
        Style.SetButtonKind(btn, btn.tabId == tab.id)
    end
    frame.mainsOnly:SetShown(tab.rosterTools and true or false)
    frame.mainsOnly.label:SetShown(tab.rosterTools and true or false)
    frame.inactivity:SetShown(tab.rosterTools and true or false)
    frame.guildLog:SetShown(tab.rosterTools and KR.GuildLog.CanView() or false)
    frame.newOrder:SetShown(tab.orderTools and true or false)
    frame.title:SetText("|cffc41f3bKor'kron|r - " .. tab.title)
end

local function UpdateStatus()
    local total, online, withAddon, players = KR.Roster:Counts()
    local guild = KR.DB:GetGuild()
    local text
    if not IsInGuild() then
        text = "You are not in a guild."
    elseif not guild then
        text = "Loading guild roster..."
    else
        text = string.format("%d characters  |cffffd100%d unique players|r  |cff40ff40%d online|r  |cffaaaaaa%d with addon|r",
            total, players, online, withAddon)
        local pending = KR.Comm:Pending()
        if pending > 0 then text = text .. "  |cff66bbffsyncing (" .. pending .. ")|r" end
    end
    frame.status:SetText(text)
end

function Main:Refresh()
    if not frame or not frame:IsShown() then return end
    guild = KR.DB:GetGuild()
    pvpDay, pvpWeek = KR.PvP.GetKeys()
    local tab = CurrentTab()
    local items = tab.items()
    local sort = SortState(tab)
    local col = FindColumn(tab, sort.key) or tab.columns[1]
    local get, asc, tiebreak = col.sortValue, sort.asc, tab.tiebreak
    -- each row's sort value once: comparing called it twice per comparison, thousands of times
    -- in a big guild (the PvP numbers and crafter lists aren't free to work out)
    local value = {}
    for i = 1, #items do value[items[i]] = get(items[i]) end
    table.sort(items, function(a, b)
        local va, vb = value[a], value[b]
        if va ~= vb then
            if asc then return va < vb end
            return va > vb
        end
        return tiebreak(a, b)
    end)
    UpdateHeaders()
    list:SetItems(items)
    UpdateStatus()
end

local function RequestRefresh()
    if frame and frame:IsShown() then
        KR:Throttle("mainRefresh", 0.25, function() Main:Refresh() end)
    end
end

function Main:SelectTab(id)
    KR.db.settings.tab = id
    if list then list:ScrollToTop() end
    self:Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "KorkronRosterMainFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, 528)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(FRAME_WIDTH, 300, FRAME_WIDTH, 1000)
    else
        frame:SetMinResize(FRAME_WIDTH, 300)
        frame:SetMaxResize(FRAME_WIDTH, 1000)
    end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "KorkronRosterMainFrame")
    UI.MakePopup(frame)
    Style.Window(frame, "")

    -- tab buttons
    local prev
    for _, tab in ipairs(TABS) do
        local btn = UI.Button(frame, TAB_WIDTH)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, TOP)
        end
        btn:SetText(tab.label)
        btn.tabId = tab.id
        btn:SetScript("OnClick", function() Main:SelectTab(tab.id) end)
        tabButtons[#tabButtons + 1] = btn
        prev = btn
    end

    -- search
    local search = UI.EditBox(frame, 170, "KorkronRosterSearchBox")
    search:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "KorkronRosterFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search.placeholder:SetText("Search names, professions, recipes")
    search:SetScript("OnTextChanged", function(self)
        searchText = Lower(strtrim(self:GetText() or ""))
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if list then list:ScrollToTop() end
        RequestRefresh()
    end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- offline toggle
    local offline = UI.CheckButton(frame)
    offline:SetPoint("LEFT", search, "RIGHT", 12, 0)
    offline.label = offline:CreateFontString(nil, "OVERLAY", "KorkronRosterFontNormalSmall")
    offline.label:SetPoint("LEFT", offline, "RIGHT", 2, 0)
    offline.label:SetText("Show offline")
    offline:SetScript("OnClick", function(self)
        KR.db.settings.showOffline = self:GetChecked() and true or false
        Main:Refresh()
    end)
    frame.offlineCheck = offline

    -- sync
    local sync = UI.Button(frame, 90)
    sync:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, TOP)
    sync:SetText("Sync Guild")
    sync:SetScript("OnClick", function()
        KR.Roster:Request()
        if KR.Sync:RequestAll() then
            KR:Print("Requested data from the guild.")
        else
            KR:Print("Sync was requested recently; please wait a moment.")
        end
        Main:Refresh()
    end)
    sync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Sync Guild")
        GameTooltip:AddLine("Share your data and ask guildmates running Kor'kron Roster for theirs. Happens automatically at login.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- column headers
    for i = 1, MAX_COLUMNS do
        local hdr = CreateFrame("Button", nil, frame)
        hdr:SetHeight(20)
        local C = Style.COLOR
        hdr.bg = hdr:CreateTexture(nil, "BACKGROUND")
        hdr.bg:SetAllPoints()
        hdr.bg:SetColorTexture(C.button[1], C.button[2], C.button[3], 0.9)
        local line = hdr:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(C.iron[1], C.iron[2], C.iron[3], 1)
        local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        hdr.text = hdr:CreateFontString(nil, "OVERLAY", "KorkronRosterFontNormalSmall")
        hdr.text:SetPoint("LEFT", 4, 0)
        hdr.text:SetPoint("RIGHT", -4, 0)
        hdr:SetScript("OnClick", function(self)
            local tab = CurrentTab()
            local sort = SortState(tab)
            if sort.key == self.col.id then
                sort.asc = not sort.asc
            else
                sort.key = self.col.id
                sort.asc = self.col.asc and true or false
            end
            Main:Refresh()
        end)
        headerButtons[i] = hdr
    end

    list = UI.CreateList(frame, "KorkronRosterList", ROW_HEIGHT, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, TOP - 54)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 30)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 11)

    local version = frame:CreateFontString(nil, "OVERLAY", "KorkronRosterFontDisableSmall")
    version:SetPoint("RIGHT", frame, "TOPRIGHT", -34, -Style.BAND / 2)
    version:SetText("v" .. KR.version)

    -- roster tab tools, bottom right
    local inactivity = UI.Button(frame, 100)
    inactivity:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 6)
    inactivity:SetText("Inactivity")
    inactivity:SetScript("OnClick", function() UI.Inactivity:Toggle() end)
    inactivity:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Inactivity report")
        GameTooltip:AddLine("Players grouped by how long since any of their characters was online.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    inactivity:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.inactivity = inactivity

    -- work orders tab tool, same corner
    local newOrder = UI.Button(frame, 140)
    Style.SetButtonKind(newOrder, true)
    newOrder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 6)
    newOrder:SetText("New Work Order")
    newOrder:SetScript("OnClick", function() UI.WorkOrderForm:Open() end)
    newOrder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("New work order")
        GameTooltip:AddLine("Pick something a guildmate can craft and post a request for it. Anyone running Kor'kron Roster can claim it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    newOrder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.newOrder = newOrder

    local mains = UI.CheckButton(frame)
    mains.label = mains:CreateFontString(nil, "OVERLAY", "KorkronRosterFontNormalSmall")
    mains.label:SetText("Mains only")
    mains.label:SetPoint("RIGHT", inactivity, "LEFT", -12, 0)
    mains:SetPoint("RIGHT", mains.label, "LEFT", -2, 0)
    mains:SetScript("OnClick", function(self)
        KR.db.settings.mainsOnly = self:GetChecked() and true or false
        if list then list:ScrollToTop() end
        Main:Refresh()
    end)
    mains:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Mains only")
        GameTooltip:AddLine("One row per player: alts are folded into their main, so the list shows how many unique people are in the guild.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mains:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.mainsOnly = mains

    -- officers only; left of Mains only so that row doesn't move for everyone else
    local guildLog = UI.Button(frame, 90)
    guildLog:SetPoint("RIGHT", mains, "LEFT", -8, 0)
    guildLog:SetText("Guild Log")
    guildLog:SetScript("OnClick", function() UI.GuildLog:Toggle() end)
    guildLog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Guild log")
        GameTooltip:AddLine("Who joined, left, was kicked, promoted or demoted, by whom and when. Only officers see this button.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guildLog:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.guildLog = guildLog

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOM") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    frame:SetScript("OnShow", function()
        offline:SetChecked(KR.db.settings.showOffline)
        mains:SetChecked(KR.db.settings.mainsOnly)
        Main:Refresh()
    end)
    frame:SetScript("OnHide", function()
        UI.Inspector:Hide()
        UI.WorkOrderForm:Hide()
        UI.WorkOrderCard:Hide()
    end)
end

function Main:Show(tabId)
    if not frame then Build() end
    if tabId then KR.db.settings.tab = tabId end
    KR.Roster:Request()
    if frame:IsShown() then
        self:Refresh()
    else
        frame:Show()
    end
end

function Main:Toggle(tabId)
    if frame and frame:IsShown() and not tabId then
        frame:Hide()
    else
        self:Show(tabId)
    end
end

function Main:IsShown()
    return frame and frame:IsShown()
end

KR:On("DATA_UPDATED", RequestRefresh)
