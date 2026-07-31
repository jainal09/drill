#!/bin/bash
# ============================================================================
#  mousecheck.sh -- does this terminal send mouse events to the program at all?
#
#  Run it IN the window you drill in. It turns mouse reporting on by hand
#  (exactly the sequences nvim sends), waits for you to click, and prints the
#  raw bytes that arrived. If nothing arrives, nothing nvim does can help --
#  the click never left the terminal.
# ============================================================================
printf '\n'
printf 'TERM  = %s\n' "${TERM:-<unset>}"
printf 'TMUX  = %s\n' "${TMUX:-<not in tmux>}"
if [ -n "${TMUX:-}" ]; then
  printf 'tmux mouse = %s   (must be "on")\n' "$(tmux show -gv mouse 2>/dev/null)"
fi
printf 'STY   = %s\n' "${STY:-<not in screen>}"
printf '\n'

cleanup() { printf '\033[?1006l\033[?1002l\033[?1000l'; stty "$SAVED" 2>/dev/null; }
SAVED=$(stty -g)
trap cleanup EXIT INT

printf '\033[?1000h\033[?1002h\033[?1006h'      # what nvim asks for
stty raw -echo

printf 'Click anywhere in this window now (waiting 6 seconds)...\r\n'
BYTES=$(dd bs=1 count=64 2>/dev/null <&0 & sleep 6; kill $! 2>/dev/null; wait 2>/dev/null)

cleanup; trap - EXIT INT
printf '\n\n'
if [ -z "$BYTES" ]; then
  printf 'RESULT: nothing arrived -- this terminal is NOT sending mouse events.\n'
  printf '        iTerm2: Settings > Profiles > Terminal > "Enable mouse reporting"\n'
  printf '        tmux:   set -g mouse on\n'
else
  printf 'RESULT: mouse events ARE arriving. Raw bytes:\n'
  printf '%s' "$BYTES" | cat -v
  printf '\n        (an SGR click looks like ^[[<0;COL;ROWM ... m)\n'
fi
printf '\n'
