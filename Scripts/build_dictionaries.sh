#!/bin/bash
# Downloads JMdict_e (EDRDG) and the kaikki.org Spanish extract, and builds the dictionary files the app bundles.
# Developer-run, needs network; the app never does this. Output: LangCore/Sources/LangCore/Resources/dictionaries/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/LangCore/Sources/LangCore/Resources/dictionaries"
WORK="$(mktemp -d)"   # downloads are untrusted data: keep them away from the scripts and the repo
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

curl -fSL --retry 3 -o "$WORK/JMdict_e.gz" https://www.edrdg.org/pub/Nihongo/JMdict_e.gz
curl -fSL --retry 3 -o "$WORK/spanish.jsonl" https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl

cd "$ROOT"
python3 -I Scripts/dictionaries/build_jmdict.py "$WORK/JMdict_e.gz" "$OUT/dictionary-ja.sqlite"
python3 -I Scripts/dictionaries/build_kaikki_es.py "$WORK/spanish.jsonl" "$OUT/dictionary-es.sqlite"
ls -l "$OUT"
