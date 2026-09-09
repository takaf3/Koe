#!/bin/bash
set -euo pipefail
KOE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KOE_ROOT"
mkdir -p build
xcodebuild -project Koe.xcodeproj -scheme Koe -configuration Release \
  -derivedDataPath .derivedData -destination 'generic/platform=macOS' build > build/release.log 2>&1 || {
    tail -n 80 build/release.log
    exit 1
  }
ditto .derivedData/Build/Products/Release/Koe.app build/Koe.app
codesign --verify --deep --strict build/Koe.app
printf 'Built %s/build/Koe.app\n' "$KOE_ROOT"
