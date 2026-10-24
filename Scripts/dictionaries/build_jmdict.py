"""Builds dictionary-ja.sqlite from JMdict_e (EDRDG, English glosses).

Usage: python3 -I build_jmdict.py JMdict_e.gz dictionary-ja.sqlite
JMdict is (c) the Electronic Dictionary Research and Development Group, CC BY-SA 4.0.
"""
import gzip
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictbuild

STANDARD_ENTITIES = "amp|lt|gt|quot|apos"
COMMON_PRIORITIES = {"news1", "ichi1", "spec1", "spec2", "gai1"}


def parse(raw):
    """Returns (root, created_comment). JMdict declares ~300 entities (part-of-speech names) in its DTD; keep
    them as their short names instead of letting expat expand them to long descriptions."""
    created = re.search(r"JMdict created: ([0-9-]+)", raw)
    raw = re.sub(r"<!DOCTYPE.*?\]>", "", raw, flags=re.S)
    raw = re.sub(rf"&(?!(?:{STANDARD_ENTITIES});)([A-Za-z0-9-]+);", r"{\1}", raw)
    return ET.fromstring(raw), created.group(1) if created else "unknown"


def strip_braces(text):
    return text.strip("{}")


def is_common_tags(tags):
    return any(t in COMMON_PRIORITIES for t in tags)


def entry_rows(entry):
    """Rows of (headword, reading, gloss, common). `common` is judged for each spelling on its own: an entry such as
    時 (とき) lists 秋 as an alternate spelling with no priority of its own, and must not outrank the real 秋 (あき)."""
    kanji = [(k.findtext("keb"), [strip_braces(i.text) for i in k.findall("ke_inf")],
              is_common_tags([p.text for p in k.findall("ke_pri")])) for k in entry.findall("k_ele")]
    readings = []
    for r in entry.findall("r_ele"):
        readings.append({
            "reb": r.findtext("reb"),
            "common": is_common_tags([p.text for p in r.findall("re_pri")]),
            "restrict": [x.text for x in r.findall("re_restr")],
            "no_kanji": r.find("re_nokanji") is not None,
        })

    senses, pos, usually_kana = [], [], False
    for s in entry.findall("sense"):
        tags = [strip_braces(p.text) for p in s.findall("pos")]
        pos = tags or pos  # an empty <pos> list means "same as the previous sense"
        if "{uk}" in [m.text for m in s.findall("misc")]:
            usually_kana = True
        glosses = [g.text for g in s.findall("gloss") if g.text]
        if glosses:
            senses.append((", ".join(pos), glosses))
    if not senses:
        return []
    gloss = dictbuild.format_senses(senses)

    rows = []
    for keb, _info, keb_common in kanji:
        for r in readings:
            if r["no_kanji"] or (r["restrict"] and keb not in r["restrict"]):
                continue
            rows.append((keb, r["reb"], gloss, keb_common))
    if not kanji or usually_kana:
        for r in readings:
            rows.append((r["reb"], r["reb"], gloss, r["common"]))
    return rows


def build(input_path, output_path):
    opener = gzip.open if input_path.endswith(".gz") else open
    with opener(input_path, "rt", encoding="utf-8") as f:
        root, created = parse(f.read())
    common, rest = [], []
    for entry in root.findall("entry"):
        for headword, reading, gloss, is_common in entry_rows(entry):
            (common if is_common else rest).append((headword, reading, gloss))
    meta = {
        "source": "JMdict_e",
        "source_url": "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz",
        "source_created": created,
        "license": "CC BY-SA 4.0, Electronic Dictionary Research and Development Group",
    }
    return dictbuild.write_database(output_path, common + rest, meta)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(f"{build(sys.argv[1], sys.argv[2])} entries")
