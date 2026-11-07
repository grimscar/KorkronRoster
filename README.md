# Kor'kron Roster

A guild roster for **World of Warcraft: Forever** (Interface 16001) that shares professions, full recipe lists and PvP standings between guildmates.

## Features

- **Roster tab**: rank, location, last seen and notes. Turn on **Mains only** to fold alts into their main and see how many unique players the guild has. The **Inactivity** report groups players by when they were last on.
- **Professions tab**: every guildmate's two main professions plus Fishing, Cooking and First Aid. Blue entries have a shared recipe list; click one to browse it.
- **Recipes tab**: every recipe known in the guild and who can craft it, with online crafters first. Click to whisper a crafter with a ready-made "Could you craft [item] for me?", or right-click to open their recipe list.
- **Work Orders tab**: ask the guild for a craft. **New Work Order** opens a searchable list of everything your guildmates can make; pick an item, set how many, say whether you'll provide the materials or the crafter should, add a short note if you like and post it. Anyone else running the addon can click the order to **claim** it, so everyone sees who's on it. When the crafter trades or mails the items, the order is marked **sent**, and the requester **confirms** they have them. Trades and mail are noticed for you.
- **Completed tab**: finished work orders, who asked and who crafted them (kept for 180 days).
- **Item tooltips**: any item a guildmate can craft shows a *Guild crafters* line.
- **PvP tab**: rank, today's and this week's HKs, weekly honor and lifetime HKs. Daily and weekly numbers reset automatically; the reset weekday can be changed in the options.
- **Recipe browser**: searchable, collapsible categories, reagents with tooltips, shift-click to link in chat.
- **Player cards**: click a name for that member's details, professions, PvP, notes (officer notes for officers) and linked alts.
- **Mains and alts**: on your own character's card, choose your main; your other characters then show as "Alt (Main)" to the whole guild.
- Searchable, sortable, resizable window. Minimap button, a Kor'kron tab on the side of the game's guild window (J), addon compartment entry and an options panel (Esc → Options → AddOns).

### Work orders in detail

- Click an order to open its card: the item, who asked and who's crafting it, who provides the materials and how many are needed for the whole order, and the note. Its buttons claim the order, give a claim back, mark it sent (the crafter), confirm you have it (the requester) or cancel it. All but claiming and giving back ask first.
- **Trades and mail are tracked for you.** When the crafter trades the requester the ordered items, the order is marked sent and confirmed in one go. When the crafter mails them, it's marked sent as the mail goes out and confirmed once it shows up in the requester's mailbox (cash on delivery counts after it's paid). Enchants done through the trade window's "Will not be traded" slot count too. One trade or mail has to hold the whole order; otherwise use the buttons.
- A sent order the requester never confirms moves to Completed after 7 days.
- Once an order is claimed, its card has ready-made whispers between the requester and the crafter: asking for the materials (or saying you'll get them yourself), saying it's ready, saying the materials are on the way, or asking how it's going. They go into your chat box with the item linked, so you can change them before pressing Enter.
- The requester can cancel their own order. Officers and the Guild Master can cancel or release any order, to tidy up stale ones.
- You get a chat message when someone posts an order one of your characters can craft, when your order is claimed or sent, when the requester confirms an order you crafted, and when an order you claimed is cancelled. Sent orders waiting for you to confirm are mentioned again when you log in. Click the name in a message to whisper them.
- Open orders nobody touches for 30 days expire.
- Orders sync like everything else: you see changes as they happen, and when you log in you catch up on what you missed.

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
| `/kr orders` | Work orders: request a craft, or claim one |
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
- Work orders: each change is shared when it's made. At login your addon compares a short fingerprint of your orders with the guild's, and only if they differ does one guildmate re-send theirs.
- Members who leave the guild are removed automatically.
- If a guildmate runs a newer version, you get a reminder in chat (and again at each login) until you update.
- Version 1.0 clients still see version 2 users and vice versa (professions and PvP only).
