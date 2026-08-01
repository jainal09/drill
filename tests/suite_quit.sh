#!/bin/bash
# ============================================================================
#  suite_quit.sh -- Ctrl+Shift+Q and its confirmation.
#
#  Asserts that the exit is reachable without ever touching the command line:
#  the chord raises a confirmation, Cancel and Esc both put you back in insert
#  with nothing typed and nothing lost, and Quit writes the file and goes --
#  from inside the interpreter too.
#
#  pty-only, for two independent reasons: <C-S-q> only exists under CSI-u (in
#  the legacy encoding it is byte-identical to <C-q>, which is visual block
#  here), and a blocking confirmation cannot be answered by headless feedkeys
#  nor read by any API -- it is only ever drawn on the screen.
#
#    ./suite_quit.sh          run everything
#    ./suite_quit.sh cancel   only cases whose name contains "cancel"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

command -v python3 >/dev/null || { echo "suite_quit.sh: python3 not on PATH" >&2; exit 2; }

# Unique socket per run so two checkouts under test cannot collide.
DRILL_SOCK="${TMPDIR:-/tmp}/drill-quit-$$.sock"
export DRILL_CONFIG="$CONFIG" DRILL_SOCK

OUT="$(timeout 240 python3 "$DIR/quit_drive.py")"
RC=$?
rm -f "$DRILL_SOCK"

if [ $RC -ne 0 ] || [ -z "$OUT" ]; then
  echo "suite_quit.sh: driver failed (rc=$RC)" >&2
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
