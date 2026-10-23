#!/bin/bash
# Runs the LangCore tests under macOS's `leaks` tool and fails if any memory is still reachable only from itself.
#
# Why: the tests check behaviour, not memory, and a retain cycle in the video transcoder went unnoticed until this was run.
# It reports leaks left at the end of the whole run; it does not cover the SwiftUI app (use Instruments for that).
#
# Use:  Scripts/check_leaks.sh          (takes about a minute; needs Xcode)
set -euo pipefail
cd "$(dirname "$0")/../LangCore"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build --build-tests >/dev/null
BUNDLE=".build/out/Products/Debug/LangCoreTests.xctest"
[ -d "$BUNDLE" ] || { echo "error: $BUNDLE not found" >&2; exit 1; }

REPORT="$(mktemp)"
MallocStackLogging=1 leaks --atExit -- "$DEVELOPER_DIR/usr/bin/xctest" "$BUNDLE" > "$REPORT" 2>&1 || true

if ! grep -q "Executed .* tests" "$REPORT"; then echo "error: the tests did not run; see $REPORT" >&2; exit 1; fi
SUMMARY="$(grep -E "[0-9]+ leaks? for" "$REPORT" | tail -1)"
echo "$SUMMARY"
if echo "$SUMMARY" | grep -qE ": 0 leaks"; then
  echo "No leaks."; rm -f "$REPORT"
else
  echo "Roots of the leaks:"
  grep -E "ROOT (CYCLE|LEAK)" "$REPORT" | sed -E 's/0x[0-9a-f]+//g; s/^ +//' | sort | uniq -c | sort -rn | head -15
  echo "Full report: $REPORT"
  exit 1
fi
