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
#  pty; headless nvim has no screen grid to click on), and a WORKING clipboard
#  provider -- pbcopy on macOS, wl-copy/xclip/xsel/win32yank elsewhere, or
#  clip.exe on WSL -- because several cases assert the real '+' register. It is
#  probed, not assumed: pbcopy over ssh and xclip with no display are both
#  installed and both useless. perl is needed only where there is no
#  timeout(1) at all, i.e. macOS; everywhere else bin/timeout hands over to the
#  real one. See NOTES.md for why the harness is shaped the way it is.
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

# Same PATH prefix every suite sets for itself, hoisted here because the
# clipboard preflight below bounds its probes with `timeout` and macOS has no
# timeout(1) -- without this the probe would fail as "command not found" on the
# one platform whose branch was added to be probed. On Linux bin/timeout finds
# the real one and hands over, so nothing about this run changes there.
PATH="$DIR/bin:$PATH"; export PATH

export DRILL_CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"

if [ ! -f "$DRILL_CONFIG" ]; then
  echo "run.sh: no config at $DRILL_CONFIG" >&2; exit 2
fi
command -v nvim >/dev/null || { echo "run.sh: nvim not on PATH" >&2; exit 2; }

# The sidebar suite drives the vendored plugins, so bring them to their pins
# first. Already there, this is an offline no-op; genuinely unfetchable (no
# network, no checkouts) it warns here and suite_tree fails loudly below --
# a gate that silently skipped a feature would be reporting coverage it
# does not have.
"$(cd "$DIR/.." && pwd)/vendor.sh" || echo "run.sh: WARNING -- vendor.sh failed; the sidebar suite will fail"

# The config sets clipboard=unnamedplus, and several cases in suite_config.sh
# assert the REAL '+' register. With no provider those fail for a reason that
# has nothing to do with the keybinding under test, and read as a regression in
# the mapping. Say it once, up front, instead.
CLIP=""
if [ "$(uname -s)" = "Darwin" ]; then
  # pbcopy IS macOS -- it cannot be missing, which is why this used to skip the
  # whole preflight and say so. But present is not working: the pasteboard lives
  # in a per-session pbs, so over ssh or on a CI runner pbcopy can be right there
  # on PATH and still have nothing to talk to. That is the same mistake the
  # xclip branch below already stopped making ("a display name is not a
  # display"), so make it once, in one shape, on both platforms.
  #
  # Both halves, because the register cases need copy AND paste, and pbpaste is
  # the one that actually reads back from pbs.
  #
  # -pboard find, NOT the general pasteboard. macOS has four named pasteboards
  # served by the same pbs, so `find` proves reachability exactly as well while
  # leaving whatever you copied alone -- the general one is destroyed later in
  # the run by the register cases themselves, but only if you actually run
  # them, and `./tests/run.sh timer` should not cost you your clipboard. The
  # non-destructive spelling exists here and has no equivalent below: xsel and
  # wl-copy have no unused selection to borrow (wl-copy offers only clipboard
  # and primary, and primary is the user's too), so that branch still writes,
  # as its own comment already owns.
  #
  # Saving and restoring the GENERAL pasteboard instead would be worse than the
  # bug: pbpaste yields text, so a round-trip silently flattens an image, RTF or
  # a file promise to nothing. On the find board that objection does not apply --
  # it holds the system find string, which is text by definition -- so this one
  # IS put back, and the probe costs you nothing at all. (Worst case a trailing
  # newline: $(...) strips them. That is a search term, not your data.)
  #
  # Compared by VALUE, not by exit code. What the register cases need is a real
  # round trip -- write it, read the same thing back -- and that is the property
  # to assert, not that two processes happened to exit 0.
  #
  # The save GATES the write, and that is the whole safety argument: never put
  # something on a board you have not proved you can put back. Reading first is
  # free, because a failed read is already the answer -- if pbs will not answer
  # a paste, it is not a working provider, CLIP stays empty, and we have written
  # nothing. Restoring unconditionally instead had a real hole: pbpaste hitting
  # the 5s timeout on a merely SLOW pbs leaves FIND_WAS empty, and the restore
  # then clears a find term that was there all along.
  if FIND_WAS="$(timeout 5 pbpaste -pboard find 2>/dev/null)"; then
    if printf x | timeout 5 pbcopy -pboard find >/dev/null 2>&1 &&
       [ "$(timeout 5 pbpaste -pboard find 2>/dev/null)" = x ]; then
      CLIP="pbcopy"
    fi
    printf %s "$FIND_WAS" | timeout 5 pbcopy -pboard find >/dev/null 2>&1
  fi
else
  # Mirror what nvimrc.lua accepts, or this warns when the editor is fine and
  # stays quiet when it is not. Two things that means: the same provider list,
  # and the same display requirement -- an installed xclip with no DISPLAY
  # cannot own a selection, so it is not a provider for this purpose either.
  # ...and here, unlike in nvimrc.lua, ACTUALLY TRY IT. A display name is not a
  # display: DISPLAY=:98765 with xclip installed passes every name-based check
  # and then fails with "Can't open display", producing exactly the register
  # failures this warning exists to explain while the warning stays silent.
  # nvimrc.lua cannot afford this probe -- it would be a subprocess on every
  # editor start -- but run.sh pays it once per suite, before the whole gate.
  # It writes, because a read cannot tell "no display" from "empty clipboard";
  # the suite clobbers the clipboard wholesale anyway.
  for c in wl-copy xclip xsel win32yank.exe lemonade doitclient; do
    command -v "$c" >/dev/null 2>&1 || continue
    case "$c" in
      wl-copy)       printf x | timeout 5 wl-copy >/dev/null 2>&1 || continue ;;
      xclip)         printf x | timeout 5 xclip -selection clipboard >/dev/null 2>&1 || continue ;;
      xsel)          printf x | timeout 5 xsel --clipboard --input >/dev/null 2>&1 || continue ;;
      win32yank.exe) printf x | timeout 5 win32yank.exe -i >/dev/null 2>&1 || continue ;;
      lemonade)      printf x | timeout 5 lemonade copy >/dev/null 2>&1 || continue ;;
      # doitclient and lemonade are network clipboards with no display to
      # check. lemonade has a write command we can run; doitclient does not, so
      # it is accepted on its name -- exactly as nvimrc.lua accepts it. Skipping
      # it instead would print "no clipboard provider" on a box where the editor
      # works fine, which is the same lie in the other direction.
      doitclient)    ;;
    esac
    CLIP="$c"; break
  done
  # The WSL fallback has to be probed too, and it is the one that matters most:
  # clip.exe and powershell.exe are usually PRESENT and can still be unusable if
  # interop is off, and accepting them on filename alone left this silent in
  # exactly that case. Both halves, because nvimrc.lua needs copy AND paste.
  if [ -z "$CLIP" ] && command -v clip.exe >/dev/null 2>&1 &&
     command -v powershell.exe >/dev/null 2>&1 &&
     printf x | timeout 10 clip.exe >/dev/null 2>&1 &&
     timeout 15 powershell.exe -NoProfile -NoLogo -Command Get-Clipboard >/dev/null 2>&1; then
    CLIP="clip.exe"
  fi
fi

if [ -z "$CLIP" ]; then
  echo "run.sh: WARNING -- no working clipboard provider."
  echo "        The cases asserting register '+' will fail for that alone."
  if [ "$(uname -s)" = "Darwin" ]; then
    # Nothing to install. A Mac in this state has no pasteboard server to
    # reach, which is a property of the session, not of the machine.
    echo "        pbcopy/pbpaste are installed but did not answer -- no user"
    echo "        session (ssh, or a CI runner) is the usual reason."
  else
    echo "        apt install wl-clipboard xclip   (see docs/wsl.md on WSL)"
  fi
  echo
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
run "file explorer sidebar"         suite_tree.sh
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
