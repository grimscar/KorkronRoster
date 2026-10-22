# Changelog

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
