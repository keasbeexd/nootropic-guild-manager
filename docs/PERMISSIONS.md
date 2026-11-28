# Permissions, guild rules and the ban list (3.2)

What the Guild Master can lock down, how every copy of the NGM Addon (and
NGM Peon) keeps to it, and the ban list. Ships in 3.2.0 with `/ngm bug`.

Decided (Guild Master, 27 November 2026):

- Permissions live **only on the Permissions page**: in game (its own
  Options page) and on NGM Peon's dashboard (a Permissions tab), NGM
  Peon's Discord permission notes included. Nothing about who-may-do-what
  anywhere else.
- **Only the Guild Master sets them.** Everyone else can see what their own
  rank may do.
- **Ranks only**, no exceptions for single players.
- Each row is one small thing, with a picker: **Everyone**, **Officers**
  (the ranks the game marks Officer), **chosen ranks**, or **Only me**.
  Every default is today's behavior, so nothing changes until the Guild
  Master changes it.

## The rows

Enforcement: **every copy** = a shared change the rule forbids is refused
by every copy (and by NGM Peon), whatever the sender's copy does. **In the
NGM Addon** = something that only happens on the player's own computer: the
NGM Addon hides and blocks it, but a modified copy could still do it (the
page says so). **Officers only, narrower** = data the game only delivers to
officer ranks: the Guild Master can narrow it to some officer ranks, never
widen it.

| Group | Row | Default | Records | Enforced |
|---|---|---|---|---|
| Profiles | Link mains and alts | Officers | `M` | every copy |
| Profiles | Edit their own profile | Everyone | `MS RL MP CN` (own) | every copy |
| Profiles | Edit other guildmates' profiles | Officers | `MS RL MP CN` | every copy |
| Profiles | Choose their own main on NGM Peon's dashboard | Everyone | NGM Peon's links | NGM Peon |
| Events | Create dungeons | Officers (with NGM Peon: its rule today) | `EG` | every copy, NGM Peon |
| Events | Create raids | Officers (same) | `EG` | every copy, NGM Peon |
| Events | Create events | Officers (same) | `EG` | every copy, NGM Peon |
| Events | Edit or cancel anyone's | Officers | `EG` | every copy, NGM Peon |
| Events | Sign up | Everyone | `ES` | every copy, NGM Peon |
| Recruiting | Use the recruiting tools (whispers, the /who button, the Invite prompt) | The game's Invite Member ranks | `RS` | every copy (statuses), in the NGM Addon (whispers) |
| Recruiting | Write the guild's recruitment messages | Only me (and needs the recruiting tools) | `GS:rmsg*` | every copy |
| Recruiting | Add to Do Not Whisper | Everyone (who may use the recruiting tools) | `DN` | every copy |
| Recruiting | Take off Do Not Whisper | The game's Invite Member ranks | `DN` "" | every copy |
| Members | Send install reminders | Everyone | `IR` | every copy |
| Members | Write the install reminder text | Only me | `GS:imsg` | every copy |
| Members | Ban and unban players | Officers | `BN` | every copy |
| Members | See the ban list | Officers | `BN` (shown) | in the NGM Addon |
| Members | See ban reasons | Officers | `BN` reason (shown) | in the NGM Addon |
| Officers | See the Audit tab | Officers | `A` | officers only, narrower |
| Officers | Write in the Officer Log | Officers | `L` | officers only, narrower |
| Hall of Fame | Hide someone from it | Officers | `HX` | every copy |
| Hall of Fame | Announce champions in guild chat | Officers | `HA` | every copy |
| NGM Peon | Bring in NGM Peon's news for the guild | Officers | NGM Peon's records | officers only, narrower |
| NGM Peon | Make codes for NGM Peon | Guild Master and officers | NGM2 | NGM Peon |

**The recruiting rows need the recruiting tools.** The messages and both
Do Not Whisper rows only reach ranks that may also use the recruiting tools,
whatever ranks they're handed to (as the Audit tab needs an officer rank).

**Messages.** The recruitment messages row's people write the guild's
messages (the same rules as today's custom messages: class, race, level and
zone, then the default), shared as one record per rule plus an index
(`GS:rmsg_<id>`, `GS:rmsgs`), since a whole set can pass a record's 4,000
bytes. A switch, **Everyone uses the guild's messages**, locks them: members
can't use their own. Off, the guild's are the starting point and members may
still write their own. The install reminder text works the same way
(`GS:imsg`, with its own switch).

**Feature switches** (on/off for the whole guild, not by rank): Recruiting,
Play Together, Upcoming Events, Overview, Who Can Craft, Hall of Fame, the
Guild Feed's level-up lines, install reminders, Get Connected. Off, the feature is hidden for everyone and its
copies stop sending for it; what's already shared is kept, so turning it
back on loses nothing.

All rules are `GS:perm_<key>` (rank numbers, as the three existing ones) and
`GS:feat_<key>` (`0` off) and `GS:lock_<key>` (`1` locked), written by the Guild Master only (every copy
already refuses `GS:perm_*` from anyone else).

## Keeping every copy on the same rules: the Guild Info code

**Off for now (3.2.0-test3).** On Forever, `C_GuildInfo.GetInfoText` is a
restricted call (`HasRestrictions` in the game's API docs): reading it from
the NGM Addon raised "Interface action failed" (blocked in combat, forbidden
when the Guild Info opened). The NGM Addon neither reads nor writes the
Guild Info; every copy takes rules only from the Guild Master (checked
whoever passes them on). The design below stays for if a safe way to read
it turns up.

As GRM does: a short code in the guild's Guild Info text, which only ranks
the game lets edit it can change.

- **The code** is a fingerprint of every rule: `NGM:7k3f9a2c` (base 36 of a
  hash over the sorted `GS:perm_*`, `GS:feat_*` and `GS:lock_*` records). The
  Guild Info holds 499 characters in all, so it stays one short line.
- **Writing it:** the Guild Master pastes it. The game forbids addons to
  write the Guild Info (`C_GuildInfo.SetInfoText` is blocked even inside
  `pcall`), so the NGM Addon never tries: the Permissions page says whether
  the line is in place and has **Copy the line**, and at login a chat line
  tells the Guild Master when it needs pasting.
- **Checking it:** every copy reads the Guild Info at login and when it
  changes (`C_GuildInfo.GetInfoText`). If its own rules give a different
  fingerprint, it says "Guild rules not up to date", asks guildmates for
  them through guild sync, and meanwhile keeps the **last rules that
  matched** the code (or the defaults, the first time).
- **Trust:** rules count only when they match the code. A copy can't push
  made-up rules, even an officer's, because the game decides who edits the
  Guild Info.
- **No code** in the Guild Info (a guild not using it yet, or a 3.1 Guild
  Master): today's behavior, the Guild Master's records as they are.
- **NGM Peon** gets the rules with the Guild Master's and officers' updates
  (`R` lines `GS:perm_*`, `GS:feat_*`, `GS:lock_*`) and takes them only
  from the Guild Master's own character. Changed on the dashboard (Guild
  Master only), they reach the game at the next sync, and the Guild Master
  is told at their next login to paste the new line.

## The ban list

The same model as GRM's (checked against its code): a ban is about a
person, not one name.

- **Ban:** from the guild roster's right-click menu or the Ban List window
  (by name), with an optional reason. **Their whole family** (their
  main and every alt linked to them) is banned together, each by the
  character's permanent game ID (GUID), so a rename doesn't get around it.
  A name the game can't put an ID to yet (someone never seen) is banned by
  name until it can.
- **Records:** `BN:<character>` = `time;by;guid;main;reason`, shared with
  the guild so every recruiter is warned; the reason shows only to ranks
  allowed to see ban reasons (a permission row). Removing writes `""`.
- **Warnings**, big, on screen and in chat:
  - **at invite:** the moment the game confirms an invite to a banned
    character ("You have invited ... to join your guild": the game's own
    message), "Banned: Marrow (alt of Brindle)", with the reason for those
    who may see it. The NGM Addon can't stop a typed `/ginvite`, so it warns
    at once.
  - **on joining:** if a banned character joins anyway, everyone allowed to
    see the ban list gets the same warning.
  - **in recruiting:** banned players are skipped in `/who` results and the
    recruiting lists, like Do Not Whisper.
- **The Ban List window**, like Do Not Whisper's: everyone banned, with all
  their characters, when, by whom and why (for those who may see it), with
  Unban.
- **NGM Addon only.** NGM Peon keeps no ban data (banned players are often
  outside the guild, and NGM Peon keeps nothing about those) and no account
  fingerprint: no privacy change. It only gets the rules about who may ban
  and see the list.

## NGM Peon

- **A Permissions tab** on the dashboard: the same rows and switches,
  editable by the Guild Master only, and the Discord permissions NGM Peon's
  role is missing for features the guild uses (moved from Guild settings).
- Event Settings' creator ranks and the officers-on-the-dashboard switch
  move into it.
- It applies the same rules to what it takes from the game and to the
  dashboard: a rank that may not edit profiles can't set roles there, a rank
  that may not sign up can't press the post's buttons.

## Older copies

Copies before 3.2 don't know the new rules: they keep offering the actions,
and the changes they make that a rule forbids are refused by everyone else
(a little wasted sync until they update). The Permissions page lists who's
on an older version when a rule depends on it.

## Order of work

1. This doc, signed off.
2. NGM Addon: rule records, checks in every copy, tests (forged changes
   included).
3. NGM Addon: the Permissions page, feature switches, messages, the Guild
   Info code.
4. NGM Addon: the ban list.
5. NGM Peon: rules in, the Permissions tab.
6. One test build; then 3.2.0 with `/ngm bug`.

## Decided at sign-off (27 November 2026)

- The ban list ships in 3.2 with everything else.
- Who sees ban reasons is a permission row like the rest.
- No privacy changes: NGM Peon keeps no ban data and no account fingerprint.
