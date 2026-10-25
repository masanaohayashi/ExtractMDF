#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${SIGNING_IDENTITY:-AEFC4120A5C56112CD029ACCCF1F4E0909EC4276}"
PROFILE="${NOTARY_PROFILE:-Notalization2021}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
RELEASE_DIR="build/release/$VERSION"
APP="$RELEASE_DIR/ExtractMDF.app"
ZIP="$RELEASE_DIR/ExtractMDF-$VERSION-macOS.zip"
mkdir -p "$RELEASE_DIR"
swift test
swift build -c release --arch arm64 --arch x86_64 --product ExtractMDF
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ExtractMDF" "$APP/Contents/MacOS/ExtractMDF"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
ditto "$BIN_DIR/ExtractMDF_LZMCore.bundle" "$APP/Contents/Resources/ExtractMDF_LZMCore.bundle"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json > "$RELEASE_DIR/notarization.json"
python3 - "$RELEASE_DIR/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Notarization:', result.get('status'), result.get('id'))
if result.get('status') != 'Accepted':
    sys.exit('Notarization was not accepted; no release package finalized.')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# Repackage after stapling so the download includes the ticket.
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$RELEASE_DIR" && shasum -a 256 "ExtractMDF-$VERSION-macOS.zip" > SHA256SUMS.txt)
echo "Release: $ZIP"
