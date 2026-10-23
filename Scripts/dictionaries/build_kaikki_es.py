"""Builds dictionary-es.sqlite from kaikki.org's extract of English Wiktionary's Spanish entries
(Spanish words, English definitions).

Usage: python3 -I build_kaikki_es.py kaikki.org-dictionary-Spanish.jsonl dictionary-es.sqlite
Wiktionary content is CC BY-SA 4.0 (and GFDL); extraction by Tatu Ylonen's wiktextract.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictbuild

MAX_GLOSSES_PER_POS = 6


def pos_block(entry):
    """(pos, glosses) for one kaikki entry, dropping inflected-form and alternative-form senses."""
    glosses = []
    for sense in entry.get("senses", []):
        if sense.get("form_of") or sense.get("alt_of"):
            continue
        chain = sense.get("glosses") or []
        if chain and chain[-1] not in glosses:
            glosses.append(chain[-1])
    return entry.get("pos", ""), glosses[:MAX_GLOSSES_PER_POS]


def build(input_path, output_path):
    by_word = {}  # insertion-ordered
    with open(input_path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            if entry.get("lang_code") != "es" or not entry.get("word"):
                continue
            pos, glosses = pos_block(entry)
            if glosses:
                by_word.setdefault(entry["word"], []).append((pos, glosses))

    rows = [(word, None, dictbuild.format_senses(blocks)) for word, blocks in by_word.items()]
    meta = {
        "source": "kaikki.org English Wiktionary extract, Spanish",
        "source_url": "https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl",
        "license": "CC BY-SA 4.0 and GFDL, Wiktionary contributors",
    }
    return dictbuild.write_database(output_path, rows, meta)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(f"{build(sys.argv[1], sys.argv[2])} entries")
