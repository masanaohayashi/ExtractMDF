#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product ExtractMDF
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/ExtractMDF.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ExtractMDF" "$APP/Contents/MacOS/ExtractMDF"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto "$BIN_DIR/ExtractMDF_LZMCore.bundle" "$APP/Contents/Resources/ExtractMDF_LZMCore.bundle"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP"
echo "作成しました: $(pwd)/$APP"
