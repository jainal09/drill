#!/bin/bash
# ============================================================================
#  keycheck.sh -- does this terminal forward Cmd chords to the program at all?
#
#  Run it IN the window you drill in, then press the chord you are wondering
#  about (say Cmd+Z). It prints the raw bytes that arrived. If nothing
#  arrives, nothing nvim can do will help -- the chord never left the
#  terminal, and docs/macos-cmd.md is the page that fixes that.
#
#  It pushes the kitty keyboard protocol itself (CSI > 1 u) before reading,
#  because that is the state nvim runs in -- and iTerm2's "Left Command key:
#  Super" setting only forwards Cmd WHILE a program speaks the protocol, so
#  testing at a bare prompt would wrongly say "nothing arrives".
# ============================================================================
printf '\n'
printf 'TERM  = %s\n' "${TERM:-<unset>}"
printf 'TMUX  = %s\n' "${TMUX:-<not in tmux>}"
printf '\n'

cleanup() { printf '\033[<u'; stty "$SAVED" 2>/dev/null; }
SAVED=$(stty -g)
# 'isig' below hands the terminal back its signal keys, so they have to land
# somewhere: cleanup rides EXIT alone, and each signal EXITS to get there. A
# bare "trap cleanup INT" would not do -- bash runs the handler and then
# RESUMES the script, so a Ctrl+C would restore the terminal and then still
# report "nothing arrived", calling a deliberate abort a failed forward.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 131' QUIT
trap 'exit 129' HUP

printf '\033[>1u'                               # the protocol nvim negotiates
# isig, because plain 'raw' clears it: Ctrl+C would then arrive as a byte in
# BYTES and the script would report "something arrived" for a user giving up.
stty raw -echo isig

printf 'Press ONE Cmd chord now, e.g. Cmd+Z (Ctrl+C aborts; waiting 6 seconds)...\r\n'
BYTES=$(dd bs=1 count=32 2>/dev/null <&0 & sleep 6; kill $! 2>/dev/null; wait 2>/dev/null)

cleanup; trap - EXIT INT TERM QUIT HUP
printf '\n\n'
if [ -z "$BYTES" ]; then
  printf 'RESULT: nothing arrived -- this terminal did NOT forward the chord.\n'
  printf '        The terminal handled it itself (its own Copy, Paste, menu...).\n'
  printf '        See docs/macos-cmd.md for the per-terminal setting that\n'
  printf '        forwards Cmd, then run this again.\n'
else
  printf 'RESULT: something arrived. Raw bytes:\n'
  printf '%s' "$BYTES" | cat -v
  printf '\n\n'
  printf 'A forwarded Cmd chord reads ^[[<code>;<mod>u -- Cmd+Z is ^[[122;9u.\n'
  printf 'The mod is 1 + its bits: Shift 1, Option 2, Ctrl 4, Cmd 8 -- so 9\n'
  printf 'is Cmd alone and 10 is Cmd+Shift. If you see that shape, drill'"'"'s\n'
  printf '<D-...> mappings will fire. Anything else (a bare letter, ^C, ^V)\n'
  printf 'means the terminal translated the chord instead of forwarding it.\n'
fi
printf '\n'
