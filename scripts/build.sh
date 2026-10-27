#!/usr/bin/env bash
# Build DSHBar.app without Xcode: one swiftc invocation, a hand-made bundle,
# then an ad-hoc signature (no paid Developer ID required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/DSHBar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -whole-module-optimization \
    -framework Cocoa \
    -o "$APP/Contents/MacOS/DSHBar" \
    "$ROOT"/app/Sources/DSHBar/*.swift

cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
