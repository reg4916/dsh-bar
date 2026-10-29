#!/usr/bin/env bash
# Compile the AppKit-free sources with the test harness and run it. Keeps the
# manual swiftc app build intact while still giving CI real native coverage.
set -eo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
BIN="$ROOT/build/native-tests"
swiftc -O -o "$BIN" \
  "$ROOT/app/Sources/DSHBar/Model.swift" \
  "$ROOT/app/Sources/DSHBar/Client.swift" \
  "$ROOT/app/Sources/DSHBar/L10n.swift" \
  "$ROOT/app/Sources/DSHBar/AnswerBatch.swift" \
  "$ROOT/app/Sources/DSHBar/UpdateChecker.swift" \
  "$ROOT/app/Tests/main.swift"
"$BIN"
