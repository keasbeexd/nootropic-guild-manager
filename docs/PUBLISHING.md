# Publishing releases

Releases are automatic: push a version tag and the [Release workflow](../.github/workflows/release.yml) runs the offline tests, packages the addon with the [BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it everywhere it's set up for.

| Where | How players get it | Set up |
| --- | --- | --- |
| **GitHub** releases | WowUp's "Install from URL", or by hand | Works now: nothing to set up |
| **CurseForge** | the CurseForge app, WowUp (CurseForge source) | Set up: [project 1793021](https://www.curseforge.com/wow/addons/nootropic-guild-manager), `CURSEFORGE` secret |
| **Wago Addons** | the Wago app, WowUp (Wago source) | Set up: [project 4N2baaNL](https://addons.wago.io/addons/nootropic-guild-manager), `WAGO` secret |
| **WowUp** | installs from GitHub, CurseForge and Wago | Nothing extra: it reads the other three |
| WoWInterface | — | Has no WoW: Forever category, so the packager skips it |

The zip is named `NootropicGuildManager-v1.2.3-forever.zip` and comes with a `release.json` saying it's for WoW: Forever. WowUp uses either one to pick the right file. Only the addon goes in the zip; `.pkgmeta` leaves out the docs, tests, preview and changelog.

## Making a release

1. Bump `## Version:` in `NootropicGuildManager.toc`.
2. Add the release at the top of `CHANGELOG.md` (it becomes the release notes on every site).
3. Merge to `master`, then tag and push:
   ```bash
   git tag -a v1.2.3 -m "Nootropic Guild Manager 1.2.3"
   git push origin v1.2.3
   ```
4. Watch it under the repository's **Actions** tab. If the tests fail, nothing is published: fix, delete the tag (`git push origin :refs/tags/v1.2.3`), and tag again.

Tags with `alpha` or `beta` in them (`v1.3.0-beta1`) are published as test versions, which most players don't get by default.

## One-time setup for CurseForge and Wago

Nothing is published to a site until both of its pieces are in place, so these can be done one at a time.

### CurseForge

1. Create the project at [authors.curseforge.com](https://authors.curseforge.com) (World of Warcraft, category Guild). New projects are reviewed by CurseForge before they're public.
2. Copy the **Project ID** from the project's "About Project" box into the TOC:
   ```toc
   ## X-Curse-Project-ID: 123456
   ```
3. Create an API token at [CurseForge > API tokens](https://authors.curseforge.com/#/settings/api-tokens).
4. In the GitHub repository: **Settings > Secrets and variables > Actions > New repository secret**, name `CURSEFORGE`, value the token.

### Wago Addons

1. Create the project at [addons.wago.io](https://addons.wago.io) (sign in, then the developer dashboard).
2. Copy its **project ID** from the dashboard into the TOC:
   ```toc
   ## X-Wago-ID: aBcD1234
   ```
3. Create an API token at [Wago > API keys](https://addons.wago.io/account/apikeys).
4. Add it as a repository secret named `WAGO`.

The workflow passes these to the packager as `CF_API_KEY` and `WAGO_API_TOKEN`. If a project ID is in the TOC but its secret is empty, the release stops at **Check upload tokens** instead of quietly skipping that site.

### Discord announcements (optional)

Each release posts to Discord: the version, its CHANGELOG.md section, and links to CurseForge, Wago and the GitHub release.
- **Every release** → the addon's channel (#guild-manager-addon), **no ping**. Posts appear as **Minor NGM Release** (fixes, like 2.9.1) or **Major NGM Release** (versions ending in `.0`).
- **Feature releases** (versions ending in `.0`, like 2.10.0 or 3.0.0) → also **#announcements**, pinging one role (Announcements). Fix releases (2.9.1) never ping.

Setup:
1. In Discord, create two webhooks: **Server Settings → Integrations → Webhooks → New Webhook**, one for #guild-manager-addon and one for #announcements. Copy each URL. They're secrets: anyone with one can post there.
2. In the GitHub repository, go to **Settings → Secrets and variables → Actions**:
   - secret `DISCORD_RELEASE_WEBHOOK` = the #guild-manager-addon URL
   - secret `DISCORD_ANNOUNCE_WEBHOOK` = the #announcements URL
   - **variable** (Variables tab) `DISCORD_ANNOUNCE_ROLE_ID` = the Announcements role's ID (Discord: Server Settings → Roles → right-click the role → Copy Role ID, with Developer Mode on). Not a secret.
3. Optional test, from the repository folder (`--dry-run` only prints):
   ```bash
   DISCORD_RELEASE_WEBHOOK='paste-url' GITHUB_REF_NAME=v2.9.1 python3 .github/scripts/discord_release.py
   ```

Missing secrets just skip their post. If Discord is down, the step fails but the release (already uploaded) doesn't. Nothing but the one role is ever pinged (never @everyone).

## Rules the sites share

- Blizzard's [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534) applies: the addon is free, has no ads, and doesn't ask for donations in game. Donation links (GitHub Sponsors, Ko-fi) belong on the project pages and the repository, never inside the addon.
- Use the same name, description and logo (`docs/logo.svg`; most sites want a square PNG: render it with `rsvg-convert -w 400 -h 400 docs/logo.svg -o logo.png`) and screenshots on every site.
- Screenshots live in `docs/screenshots/` (the README shows them too). Blur other players' names before publishing one: guildmates, recruits and anyone on the Do Not Whisper list.

## Security of the workflow

- It runs only when you push a tag, never for pull requests, so code from forks can't reach the tokens.
- Actions are pinned to exact commits (`actions/checkout` v7.0.1, `BigWigsMods/packager` v2.6.1). To update one, check the new release's notes, wait until it's been out a couple of weeks, and pin its commit.
- The job can only write releases (`permissions: contents: write`), and the checkout doesn't keep the GitHub token.
- Tokens are repository secrets: GitHub hides them in logs. If one leaks, revoke it on its site and add a new one.
