#!/usr/bin/env python3
"""Checks that the changelog, the app's version and the website's latest.json agree. Run it before tagging a release.

  - the changelog's newest section is the version in the Xcode project (a release has notes, and the notes are not stale);
  - the version in site/public/latest.json (what Check for Updates announces) has a changelog section, and is not newer
    than the project's version;
  - the JMdict and KANJIDIC2 data in the built dictionaries is not more than a month old: the EDRDG licence asks for "a
    procedure for regular updating", and says failing to keep the data up to date is a violation of it.
latest.json is raised only after a release is published, so it may be one release behind; it may never be ahead.
Exits 1 and says what is wrong; 0 when everything agrees.
"""
import datetime
import json
import os
import re
import sqlite3
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


EDRDG_FILES = ("dictionary-ja.sqlite", "kanji-ja.sqlite")
MAX_DATA_AGE_DAYS = 31
DICTIONARIES = os.path.join(ROOT, "LangCore", "Sources", "LangCore", "Resources", "dictionaries")


def data_dates(directory):
    """Each EDRDG-derived file's source_created date (as the builders record it), or None when the file or the date is missing."""
    dates = {}
    for name in EDRDG_FILES:
        try:
            with sqlite3.connect(f"file:{os.path.join(directory, name)}?mode=ro", uri=True) as db:
                row = db.execute("SELECT value FROM meta WHERE key = 'source_created'").fetchone()
            dates[name] = row[0] if row else None
        except sqlite3.Error:
            dates[name] = None
    return dates


def data_problems(dates, today, max_days=MAX_DATA_AGE_DAYS):
    issues = []
    for name, created in sorted(dates.items()):
        if created is None:
            issues.append(f"{name} is missing, or has no source_created date: run Scripts/build_dictionaries.sh")
            continue
        age = (today - datetime.date.fromisoformat(created)).days
        if age > max_days:
            issues.append(f"{name} is built from EDRDG data of {created}, {age} days old; the licence asks for regular updating, "
                          f"so refresh it (more than {max_days} days is too long): run Scripts/build_dictionaries.sh")
    return issues


def main():
    read = lambda *path: open(os.path.join(ROOT, *path), encoding="utf-8").read()
    issues = problems(read("Kikimi.xcodeproj", "project.pbxproj"), read("CHANGELOG.md"),
                      json.loads(read("site", "public", "latest.json")))
    issues += data_problems(data_dates(DICTIONARIES), datetime.date.today())
    for issue in issues:
        print("MISMATCH:", issue)
    if issues:
        sys.exit(1)
    print("The changelog, the app's version and latest.json agree, and the EDRDG data is recent.")


if __name__ == "__main__":
    main()
