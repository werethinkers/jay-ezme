#!/bin/bash
# Installs EzMe on this Mac, checks it launches and stays running, then checks the in-app updater
# replaces it with a newer build from a local feed and relaunches it.
#   APP_ZIP   the built EzMe zip (from app/build.sh)
#   OUT       folder for screenshots and logs
set -uo pipefail
APP_ZIP="$1"; OUT="$2"
mkdir -p "$OUT"
FAIL=0
pass(){ echo "PASS: $*"; }
fail(){ echo "FAIL: $*"; FAIL=1; }
plist_build(){ /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null; }
running(){ pgrep -x EzMe >/dev/null; }
stop_app(){ osascript -e 'quit app "EzMe"' >/dev/null 2>&1; sleep 3; pkill -x EzMe 2>/dev/null; sleep 1; }

WORK="$(mktemp -d)"
ditto -x -k "$APP_ZIP" "$WORK/a"
A="$WORK/a/EzMe.app"
BUILD_A="$(plist_build "$A")"
echo "Testing EzMe build $BUILD_A"

# 1. Signature and bundle
codesign --verify --strict --verbose=2 "$A" && pass "code signature is valid" || fail "code signature"
[ "$(lipo -archs "$A/Contents/MacOS/EzMe")" = "arm64" ] && pass "binary is Apple silicon (arm64)" || fail "architecture"
for f in EzMeLogo EzMeInvoiceReference EzMeQuoteReference EzMePurchaseOrderReference; do
  [ -f "$A/Contents/Resources/$f.png" ] || fail "missing resource $f.png"
done

# 2. Install and launch
stop_app
rm -rf /Applications/EzMe.app
ditto "$A" /Applications/EzMe.app
defaults delete com.ezme.mac >/dev/null 2>&1
open /Applications/EzMe.app
sleep 25
if running; then pass "EzMe launched and is still running after 25 seconds"; else fail "EzMe is not running after launch"; fi
screencapture -x "$OUT/1-launch.png" 2>/dev/null
osascript -e 'tell application "System Events" to get name of every window of process "EzMe"' > "$OUT/windows.txt" 2>&1
echo "Windows: $(cat "$OUT/windows.txt")"
stop_app

# 3. Updater: offer a newer build from a local feed and let the app install it
B_DIR="$WORK/b"; mkdir -p "$B_DIR"
ditto "$A" "$B_DIR/EzMe.app"
NEW_BUILD=$((BUILD_A + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$B_DIR/EzMe.app/Contents/Info.plist"
codesign --force --sign - "$B_DIR/EzMe.app"
SERVE="$WORK/serve"; mkdir -p "$SERVE"
ditto -c -k --keepParent "$B_DIR/EzMe.app" "$SERVE/EzMe-test.zip"
SHA="$(shasum -a 256 "$SERVE/EzMe-test.zip" | cut -d' ' -f1)"
cat > "$SERVE/latest.json" <<JSON
{"version":"test","build":$NEW_BUILD,"url":"http://127.0.0.1:8765/EzMe-test.zip","sha256":"$SHA","notes":"Smoke test build","minimumSystemVersion":"14.0"}
JSON
(cd "$SERVE" && python3 -m http.server 8765 --bind 127.0.0.1 > "$OUT/feed-server.log" 2>&1) &
SERVER=$!
sleep 2
defaults write com.ezme.mac EzMeUpdateFeed "http://127.0.0.1:8765/latest.json"
defaults write com.ezme.mac EzMeAutoInstallUpdate -bool YES
open /Applications/EzMe.app
UPDATED=0
for i in $(seq 1 60); do
  sleep 2
  if [ "$(plist_build /Applications/EzMe.app)" = "$NEW_BUILD" ]; then UPDATED=1; break; fi
done
if [ $UPDATED = 1 ]; then pass "updater replaced build $BUILD_A with build $NEW_BUILD"; else fail "updater did not install build $NEW_BUILD (still $(plist_build /Applications/EzMe.app))"; fi
sleep 15
if running; then pass "updated EzMe relaunched and is running"; else fail "EzMe did not relaunch after the update"; fi
screencapture -x "$OUT/2-after-update.png" 2>/dev/null
codesign --verify --strict /Applications/EzMe.app && pass "updated app signature is valid" || fail "updated app signature"
defaults write com.ezme.mac EzMeAutoInstallUpdate -bool NO
stop_app
kill $SERVER 2>/dev/null

# 4. Crash reports
if ls ~/Library/Logs/DiagnosticReports/EzMe* >/dev/null 2>&1; then
  fail "crash report found"; cp ~/Library/Logs/DiagnosticReports/EzMe* "$OUT/" 2>/dev/null
  head -60 ~/Library/Logs/DiagnosticReports/EzMe* 
else
  pass "no crash reports"
fi
log show --last 10m --predicate 'process == "EzMe"' --style compact 2>/dev/null | tail -200 > "$OUT/ezme-log.txt"
defaults delete com.ezme.mac >/dev/null 2>&1

[ $FAIL = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
