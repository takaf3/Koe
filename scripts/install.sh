#!/bin/bash
set -euo pipefail
KOE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$KOE_ROOT/scripts/build.sh"
KOE_DEST="$HOME/Applications/Koe.app"
mkdir -p "$HOME/Applications"
if pgrep -x Koe >/dev/null; then
  printf 'Quit Koe from its menu bar menu, then run this installer again.\n' >&2
  exit 1
fi
ditto "$KOE_ROOT/build/Koe.app" "$KOE_DEST"
open "$KOE_DEST"
printf 'Installed %s\n' "$KOE_DEST"
