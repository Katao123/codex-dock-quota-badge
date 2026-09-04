#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
build_dir="$repo_dir/.build"
output_path="$build_dir/CodexDockQuotaFeed"

/usr/bin/xcrun --find swiftc >/dev/null
/bin/mkdir -p "$build_dir"
/usr/bin/xcrun swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  "$repo_dir/src/NativeQuotaFeed.swift" \
  -o "$output_path"
/usr/bin/codesign --force --sign - "$output_path"
/usr/bin/codesign --verify --strict --verbose=2 "$output_path"
print -r -- "$output_path"
