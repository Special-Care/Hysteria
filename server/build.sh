#!/usr/bin/env bash
# Concatenates server/src/*.sh (deterministic lexical order) into server/hy2.sh.
#
# server/hy2.sh is a BUILD ARTIFACT — do not hand-edit it. Edit the files under
# server/src/ and re-run this script. Module ordering is by filename, so the
# NNN- numeric prefixes control concatenation order; 90-main.sh (the top-level
# dispatcher) must sort last so every function is defined before it runs.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT="$SCRIPT_DIR/hy2.sh"

shopt -s nullglob
export LC_ALL=C
cat "$SCRIPT_DIR"/src/*.sh > "$OUT"
chmod +x "$OUT"
echo "Built $OUT"
