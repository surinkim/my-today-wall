#!/bin/zsh
# BingClient·ImageStore·WallpaperService를 커맨드라인으로 빌드해 실제 Bing API로 동작을 확인한다.
# 사용법: scripts/check-core.sh [저장 폴더]   (기본: 임시 폴더, 실제 ~/Pictures는 건드리지 않음)
set -euo pipefail
cd "$(dirname "$0")/.."

out="${TMPDIR:-/tmp}/mytodaywall-core-check"
mkdir -p "$out"
xcrun swiftc -swift-version 5 -o "$out/core-check" \
  MyTodayWall/{Log,DateFormatting,BingClient,ImageStore,WallpaperService}.swift \
  Tools/CoreCheck/main.swift
"$out/core-check" "${1:-$out/images}"
