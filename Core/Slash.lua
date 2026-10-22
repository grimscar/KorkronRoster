-- Kor'kron Roster: chat commands.
local _, KR = ...

local function PrintHelp()
    local c = "|cffffd100"
    KR:Print("commands (v%s):", KR.version)
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr|r - open or close the roster")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr roster|r, " .. c .. "/kr prof|r, " .. c .. "/kr pvp|r, " .. c .. "/kr recipes|r - open a specific tab")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr inactive|r - inactivity report")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr find <text>|r - search the guild's recipes")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr sync|r - share your data and request the guild's")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr options|r - open the options panel")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr minimap|r - show or hide the minimap button")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr settoday <n>|r, " .. c .. "/kr setweek <n>|r - correct your HK counts")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr debug [on|off]|r - toggle debug messages")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr version|r - show who in the guild runs which version")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr remove <name>|r - delete one roster entry")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "/kr purge|r - delete all stored data for this guild")
end

local function SetDebug(on)
    KR.db.settings.debug = on
    KR:Print("Debug messages %s.", on and "|cff00ff00on|r" or "|cffff0000off|r")
end

local function PrintVersions()
    local byVersion, none = {}, 0
    for name, m in KR.DB:IterateMembers() do
        if m.version then
            byVersion[m.version] = byVersion[m.version] or {}
            table.insert(byVersion[m.version], name)
        else
            none = none + 1
        end
    end
    KR:Print("You are running v%s.", KR.version)
    for version, names in pairs(byVersion) do
        table.sort(names)
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100v" .. version .. "|r: " .. table.concat(names, ", "))
    end
    DEFAULT_CHAT_FRAME:AddMessage("  " .. none .. " member(s) have not been seen with the addon.")
end

local function HandleCommand(msg)
    if not KR.db then return end
    local cmd, arg = string.match(strtrim(msg or ""), "^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "" then
        KR.UI.Main:Toggle()
    elseif cmd == "help" or cmd == "?" then
        PrintHelp()
    elseif cmd == "roster" then
        KR.UI.Main:Show("ROSTER")
    elseif cmd == "inactive" or cmd == "inactivity" then
        KR.UI.Inactivity:Toggle()
    elseif cmd == "prof" or cmd == "professions" then
        KR.UI.Main:Show("PROFESSIONS")
    elseif cmd == "pvp" then
        KR.UI.Main:Show("PVP")
    elseif cmd == "recipes" or cmd == "find" or cmd == "craft" then
        KR.UI.Main:Show("RECIPES")
        if arg ~= "" and KorkronRosterSearchBox then KorkronRosterSearchBox:SetText(arg) end
    elseif cmd == "sync" then
        KR.Roster:Request()
        if KR.Sync:RequestAll() then
            KR:Print("Requested data from the guild.")
        else
            KR:Print("Sync was requested recently; please wait a moment.")
        end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        KR.UI.Options:Open()
    elseif cmd == "minimap" then
        KR.db.settings.minimap.hide = not KR.db.settings.minimap.hide
        KR.UI.MinimapButton:Update()
    elseif cmd == "settoday" or cmd == "setweek" then
        local n = tonumber(arg)
        if not n or n < 0 then
            KR:Print("Usage: /kr %s <number>", cmd)
            return
        end
        if cmd == "settoday" then
            KR:Print("Today's HKs set to |cff66ff66%s|r.", KR.PvP:SetToday(n))
        else
            KR:Print("Weekly HKs set to |cffffd100%s|r.", KR.PvP:SetWeek(n))
        end
        KR.DB:SyncSelf()
        KR.Sync:SendProfile(false)
        KR:Fire("DATA_UPDATED")
    elseif cmd == "debug" then
        if arg == "on" then SetDebug(true)
        elseif arg == "off" then SetDebug(false)
        else SetDebug(not KR.db.settings.debug) end
    elseif cmd == "debugon" then
        SetDebug(true)
    elseif cmd == "debugoff" then
        SetDebug(false)
    elseif cmd == "version" or cmd == "versions" then
        PrintVersions()
    elseif cmd == "remove" or cmd == "delete" then
        local target = KR.NameKey(arg)
        local g = KR.DB:GetGuild()
        if not target or not g then
            KR:Print("Usage: /kr remove <name>  (exactly as shown in the roster)")
            return
        end
        local removed = 0
        for name in pairs(g.members) do
            if string.lower(name) == string.lower(target) then
                g.members[name] = nil
                removed = removed + 1
            end
        end
        if removed > 0 then
            KR.Recipes.InvalidateIndex()
            KR:Print("Removed %s. Guild members come back on the next roster update.", target)
            KR:Fire("DATA_UPDATED")
        else
            KR:Print("No entry named %s.", target)
        end
    elseif cmd == "purge" then
        StaticPopup_Show("KORKRON_ROSTER_PURGE")
    else
        PrintHelp()
    end
end

SLASH_KORKRONROSTER1 = "/korkron"
SLASH_KORKRONROSTER2 = "/kr"
SlashCmdList["KORKRONROSTER"] = HandleCommand

-- 1.0 commands
SLASH_KRHELP1 = "/krhelp"
SlashCmdList["KRHELP"] = PrintHelp
SLASH_KRDEBUGON1 = "/krdebugon"
SlashCmdList["KRDEBUGON"] = function() SetDebug(true) end
SLASH_KRDEBUGOFF1 = "/krdebugoff"
SlashCmdList["KRDEBUGOFF"] = function() SetDebug(false) end

-- AddonCompartmentFunc in the .toc
function KorkronRoster_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        KR.UI.Options:Open()
    else
        KR.UI.Main:Toggle()
    end
end
