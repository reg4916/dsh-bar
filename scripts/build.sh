#!/usr/bin/env bash
# Build DSHBar.app without Xcode: swiftc per architecture, a hand-made bundle,
# then an ad-hoc signature (no paid Developer ID required).
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/DSHBar.app"

UNIVERSAL=0
if [ $# -gt 0 ] && [ "$1" = "--universal" ]; then
  UNIVERSAL=1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
  mkdir -p "$OUT/arm64" "$OUT/x86_64"
  echo "compiling arm64..."
  swiftc -O -whole-module-optimization -target arm64-apple-macos13.0 -framework Cocoa \
      -o "$OUT/arm64/DSHBar" "$ROOT"/app/Sources/DSHBar/*.swift
  echo "compiling x86_64..."
  swiftc -O -whole-module-optimization -target x86_64-apple-macos13.0 -framework Cocoa \
      -o "$OUT/x86_64/DSHBar" "$ROOT"/app/Sources/DSHBar/*.swift
  echo "lipo..."
  lipo -create "$OUT/arm64/DSHBar" "$OUT/x86_64/DSHBar" -output "$APP/Contents/MacOS/DSHBar"
else
  ARCH="$(uname -m)"
  echo "compiling $ARCH..."
  swiftc -O -whole-module-optimization -target "$ARCH-apple-macos13.0" -framework Cocoa \
      -o "$APP/Contents/MacOS/DSHBar" "$ROOT"/app/Sources/DSHBar/*.swift
fi

cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
for lproj in "$ROOT"/app/Resources/*.lproj; do
  if [ -d "$lproj" ]; then
    cp -R "$lproj" "$APP/Contents/Resources/"
  fi
done

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
lipo -info "$APP/Contents/MacOS/DSHBar"
