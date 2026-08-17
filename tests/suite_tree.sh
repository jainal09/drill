#!/bin/bash
# ============================================================================
#  suite_tree.sh -- the Ctrl+B sidebar, driven by real mouse gestures.
#
#  Everything the sidebar promises is a gesture -- click to open, click to
#  expand, toolbar buttons, right-click menu, ctrl-click multi-select, drag a
#  file onto a folder -- and none of it exists in headless nvim (no screen
#  grid, no winbar, no mouse). So tree_drive.py runs the real editor on a pty
#  and writes real SGR mouse sequences, exactly like suite_mouse.sh.
#
#  Needs the pinned checkouts under vendor/ -- run.sh fetches them as a
#  preflight; by hand it is one command: ./vendor.sh
#
#    ./suite_tree.sh          run everything
#    ./suite_tree.sh click    only cases whose name contains "click"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

command -v python3 >/dev/null || { echo "suite_tree.sh: python3 not on PATH" >&2; exit 2; }
if [ ! -d "$DIR/../vendor/nvim-tree.lua/lua" ]; then
  echo "suite_tree.sh: vendor/ is missing -- run ./vendor.sh first" >&2
  exit 1
fi

# Unique socket per run so two checkouts under test cannot collide.
DRILL_SOCK="${TMPDIR:-/tmp}/drill-tree-$$.sock"
export DRILL_CONFIG="$CONFIG" DRILL_SOCK

OUT="$(timeout 300 python3 "$DIR/tree_drive.py")"
RC=$?
rm -f "$DRILL_SOCK"

if [ $RC -ne 0 ] || [ -z "$OUT" ]; then
  echo "suite_tree.sh: driver failed (rc=$RC)" >&2
  [ -n "$OUT" ] && echo "$OUT" >&2
  exit 2
fi

PASS=0; FAIL=0
declare -a BAD=()
while IFS=$'\t' read -r verdict name got; do
  case "$verdict" in PASS|FAIL) ;; *) continue ;; esac
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  if [ "$verdict" = PASS ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name"); printf '\033[31mFAIL\033[0m  %s  -- got: %s\n' "$name" "$got"
  fi
done <<< "$OUT"

echo
echo "=========================================================="
echo "CONFIG=$CONFIG  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
