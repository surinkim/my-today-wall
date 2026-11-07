#!/bin/zsh
# Builds BingClient, ImageStore and WallpaperService as a command-line tool and checks them against the real Bing API.
# Usage: scripts/check-core.sh [folder]   (default: a temp folder; ~/Pictures is never touched)
set -euo pipefail
cd "$(dirname "$0")/.."

out="${TMPDIR:-/tmp}/mytodaywall-core-check"
mkdir -p "$out"
xcrun swiftc -swift-version 5 -o "$out/core-check" \
  MyTodayWall/{Log,DateFormatting,BingClient,ImageStore,WallpaperService}.swift \
  Tools/CoreCheck/main.swift
"$out/core-check" "${1:-$out/images}"
