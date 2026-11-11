#!/usr/bin/env python3
"""Posts a release announcement to a Discord channel through a webhook.

Reads (environment):
  DISCORD_RELEASE_WEBHOOK  the webhook URL (a repository secret; never printed)
  GITHUB_REF_NAME          the tag, e.g. v2.9.1
  GITHUB_REPOSITORY        owner/repo
Posts: the version, its CHANGELOG.md section, and links to CurseForge, Wago
and the GitHub release. Pings nobody. With --dry-run it prints the message
instead of sending it.
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


def payload(version: str, notes: str, repo: str, tag: str) -> dict:
    release = f"https://github.com/{repo}/releases/tag/{tag}"
    return {
        "username": "Nootropic Guild Manager",
        "allowed_mentions": {"parse": []},
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
    body = payload(version, notes, repo, tag)
    if dry:
        print(json.dumps(body, indent=2))
        return 0
    url = os.environ.get("DISCORD_RELEASE_WEBHOOK", "")
    if not url:
        print("No DISCORD_RELEASE_WEBHOOK secret: skipping the Discord announcement.")
        return 0
    if not url.startswith("https://discord.com/api/webhooks/"):
        print("::error::DISCORD_RELEASE_WEBHOOK isn't a Discord webhook URL")
        return 1
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "ngm-release"})
    with urllib.request.urlopen(req, timeout=15) as r:
        print(f"Announced {version} on Discord (HTTP {r.status}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
