"""Builds kanji-ja.sqlite from KANJIDIC2 (EDRDG): each kanji with its on'yomi, kun'yomi and English meanings.

Usage: python3 -I build_kanjidic.py kanjidic2.xml.gz kanji-ja.sqlite
KANJIDIC2 is (c) the Electronic Dictionary Research and Development Group, CC BY-SA 4.0.
Left out on purpose: name readings (nanori), other languages' meanings, stroke counts and index numbers.
"""
import gzip
import os
import sqlite3
import sys
import xml.etree.ElementTree as ET

MAX_MEANINGS = 6


def kanji_rows(root):
    """(literal, on_yomi, kun_yomi, meanings) for each kanji that has a reading or a meaning. Readings are joined with
    '、', meanings with '; '. On'yomi stay in katakana and kun'yomi in hiragana, as KANJIDIC2 has them, which is how
    the two are told apart on the page. A '.' in a kun'yomi marks where the okurigana begins (た.べる)."""
    for character in root.findall("character"):
        literal = character.findtext("literal")
        on, kun, meanings = [], [], []
        for group in character.iterfind("reading_meaning/rmgroup"):
            on += [r.text for r in group.findall("reading") if r.get("r_type") == "ja_on" and r.text]
            kun += [r.text for r in group.findall("reading") if r.get("r_type") == "ja_kun" and r.text]
            # A meaning with no m_lang attribute is English.
            meanings += [m.text for m in group.findall("meaning") if m.get("m_lang") is None and m.text]
        if literal and (on or kun or meanings):
            yield literal, "、".join(on), "、".join(kun), "; ".join(meanings[:MAX_MEANINGS])


def build(input_path, output_path):
    opener = gzip.open if input_path.endswith(".gz") else open
    with opener(input_path, "rb") as f:
        root = ET.parse(f).getroot()
    created = root.findtext("header/date_of_creation") or "unknown"
    if os.path.exists(output_path):
        os.remove(output_path)
    db = sqlite3.connect(output_path)
    db.execute("PRAGMA journal_mode = DELETE")
    db.execute("CREATE TABLE kanji (literal TEXT PRIMARY KEY, on_yomi TEXT NOT NULL, kun_yomi TEXT NOT NULL, meaning TEXT NOT NULL) WITHOUT ROWID")
    db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.executemany("INSERT INTO kanji VALUES (?, ?, ?, ?)", kanji_rows(root))
    db.executemany("INSERT INTO meta VALUES (?, ?)", sorted({
        "source": "KANJIDIC2",
        "source_url": "https://www.edrdg.org/kanjidic/kanjidic2.xml.gz",
        "source_created": created,
        "license": "CC BY-SA 4.0, Electronic Dictionary Research and Development Group",
    }.items()))
    db.commit()
    count = db.execute("SELECT COUNT(*) FROM kanji").fetchone()[0]
    db.execute("VACUUM")
    db.close()
    return count


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(f"{build(*sys.argv[1:])} kanji")
