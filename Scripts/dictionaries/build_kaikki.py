"""Builds dictionary-<code>.sqlite from kaikki.org's extract of English Wiktionary's entries for one language
(that language's words, English definitions).

Usage: python3 -I build_kaikki.py kaikki.org-dictionary-Spanish.jsonl dictionary-es.sqlite es Spanish
Wiktionary content is CC BY-SA 4.0 (and GFDL); extraction by Tatu Ylonen's wiktextract.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictbuild

MAX_GLOSSES_PER_POS = 8   # separate meanings, after repeats are removed


def meanings(gloss):
    """The separate meanings in one gloss, split at ';' outside brackets: "to have; to possess" is two."""
    parts, depth, current = [], 0, ""
    for ch in gloss:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth = max(0, depth - 1)
        if ch == ";" and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    parts.append(current)
    return [p.strip() for p in parts if p.strip()]


def pos_block(entry):
    """(pos, glosses) for one kaikki entry, dropping inflected-form and alternative-form senses. Wiktionary senses often
    repeat each other's meanings ("to have; to possess" then "to have; to possess; to be..."), so each meaning is kept once."""
    glosses, seen = [], set()
    for sense in entry.get("senses", []):
        if sense.get("form_of") or sense.get("alt_of"):
            continue
        chain = sense.get("glosses") or []
        if not chain:
            continue
        for meaning in meanings(chain[-1]):
            if meaning.casefold() not in seen:
                seen.add(meaning.casefold())
                glosses.append(meaning)
    return entry.get("pos", ""), glosses[:MAX_GLOSSES_PER_POS]


def build(input_path, output_path, code, name):
    by_word = {}  # insertion-ordered
    with open(input_path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            if entry.get("lang_code") != code or not entry.get("word"):
                continue
            pos, glosses = pos_block(entry)
            if glosses:
                by_word.setdefault(entry["word"], []).append((pos, glosses))

    rows = [(word, None, dictbuild.format_senses(blocks)) for word, blocks in by_word.items()]
    meta = {
        "source": f"kaikki.org English Wiktionary extract, {name}",
        "source_url": f"https://kaikki.org/dictionary/{name}/kaikki.org-dictionary-{name}.jsonl",
        "license": "CC BY-SA 4.0 and GFDL, Wiktionary contributors",
    }
    return dictbuild.write_database(output_path, rows, meta)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    print(f"{build(*sys.argv[1:])} entries")
