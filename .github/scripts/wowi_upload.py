#!/usr/bin/env python3
"""Uploads a release to WoWInterface.

The BigWigs packager uploads to WoWInterface for other game types but skips
WoW: Forever ("not supported"), although WoWInterface has a Forever game
version. So the workflow tells the packager to leave WoWInterface out (-w 0)
and this does the same upload it would, through the same API
(https://api.wowinterface.com/addons/update, answered 202 when taken).

Reads:
  NootropicGuildManager.toc   ## X-WoWI-ID (nothing to do without one) and
                              ## Interface (picks the matching game version)
  CHANGELOG.md                the release's section, sent as the changelog
  .release/NootropicGuildManager-<tag>-forever.zip   the packager's zip
  WOWI_API_TOKEN              repository secret WOWI (never printed)
  GITHUB_REF_NAME             the tag, e.g. v3.0.9
With --dry-run it prints what it would send instead of sending it.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

TOC = "NootropicGuildManager.toc"
COMPATIBLE = "https://api.wowinterface.com/addons/compatible.json"
UPDATE = "https://api.wowinterface.com/addons/update"
UA = "ngm-release (+https://github.com/keasbeexd/nootropic-guild-manager)"


def toc_field(text: str, name: str) -> str:
    m = re.search(rf"^## {re.escape(name)}:\s*(\S+)\s*$", text, re.M)
    return m.group(1) if m else ""


def changelog_bbcode(text: str, version: str) -> str:
    """The lines under '## <version>', in WoWInterface's BBCode."""
    out, inside, listing = [], False, False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip() == version
            continue
        if not inside:
            continue
        line = re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", line)
        line = re.sub(r"`([^`]+)`", r"\1", line)
        line = re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r"[url=\2]\1[/url]", line)
        if line.startswith("- "):
            if not listing:
                out.append("[list]")
                listing = True
            out.append("[*]" + line[2:])
            continue
        if listing:
            out.append("[/list]")
            listing = False
        out.append(line)
    if listing:
        out.append("[/list]")
    return "\n".join(out).strip()


def game_version(versions: list, interface: str) -> str:
    """WoWInterface's Forever version for this TOC's interface, else its newest."""
    forever = [v for v in versions if isinstance(v, dict) and v.get("game") == "Forever" and v.get("id")]
    exact = [v["id"] for v in forever if str(v.get("interface")) == interface]
    if exact:
        return exact[0]
    return max((v["id"] for v in forever), key=lambda s: [int(p) for p in re.findall(r"\d+", s)], default="")


def multipart(fields: dict, file_field: str, path: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    with open(path, "rb") as f:
        data = f.read()
    name = os.path.basename(path)
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{name}"\r\n'
                 f"Content-Type: application/zip\r\n\r\n".encode() + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def main() -> int:
    dry = "--dry-run" in sys.argv
    tag = os.environ.get("GITHUB_REF_NAME", "")
    if not re.fullmatch(r"v\d+\.\d+(\.\d+)?", tag):
        print(f"Not a release tag ({tag!r}); nothing to upload to WoWInterface.")
        return 0
    with open(TOC, encoding="utf-8") as f:
        toc = f.read()
    addon_id = toc_field(toc, "X-WoWI-ID")
    if not re.fullmatch(r"\d{1,8}", addon_id):
        print("No X-WoWI-ID in the TOC: not uploading to WoWInterface.")
        return 0
    token = os.environ.get("WOWI_API_TOKEN", "")
    if not token and not dry:
        print("::error::The WOWI secret is empty, so nothing would go to WoWInterface")
        return 1
    version = tag[1:]
    zip_path = os.path.join(".release", f"NootropicGuildManager-{tag}-forever.zip")
    if not os.path.isfile(zip_path):
        print(f"::error::{zip_path} isn't there (did the packager run?)")
        return 1
    req = urllib.request.Request(COMPATIBLE, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        compatible = game_version(json.load(r), toc_field(toc, "Interface"))
    if not compatible:
        print("::error::WoWInterface lists no WoW: Forever game version")
        return 1
    with open("CHANGELOG.md", encoding="utf-8") as f:
        changelog = changelog_bbcode(f.read(), version)
    fields = {"id": addon_id, "version": version, "compatible": compatible, "changelog": changelog or "See the GitHub release."}
    if dry:
        print(json.dumps({**fields, "updatefile": zip_path}, indent=2))
        return 0
    body, ctype = multipart(fields, "updatefile", zip_path)
    req = urllib.request.Request(UPDATE, data=body, method="POST",
                                 headers={"x-api-token": token, "Content-Type": ctype, "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            status = r.status
            answer = r.read(2000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        status, answer = e.code, e.read(2000).decode("utf-8", "replace")
    if status == 202:
        print(f"Uploaded {os.path.basename(zip_path)} ({compatible}) to https://www.wowinterface.com/downloads/info{addon_id}")
        return 0
    print(f"::error::WoWInterface answered HTTP {status}: {answer}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
