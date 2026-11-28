#!/usr/bin/env python3
"""Posts a release announcement to a Discord channel through a webhook.

Reads (environment):
  DISCORD_RELEASE_WEBHOOK    webhook for the addon's channel: every release,
                             no ping (repository secret; never printed)
  DISCORD_ANNOUNCE_WEBHOOK   webhook for #announcements: feature releases only
                             (versions ending in .0), with a role ping
                             (repository secret; never printed)
  DISCORD_ANNOUNCE_ROLE_ID   the role(s) to ping there, e.g. Announcements;
                             several role IDs separated by commas ping each
                             (repository variable; not secret). No ping without it.
  GITHUB_REF_NAME            the tag, e.g. v2.9.1
  GITHUB_REPOSITORY          owner/repo
Posts: the version, its CHANGELOG.md section, and links to CurseForge, Wago,
WoWInterface (once ## X-WoWI-ID is in the TOC) and the GitHub release. With --dry-run it prints the messages instead of
sending them.
"""
import json
import os
import re
import sys
import urllib.request

CURSEFORGE = "https://www.curseforge.com/wow/addons/nootropic-guild-manager"
WAGO = "https://addons.wago.io/addons/nootropic-guild-manager"
# the same footer on every NGM changelog post (NGM Peon's and NGM Desktop's too)
# (the support line on feature releases only, x.y.0)
FOOTER = "Free for every guild · by keasbeexd"
SUPPORT = "Enjoying NGM? [Ko-fi](https://ko-fi.com/keasbeexd) · [GitHub Sponsors](https://github.com/sponsors/keasbeexd)"
MAX_NOTES = 3500  # an embed description holds 4096 characters


def changelog_section(text: str, version: str) -> str:
    """The lines under '## <version>' up to the next '## ' heading."""
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip() == version
            continue
        if inside:
            out.append(line)
    notes = "\n".join(out).strip()
    if len(notes) > MAX_NOTES:
        notes = notes[:MAX_NOTES].rsplit("\n", 1)[0] + "\n…"
    return notes


def headlines(notes: str) -> str:
    """Just each entry's bold header ("- **Works with a controller.**"), or
    its first sentence when it has none: the full notes are on the What's
    new page, linked under it."""
    out = []
    for line in notes.splitlines():
        m = re.match(r"^(\s*[-*] )\*\*(.+?)\*\*", line)
        if m:
            out.append(f"{m.group(1)}**{m.group(2)}**")
        elif re.match(r"^\s*[-*] ", line):
            out.append(re.split(r"(?<=[.!?])\s", line, maxsplit=1)[0])
    return "\n".join(out)


def is_feature_release(version: str) -> bool:
    """2.10.0, 3.0.0, 3.0 (not 2.9.1): the ones worth a ping."""
    parts = version.split(".")
    return len(parts) == 2 or (len(parts) == 3 and parts[2] == "0")


def wowi_link() -> str:
    """ · [WoWInterface](...) when the TOC has its id, else nothing."""
    try:
        with open("NootropicGuildManager.toc", encoding="utf-8") as f:
            m = re.search(r"^## X-WoWI-ID:\s*(\d{1,8})\s*$", f.read(), re.M)
    except OSError:
        return ""
    return f" · [WoWInterface](https://www.wowinterface.com/downloads/info{m.group(1)})" if m else ""


def payload(version: str, notes: str, repo: str, tag: str, ping_roles: list[str] | None = None) -> dict:
    release = f"https://github.com/{repo}/releases/tag/{tag}"
    body = {
        "username": "Nootropic Guild Manager",
        # only the roles named, and only when asked; never @everyone
        "allowed_mentions": {"parse": [], "roles": ping_roles or []},
        "embeds": [{
            "title": f"Nootropic Guild Manager {version} is out",
            "url": release,
            "description": notes or "See the release notes on GitHub.",
            "color": 0xC79C3E,
            "fields": [{
                "name": "Links",
                "value": f"[CurseForge]({CURSEFORGE}) · [Wago]({WAGO}){wowi_link()} · [GitHub]({release}) · [What's new](https://ngmpeon.app/changelog#addon)"
                         + (f"\n{SUPPORT}" if is_feature_release(version) else ""),
            }],
            "footer": {"text": FOOTER},
        }],
    }
    if ping_roles:
        body["content"] = " ".join(f"<@&{r}>" for r in ping_roles)
    return body


def send(url: str, body: dict, label: str) -> None:
    if not url.startswith("https://discord.com/api/webhooks/"):
        raise SystemExit(f"::error::{label} isn't a Discord webhook URL")
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "ngm-release"})
    with urllib.request.urlopen(req, timeout=15) as r:
        print(f"Posted to {label} (HTTP {r.status}).")


def main() -> int:
    dry = "--dry-run" in sys.argv
    tag = os.environ.get("GITHUB_REF_NAME", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "keasbeexd/nootropic-guild-manager")
    if not re.fullmatch(r"v\d+\.\d+(\.\d+)?", tag):
        print(f"Not a version tag ({tag!r}); nothing to announce.")
        return 0
    version = tag[1:]
    with open("CHANGELOG.md", encoding="utf-8") as f:
        notes = headlines(changelog_section(f.read(), version))
    # one role ID, or several separated by commas: each is pinged
    roles = [r.strip() for r in os.environ.get("DISCORD_ANNOUNCE_ROLE_ID", "").split(",") if r.strip()]
    if any(not re.fullmatch(r"\d{17,20}", r) for r in roles):
        print("::warning::DISCORD_ANNOUNCE_ROLE_ID isn't a role ID (or comma-separated role IDs); posting without a ping")
        roles = []
    roles = list(dict.fromkeys(roles))[:5]
    feature = is_feature_release(version)
    posts = [("DISCORD_RELEASE_WEBHOOK", payload(version, notes, repo, tag))]
    if feature:
        posts.append(("DISCORD_ANNOUNCE_WEBHOOK", payload(version, notes, repo, tag, roles or None)))
    for env_name, body in posts:
        if dry:
            print(f"--- {env_name} ---")
            print(json.dumps(body, indent=2))
            continue
        url = os.environ.get(env_name, "")
        if not url:
            print(f"No {env_name} secret: skipping that post.")
            continue
        send(url, body, env_name)
    if not feature:
        print(f"{version} is a fix release: not posted to #announcements.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
