#!/bin/bash
# Copies your data from the old app container (dev.langsrs.LangSRS) into Reprise's (com.surreptus.Reprise).
#
# Why: the bundle ID decides where a sandboxed app keeps its files, so after the rename the new app starts empty.
# This copies the library (videos, audio), the database, the downloaded speech models and your settings.
#
# Safe by design: it only copies. The old container is never changed or deleted, and anything already in the new
# one is moved aside (not removed). On APFS the copy is a clone, so it takes almost no extra space or time.
#
# Use:  1. Open Reprise once and quit it (this creates its container).
#       2. Run  Scripts/migrate_container.sh --dry-run   to see what would happen.
#       3. Run  Scripts/migrate_container.sh             to do it.
# Terminal may ask permission to access data from other apps; allow it.
set -euo pipefail

OLD_ID="dev.langsrs.LangSRS"
NEW_ID="com.surreptus.Reprise"
OLD="$HOME/Library/Containers/$OLD_ID/Data/Library"
NEW="$HOME/Library/Containers/$NEW_ID/Data/Library"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { echo "== $*"; }
fail() { echo "error: $*" >&2; exit 1; }
run() { if [ "$DRY" -eq 1 ]; then echo "   would run: $*"; else "$@"; fi; }

[ -d "$OLD/Application Support/LangSRS" ] || fail "nothing to copy: no data at $OLD/Application Support/LangSRS"
[ -d "$HOME/Library/Containers/$NEW_ID" ] || fail "open Reprise once first, so macOS creates $NEW_ID's container"
if pgrep -x Reprise >/dev/null || pgrep -x LangSRS >/dev/null; then fail "quit Reprise (and any older LangSRS) first"; fi

SIZE=$(du -sh "$OLD/Application Support/LangSRS" | cut -f1)
say "Copying $SIZE of data from $OLD_ID to $NEW_ID"

DEST="$NEW/Application Support/LangSRS"
if [ -e "$DEST" ]; then
  ASIDE="$DEST.before-migration-$(date +%Y%m%d-%H%M%S)"
  say "The new app already has data; moving it aside to $(basename "$ASIDE")"
  run mv "$DEST" "$ASIDE"
fi
run mkdir -p "$NEW/Application Support"
run cp -cR "$OLD/Application Support/LangSRS" "$DEST"

OLD_PREFS="$OLD/Preferences/$OLD_ID.plist"
if [ -f "$OLD_PREFS" ]; then
  say "Copying settings"
  run mkdir -p "$NEW/Preferences"
  [ -e "$NEW/Preferences/$NEW_ID.plist" ] && run mv "$NEW/Preferences/$NEW_ID.plist" "$NEW/Preferences/$NEW_ID.plist.before-migration"
  run cp -c "$OLD_PREFS" "$NEW/Preferences/$NEW_ID.plist"
fi

if [ "$DRY" -eq 1 ]; then say "Dry run: nothing was changed"; else say "Done. Open Reprise. The old container is untouched; delete it yourself once you're happy."; fi
