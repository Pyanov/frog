#!/usr/bin/env bash
# Builds web/ (three.js pet) and the Swift app, then assembles build/VoicePet.app
set -euo pipefail
cd "$(dirname "$0")"
(cd web && npm run build --silent)
swift build -c release
BIN=.build/release/VoicePet
if [ ! -x "$BIN" ]; then
  echo "error: Swift build completed without producing $BIN" >&2
  exit 1
fi
APP=build/VoicePet.app
STAGING=build/VoicePet.app.staging
rm -rf "$STAGING"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources/web"
cp Resources/Info.plist "$STAGING/Contents/"
cp "$BIN" "$STAGING/Contents/MacOS/"
cp -R web/dist/. "$STAGING/Contents/Resources/web/"
# binary frameworks from dependencies (llama.cpp for the on-device brain)
mkdir -p "$STAGING/Contents/Frameworks"
for fw in $(find .build -type d -name "*.framework" -path "*macos*" 2>/dev/null; find .build/artifacts -type d -name "*.framework" 2>/dev/null); do
  name=$(basename "$fw"); [ -d "$STAGING/Contents/Frameworks/$name" ] || cp -R "$fw" "$STAGING/Contents/Frameworks/"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$STAGING/Contents/MacOS/VoicePet" 2>/dev/null || true
# SwiftPM resource bundles from dependencies, if any
for b in .build/release/*.bundle; do
  if [ -d "$b" ]; then cp -R "$b" "$STAGING/Contents/Resources/"; fi
done
# Sign with the stable local identity if it exists (keeps macOS permission grants across rebuilds), else ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "VoicePet Dev"; then
  codesign --force --deep --sign "VoicePet Dev" "$STAGING" && echo "signed with VoicePet Dev"
else
  codesign --force --deep --sign - "$STAGING" && echo "signed ad-hoc (permissions may reset on rebuild)"
fi
rm -rf "$APP"
mv "$STAGING" "$APP"
trap - EXIT
echo "Built $APP"
