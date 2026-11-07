# Changelog

## 2.5.0
- New work orders ask who provides the materials: you, or the crafter. The Work Orders tab shows the answer in a new **Mats by** column.
- Clicking an order opens its own card: the item, who asked and who's crafting it, who provides the materials and how many are needed for the whole order, the note, and buttons to claim, give back, mark sent, confirm or cancel it.
- Work orders finish in two steps: the crafter marks the order **sent**, then the requester **confirms** they have the items and it moves to Completed. Sent orders waiting for you are mentioned when you log in, and one nobody confirms moves to Completed after 7 days.
- Trades and mail are tracked for you. Trading the requester the ordered items (or putting the enchant on their item) marks the order sent and confirmed in one go. Mailing them marks it sent, and it's confirmed when the mail shows up in the requester's mailbox.
- Once an order is claimed, its card has ready-made whispers between the requester and the crafter: ask for the materials or say you'll get them yourself, say it's ready, say the materials are on the way, or ask how it's going. They go into your chat box with the item linked, so you can change them before pressing Enter.
- Names in work order chat messages can be clicked to whisper that person.
- Guildmates still on 2.4.0 can keep using work orders with you. Until they update, they don't see the materials answer, and a sent order shows as claimed until it's confirmed.

## 2.4.0
- New **Work Orders** tab: request a craft from the guild. **New Work Order** opens a searchable list of everything your guildmates can make (from their shared recipe lists) with who can craft it and the reagents. Pick an item, set a quantity and an optional note, and post it.
- Anyone else running the addon can claim an open order, and everyone sees who has it. Click an order to claim it, give it back, mark it complete once the items are traded or mailed, cancel it, or whisper the requester or crafter. Completing and cancelling ask first.
- New **Completed** tab: the history of finished orders, with who asked and who crafted them, kept for 180 days.
- The requester can cancel their own order. Officers and the Guild Master can cancel or release any order. Open orders nobody touches for 30 days expire.
- Chat messages when someone posts an order you can craft, when your order is claimed or completed, and when an order you claimed is cancelled.
- A Kor'kron tab on the side of the game's own guild window (J) opens the roster.
- New command `/kr orders`.
- When a guildmate runs a newer version, the chat message now says how to update (WowUp, or the GitHub page) and comes back at each login until you update, even when nobody running the new version is online.
- The main window is a little wider to fit the new tabs.

## 2.3.3
- Sturdier inside dungeons and raids: the game can hide some information from addons there. Kor'kron Roster now skips what it can't read instead of stopping, and a problem in one part no longer stops the rest. If something does go wrong, you'll see one short note in chat.
- Fixed: "today" and "this week" for honorable kills now follow the realm's calendar instead of each player's own PC clock, so guildmates in other time zones no longer show 0 kills for part of the day.
- `/kr help` is shorter.
- Faster in big guilds: sorting the PvP Standings and Recipes tabs, the roster scan and the "Guild crafters" tooltip line do far less work per member, which adds up in a guild of hundreds.

## 2.3.2
- Player card: the Kor'kron title and in-game rank are on their own line, so long titles no longer wrap over the online/zone line. Single-line fields are cut short with "..." instead of wrapping.
- Dropdown menus (Set Rank, main character) use the game's standard dropdown style: dark dialog background, grey border, gold section titles, a checkmark on the current choice. This replaces the yellow block.

## 2.3.1
- Fixed: changing someone's rank was blocked by the game ("blocked an action") and could get the addon disabled. Addons may not promote or demote directly. Picking a title that needs a rank change now opens a confirm box, and its Confirm button runs `/gpromote` / `/gdemote` through a secure click, which the game allows. Title-only changes (same in-game rank) still apply instantly. Not available in combat.
- The Guild Master's title is now High Overlord.

## 2.3.0
- Kor'kron titles shown instead of in-game ranks for everyone running the addon:
  - Guild Master: Warchief
  - Officer: Warmaster, Blood Guard, Quartermaster, Hearth-Caller
  - Veteran: Kor'Kron Vanguard
  - Member: Legionnaire, Oathbound, Hearthguard
  - Initiate: Scout
- Officers and the Guild Master can set ranks from the player card (Set Rank) or by clicking the Rank column on the Roster tab. Picking a title moves the in-game rank to match (promote/demote) and assigns the title. You can only change members below your own rank, matching the game's rules.
- Titles sync over the addon channel and are only accepted from Officers and the GM, for members below them. When someone logs in, one online officer re-shares the full title list.
- Tooltips, player cards and the inactivity report show titles.
- For other addons: `KorkronRoster:GetTitle("First Last")` returns the title, the in-game rank and the tier.

## 2.2.1
- Fixed overlapping windows (player card, inactivity report, recipe browser) drawing through each other. The window you opened or clicked last is now fully on top.

## 2.2.0
- New Roster tab (now the first tab): level, class, name, guild rank, location, last seen and public note. An orange * marks an officer note; hover to read it (officers only).
- Mains only toggle on the Roster tab: one row per player, with alts folded in ("Name (+2 alts)"). If an alt is online, the row shows as online, with "on <alt>" next to the zone.
- The status bar shows unique players alongside total characters.
- Inactivity report (Roster tab button or `/kr inactive`): players grouped into this week, 1 to 4 weeks, 1 to 3 months and 3+ months, each counted once by their most recently active character. Click a name for the player card.
- New commands `/kr roster` and `/kr inactive`.

## 2.1.0
- Player card: click a name in the roster for level, rank, zone or last seen, professions (click one to browse recipes), PvP, public note, officer note (officers only), and main/alt links.
- Mains and alts: on any of your own characters' cards, pick your main from the characters you've logged into on this account. Each of your other characters in the guild then shows as "Alt Name (Main Name)" in the roster, the Recipes tab and item tooltips once it logs in. A character's main is only accepted from that character itself, so nobody can claim someone else as an alt.
- Searching for a main's name also finds their alts.
- Name column widened to fit the main's name.

## 2.0.3
- Whisper with a selected recipe now fills in the link on the first click. Previously the first click opened an empty whisper because the text was added before the chat box finished switching to whisper mode.

## 2.0.2
- Whisper button in the recipe browser links the recipe you selected ("Could you craft [item] for me?"). Items the game hasn't loaded yet are fetched first, so the link works for guildmates' recipes too.
- The automatically highlighted first recipe is no longer linked; only one you click (or open from the Recipes tab).
- Recipes tab click-to-whisper uses the same reliable linking.

## 2.0.1
- Forever's two-part names ("First Last"): your own data was filed under your first name only, so you appeared twice and the full-name entry had no professions. The addon now learns your full name from the guild roster or its own messages, merges the entries, and treats "First Last", "First-Last" and "-Realm" variants as the same person.
- Existing duplicate entries are cleaned up automatically on first login.
- Whispers use the exact name the game reports for the player.

## 2.0.0

Rewrite into modules (`Core\`, `UI\`). Saved data from 1.0 is migrated automatically on first login.

### New
- Recipe lists are shared with the guild, so the recipe browser works for everyone, not just your own characters.
- Recipes tab: search every recipe in the guild and see who can craft it; click to whisper a crafter.
- "Guild crafters" line on item tooltips.
- Search box, sortable columns on every tab, height-resizable window.
- Minimap button, options panel, right-click on the addon compartment opens options.
- `/kr find`, `/kr sync`, `/kr options`, `/kr minimap`, `/kr version`.
- Notice when a guildmate runs a newer version.
- Alliance PvP rank names.
- Configurable PvP weekly reset day.

### Fixed
- Weekly honor never reset; it now restarts each PvP week.
- Today/weekly numbers from guildmates who last synced before a reset now show as 0 instead of stale values.
- Highest PvP rank could be read from the dishonorable-kills value.
- Every loading screen sent a sync request, and every guildmate answered at once. Sync now happens once per login with spread-out replies and a bandwidth-limited send queue.
- Any guildmate could overwrite another member's data; data is now only accepted from its sender.
- Members were identified by first name plus class, merging characters that shared both. Unknown classes defaulted to Warrior.
- Members who left the guild were never removed.
- Data from different guilds (alts) was mixed into one list.
- Opening the profession window with "Have Materials" checked, or viewing a linked profession, could replace or corrupt your recipe list.
- Scanning left the skill tab's headers expanded.
- The roster rebuilt every row and click handler on each refresh; it now only draws visible rows.

## 1.0.0
- Initial release: guild profession roster, recipe inspector for your own characters, PvP standings.
