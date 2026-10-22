-- Kor'kron Roster: "Guild crafters" lines on item tooltips.
local _, KR = ...

local Tooltip = {}
KR.Tooltip = Tooltip

local MAX_NAMES = 6

local function AddCrafters(tooltip, itemID)
    if not itemID or not KR.db or not KR.db.settings.tooltips then return end
    local entry = KR.Recipes.GetIndex().byItem[itemID]
    if not entry then return end

    local online, offline = {}, {}
    for _, name in ipairs(entry.crafters) do
        local m = KR.DB:GetMember(name)
        local main = (m and m.main) and (" |cff9d9d9d(" .. m.main .. ")|r") or ""
        if m and m.online then
            online[#online + 1] = "|cff40ff40" .. name .. "|r" .. main
        else
            offline[#offline + 1] = "|cff9d9d9d" .. name .. "|r" .. main
        end
    end
    local names = {}
    for _, n in ipairs(online) do names[#names + 1] = n end
    for _, n in ipairs(offline) do names[#names + 1] = n end
    local extra = #names - MAX_NAMES
    for i = #names, MAX_NAMES + 1, -1 do names[i] = nil end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffc41f3bGuild crafters|r (" .. entry.prof .. "):", 1, 0.82, 0)
    tooltip:AddLine(table.concat(names, ", ") .. (extra > 0 and (" |cffaaaaaa+" .. extra .. " more|r") or ""), 1, 1, 1, true)
    tooltip:Show()
end

local function ItemIDFromTooltip(tooltip)
    if not tooltip.GetItem then return nil end
    local _, link = tooltip:GetItem()
    return link and tonumber(string.match(link, "item:(%d+)"))
end

function Tooltip:Init()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            AddCrafters(tooltip, (data and data.id) or ItemIDFromTooltip(tooltip))
        end)
        return
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", function(self)
                AddCrafters(self, ItemIDFromTooltip(self))
            end)
        end
    end
end
