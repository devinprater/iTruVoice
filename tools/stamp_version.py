#!/usr/bin/env python3
"""Stamp the app's version and build into the built .app's plists.

The About screen reads CFBundleShortVersionString and CFBundleVersion from the
bundle, so those two values are the only thing that makes it truthful. xtool
generates the plist from xtool.yml and has no field for either (`version: 1` in
that file is the SCHEMA version, not the app's), so every build this repository
ever cut said 1.0.0 (1) while the tags reached v1.0.3 -- an About screen that
misreports the build is worse than no About screen, because a bug report names
the wrong version and the fix is looked for in the wrong place.

So the values are stamped here, from the release tag, after xtool has built the
bundle and before the .ipa is assembled. Both plists are stamped: the app's and
the provider extension's, which the system reads separately.

Usage:
    stamp_version.py APP_DIR VERSION [--build N]
    stamp_version.py APP_DIR --from-tag v1.2.3
"""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys


def version_from_tag(tag: str) -> str:
    """v1.2.3 -> 1.2.3. A tag that is not a version is an error, not a guess."""
    cleaned = tag[1:] if tag.startswith("v") else tag
    if not re.fullmatch(r"\d+(\.\d+)*", cleaned):
        sys.exit(f"tag is not a version: {tag}")
    return cleaned


def build_number(version: str) -> str:
    """A build number that cannot go backwards as the version rises.

    NOT the sum of the parts: 1.0.12 sums to 13, but 1.1.0 would sum to 2 --
    a lower build number for a higher version, which App Store Connect refuses
    outright ("must be higher than the previously uploaded build"). Weighting
    each field instead gives 1.0.12 -> 10012 and 1.1.0 -> 10100, so the number
    only ever moves forward.

    Assumes each field stays under 100; a version with a 3-digit minor needs the
    weight raised rather than silently colliding.
    """
    parts = [int(p) for p in version.split(".")]
    while len(parts) < 3:
        parts.append(0)
    if any(p > 99 for p in parts):
        sys.exit(f"version field over 99 in {version}; build numbering needs revision")
    return str(parts[0] * 10000 + parts[1] * 100 + parts[2])


def stamped(path: str, version: str, build: str) -> str | None:
    """Set both keys in one plist. Returns a note, or None when already right."""
    with open(path, "rb") as f:
        plist = plistlib.load(f)

    if "CFBundleShortVersionString" not in plist or "CFBundleVersion" not in plist:
        sys.exit(f"{path}: has no version keys to stamp; wrong file?")

    if (plist["CFBundleShortVersionString"] == version
            and plist["CFBundleVersion"] == build):
        return None

    before = f"{plist['CFBundleShortVersionString']} ({plist['CFBundleVersion']})"
    plist["CFBundleShortVersionString"] = version
    plist["CFBundleVersion"] = build
    with open(path, "wb") as f:
        plistlib.dump(plist, f)
    return f"{os.path.basename(os.path.dirname(path))}: {before} -> {version} ({build})"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", help="the built .app directory")
    parser.add_argument("version", nargs="?", help="CFBundleShortVersionString")
    parser.add_argument("--from-tag", help="take the version from a git tag")
    parser.add_argument("--build", help="CFBundleVersion (default: derived)")
    args = parser.parse_args()

    if bool(args.version) == bool(args.from_tag):
        sys.exit("give exactly one of VERSION or --from-tag")
    version = version_from_tag(args.from_tag) if args.from_tag else args.version
    if not re.fullmatch(r"\d+(\.\d+)*", version):
        sys.exit(f"not a version number: {version}")
    build = args.build or build_number(version)

    if not os.path.isdir(args.app):
        sys.exit(f"no such app: {args.app}")

    # Every plist inside the bundle that declares a version, the extension's
    # included: the system reads the extension's separately, and a mismatch
    # between the two is what makes an install fail.
    targets = []
    for root, _dirs, files in os.walk(args.app):
        for name in files:
            if name == "Info.plist":
                targets.append(os.path.join(root, name))
    if not targets:
        sys.exit(f"no Info.plist anywhere in {args.app}")

    changed = 0
    for path in sorted(targets):
        note = stamped(path, version, build)
        print(note if note else f"{path}: already {version} ({build})")
        if note:
            changed += 1

    print(f"{len(targets)} plist(s) checked, {changed} stamped: {version} ({build})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
