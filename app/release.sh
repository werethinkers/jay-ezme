#!/bin/bash
# KeyDo local release: build → sign → notarize → staple → GitHub release → update latest.json
# Usage: bash release.sh [BUILD_NUMBER]
#   BUILD_NUMBER  optional; defaults to (latest published build + 1)
#
# Required env vars (or will prompt):
#   APPLE_ID          Apple ID for notarization (default: abhijayjain0@gmail.com)
#   APPLE_TEAM_ID     Team ID (default: PY9D2VJ6VQ)
#   APPLE_APP_PASSWORD  app-specific password from appleid.apple.com
#   GITHUB_TOKEN      personal access token with repo scope (for release upload)
#   SIGN_IDENTITY     codesign identity (default: Developer ID Application: abhijay jain (PY9D2VJ6VQ))

set -euo pipefail
cd "$(dirname "$0")"

REPO="werethinkers/jay-ezme"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: abhijay jain (PY9D2VJ6VQ)}"
APPLE_ID="${APPLE_ID:-abhijayjain0@gmail.com}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-PY9D2VJ6VQ}"

# ── Build number ──────────────────────────────────────────────────────────────
if [ -n "${1:-}" ]; then
  BUILD="$1"
else
  LATEST_BUILD=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tag_name'])" \
    | grep -oE '[0-9]+$' || echo "484")
  BUILD=$(( LATEST_BUILD + 1 ))
  echo "Auto build number: $BUILD (latest was $LATEST_BUILD)"
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
echo ""
echo "=== KeyDo $VERSION (build $BUILD) ==="
echo ""

# ── Credentials ───────────────────────────────────────────────────────────────
if [ -z "${APPLE_APP_PASSWORD:-}" ]; then
  # Try keychain first
  APPLE_APP_PASSWORD=$(security find-generic-password -a "$APPLE_ID" -s "notarytool-password" -w 2>/dev/null || true)
  if [ -z "$APPLE_APP_PASSWORD" ]; then
    echo "Enter app-specific password from appleid.apple.com (xxxx-xxxx-xxxx-xxxx):"
    read -rs APPLE_APP_PASSWORD
    echo ""
    # Offer to save to keychain for next time
    echo "Save to keychain for next time? (y/n)"
    read -r SAVE_KC
    if [ "$SAVE_KC" = "y" ]; then
      security add-generic-password -a "$APPLE_ID" -s "notarytool-password" -w "$APPLE_APP_PASSWORD" 2>/dev/null || \
        security add-generic-password -U -a "$APPLE_ID" -s "notarytool-password" -w "$APPLE_APP_PASSWORD"
      echo "Saved to keychain (service: notarytool-password)."
    fi
  else
    echo "Using app-specific password from keychain."
  fi
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Enter GitHub personal access token (repo scope):"
  read -rs GITHUB_TOKEN
  echo ""
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "▶ Building..."
BUILD_NUMBER="$BUILD" SIGN_IDENTITY="$SIGN_IDENTITY" bash build.sh
APP="build/EzMe.app"
ZIP="build/EzMe-$VERSION-macOS.zip"

echo "▶ Verifying signature..."
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -3

# ── Notarize ──────────────────────────────────────────────────────────────────
echo ""
echo "▶ Submitting for notarization (this takes 1–5 minutes)..."
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait \
  --verbose 2>&1 | grep -E "id:|status:|message:|Accepted|Invalid|Waiting"

# ── Staple ────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Stapling notarization ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# ── Repackage ─────────────────────────────────────────────────────────────────
echo "▶ Repackaging stapled app..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')
SIZE=$(wc -c < "$ZIP" | tr -d ' ')
echo "   SHA256: $SHA256"
echo "   Size:   $SIZE bytes"

# ── GitHub release ────────────────────────────────────────────────────────────
TAG="v$VERSION-build$BUILD"
echo ""
echo "▶ Creating GitHub release $TAG..."

RELEASE=$(curl -sf -X POST "https://api.github.com/repos/$REPO/releases" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"$TAG\",
    \"name\": \"KeyDo $VERSION (build $BUILD)\",
    \"body\": $(python3 -c "import json; print(json.dumps(open('../app/RELEASE_NOTES.md').read()))"),
    \"draft\": false,
    \"prerelease\": false
  }")

RELEASE_ID=$(echo "$RELEASE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
UPLOAD_URL="https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets"

echo "▶ Uploading $ZIP..."
curl -sf -X POST "$UPLOAD_URL?name=EzMe-$VERSION-macOS.zip" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/zip" \
  --data-binary "@$ZIP" > /dev/null
echo "   Uploaded."

# ── Update latest.json ────────────────────────────────────────────────────────
PUBLISHED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/EzMe-$VERSION-macOS.zip"
NOTES=$(python3 -c "import json; print(json.dumps(open('../app/RELEASE_NOTES.md').read()))")

python3 - <<PYEOF
import json, sys

with open('../update/latest.json') as f:
    d = json.load(f)

d['version'] = '$VERSION'
d['build'] = $BUILD
d['url'] = '$DOWNLOAD_URL'
d['sha256'] = '$SHA256'
d['published'] = '$PUBLISHED'
d['notes'] = open('../app/RELEASE_NOTES.md').read()
d['minimumSystemVersion'] = '14.0'

with open('../update/latest.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')

print('latest.json updated → build $BUILD, sha256 $SHA256')
PYEOF

# ── Commit & push ─────────────────────────────────────────────────────────────
echo ""
echo "▶ Committing latest.json..."
cd ..
git add update/latest.json
git commit -m "release: KeyDo $VERSION build $BUILD

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin main

echo ""
echo "✅ Done! KeyDo $VERSION build $BUILD is live."
echo "   Release:  https://github.com/$REPO/releases/tag/$TAG"
echo "   Download: $DOWNLOAD_URL"
