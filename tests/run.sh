#!/bin/bash
# ============================================================================
#  tests/run.sh -- the pre-push gate for drill.
#
#  Every keybinding in nvimrc.lua is asserted by driving the REAL config in
#  headless nvim, feeding real keycodes, and diffing the resulting buffer.
#  Nothing here mocks anything: if a test passes, that keystroke does that
#  thing in that config.
#
#    ./tests/run.sh              everything (both suites, all Ctrl+/ spellings)
#    ./tests/run.sh sel_         only cases whose name contains "sel_"
#
#  Exit code is 0 only if every case passes. Run it before you push.
#
#  Requires: nvim 0.9+, perl (for the `timeout` shim -- macOS ships no
#  GNU coreutils), python3 (the mouse suite needs a pty; headless nvim has no
#  screen grid to click on). See NOTES.md for why the harness is shaped the
#  way it is.
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

export DRILL_CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"

if [ ! -f "$DRILL_CONFIG" ]; then
  echo "run.sh: no config at $DRILL_CONFIG" >&2; exit 2
fi
command -v nvim >/dev/null || { echo "run.sh: nvim not on PATH" >&2; exit 2; }

echo "config: $DRILL_CONFIG"
echo "nvim:   $(nvim --version | head -1)"
echo

TOTAL_FAIL=0

run() {                                  # run <label> <script> [env assignments]
  local label="$1"; shift
  local script="$1"; shift
  echo "############################################################"
  echo "# $label"
  echo "############################################################"
  env "$@" "$DIR/$script" "$FILTER"
  local rc=$?
  [ $rc -ne 0 ] && TOTAL_FAIL=$((TOTAL_FAIL + rc))
  echo
  return 0
}

run "config invariants"             suite_options.sh
run "config regressions"            suite_config.sh
run "mouse: click to caret"         suite_mouse.sh
run "find + search highlight"       suite_search.sh

# Ctrl+/ has no legacy control byte, so a terminal sends it EITHER as 0x1F
# (<C-_>) or, with the kitty/CSI-u protocol negotiated, as ESC[47;5u (<C-/>).
# Those are DIFFERENT keys to nvim -- "\31" vs "\128\252\4/" -- so each spelling
# is a separate mapping and each gets its own full pass.
for KEY in '<C-_>' '<C-/>' '<C-S-/>'; do
  run "comment toggle -- KEY=$KEY" suite_comment.sh "KEY=$KEY"
done

echo "############################################################"
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "# ALL SUITES PASSED"
  echo "############################################################"
  exit 0
fi
echo "# $TOTAL_FAIL FAILING CASE(S) -- do not push"
echo "############################################################"
exit 1
