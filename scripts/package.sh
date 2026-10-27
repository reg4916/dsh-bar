#!/usr/bin/env bash
# Package the universal app, the npm host plugin, and checksums for a GitHub
# release. Everything here is free/open source; signing stays ad-hoc.
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(node -p "require('$ROOT/plugin/package.json').version")"

rm -rf "$DIST"
mkdir -p "$DIST"

"$ROOT/scripts/build.sh" --universal

ditto -c -k --keepParent "$ROOT/build/DSHBar.app" "$DIST/DSHBar-$VERSION-macos-universal.zip"
(cd "$ROOT/plugin" && npm pack --pack-destination "$DIST" >/dev/null)
(cd "$DIST" && shasum -a 256 * > SHA256SUMS)

echo "packaged version $VERSION:"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS"
