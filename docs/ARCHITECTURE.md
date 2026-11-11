# How Nootropic Guild Manager works

A guide for anyone reading or changing the code. For using the addon, see the [README](../README.md).

## Layout

The addon is plain Lua and Blizzard frames, no libraries. Files load in the order of `NootropicGuildManager.toc`; every file starts with a comment saying what it does.

| Folder | What's in it |
| --- | --- |
| `Core/` | `Core.lua` (namespace, events, helpers, slash commands, start-up), `Data.lua` (classes, specs, professions, roles, recruiting defaults, raid readiness checks, About links), `Database.lua` (saved data, settings, permissions), `Sync.lua` (shared records, repair, transport, security checks) |
| `Services/` | Logic with no windows: `Roster.lua` (guild roster, search, sort), `Comm.lua` (your own spec and professions), `Profile.lua` (contact info, usual play hours), `Recruit.lua` (/who, whispers, lockouts, Do Not Whisper, invites), `Messages.lua` (custom recruitment messages), `Audit.lua` (audit text), `RosterLog.lua` (joins, leaves, promotions from the guild event log and roster), `Recipes.lua` (shared recipes), `Readiness.lua` (raid attunements and keys), `HallOfFame.lua` (your character statistics for the leaderboards), `Sharing.lua` (what you share: switches that stop and clear your shared data) |
| `UI/` | Windows and hooks: `MainFrame.lua` (the window and its tabs), `RosterView.lua` (Find), `TogetherView.lua` (Play Together), `OverviewView.lua` (Overview: census and play-time heatmap), `HallOfFameView.lua` (Hall of Fame leaderboards), `RecruitView.lua` + `MessagesView.lua` (Recruitment), `AuditView.lua`, `DetailPanel.lua` (profiles), `RecipesView.lua` (Who Can Craft?), `DNWView.lua` (Do Not Whisper window and name menus), `InvitePrompt.lua`, `Options.lua`, `Welcome.lua` (first-launch tour), `GuildRoster.lua` + `Communities.lua` (hooks on the game's Guild & Communities window), `WhoWhisper.lua` (button on the game's /who results), `MinimapButton.lua`, and shared pieces (`Widgets.lua`, `Columns.lua`, `ScheduleGrid.lua`, `BrandIcon.lua`, `MemberPicker.lua`) |
| `docs/` | This file |
| `tests/` | Offline tests that run the real files against stand-ins for the game (see [Testing](#testing)) |

Modules hang off the addon namespace (`ns.Sync`, `ns.Roster`, `ns.DB`...). `ADDON_LOADED` sets up saved data (`ns.DB:Init`); `PLAYER_LOGIN` starts everything else (see the end of `Core/Core.lua`). Modules talk through `ns:Fire(event)` / `ns:On(event, fn)` (e.g. `ROSTER_UPDATED`, `MEMBER_CHANGED`, `RECIPES_CHANGED`, `AUDIT_CHANGED`).

## Saved data

`NootropicGuildManagerDB` (account-wide):

- `settings` — your options (minimap, window size, columns, whispers per hour, Play Together range...).
- `guilds["<Guild>-<Realm>"]` — one entry per guild:
  - `sync.guild` / `sync.officer` — the shared records (below). Everything shared lives here.
  - `members[full]` — working data built from the records, plus `note`, your private note, which is never shared.
  - `recruit` — your recruiting setup (messages, keywords, the players you found).
  - `rosterSnap` — the last roster seen, to notice level-ups, note and name changes.

## Sync

Everything the guild shares is a **record**: `key -> { v = value, t = server time, a = author }`. The newest version of a record wins (ties broken by author, then value), so every copy ends up the same whatever order messages arrive in. Records are sent with `C_ChatInfo.SendAddonMessage` under the prefix `NootropicGM` on the **GUILD** channel, or on the **OFFICER** channel for officer-only data. Only those two channels are read, plus whispers to an officer from a guildmate whose guild channel doesn't deliver (below).

### Messages

All messages start with the protocol number (`PROTO`, currently 5); other versions are ignored, and so are kinds a copy doesn't know. Fields are tab-separated.

| Kind | Fields | Meaning |
| --- | --- | --- |
| `R` | key, time, author, batch, value | one record |
| `Z` | same as `R`, value compressed | one big record, Deflate + Base64 (`C_EncodingUtil`) (2.10+) |
| `S` | lane, `author:newest:sum,...` | a sync check: per author, their newest record's time and a checksum (base 36) (2.11+) |
| `Q` | lane, target, author, since | "send me this author's records newer than `since`" (`0`: all) (2.11+) |
| `C` | id, part, parts, data | a piece of a message longer than 250 bytes (at most 16 parts) |

Local changes are sent together 15 seconds after the first one (a **batch**, which the audit groups). Every 10 minutes, when the window opens, and when a guildmate's first check of the session arrives, each copy sends a check per **lane**:

| Lane | Channel | Records | Who sends a check | Entries |
| --- | --- | --- | --- | --- |
| guild | GUILD | guild records except recruitment statuses | everyone | members: only themselves; officers: every author |
| officer | OFFICER | officer records | officers | every author |
| recruit | GUILD | recruitment statuses (`RS`) | members whose rank may recruit (others don't keep them) | every author |

A copy compares each entry with its own. Where the checksum differs and the sender's newest is later, it asks (`Q`) for that author's records since its own newest; where the newest times match but the checksums don't (an older record was lost), it asks for all of them, and then not again for 15 minutes for that author. It only asks someone it would accept those records from: the author, an officer, or (recruit and officer lanes) anyone in the lane. Before asking it waits up to 3 seconds and skips if someone else just asked, since the answer goes to the whole channel. A copy answers a given request at most once per 20 seconds, and one requester at most 30 times a minute.

Who passes on what: everyone answers for their own records (fast lane); officers also answer for everyone's guild and officer records, and recruiters for everyone's recruitment statuses (slow lane). The same record is never queued twice while it's waiting to go out.

**Officers by rank.** Members can't see the officer channel. The Guild Master's copy records the rank of everyone it sees on it in `GS:officers` (rank names, `;`-separated), which only the current Guild Master may write. Every copy treats the Guild Master, those ranks, and anyone it has seen on the officer channel as officers.

**A guild channel that doesn't deliver.** The game echoes guild addon messages back to their sender. A copy that has sent 3 or more over 20 seconds and heard none back whispers its messages to an online officer running 2.11 or later instead (its sync checks still go on the guild channel too, so it notices if that starts working). The officer applies that member's records as if they came on the guild channel, passes on only records that member wrote, and answers or forwards their requests.

Records over 150 bytes are sent as `Z` only while every guildmate online with the addon runs 2.10 or later. Copies before 2.11 send their own kind of checks (`D`, `L`, `B`), which 2.11 ignores: they still exchange live changes, but not repairs.

### Record types

| Key | Value | Scope | Who may write it |
| --- | --- | --- | --- |
| `M:<member>` | their main ("" = a main) | guild | ranks with the **links** permission |
| `MS:<member>` | spec override | guild | the member (**own profile** permission) or ranks with **profiles** |
| `RL:<member>` | roles: `tank,healer,damage` | guild | same as `MS` |
| `MP:<member>` | manual professions | guild | same as `MS` |
| `CN:<member>` | `discord;note` | guild | same as `MS` |
| `P:<member>` | spec and professions their addon read | guild | the member only |
| `AV:<member>` | addon version | guild | the member only |
| `SC:<member>` | usual play hours (168 bits as hex) | guild | the member only |
| `RP:<member>:<professionID>` | `profession;id,id,...` (base-36 recipe spell IDs) | guild | the member only |
| `RR:<member>` | completed readiness checks (`ony,brooch`, or `-`) | guild | the member only |
| `HF:<member>` | `1;month;all time;this month;last month id;last month` (each `key=n,...`; month as `202611`, UTC) | guild | the member only |

Hall of Fame extras (Services/HallOfFame.lua): `social` is a count of 15-minute guild chat blocks (you and someone else spoke; 8 a day max), tracked from `CHAT_MSG_GUILD` per character in `Settings().hof[character].social`. Champion titles (`champs`) are never self-reported: officers' copies write `HW:<month>` from `HF:Champions` and every copy counts those. `HF.Plausible` drops records whose numbers beat a per-statistic daily rate since launch (all time), 31 days of it (a month), or all time (a month).
| `HX:<member>` | left out of the Hall of Fame (`1`, or empty = shown) | guild | officers |
| `HW:<month>` | that month's champions, `quests=Name,Name;kills=Name` (written once, from the 2nd of the next month) | guild | officers |
| `HA:<month>` | that month's champions were announced in guild chat (the time; author = who announced) | guild | officers |
| `HC:<member>` | Hall of Fame numbers checked against the game on inspect: `<time>;ok` or `<time>;bad;key=claimed/real,...` | officer | officers |
| `IR:<member>` | when they were reminded to install the addon (the time; the record's author is who reminded them; kept 30 days) | guild | anyone in the guild |
| `PS:<member>` | sharing choices others must respect (`together` = leave me out of Play Together) | guild | the member only |
| `DN:<player>` | `time;what they said` ("" = removed) | guild | anyone adds; removing needs **recruit** |
| `RS:<player>` | `whispered;replied;invited;reply` (kept 14 days) | guild | anyone in the guild |
| `GS:<name>` | guild setting, e.g. `GS:perm_links = "1,3"` | guild | officers; `perm_*` and `officers` only the Guild Master |
| `L:<member>:<id>` | officer log entry | officer | officers |
| `A:<id>` | audit entry | officer | officers (written locally from changes, or by the roster log) |
| `JN:<member>` | `time;inviter` (joined) | officer | officers |
| `RK:<member>` | `time;rank;by` (rank since) | officer | officers |

### Security

A record's author is only what the sender claims; the sender is the one name the game vouches for. So every copy of the addon checks each incoming record (`S:SenderAllowed` in `Core/Sync.lua`):

- The author must be allowed to write the record (their own data, their rank's permissions from the guild roster, or officer), and must be the sender, unless the sender is a **known officer** passing on someone else's record. Officers are known by having sent on the officer channel, which the game only allows officer ranks to do.
- Permission settings (`GS:perm_*`) only count when their author is the current Guild Master.
- "Self-only" records (`P`, `AV`, `SC`, `RP`, `RR`, `PS`) must be authored by the member they're about.
- Records on the officer channel come only from officers, by the game's rules.
- Keys or authors containing `|` are dropped and `|` in values is replaced, so shared text can't inject textures, colors or links. Chunked messages are capped (16 parts, 8 unfinished per sender, no chunks inside chunks).

- Limits on what one guildmate can add (`S:WithinLimits`): values up to 4,000 bytes; recipe lists only under numeric profession IDs and at most 12 per member; and at most 500 new records per 10 minutes from any non-officer sender, so a modified client can't flood everyone's saved data with records it's allowed to write. Officers are exempt, since their repairs legitimately carry hundreds of records.

Your private notes never leave your computer. Officer data goes only over the officer channel.

## WoW: Forever restrictions worth knowing

- **Guild invites from addons are blocked**, in every form: `C_GuildInfo.Invite`, `/ginvite` from a secure macro button, and `/ginvite` put in the chat box by the addon (opening the chat box from addon code taints it). Only `/ginvite` the player types or pastes works, so the Invite prompt shows the command to copy. **Don't open the chat box from addon code**: it would also taint the player's own `/ginvite` for the rest of the session.
- `/who` must run from a hardware event: the Search button is a secure macro button (`W.SecureOverlay`) placed over the visible one.
- Names have two parts and no realms in chat: whisper and invite by `ns.ChatName(full)`.
- The game still tags names with the server shard each player lives on (`Name-CAMWOWUS2Realm2PvP`), different for different guildmates and left off for your own shard. Since 2.7.2 every name is stored plain (`ns.NormalizeName` drops the tag when `ns.NO_REALMS`), records from older copies are tidied on arrival (`Sync.Canon`), and saved data from before is tidied once (`Sync:CanonicalizeSaved`, `DB:AdoptShardGuilds`).
- Whispers are capped at 255 bytes: `RC:Format` uses first names and cuts at whole words when needed.
- `C_Calendar.AddEvent` is restricted; reading the calendar is fine.
- The window templates' close button calls `HideUIPanel`, which does nothing in combat. Every window calls `W.CombatSafeClose(f)` right after it's created so its X hides it directly.
- Addons can't read other players' quests, bags or recipes: each member's own addon reports theirs (`P`, `RP`, `RR`).

## Adding a shared record type

1. Add it to `S.TYPES` in `Core/Sync.lua` with its scope and who may write it (`selfOnly`, `self`, `officer`, `anyone`, or a permission in `DB.PERM_BY_TYPE`). The security checks follow from these.
2. If its key has more than a member (like `L:` or `RP:`), teach `S.ParseKey` where the member name is.
3. Turn the value into working data in `S:Materialize` (or read it straight from the store, as `Recipes.lua` does).
4. Describe it in the comment at the top of `Core/Sync.lua` and in the table above.
5. Records of a type that's later removed are deleted on load by `S:PurgeUnknown`. If old clients would fight over the change, bump `PROTO`.

## Testing

`tests/run.sh` runs every test with LuaJIT (or `lua5.1`). The tests load the real addon files with stand-ins for the game's API and check sync permissions against forged messages, the roster change log, recruitment message lengths and Do Not Whisper rules, the Invite prompt, Play Together, recipes and raid readiness. They don't replace trying it in the game: anything about frames, layout or Blizzard's restrictions needs an in-game check.

## Releasing

Push a version tag; the Release workflow tests, packages and uploads it to GitHub (and CurseForge and Wago once they're set up). The steps and the one-time site setup are in [PUBLISHING.md](PUBLISHING.md).
