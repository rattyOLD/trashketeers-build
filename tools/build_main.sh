#!/usr/bin/env bash
# Build a tested release locally; publishing remains an explicit git push.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-godot}
LOG=${LOG:-/tmp/trashsquad-release}
PROJECT=$(mktemp -d /tmp/trashsquad-project.XXXXXX)
trap 'rm -rf "$PROJECT"' EXIT
mkdir -p "$LOG" "$ROOT/source/build/web"
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$LOG/editor-config}
python3 - "$ROOT/source" "$PROJECT" <<'PY'
import shutil, sys
shutil.copytree(sys.argv[1], sys.argv[2], dirs_exist_ok=True, ignore=shutil.ignore_patterns('.godot', 'build'))
PY
cd "$ROOT"
python3 tools/validate_v32_art.py
XDG_DATA_HOME="$LOG/user" GODOT="$GODOT" LOG="$LOG" bash tools/verify.sh "$PROJECT"
"$GODOT" --headless --path "$PROJECT" --export-release Web "$ROOT/source/build/web/index.html" > "$LOG/export.log" 2>&1
if rg -q 'SCRIPT ERROR|Export failed' "$LOG/export.log"; then
    cat "$LOG/export.log"
    exit 1
fi
python3 tools/make_site.py "$ROOT/source/build/web" > "$LOG/site.log"
echo "Release build ready: $ROOT/tools/site"
