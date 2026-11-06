#!/usr/bin/env python3
"""Writes a GitHub release's notes from CHANGELOG.md, so the changelog, the release page and the website say the same.

Usage: python3 -I Scripts/release_notes.py 0.15.1 --zip build/Kikimi-0.15.1-macOS.zip --commit c3185c8 [--tests "394 tests pass"] [--out FILE]

The notes are the version's section of CHANGELOG.md, then what changes with every release: the beta notice, the download
with its checksum, and the standing limits in Release/known-limits.md. Prints to the terminal unless --out is given.
"""
import argparse
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def section(changelog, version):
    """The changelog's text for one version (without its '## x.y.z' line), or None when there is none."""
    match = re.search(rf"^## {re.escape(version)}\s*$", changelog, re.M)
    if not match:
        return None
    rest = changelog[match.end():]
    following = re.search(r"^## ", rest, re.M)
    return (rest[:following.start()] if following else rest).strip("\n")


def checksum(path):
    digest, size = hashlib.sha256(), 0
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def compose(version, body, sha256, size_bytes, commit, limits, tests=None):
    megabytes = round(size_bytes / 1e6)
    name = f"Kikimi-{version}-macOS.zip"
    parts = [
        f"## Kikimi {version} (beta)",
        "",
        "**This is a beta, and the app is not notarized.** macOS blocks it the first time you open it; the README explains how "
        "to open it anyway (Install). Or build from source, which avoids the warning.",
        "",
        # The changelog's own lead line is "*date.* Summary"; the date is on the release page already.
        re.sub(r"^\*[^*]+\.\*\s*", "", body.strip(), count=1),
        "",
        "### Download and verify",
        f"`{name}` ({megabytes} MB), built from the `v{version}` tag (commit `{commit}`). Check it before opening:",
        "",
        "```",
        f"shasum -a 256 {name}",
        sha256,
        "```",
        "",
        "A matching checksum shows you have the file published here, not that the app is safe. The code is public, and you can "
        "build the same version from the tag. The repository is scanned with CodeQL and watched by Dependabot, which looks for "
        "common mistakes and doesn't show the code is free of problems.",
        "",
        "### Known limits",
        limits.strip(),
    ]
    if tests:
        parts += ["", "### Under the hood", tests]
    return "\n".join(parts) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version")
    parser.add_argument("--zip", required=True, help="the file you will attach")
    parser.add_argument("--commit", required=True, help="the commit the tag is on")
    parser.add_argument("--tests", help='one line for "Under the hood", such as "394 tests pass"')
    parser.add_argument("--out")
    args = parser.parse_args(argv)
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as f:
        body = section(f.read(), args.version)
    if body is None:
        sys.exit(f"CHANGELOG.md has no section for {args.version}. Write it first.")
    with open(os.path.join(ROOT, "Release", "known-limits.md"), encoding="utf-8") as f:
        limits = f.read()
    sha256, size = checksum(args.zip)
    text = compose(args.version, body, sha256, size, args.commit, limits, args.tests)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {args.out}")
    else:
        print(text, end="")


if __name__ == "__main__":
    main(sys.argv[1:])
