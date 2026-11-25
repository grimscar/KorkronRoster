# Kor'kron Roster

A guild roster for **World of Warcraft: Forever** (Interface 16001) that shares professions, full recipe lists and PvP standings between guildmates.

## Features

- **Roster tab**: rank, location, last seen and notes. Turn on **Mains only** to fold alts into their main and see how many unique players the guild has. The **Inactivity** report groups players by when they were last on.
- **Guild Log** (officers): who joined, left, was kicked, promoted or demoted, by whom and when, from a button on the Roster tab. It starts with what the game's own guild log still holds and keeps it after the game drops it. Times are to the nearest hour.
- **Professions tab**: every guildmate's two main professions plus Fishing, Cooking and First Aid. Blue entries have a shared recipe list; click one to browse it.
- **Recipes tab**: every recipe known in the guild and who can craft it, with online crafters first. Click to whisper a crafter with a ready-made "Could you craft [item] for me?", or right-click to open their recipe list.
- **Work Orders tab**: ask the guild for a craft. **New Work Order** opens a searchable list of everything your guildmates can make; pick an item, set how many, say whether you'll provide the materials or the crafter should, add a short note if you like and post it. Anyone else running the addon can click the order to **claim** it, so everyone sees who's on it. If you provide the materials, they're marked **sent** when you hand them over and **received** when the crafter gets them. When the crafter trades or mails the items, the order is marked **sent**, and the requester **confirms** they have them. Trades and mail are noticed for you, and each order keeps a history of every step.
- **Completed tab**: finished work orders, who asked and who crafted them (kept for 180 days).
- **Raid Planner tab**: the Guild Master's raid line-ups. Each plan is a board for a 10, 20 or 40-player raid, with a column per role (Tank, Off Tank, Melee DPS, Ranged DPS, Healer): who's in the raid at the top of each column and the bench for that role below. Everyone can look at every plan; only the Guild Master can change them (see below).
- **Item tooltips**: any item a guildmate can craft shows a *Guild crafters* line.
- **PvP tab**: rank, today's and this week's HKs, weekly honor and lifetime HKs. Daily and weekly numbers reset automatically; the reset weekday can be changed in the options.
- **Recipe browser**: searchable, collapsible categories, reagents with tooltips, shift-click to link in chat.
- **Player cards**: click a name for that member's details, professions, PvP, notes (officer notes for officers) and linked alts.
- **Mains and alts**: on your own character's card, choose your main; your other characters then show as "Alt (Main)" to the whole guild. Officers (Hearth-Caller and up) can set the main on anyone else's card too, so players who don't run the addon can be linked. A player's own choice counts over an officer's.
- Searchable, sortable, resizable window. Minimap button, a Kor'kron tab on the side of the game's guild window (J), addon compartment entry and an options panel (Esc → Options → AddOns).

### Work orders in detail

- Click an order to open its card: the item, who asked and who's crafting it, who provides the materials, how many are needed for the whole order and whether they've been sent and received, the note, and the order's history. Its buttons claim the order, give a claim back, mark it sent (the crafter), confirm you have it (the requester) or cancel it. All but claiming and giving back ask first.
- **Trades and mail are tracked for you.** When the crafter trades the requester the ordered items, the order is marked sent and confirmed in one go. When the crafter mails them, it's marked sent as the mail goes out and confirmed once it shows up in the requester's mailbox (cash on delivery counts after it's paid). Enchants done through the trade window's "Will not be traded" slot count too. One trade or mail has to hold the whole order; otherwise use the buttons.
- **Materials from the requester are tracked the same way.** Once the requester has traded or mailed the crafter every material for the whole order, they're marked sent; once the crafter has them all, by trade or in their mailbox, they're marked received. They can come in several trades or letters. Mail in the crafter's mailbox counts while it's there, so if the crafter takes some letters out before the rest arrive, they can press **Mark Received** on the card's Materials line (the requester has **Mark Sent**). The same goes for anything tracking can't see, like materials sent from another character.
- **History:** every step of an order (posted, claimed, materials sent and received, sent, completed, given back, cancelled) with who did it, when, and whether by trade, mail or by hand. Everyone running the addon sees it, so there's a record both ways. If a crafter gives an order back after receiving your materials, you're warned in chat.
- A sent order the requester never confirms moves to Completed after 7 days.
- Once an order is claimed, its card has ready-made whispers between the requester and the crafter: asking for the materials (or saying you'll get them yourself), saying it's ready, saying the materials are on the way, or asking how it's going. They go into your chat box with the item linked, so you can change them before pressing Enter.
- The requester can cancel their own order. Officers and the Guild Master can cancel or release any order, to tidy up stale ones.
- You get a chat message when someone posts an order one of your characters can craft, when your order is claimed or sent, when materials are sent to you or your materials arrive, when the requester confirms an order you crafted, and when an order you claimed is cancelled. Sent orders waiting for you to confirm are mentioned again when you log in. Click the name in a message to whisper them.
- Open orders nobody touches for 30 days expire.
- Orders sync like everything else: you see changes as they happen, and when you log in you catch up on what you missed, history included.

### Raid Planner in detail

- **Making plans (Guild Master):** **New** starts an empty plan and asks for its name, **Copy** makes a new plan from the one shown (for example a 20-player version of a 40-player plan), **Rename** and **Delete** do what they say (Delete asks first), and the **10 / 20 / 40** buttons set the raid's size. Keep as many plans as you like and switch between them with the plan button on the left.
- **Placing people:** the guild's members are listed on the left by class, highest level first, with a search box, a class filter, **Online** and **Mains only**. Drag a name into a column's top half to put them in the raid in that role, or into its bottom half for that role's bench. Drop a name on another to put it just in front of them, drag it to another column to move it, or back to the list to take it off the plan. Right-click a name for a **Move to** menu instead.
- **Warnings:** the count at the top turns red when more people are in the raid than the size allows (nobody is removed for you), and a red **!** marks two characters of the same player both in the raid.
- Click a name for their player card.
- **Everyone else** sees the plans read-only and picks which one to look at. They're sent to the guild a few seconds after each change; someone who was offline gets the latest the next time they're online while the Guild Master is.

## Installation

Put the `KorkronRoster` folder in `World of Warcraft\_classic_beta_\Interface\AddOns` (or your Forever install's `Interface\AddOns`). Everyone in the guild should run the same version.

Recipe lists are shared once each person opens each of their profession windows with the addon installed.

## Commands

| Command | Action |
|---|---|
| `/kr` | Open or close the roster |
| `/kr roster`, `/kr prof`, `/kr pvp`, `/kr recipes` | Open a specific tab |
| `/kr inactive` | Inactivity report |
| `/kr log` | Guild log (officers) |
| `/kr find <text>` | Search the guild's recipes |
| `/kr orders` | Work orders: request a craft, or claim one |
| `/kr raids` | Raid planner |
| `/kr sync` | Share your data and request everyone else's |
| `/kr options` | Options panel |
| `/kr minimap` | Toggle the minimap button |
| `/kr version` | Which guildmates run which version |

## How syncing works

All traffic uses the hidden `KRROSTER` addon channel on the guild, rate-limited to about 800 bytes/second.

- At login each client asks the guild once for profiles. Answers are spread over several seconds so the whole guild never replies in the same frame.
- Profiles (levels, skills, PvP) are re-sent only when they change, at most every 20 seconds.
- Recipe lists are advertised by checksum. A list is only transferred when someone's stored copy is out of date, and one request serves everyone who needs it.
- Data is only ever stored under the name of the player who actually sent it. The exceptions are the mains and alts officers set, which are only accepted from officers, and raid plans, which are only accepted from the Guild Master.
- Work orders: each change is shared when it's made. At login your addon compares a short fingerprint of your orders with the guild's, and only if they differ does one guildmate re-send theirs.
- Mains and alts set by officers: shared when they're set. At login your addon compares a fingerprint the same way, and an officer who's online re-sends them if yours is out of date.
- Raid plans: the Guild Master's addon sends a short list of the plans and when each last changed, then the changed plans. At login your addon compares its copy and asks for any plan it's missing.
- Members who leave the guild are removed automatically.
- If a guildmate runs a newer version, you get a reminder in chat (and again at each login) until you update.
- Version 1.0 clients still see version 2 users and vice versa (professions and PvP only).
