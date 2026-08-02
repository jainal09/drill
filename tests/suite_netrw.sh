#!/bin/bash
# ============================================================================
#  suite_netrw.sh -- the directory listing must not be mistaken for a file.
#
#  netrw's buftype is EMPTY, so every guard written as `buftype ~= ""` sails
#  straight through the bare `d` listing. Two bugs came from exactly that:
#  Ctrl+S wedged the editor behind a modal "Press ENTER", and Ctrl+E opened a
#  split running `python3 -i ''` (expand("%:p") is "" there, and "" is TRUTHY
#  in Lua, so the `if not f` guard never fired).
#
#  pty, NOT headless: headless nvim opened on a directory does not produce a
#  netrw buffer at all -- measured, filetype "", modifiable true, and a real
#  filename -- so every guard behaves differently and the suite would be
#  asserting a reality no user is ever in.
#
#    ./suite_netrw.sh          run everything
#    ./suite_netrw.sh ctrl_s   only cases whose name contains "ctrl_s"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

command -v python3 >/dev/null || { echo "suite_netrw.sh: python3 not on PATH" >&2; exit 2; }

# Unique socket per run so two checkouts under test cannot collide.
DRILL_SOCK="${TMPDIR:-/tmp}/drill-netrw-$$.sock"
export DRILL_CONFIG="$CONFIG" DRILL_SOCK

OUT="$(timeout 240 python3 "$DIR/netrw_drive.py")"
RC=$?
rm -f "$DRILL_SOCK"

if [ $RC -ne 0 ] || [ -z "$OUT" ]; then
  echo "suite_netrw.sh: driver failed (rc=$RC)" >&2
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
