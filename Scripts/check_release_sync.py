#!/usr/bin/env python3
"""Checks that the changelog, the app's version and the website's latest.json agree. Run it before tagging a release.

  - the changelog's newest section is the version in the Xcode project (a release has notes, and the notes are not stale);
  - the version in site/public/latest.json (what Check for Updates announces) has a changelog section, and is not newer
    than the project's version.
latest.json is raised only after a release is published, so it may be one release behind; it may never be ahead.
Exits 1 and says what is wrong; 0 when everything agrees.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def project_version(pbxproj):
    """The MARKETING_VERSION shared by every configuration, or an error string."""
    versions = set(re.findall(r"MARKETING_VERSION = ([0-9.]+);", pbxproj))
    if len(versions) != 1:
        return None, f"the Xcode project has {len(versions)} different MARKETING_VERSION values: {sorted(versions)}"
    return versions.pop(), None


def changelog_versions(changelog):
    """The versions with a section, newest first as written."""
    return re.findall(r"^## ([0-9]+\.[0-9]+\.[0-9]+)\s*$", changelog, re.M)


def problems(pbxproj, changelog, latest):
    found, error = project_version(pbxproj)
    if error:
        return [error]
    sections, issues = changelog_versions(changelog), []
    if found not in sections:
        issues.append(f"CHANGELOG.md has no section for {found}, the version in the Xcode project")
    elif sections[0] != found:
        issues.append(f"CHANGELOG.md's newest section is {sections[0]}, but the Xcode project is {found}")
    announced = latest["version"]
    if announced not in sections:
        issues.append(f"latest.json announces {announced}, which has no section in CHANGELOG.md")
    if version_tuple(announced) > version_tuple(found):
        issues.append(f"latest.json announces {announced}, newer than the Xcode project's {found}")
    return issues


def main():
    read = lambda *path: open(os.path.join(ROOT, *path), encoding="utf-8").read()
    issues = problems(read("Kikimi.xcodeproj", "project.pbxproj"), read("CHANGELOG.md"),
                      json.loads(read("site", "public", "latest.json")))
    for issue in issues:
        print("MISMATCH:", issue)
    if issues:
        sys.exit(1)
    print("The changelog, the app's version and latest.json agree.")


if __name__ == "__main__":
    main()
