# Changelog

Every release is on the [releases page](https://github.com/keasbeexd/nootropic-guild-manager/releases) with a `-forever.zip` that WowUp installs. Versions 2.1 and newer sync with each other; 2.0 and 1.x use older sync protocols and don't exchange data with them.

## 2.5.1

- **Sync limits**: a guildmate's copy can't flood everyone's saved data: values are capped at 4,000 bytes, recipe lists need a real profession ID (at most 12 per member), and a non-officer can add at most 500 new records per 10 minutes.
- Releases are now published automatically (GitHub today; CurseForge and Wago once their projects exist). See docs/PUBLISHING.md.

## 2.5.0

- **Welcome tour** on first launch (and once for everyone updating): a page per tab, your sharing choices, your profile basics (Discord, contact note, roles), and for the Guild Master the permissions. Reopen it from Options or `/ngm welcome`.
- **Sharing options** (Options > Sharing): Share my spec and professions, Share my recipes, Learn when I usually play, and Show me in Play Together. Turning one off stops sharing it and clears what was already shared; hiding from Play Together is respected by everyone's copy.
- Fix: when someone stops sharing their spec and professions, guildmates' copies drop them right away instead of after a reload.

## 2.4.0

- **Who Can Craft?** Every recipe your guildmates know, searchable, with online crafters first. Recipes are shared automatically when someone with the addon opens one of their profession windows (only recipes they've learned, never someone else's linked list). Open it from the Find tab's **Who Can Craft?** button or `/ngm craft <name>`. Each profile's professions show a **Recipes** button.
- **Raids tab on profiles.** Raid readiness worked out by each member's own addon: the Onyxia attunement (Drakefire Amulet, from quest 6602 Horde / 6502 Alliance or the amulet itself) and the Brooch of the Wardens for The Barrow Deeps' prison. The Barrow Deeps and Hyjal Summit need no attunement.
- **About page** in Options: what the addon does, credits, and links to the maintainer's site, the Nootropic Discord and the GitHub page.
- **New icon**: the Nootropic Medallion, the addon's own artwork (also the logo on GitHub), is now the icon on the window, the minimap button, the Guild & Communities shortcut and the AddOns list. The game's Ale Mug and Brewfest Stein icons and your guild emblem are still choices in Options.
- A **How It Works** introduction at the top of Options.
- Documentation: in-game introductions, this changelog, `docs/ARCHITECTURE.md`, and an offline test suite in `tests/`.

## 2.3.0

- **Play Together** tab for everyone: guildmates online near your level (your zone first) and guildmates who usually play at this hour. `/ngm play`.

## 2.2.1

- The **Recruit** permission defaults to officers (guilds that already picked ranks keep their choice).
- New **Edit their own profile** permission, everyone by default.

## 2.2.0 — first public release

- **Sync checks the sender.** A shared record only counts if the player who sent it may make that change; only officers may pass on other people's records; permission settings only count from the current Guild Master. Before this, any guildmate could forge someone's profile or the Guild Master's permissions with a hand-made addon message.
- Escape codes in shared text are defused; oversized chunked messages are refused.
- Taking someone off the Do Not Whisper list needs the Recruit permission (anyone can still add).
- Cleanup of code left from removed features.

## 2.1.10

- Guild invites by copy and paste: the Invite prompt shows `/ginvite First Last` to copy (Ctrl+C), then Enter, Ctrl+V, Enter. WoW: Forever blocks every invite that comes from an addon, including `/ginvite` put in the chat box by one.

## 2.1.9

- Whispers read like a person typed them: first name (new `$first` token), "I'm recruiting for...", and a question instead of "Just reply invite". `yeah` joined the invite keywords.

## 2.1.8

- Invite tried putting `/ginvite` in the chat box (still blocked; see 2.1.10).

## 2.1.7

- The secure Invite button stays above the visible one (it could slip underneath and miss clicks). Invite added to `/ngm diag`.

## 2.1.6

- Invites through a secure `/ginvite` button, replacing the popup that called the blocked invite function (still blocked on Forever; see 2.1.10).

## 2.1.5

- Built-in class messages rewritten in the default message's voice.

## 2.1.4

- **Do Not Whisper window** (`/ngm dnw`): the permanent list plus everyone whispered in the last 14 days, with the time left.
- **Add to Do Not Whisper** on the right-click menu of names in chat and on unit frames.
- Whispers per hour is a setting (40 by default).

## 2.1.3

- Whispers fit WoW's 255-character limit with Forever's two-part names: a shorter default message, first name only when needed, never cut mid-word. Editors show the longest a message can get.
- `no` joined the Do Not Whisper words, and only answers to the addon's own whisper can put someone on the list.

## 2.1.2

- Options text and checkbox hints wrap instead of overlapping or running off the page. Settings left over from tags cleared.

## 2.1.1

- Options page text overlap fixed; new default recruitment message.

## 2.1

- **Roster change log** in the Audit tab: joins (with who invited), rejoins, leaves, kicks, promotions and demotions from the guild event log, plus level-ups, note changes and name changes from the roster. Join dates and "rank since" on profiles.
- Tags removed. New sync protocol (5).

## 2.0

- Launch release for WoW: Forever, slimmed down from aigoodandy's 1.x: guild reviews, ratings, map sharing, polls/stats/goals, kudos, About me/status/pronouns, the compact roster, the recruiting bar, roster export and tab customization removed. Hybrid with the game's Guild & Communities roster. Guild Master permissions. MIT licence.
