#!/bin/bash
# ============================================================================
#  suite_runwin.sh -- the lifecycle of the Ctrl+R output window.
#
#  A finished run window closes itself the moment you leave it; a still-running
#  one does not. Before that rule you could only dismiss it from INSIDE -- go
#  back to the file first and it stayed for good, with no key in the config
#  able to close it and Ctrl+E stacking a third window underneath.
#
#  pty-only: every case is a window count or a terminal-job state, and headless
#  nvim has neither a screen to split nor a job whose liveness means anything.
#
#    ./suite_runwin.sh          run everything
#    ./suite_runwin.sh leaving  only cases whose name contains "leaving"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

command -v python3 >/dev/null || { echo "suite_runwin.sh: python3 not on PATH" >&2; exit 2; }

# Unique socket per run so two checkouts under test cannot collide.
DRILL_SOCK="${TMPDIR:-/tmp}/drill-runwin-$$.sock"
export DRILL_CONFIG="$CONFIG" DRILL_SOCK

OUT="$(timeout 240 python3 "$DIR/runwin_drive.py")"
RC=$?
rm -f "$DRILL_SOCK"

if [ $RC -ne 0 ] || [ -z "$OUT" ]; then
  echo "suite_runwin.sh: driver failed (rc=$RC)" >&2
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
