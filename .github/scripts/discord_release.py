#!/usr/bin/env python3
"""Posts a release announcement to a Discord channel through a webhook.

Reads (environment):
  DISCORD_RELEASE_WEBHOOK    webhook for the addon's channel: every release,
                             no ping (repository secret; never printed)
  DISCORD_ANNOUNCE_WEBHOOK   webhook for #announcements: feature releases only
                             (versions ending in .0), with a role ping
                             (repository secret; never printed)
  DISCORD_ANNOUNCE_ROLE_ID   the role to ping there, e.g. Announcements
                             (repository variable; not secret). No ping without it.
  GITHUB_REF_NAME            the tag, e.g. v2.9.1
  GITHUB_REPOSITORY          owner/repo
Posts: the version, its CHANGELOG.md section, and links to CurseForge, Wago
and the GitHub release. With --dry-run it prints the messages instead of
sending them.
"""
import json
import os
import re
import sys
import urllib.request

CURSEFORGE = "https://www.curseforge.com/wow/addons/nootropic-guild-manager"
WAGO = "https://addons.wago.io/addons/nootropic-guild-manager"
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


def is_feature_release(version: str) -> bool:
    """2.10.0, 3.0.0, 3.0 (not 2.9.1): the ones worth a ping."""
    parts = version.split(".")
    return len(parts) == 2 or (len(parts) == 3 and parts[2] == "0")


# The name the post appears under in Discord.
MINOR_NAME = "Minor NGM Release"   # fixes: 2.9.1
MAJOR_NAME = "Major NGM Release"   # feature releases: 2.10.0, 3.0.0


def payload(version: str, notes: str, repo: str, tag: str, ping_role: str | None = None) -> dict:
    release = f"https://github.com/{repo}/releases/tag/{tag}"
    body = {
        "username": MAJOR_NAME if is_feature_release(version) else MINOR_NAME,
        # only the one role, and only when asked; never @everyone
        "allowed_mentions": {"parse": [], "roles": [ping_role] if ping_role else []},
        "embeds": [{
            "title": f"Nootropic Guild Manager {version} is out",
            "url": release,
            "description": notes or "See the release notes on GitHub.",
            "color": 0xC79C3E,
            "fields": [{
                "name": "Get it",
                "value": f"[CurseForge]({CURSEFORGE}) · [Wago]({WAGO}) · [GitHub]({release})\n"
                         "WowUp and the CurseForge app pick it up automatically.",
            }],
        }],
    }
    if ping_role:
        body["content"] = f"<@&{ping_role}>"
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
        notes = changelog_section(f.read(), version)
    role = os.environ.get("DISCORD_ANNOUNCE_ROLE_ID", "").strip()
    if role and not re.fullmatch(r"\d{17,20}", role):
        print("::warning::DISCORD_ANNOUNCE_ROLE_ID isn't a role ID; posting without a ping")
        role = ""
    feature = is_feature_release(version)
    posts = [("DISCORD_RELEASE_WEBHOOK", payload(version, notes, repo, tag))]
    if feature:
        posts.append(("DISCORD_ANNOUNCE_WEBHOOK", payload(version, notes, repo, tag, role or None)))
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
