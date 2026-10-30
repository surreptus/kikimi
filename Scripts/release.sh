#!/bin/bash
# Builds a release archive of Kikimi and exports it. Nothing runs until you choose a mode.
#
#   TEAM_ID=ABCDE12345 Scripts/release.sh developer-id            archive + export for direct download
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=kikimi Scripts/release.sh developer-id --notarize
#                                                                 ... then notarize, staple, make a DMG
#   TEAM_ID=ABCDE12345 Scripts/release.sh app-store               archive + export a .pkg for App Store Connect
#   Scripts/release.sh developer-id --dry-run                     print every command, change nothing
#
# Options: --notarize (developer-id only), --skip-tests, --dry-run
# Environment: TEAM_ID (your 10-character Apple team ID), NOTARY_PROFILE (a `notarytool store-credentials` profile)
#
# Before the first real run, see Release/CHECKLIST.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

MODE="" NOTARIZE=0 DRY=0 SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    developer-id|app-store) MODE="$arg" ;;
    --notarize) NOTARIZE=1 ;;
    --dry-run) DRY=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { sed -n '2,14p' "$0"; exit 2; }
[ "$NOTARIZE" -eq 0 ] || [ "$MODE" = "developer-id" ] || { echo "--notarize only applies to developer-id" >&2; exit 2; }

fail() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
run() {
  if [ "$DRY" -eq 1 ]; then printf '+'; printf ' %q' "$@"; echo; else "$@"; fi
}

# ---------- Preflight: everything here is read-only and happens before anything is built or signed ----------
TEAM_ID="${TEAM_ID:-}"
if [ "$DRY" -eq 1 ] && [ -z "$TEAM_ID" ]; then TEAM_ID="TEAMID0000"; warn "TEAM_ID not set; using a placeholder for this dry run"; fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "set TEAM_ID to your 10-character Apple team ID (developer.apple.com > Membership)"

missing=0
for f in LangCore/Sources/LangCore/Resources/ipadic/sys.dic \
         LangCore/Sources/LangCore/Resources/dictionaries/dictionary-ja.sqlite \
         LangCore/Sources/LangCore/Resources/dictionaries/dictionary-es.sqlite \
         LangCore/Sources/LangCore/Resources/dictionaries/dictionary-fr.sqlite \
         LangCore/Sources/LangCore/Resources/dictionaries/dictionary-de.sqlite \
         LangCore/Sources/LangCore/Resources/dictionaries/kanji-ja.sqlite \
         Kikimi/PrivacyInfo.xcprivacy; do
  [ -e "$f" ] || { echo "missing: $f" >&2; missing=1; }
done
if [ "$missing" -eq 1 ]; then
  if [ "$DRY" -eq 1 ]; then warn "required files are missing (see above); a real run would stop here"
  else fail "run Scripts/build_ipadic.sh and Scripts/build_dictionaries.sh first"; fi
fi

if ! ls Kikimi/Assets.xcassets/AppIcon.appiconset/*.png >/dev/null 2>&1; then
  if [ "$MODE" = "app-store" ] && [ "$DRY" -eq 0 ]; then fail "the App Store requires an app icon: add PNGs to Assets.xcassets/AppIcon"; fi
  warn "no app icon images in Assets.xcassets/AppIcon"
fi

if [ "$NOTARIZE" -eq 1 ] && [ -z "${NOTARY_PROFILE:-}" ] && [ "$DRY" -eq 0 ]; then
  fail "set NOTARY_PROFILE (create one with: xcrun notarytool store-credentials <name> --apple-id ... --team-id $TEAM_ID)"
fi

# ---------- Build ----------
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/Kikimi.xcarchive"
EXPORT="$BUILD/export-$MODE"
OPTIONS_SRC="$ROOT/Release/ExportOptions-$([ "$MODE" = developer-id ] && echo DeveloperID || echo AppStore).plist"
OPTIONS="$BUILD/ExportOptions-$MODE.plist"

if [ "$SKIP_TESTS" -eq 0 ]; then
  echo "== Tests"
  run bash -c "cd '$ROOT/LangCore' && swift test"
fi

echo "== Archive ($MODE, team $TEAM_ID)"
run mkdir -p "$BUILD"
run rm -rf "$ARCHIVE" "$EXPORT"
run xcodebuild -project Kikimi.xcodeproj -scheme Kikimi -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" archive

echo "== Export"
run bash -c "sed 's/YOUR_TEAM_ID/$TEAM_ID/' '$OPTIONS_SRC' > '$OPTIONS'"
run xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates

if [ "$MODE" = "app-store" ]; then
  echo "== Done. Upload the .pkg in $EXPORT with the Transporter app (or xcrun altool), then submit in App Store Connect."
  exit 0
fi

APP="$EXPORT/Kikimi.app"
if [ "$NOTARIZE" -eq 1 ]; then
  echo "== Notarize"
  run ditto -c -k --keepParent "$APP" "$BUILD/Kikimi-notarize.zip"
  run xcrun notarytool submit "$BUILD/Kikimi-notarize.zip" --keychain-profile "${NOTARY_PROFILE:-PROFILE}" --wait
  run xcrun stapler staple "$APP"
  run spctl --assess --type execute --verbose "$APP"
  echo "== DMG"
  run hdiutil create -volname Kikimi -srcfolder "$APP" -ov -format UDZO "$BUILD/Kikimi.dmg"
  echo "== Done: $BUILD/Kikimi.dmg"
else
  echo "== Done: $APP (signed, NOT notarized: add --notarize before sharing it)"
fi
