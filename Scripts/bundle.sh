#!/usr/bin/env bash
# Assemble and codesign the .app bundle from the SwiftPM binary.
# Usage: bundle.sh <bundle-path> <binary-path> <exec-name> <display-name> \
#                  <bundle-id> <version> <identity>
#
# The executable keeps a space-free name (it is what shows in ps and pkill)
# while the bundle and its display name carry the human form.
set -euo pipefail

BUNDLE="$1"; BIN="$2"; EXEC="$3"; DISPLAY_NAME="$4"
BUNDLE_ID="$5"; VERSION="$6"; IDENTITY="$7"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$BIN" ]]; then
  echo "error: binary not found at $BIN - run 'make build' first" >&2
  exit 1
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN" "$BUNDLE/Contents/MacOS/$EXEC"

sed -e "s|__EXEC__|$EXEC|g" \
    -e "s|__DISPLAY_NAME__|$DISPLAY_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    "$ROOT/Resources/Info.plist.template" > "$BUNDLE/Contents/Info.plist"
plutil -lint "$BUNDLE/Contents/Info.plist" > /dev/null

printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

shopt -s nullglob
for f in "$ROOT/Resources"/*; do
  [[ "$(basename "$f")" == "Info.plist.template" ]] && continue
  cp -R "$f" "$BUNDLE/Contents/Resources/"
done
shopt -u nullglob

# Prefer the stable self-signed identity so Keychain ACLs survive rebuilds.
# Fall back to ad-hoc so a fresh clone still builds.
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  SIGN="$IDENTITY"
else
  SIGN="-"
  echo "warn: codesigning identity '$IDENTITY' not found - using ad-hoc signature." >&2
  echo "      Keychain items will re-prompt after every rebuild." >&2
  echo "      Run Scripts/make-signing-cert.sh once to create a stable identity." >&2
fi

codesign --force --options runtime --timestamp=none -s "$SIGN" "$BUNDLE"
codesign --verify --strict "$BUNDLE"

echo "built $BUNDLE (signed: $SIGN)"
