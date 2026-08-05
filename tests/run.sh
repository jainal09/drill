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
#  Requires: nvim 0.9+, zsh (the timer suite runs drill.sh under bash AND
#  zsh -- they disagree about word splitting), python3 (the mouse suite needs a
#  pty; headless nvim has no screen grid to click on), and a clipboard provider
#  -- wl-copy/xclip/xsel/win32yank, or clip.exe on WSL -- because several cases
#  assert the real '+' register. perl is needed only where there is no
#  timeout(1) at all, i.e. macOS; everywhere else bin/timeout hands over to the
#  real one. See NOTES.md for why the harness is shaped the way it is.
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

export DRILL_CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"

if [ ! -f "$DRILL_CONFIG" ]; then
  echo "run.sh: no config at $DRILL_CONFIG" >&2; exit 2
fi
command -v nvim >/dev/null || { echo "run.sh: nvim not on PATH" >&2; exit 2; }

# The config sets clipboard=unnamedplus, and several cases in suite_config.sh
# assert the REAL '+' register. With no provider those fail for a reason that
# has nothing to do with the keybinding under test, and read as a regression in
# the mapping. Say it once, up front, instead. macOS always has pbcopy, so this
# is silent there.
if [ "$(uname -s)" != "Darwin" ]; then
  # Mirror what nvimrc.lua accepts, or this warns when the editor is fine and
  # stays quiet when it is not. Two things that means: the same provider list,
  # and the same display requirement -- an installed xclip with no DISPLAY
  # cannot own a selection, so it is not a provider for this purpose either.
  CLIP=""
  for c in wl-copy xclip xsel win32yank.exe lemonade doitclient; do
    command -v "$c" >/dev/null 2>&1 || continue
    case "$c" in
      wl-copy)      [ -n "${WAYLAND_DISPLAY:-}" ] || continue ;;
      xclip|xsel)   [ -n "${DISPLAY:-}" ]         || continue ;;
    esac
    CLIP="$c"; break
  done
  # on WSL nvimrc.lua falls back to these two, so they count as a provider
  if [ -z "$CLIP" ] && command -v clip.exe >/dev/null 2>&1 &&
     command -v powershell.exe >/dev/null 2>&1; then CLIP="clip.exe"; fi
  if [ -z "$CLIP" ]; then
    echo "run.sh: WARNING -- no clipboard provider on PATH."
    echo "        The cases asserting register '+' will fail for that alone."
    echo "        apt install wl-clipboard xclip   (see docs/wsl.md on WSL)"
    echo
  fi
fi

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
  # count SUITES, not exit codes. Adding up rc called 30 failing timer cases
  # "2 FAILING CASE(S)" (one suite exiting 1, another 2) -- a number small
  # enough to look like a flake when it was a whole feature broken.
  [ $rc -ne 0 ] && TOTAL_FAIL=$((TOTAL_FAIL + 1))
  echo
  return 0
}

run "config invariants"             suite_options.sh
run "config regressions"            suite_config.sh
run "mouse: click to caret"         suite_mouse.sh
run "find + search highlight"       suite_search.sh
run "autosave"                      suite_autosave.sh
run "quit confirmation"             suite_quit.sh
run "run-window lifecycle"          suite_runwin.sh
run "directory listing"             suite_netrw.sh
run "shell: timer"                  suite_timer.sh
run "shell: projects + search"      suite_projects.sh
run "preload: the LeetCode desk"    suite_preload.sh

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
echo "# $TOTAL_FAIL FAILING SUITE(S) -- scroll up for the cases, and do not push"
echo "############################################################"
exit 1
