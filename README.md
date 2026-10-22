# Kor'kron Roster

A guild roster for **World of Warcraft: Forever** (Interface 16001) that shares professions, full recipe lists and PvP standings between guildmates.

## Features

- **Roster tab**: rank, location, last seen and notes. Turn on **Mains only** to fold alts into their main and see how many unique players the guild has. The **Inactivity** report groups players by when they were last on.
- **Professions tab**: every guildmate's two main professions plus Fishing, Cooking and First Aid. Blue entries have a shared recipe list; click one to browse it.
- **Recipes tab**: every recipe known in the guild and who can craft it, with online crafters first. Click to whisper a crafter with a ready-made "Could you craft [item] for me?", or right-click to open their recipe list.
- **Item tooltips**: any item a guildmate can craft shows a *Guild crafters* line.
- **PvP tab**: rank, today's and this week's HKs, weekly honor and lifetime HKs. Daily and weekly numbers reset automatically; the reset weekday can be changed in the options.
- **Recipe browser**: searchable, collapsible categories, reagents with tooltips, shift-click to link in chat.
- **Player cards**: click a name for that member's details, professions, PvP, notes (officer notes for officers) and linked alts.
- **Mains and alts**: on your own character's card, choose your main; your other characters then show as "Alt (Main)" to the whole guild.
- Searchable, sortable, resizable window. Minimap button, addon compartment entry and an options panel (Esc → Options → AddOns).

## Installation

Put the `KorkronRoster` folder in `World of Warcraft\_classic_beta_\Interface\AddOns` (or your Forever install's `Interface\AddOns`). Everyone in the guild should run the same version.

Recipe lists are shared once each person opens each of their profession windows with the addon installed.

## Commands

| Command | Action |
|---|---|
| `/kr` | Open or close the roster |
| `/kr roster`, `/kr prof`, `/kr pvp`, `/kr recipes` | Open a specific tab |
| `/kr inactive` | Inactivity report |
| `/kr find <text>` | Search the guild's recipes |
| `/kr sync` | Share your data and request everyone else's |
| `/kr options` | Options panel |
| `/kr minimap` | Toggle the minimap button |
| `/kr version` | Which guildmates run which version |

## How syncing works

All traffic uses the hidden `KRROSTER` addon channel on the guild, rate-limited to about 800 bytes/second.

- At login each client asks the guild once for profiles. Answers are spread over several seconds so the whole guild never replies in the same frame.
- Profiles (levels, skills, PvP) are re-sent only when they change, at most every 20 seconds.
- Recipe lists are advertised by checksum. A list is only transferred when someone's stored copy is out of date, and one request serves everyone who needs it.
- Data is only ever stored under the name of the player who actually sent it.
- Members who leave the guild are removed automatically.
- Version 1.0 clients still see version 2 users and vice versa (professions and PvP only).
