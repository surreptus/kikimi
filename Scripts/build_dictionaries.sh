#!/bin/bash
# Downloads JMdict_e and KANJIDIC2 (EDRDG) and the kaikki.org Spanish, French and German extracts, and builds the dictionary files the app bundles.
# Developer-run, needs network; the app never does this. Output: LangCore/Sources/LangCore/Resources/dictionaries/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/LangCore/Sources/LangCore/Resources/dictionaries"
WORK="$(mktemp -d)"   # downloads are untrusted data: keep them away from the scripts and the repo
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

curl -fSL --retry 3 -o "$WORK/JMdict_e.gz" https://www.edrdg.org/pub/Nihongo/JMdict_e.gz
curl -fSL --retry 3 -o "$WORK/kanjidic2.xml.gz" https://www.edrdg.org/kanjidic/kanjidic2.xml.gz
for language in Spanish French German; do
    curl -fSL --retry 3 -o "$WORK/$language.jsonl" "https://kaikki.org/dictionary/$language/kaikki.org-dictionary-$language.jsonl"
done

cd "$ROOT"
python3 -I Scripts/dictionaries/build_jmdict.py "$WORK/JMdict_e.gz" "$OUT/dictionary-ja.sqlite"
python3 -I Scripts/dictionaries/build_kanjidic.py "$WORK/kanjidic2.xml.gz" "$OUT/kanji-ja.sqlite"
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/Spanish.jsonl" "$OUT/dictionary-es.sqlite" es Spanish
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/French.jsonl" "$OUT/dictionary-fr.sqlite" fr French
python3 -I Scripts/dictionaries/build_kaikki.py "$WORK/German.jsonl" "$OUT/dictionary-de.sqlite" de German
ls -l "$OUT"
