#!/bin/bash
# Downloads JMdict_e and KANJIDIC2 (EDRDG) and the kaikki.org Spanish, French and German extracts, and builds the dictionary files the app bundles.
# Developer-run, needs network; the app never does this. Output: LangCore/Sources/LangCore/Resources/dictionaries/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/LangCore/Sources/LangCore/Resources/dictionaries"
# Downloads are untrusted data: keep them away from the scripts and the repo. Set DICTIONARY_DOWNLOADS to a folder to keep
# them between runs, so a dropped connection resumes where it stopped instead of starting over.
if [ -n "${DICTIONARY_DOWNLOADS:-}" ]; then
    WORK="$DICTIONARY_DOWNLOADS"; mkdir -p "$WORK"
else
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fi
mkdir -p "$OUT"

# fetch URL FILE: skips a file that is already whole, and resumes one that stopped part-way.
fetch() {
    local want
    want=$(curl -sIL --retry 3 "$1" | tr -d '\r' | awk 'tolower($1)=="content-length:" {n=$2} END {print n}')
    if [ -n "$want" ] && [ -f "$2" ] && [ "$(wc -c < "$2" | tr -d ' ')" = "$want" ]; then return; fi
    curl -fSL --retry 5 --retry-all-errors -C - -o "$2" "$1"
}

fetch https://www.edrdg.org/pub/Nihongo/JMdict_e.gz "$WORK/JMdict_e.gz"
fetch https://www.edrdg.org/kanjidic/kanjidic2.xml.gz "$WORK/kanjidic2.xml.gz"
for language in Spanish French German; do
    fetch "https://kaikki.org/dictionary/$language/kaikki.org-dictionary-$language.jsonl" "$WORK/$language.jsonl"
done

cd "$ROOT"
python3 -I Scripts/dictionaries/build_jmdict.py "$WORK/JMdict_e.gz" "$OUT/dictionary-ja.sqlite"
python3 -I Scripts/dictionaries/build_kanjidic.py "$WORK/kanjidic2.xml.gz" "$OUT/kanji-ja.sqlite"
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/Spanish.jsonl" "$OUT/dictionary-es.sqlite" es Spanish
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/French.jsonl" "$OUT/dictionary-fr.sqlite" fr French
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/German.jsonl" "$OUT/dictionary-de.sqlite" de German
ls -l "$OUT"
