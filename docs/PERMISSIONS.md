# Permissions, guild rules and the ban list (3.2, draft for sign-off)

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
| Events | Create dungeons | Officers (with NGM Peon: its rule today) | `EG` | every copy, NGM Peon |
| Events | Create raids | Officers (same) | `EG` | every copy, NGM Peon |
| Events | Create events | Officers (same) | `EG` | every copy, NGM Peon |
| Events | Edit or cancel anyone's | Officers | `EG` | every copy, NGM Peon |
| Events | Sign up | Everyone | `ES` | every copy, NGM Peon |
| Recruiting | Use the recruiting tools (whispers, the /who button, the Invite prompt) | The game's Invite Member ranks | `RS` | every copy (statuses), in the NGM Addon (whispers) |
| Recruiting | Write the guild's recruitment messages | Only me | `GS:rmsg*` | every copy |
| Recruiting | Add to Do Not Whisper | Everyone | `DN` | every copy |
| Recruiting | Take off Do Not Whisper | The game's Invite Member ranks | `DN` "" | every copy |
| Members | Send install reminders | Everyone | `IR` | every copy |
| Members | Write the install reminder text | Only me | `GS:imsg` | every copy |
| Members | Ban and unban players | Officers | `BN` | every copy |
| Members | See the ban list | Officers | `BN` (shown) | in the NGM Addon |
| Officers | See the Audit tab | Officers | `A` | officers only, narrower |
| Hall of Fame | Hide someone from it | Officers | `HX` | every copy |
| Hall of Fame | Announce champions in guild chat | Officers | `HA` | every copy |
| NGM Peon | Bring in NGM Peon's news for the guild | Officers | NGM Peon's records | officers only, narrower |
| NGM Peon | Make codes for NGM Peon | Guild Master and officers | NGM2 | NGM Peon |

**Messages.** The recruitment messages row's people write the guild's
messages (the same rules as today's custom messages: class, race, level and
zone, then the default), shared as one record per rule plus an index
(`GS:rmsg_<id>`, `GS:rmsgs`), since a whole set can pass a record's 4,000
bytes. A switch, **Everyone uses the guild's messages**, locks them: members
can't use their own. Off, the guild's are the starting point and members may
still write their own. The install reminder text works the same way
(`GS:imsg`, with its own switch).

**Feature switches** (on/off for the whole guild, not by rank): Recruiting,
Play Together, Hall of Fame, the Guild Feed's level-up lines, install
reminders, Get Connected. Off, the feature is hidden for everyone, and its
shared changes are refused.

All rules are `GS:perm_<key>` (rank numbers, as the three existing ones) and
`GS:feat_<key>` (`0` off), written by the Guild Master only (every copy
already refuses `GS:perm_*` from anyone else).

## Keeping every copy on the same rules: the Guild Info code

As GRM does: a short code in the guild's Guild Info text, which only ranks
the game lets edit it can change.

- **The code** is a fingerprint of every rule: `NGM:7k3f9a2c` (base 36 of a
  hash over the sorted `GS:perm_*`, `GS:feat_*` and message records). The
  Guild Info holds 499 characters in all, so it stays one short line.
- **Writing it:** whenever the Guild Master changes a rule, their copy
  updates the line in the Guild Info by itself (`C_GuildInfo.SetInfoText`,
  out of combat; the Guild Master can always edit it). If the game doesn't
  let it, the Permissions page shows the line to paste.
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
  (`R` lines `GS:perm_*`, `GS:feat_*`), and checks the fingerprint too.
  Changed on the dashboard (Guild Master only), they reach the game at the
  next sync, and the Guild Master's game updates the code at their next
  login.

## The ban list

The same model as GRM's (checked against its code): a ban is about a
person, not one name.

- **Ban:** from a profile, the guild roster's right-click menu, the Ban List
  window or by name, with an optional reason. **Their whole family** (their
  main and every alt linked to them) is banned together, each by the
  character's permanent game ID (GUID), so a rename doesn't get around it.
  A name the game can't put an ID to yet (someone never seen) is banned by
  name until it can.
- **Records:** `BN:<character>` = `time;by;guid;main` (shared with the
  guild, so every recruiter is warned) and `BR:<character>` = the reason
  (officer channel: officers only). Removing writes `""`.
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
  their characters, when, by whom and why (for those who may see it),
  searchable, with Remove.
- **With NGM Peon:** a ban of a member who linked keeps a one-way
  fingerprint of their Battle.net account (a keyed hash: it can't be turned
  back into the account), so any character on that account is flagged if
  they ever link again, and that reaches the game. To have it at ban time,
  NGM Peon would keep that fingerprint for every linked member (the privacy
  page says so). Optionally, `/ngm link` refuses a banned account.

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
5. NGM Peon: rules in, the Permissions tab, the ban fingerprint.
6. One test build; then 3.2.0 with `/ngm bug`.

## Still open

1. The ban list in 3.2 with the rest, or 3.3 on its own?
2. Ban reasons: officers only (as above), or everyone who may see the list?
3. NGM Peon keeping an account fingerprint for every linked member (for
   bans), and refusing `/ngm link` from a banned account: yes or no?
