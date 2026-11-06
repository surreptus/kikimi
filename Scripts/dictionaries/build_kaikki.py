"""Builds dictionary-<code>.sqlite from kaikki.org's extract of English Wiktionary's entries for one language
(that language's words, English definitions).

Usage: python3 -I build_kaikki.py kaikki.org-dictionary-Spanish.jsonl dictionary-es.sqlite es Spanish [--forms]
--forms also writes a table of the spellings of common verbs, for checking a tagger's lemmas (Spanish uses it).
Wiktionary content is CC BY-SA 4.0 (and GFDL); extraction by Tatu Ylonen's wiktextract.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictbuild

MAX_GLOSSES_PER_POS = 8   # separate meanings, after repeats are removed
# A verb needs this many meanings of its own to count as a common one in the forms table: a tagger that reads a spelling
# as a rare verb (puede as podar) is then overruled. Wiktionary has no frequency, and meanings stand in for it.
MIN_VERB_MEANINGS = 2
GENDER_TAGS = {"masculine": "m", "feminine": "f", "neuter": "n"}
GENDER_ORDER = "mfn"


# Senses that are only for some speakers or some uses. A region's name starts with a capital ("Mexico", "Europe").
UNCOMMON_TAGS = {"slang", "colloquial", "informal", "vulgar", "rare", "archaic", "dated", "obsolete", "dialectal",
                 "regional", "historical", "humorous", "derogatory", "poetic", "literary"}


def is_uncommon(sense):
    return any(t in UNCOMMON_TAGS or t[:1].isupper() for t in sense.get("tags", []))


# Short forms that are mistakes or spoken spellings are not worth a headword of their own.
NOT_STANDARD_TAGS = {"misspelling", "nonstandard", "pronunciation-spelling", "eye-dialect", "proscribed"}


def noun_gender(entry):
    """(ordinary, uncommon): the genders of a noun entry as sets of letters ("m", "f", "n"), the first from its ordinary
    senses and the second from senses meant for some regions or registers; both empty for any other part of speech
    or when Wiktionary gives none. The senses' tags are used first; the headword line ("casa f (plural casas)") is
    the fallback."""
    if entry.get("pos") != "noun":
        return set(), set()
    senses = [s for s in entry.get("senses", []) if not (s.get("form_of") or s.get("alt_of"))]

    def genders(chosen):
        return {GENDER_TAGS[t] for s in chosen for t in s.get("tags", []) if t in GENDER_TAGS}

    ordinary, uncommon = genders([s for s in senses if not is_uncommon(s)]), genders([s for s in senses if is_uncommon(s)])
    if not ordinary and not uncommon:
        for template in entry.get("head_templates", []):
            # Only the words before the first bracket: "Buch n (strong, genitive Buches...)".
            ordinary.update(w for w in template.get("expansion", "").split("(")[0].split() if w in ("m", "f", "n"))
    return ordinary, uncommon


def merge_genders(existing, new):
    """The genders found so far for one word, with another entry's added."""
    existing = existing or (set(), set())
    return existing[0] | new[0], existing[1] | new[1]


def gender_text(found):
    """The word's gender as "m", "f", "n" or a mix such as "m,f" (two real senses, like Teil), or None. Genders that
    only uncommon senses give (mano's Mexican slang "m") count only when no ordinary sense gives one."""
    chosen = (found[0] or found[1]) if found else set()
    letters = [g for g in GENDER_ORDER if g in chosen]
    return ",".join(letters) if letters else None


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
    """(pos, glosses) for one kaikki entry, dropping inflected-form and alternative-form senses, except a short form that
    gives a meaning of its own ("muy": apocopic form of mucho, "very"), which is that meaning. Wiktionary senses often
    repeat each other's meanings ("to have; to possess" then "to have; to possess; to be..."), so each meaning is kept once."""
    glosses, seen = [], set()
    for sense in entry.get("senses", []):
        if sense.get("form_of"):
            continue
        if sense.get("alt_of"):
            if is_uncommon(sense) or NOT_STANDARD_TAGS & set(sense.get("tags", [])):
                continue
            own = " ".join(a.get("extra", "") for a in sense["alt_of"]).strip()
            if not own:
                continue
            chain = [own]
        else:
            chain = sense.get("glosses") or []
        if not chain:
            continue
        for meaning in meanings(chain[-1]):
            if meaning.casefold() not in seen:
                seen.add(meaning.casefold())
                glosses.append(meaning)
    return entry.get("pos", ""), glosses[:MAX_GLOSSES_PER_POS]



def verb_forms(pending, meanings):
    """{spelling: [(lemma, meanings)]} for the forms of verbs with at least MIN_VERB_MEANINGS meanings, most meanings first."""
    forms = {}
    for form, lemma in pending:
        count = meanings.get(lemma, 0)
        if count >= MIN_VERB_MEANINGS and (lemma, count) not in forms.setdefault(form, []):
            forms[form].append((lemma, count))
    for lemmas in forms.values():
        lemmas.sort(key=lambda item: -item[1])
    return {form: lemmas for form, lemmas in forms.items() if lemmas}


def build(input_path, output_path, code, name, with_forms=False):
    by_word = {}  # insertion-ordered
    genders = {}
    verb_meanings, form_pairs = {}, []
    with open(input_path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            if entry.get("lang_code") != code or not entry.get("word"):
                continue
            pos, glosses = pos_block(entry)
            if with_forms and pos == "verb":
                word = entry["word"].lower()
                own = [x for x in entry.get("senses", []) if not (x.get("form_of") or x.get("alt_of")) and x.get("glosses")]
                if own:
                    verb_meanings[word] = verb_meanings.get(word, 0) + len(own)
                for sense in entry.get("senses", []):
                    for target in sense.get("form_of") or []:
                        if target.get("word") and target["word"].lower() != word:
                            form_pairs.append((word, target["word"].lower()))
            if glosses:
                by_word.setdefault(entry["word"], []).append((pos, glosses))
                genders[entry["word"]] = merge_genders(genders.get(entry["word"]), noun_gender(entry))

    rows = [(word, None, dictbuild.format_senses(blocks), gender_text(genders.get(word))) for word, blocks in by_word.items()]
    meta = {
        "source": f"kaikki.org English Wiktionary extract, {name}",
        "source_url": f"https://kaikki.org/dictionary/{name}/kaikki.org-dictionary-{name}.jsonl",
        "license": "CC BY-SA 4.0 and GFDL, Wiktionary contributors",
    }
    count = dictbuild.write_database(output_path, rows, meta)
    if with_forms:
        print(f"{dictbuild.add_forms(output_path, verb_forms(form_pairs, verb_meanings))} verb spellings in the forms table")
    return count


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--forms"]
    if len(args) != 4:
        sys.exit(__doc__)
    print(f"{build(*args, with_forms='--forms' in sys.argv)} entries")
