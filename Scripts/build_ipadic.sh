#!/bin/bash
# Builds the UTF-8 IPADIC binary dictionary used by the Japanese tokenizer.
# Needs network (clones MeCab's repo at a pinned commit) and Xcode command line tools. Run it yourself, once;
# the app never does. Output: LangCore/Sources/LangCore/Resources/ipadic (gitignored, ~60 MB).
set -euo pipefail

COMMIT=61b90ba6e669dc2d7d533d4a80d206f3b31d52b1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMECAB="$ROOT/LangCore/Sources/CMeCab"
OUT="$ROOT/LangCore/Sources/LangCore/Resources/ipadic"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/taku910/mecab.git "$WORK/src"
git -C "$WORK/src" checkout --quiet "$COMMIT"

# The dictionary compiler is built from the same vendored sources the app links.
clang++ -std=c++14 -O1 -w -DHAVE_CONFIG_H -I "$CMECAB" -I "$CMECAB/include" \
  "$CMECAB"/*.cpp "$ROOT/Scripts/mecab/mecab-dict-index.cpp" -liconv -o "$WORK/mecab-dict-index"

rm -rf "$OUT"
mkdir -p "$OUT"
"$WORK/mecab-dict-index" -d "$WORK/src/mecab-ipadic" -o "$OUT" -f euc-jp -t utf-8 > "$WORK/index.log" 2>&1 \
  || { cat "$WORK/index.log"; exit 1; }
# The source dicrc declares EUC-JP; the compiled dictionary is UTF-8.
sed 's/^config-charset = EUC-JP/config-charset = UTF-8/' "$WORK/src/mecab-ipadic/dicrc" > "$OUT/dicrc"
du -sh "$OUT"
