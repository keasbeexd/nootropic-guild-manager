# Events made in game, and in-game sign-ups (3.1)

Design for the NGM Addon and NGM Peon (ngm-hub). Decided with the user on
2026-11-25.

## What players get

- **Create** on the Upcoming Events tab: kind (Dungeon, Raid, Event), title,
  date and time (your own), length, description. The same lengths as NGM
  Peon's form.
- **Edit** and **Cancel** on the event's card: your own events; officers
  anyone's (with NGM Peon: its managers). An event made in game stays
  editable in game after NGM Peon posts it.
- **Cancelled** events stay on the card list, marked Cancelled in red, with
  sign-ups closed, for as long as their Discord post does: NGM Peon's "Clear
  old posts", counted from when it was cancelled in game. With Never, or
  without NGM Peon: until the event would have ended.
- **Sign up** on every event's card: Tank, Healer, DPS, Tentative, Can't come
  for dungeons and raids; Going, Tentative, Can't come for events. Role limits
  and the bench as NGM Peon's (dungeon 1 / 1 / 3 by default). You sign up as
  your main; Change character picks an alt, as on Discord.
- Guilds **without NGM Peon** get all of this through guild sync. Guilds
  **with NGM Peon** get it both ways: made in game, posted in Discord; signed
  up in game, counted on the Discord post, and the other way round.

## Who may create

- **With NGM Peon** (the guild has `GS:peon`): NGM Peon's Event Settings, sent
  to the game as `GS:evranks` = `dungeon=<rank>;raid=<rank>;event=<rank>;officers=<0|1>;keep=<minutes|->`
  (the lowest rank that may create that kind, `-` = managers only; officers:
  whether the dashboard's "Officers can change settings" makes them
  managers; keep: "Clear old posts" in minutes, `-` = Never, so a cancelled
  event leaves the game with its post). Managers always may: the Guild Master, officers if that's on.
  (Discord's Manage Server permission also makes a manager on the dashboard;
  the game can't see it, so those people create on the dashboard.) A member
  has at most 10 upcoming events of their own, as on the dashboard. The
  Create button only offers the kinds your rank may make.
- **Without NGM Peon:** the Guild Master and officers.

## Records (Core/Records.lua)

Every copy judges each record by these rules, as for all records.

    EG:<id>            an event made in game
                       "kind;starts;minutes;creator;state;title;description"
                       id: base-36 creation time + 2 random base-36 digits
                       creator: the character that made it (kept on edits)
                       state: "" on, "x" cancelled
                       numbers base 36; no tabs or line breaks; "|" sent as "/"
    ES:<event>:<member>  a sign-up: "part;picked;time"
                       event: "g<EG id>" or "p<NGM Peon id>"
                       part: tank, healer, dps, going, tentative, absent ("" = withdrawn)
                       picked: the character brought ("" = the member's main)
                       written by the member themselves only
    GS:evranks         who may create, from NGM Peon (above)
    LK:<member>        "1": this character is linked to NGM Peon (written by
                       NGM Peon only; "" = unlinked)
    EL:<NGM Peon id>   NGM Peon's post for an event: "<EG id>;<tank>,<healer>,<dps>"
                       (the event made in game it came from, "" if made on the
                       dashboard; its role limits, "" = no limit; written by
                       NGM Peon only)

- `EG` may be written by the creator (if allowed to create that kind) and by
  officers; edits keep the creator. Past events stop being editable once
  they've started; records for events over 7 days ago are dropped (ttl).
- `ES` is self-only. Sign-ups close when the event starts, as on Discord.
- An event made in game is listed at once for the whole guild.

## With NGM Peon

Nothing new travels in its own line type: NGM Addon 3.0 refuses NGM Peon
codes with lines it doesn't know, so everything below is records (`R` lines,
which 3.0 skips by record type) or extra fields on existing lines.

**Game to NGM Peon (NGM2, NGM Desktop or `/ngm discord`):** `EG` and `ES`
records join M, RL and JN in the `R` lines, under the update code's trust
rule: an officer's or the Guild Master's code carries everyone's, a member's
only their own.

- `EG`: NGM Peon posts it in the kind's channel (Event Settings) with its
  default limits, or edits or cancels the post it made for it. It checks the
  creator's rank against Event Settings (the creator's character must be
  linked: that's how NGM Peon knows the rank, and whose event it is). Each
  `EG` id is posted once (events.game_id).
- `ES`: the sign-up counts on the Discord post (as the character picked, or
  their main). Only linked characters can sign up at all in a guild with NGM
  Peon, in game as on Discord: a character without `LK` gets no sign-up
  buttons, but "Link your characters to sign up: type /ngm link in Discord".
  NGM Peon refuses an `ES` from a character that isn't linked.

**NGM Peon to game (NGMP1, NGM Desktop or `/ngm peon`):**

- `EL:<id>` records link NGM Peon's event to the `EG` it came from, so the
  addon lists it once, as NGM Peon's, with its Discord post; and carry the
  post's role limits. (An `E` line can't grow: the `EV` record it becomes
  ends with the description, and 3.0 copies check its shape.)
- Sign-ups on a linked event: in game they're written under NGM Peon's id
  (`ES:p<id>:...`); ones written before the link (`ES:g<EG id>:...`) are
  read with them, newest per member wins.
- Discord sign-ups come back as `ES:p<id>:<member>` records written by NGM
  Peon (each linked member's main as the member name), so the game shows who
  signed up where, whichever side they used. Newest wins on both sides.
- `GS:evranks` as an `R` line, and `LK:<member>` for every linked character
  (cleared when they unlink). After linking, in-game sign-ups open with the
  next update from NGM Peon; Discord's buttons work at once.

Each event is edited where it was made: events made on the dashboard show
"Made on the dashboard: edit it there" in game instead of Edit and Cancel,
and events made in game show "Made in game: edit it there" on the
dashboard's Create Events tab.

## The window

The Upcoming Events tab gets Create; cards get Sign up, Change character,
Edit and Cancel; the form is a popup window. Both are registered with the
gamepad interface (docs/CONTROLLER.md) and use the game's own dropdowns and
edit boxes, so smart navigation finds them.

## Order of work

1. Records `EG`, `ES`, `GS:evranks` and their rules, with tests (sync sim).
2. Upcoming Events: list `EG` events, the form, Edit and Cancel.
3. Sign-ups: buttons, limits and bench, Change character.
4. NGM Peon: `EG`/`ES` in NGM2; posting, editing, cancelling; sign-ups both
   ways; `GS:evranks` and the `E` link field; tests on both sides with a
   shared code.
5. One test zip for the whole of 3.1 (controller, resets and holidays,
   events) in game, then NGM Peon deployed before the tag.
