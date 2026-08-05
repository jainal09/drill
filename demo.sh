#!/bin/bash
# ============================================================================
#  demo.sh -- drive the drill editor through every feature, for screen capture.
#
#  Start your recorder (and your keystroke-display app), run this, and don't
#  touch the keyboard. It types, clicks, runs, and narrates itself.
#
#    ./demo.sh                    the whole tour
#    ./demo.sh --list             what the chapters are
#    ./demo.sh --only find        just one chapter
#    ./demo.sh --only find,mouse  a few
#    ./demo.sh --speed 0.5        half the pauses (2 = twice as slow)
#    ./demo.sh --keys socket      send keys to nvim directly (see below)
#    ./demo.sh --check            dry-run the risky chords and report -- do this
#                                 BEFORE you record, not during
#
#  HOW THE KEYS ARE SENT, and why it matters for your recording
#  -----------------------------------------------------------
#  A keystroke-display app (KeyCastr and friends) watches the OS event stream.
#  It can only show keys that really went through it.
#
#    --keys system   (default when permitted)  presses the keys through macOS
#                    System Events, so they are real events and your keycast
#                    app shows them. The terminal must stay FRONTMOST -- the
#                    keys go wherever the focus is, so do not switch windows.
#
#    --keys socket   sends straight into nvim over --listen. Rock solid, works
#                    over ssh and on Linux, needs no permissions -- but the
#                    keys never touch the OS, so a keycast app shows NOTHING.
#
#  Either way the on-screen caption names the key being pressed, so the
#  recording is readable even with no keycast app at all.
#
#  macOS will ask to allow "Accessibility" control for your terminal the first
#  time. If you decline, this falls back to --keys socket and says so.
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${DRILL_CONFIG:-$HERE/nvimrc.lua}"
SPEED="${DEMO_SPEED:-1}"
KEYMODE="auto"
ONLY=""
LIST=0
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list)   LIST=1; shift ;;
    --check)  CHECK=1; shift ;;
    --only)   ONLY="$2"; shift 2 ;;
    --speed)  SPEED="$2"; shift 2 ;;
    --keys)   KEYMODE="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "demo.sh: unknown argument $1 (try --help)" >&2; exit 2 ;;
  esac
done

CHAPTERS="shell typing comment indent select clipboard find mouse autosave undo run repl quit"

if [ "$LIST" = 1 ]; then
  echo "chapters, in order:"
  echo "  shell      d / ds / r / ri and the timer, incl. t -l and t -k"
  echo "  typing     type code with nothing helping -- no popup, ever"
  echo "  comment    Ctrl+/ on a line and on a selection"
  echo "  indent     Tab / Shift+Tab over a selection"
  echo "  select     Shift+arrows, and typing over a selection"
  echo "  clipboard  Ctrl+C / Ctrl+X / Ctrl+V against the system clipboard"
  echo "  find       Ctrl+F, and the highlight clearing when you type again"
  echo "  mouse      click anywhere -- blank lines and past end-of-line included"
  echo "  autosave   the file writing itself, no Ctrl+S"
  echo "  undo       Ctrl+Z / Ctrl+Y"
  echo "  run        Ctrl+R -- save and run in a split"
  echo "  repl       Ctrl+E -- the interpreter, and coming back still typing"
  echo "  quit       Ctrl+Shift+Q and its confirmation"
  exit 0
fi

command -v nvim >/dev/null || { echo "demo.sh: nvim not on PATH" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "demo.sh: no config at $CONFIG" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/drill-demo.XXXXXX")"
SOCK="$WORK/demo.sock"
FILE="$WORK/bfs.py"
trap 'rm -rf "$WORK"; pkill -f "drill-demo-timer" 2>/dev/null; true' EXIT

# ---------------------------------------------------------------------------
# how keys get pressed
# ---------------------------------------------------------------------------
# The permission probe asks System Events a QUESTION rather than sending a
# keystroke: if Accessibility is not granted this fails harmlessly, where a
# test keystroke would have been typed into whatever happens to be focused.
can_system_events() {
  [ "$(uname)" = "Darwin" ] || return 1
  osascript -e 'tell application "System Events" to return name of first process whose frontmost is true' \
    >/dev/null 2>&1
}

if [ "$KEYMODE" = "auto" ]; then
  if can_system_events; then KEYMODE=system; else KEYMODE=socket; fi
fi

if [ "$KEYMODE" = "system" ] && ! can_system_events; then
  echo "demo.sh: System Events is not permitted, falling back to --keys socket." >&2
  echo "         (your keycast app will not show the keys; the captions still name them)" >&2
  KEYMODE=socket
fi

# nvim's own notation, used for --keys socket and for the caption text
# spec                nvim notation      applescript
#   C-e               <C-e>              keystroke "e" using {control down}
#   CS-q              <C-S-q>            keystroke "q" using {control down, shift down}
#   Esc CR Tab BS     <Esc> <CR> ...     key code 53 / 36 / 48 / 51
_nvim_notation() {
  case "$1" in
    CR) printf '<CR>' ;;  Esc) printf '<Esc>' ;;  Tab) printf '<Tab>' ;;
    BS) printf '<BS>' ;;  Space) printf '<Space>' ;;
    S-Tab) printf '<S-Tab>' ;;
    Up|Down|Left|Right) printf '<%s>' "$1" ;;
    S-Up|S-Down|S-Left|S-Right) printf '<%s>' "$1" ;;
    C-_) printf '<C-_>' ;;
    C-*) printf '<%s>' "$1" ;;
    CS-*) printf '<C-S-%s>' "${1#CS-}" ;;
    *) printf '%s' "$1" ;;
  esac
}

_applescript_for() {
  local k="$1"
  case "$k" in
    CR)    echo 'key code 36' ;;
    Esc)   echo 'key code 53' ;;
    Tab)   echo 'key code 48' ;;
    S-Tab) echo 'key code 48 using {shift down}' ;;
    BS)    echo 'key code 51' ;;
    Space) echo 'key code 49' ;;
    Left)  echo 'key code 123' ;;  Right) echo 'key code 124' ;;
    Down)  echo 'key code 125' ;;  Up)    echo 'key code 126' ;;
    S-Left)  echo 'key code 123 using {shift down}' ;;
    S-Right) echo 'key code 124 using {shift down}' ;;
    S-Down)  echo 'key code 125 using {shift down}' ;;
    S-Up)    echo 'key code 126 using {shift down}' ;;
    # Ctrl+/ -- `key code 44`, NOT `keystroke "/"`. AppleScript's keystroke is
    # unreliable at applying a modifier to PUNCTUATION: measured, `keystroke "/"
    # using {control down}` dropped the Ctrl and typed a literal slash, so the
    # comment chapter put "//" into a python file instead of toggling "#" twice.
    # Letters are fine, which is why every other chord here still uses keystroke.
    # 44 is "/" on a US layout; on another layout, use --keys socket.
    C-_)   echo 'key code 44 using {control down}' ;;
    CS-*)  printf 'keystroke "%s" using {control down, shift down}\n' "$(printf '%s' "${k#CS-}" | tr 'A-Z' 'a-z')" ;;
    C-*)   printf 'keystroke "%s" using {control down}\n' "$(printf '%s' "${k#C-}" | tr 'A-Z' 'a-z')" ;;
    *)     printf 'keystroke "%s"\n' "$k" ;;
  esac
}

# </dev/null on BOTH, and it is not tidiness. The --server client is a full
# nvim: with a tty on stdin it starts a TUI, which means it takes the alternate
# screen and hands it back (ESC[?1049h ... ESC[?1049l) on EVERY call -- the
# whole recording flickers, once per caption and once per key. And with stdout
# captured, its terminal-capability probes (ESC[?69$p and friends) land inside
# $( ), so a helper that should return a line number returns a pile of escape
# sequences instead. Measured, same command, inside a pty:
#     without  ->  [^[[?1049h^[[?1h^[= ... ^[[?1049l]
#     with     ->  [42]
nv()  { nvim --server "$SOCK" --remote-send "$1" </dev/null >/dev/null 2>&1; }
nvx() { nvim --server "$SOCK" --remote-expr "$1" </dev/null 2>/dev/null; }

# secs <factor> -- <factor> * $SPEED, as a number `sleep` will take.
#
# This was `bc`, which is NOT installed by default on Debian or Ubuntu, and so
# not on most WSL images. It is called once per keystroke, once per caption and
# once per pause, and the failure is silent: there is no `set -e` here, so a
# missing bc makes every `$( )` empty, every `sleep ""` an error, and the demo
# races through at full speed printing "sleep: missing operand" instead of
# recording anything. awk ships with both macOS and every Linux, and returns
# the same numbers.
secs() { awk -v f="$1" -v s="$SPEED" 'BEGIN { printf "%.4f", f * s }'; }

# key <spec> -- press one key
key() {
  local spec="$1"
  if [ "$KEYMODE" = system ]; then
    osascript -e "tell application \"System Events\" to $(_applescript_for "$spec")" >/dev/null 2>&1
  else
    nv "$(_nvim_notation "$spec")"
  fi
  sleep "$(secs 0.09)"
}

# Escape for an AppleScript double-quoted literal. Written out by hand because
# macOS ships bash 3.2, where ${var@Q} does not exist -- and it fails at RUN
# time, not at parse time, so `bash -n` says the script is fine right up until
# the first line it tries to type.
_as_quote() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# type <text> -- type it a character at a time, like a person
type_text() {
  local text="$1" per; per="$(secs 0.045)"
  if [ "$KEYMODE" = system ]; then
    # one osascript for the whole string: spawning a process per character
    # makes even short lines take seconds
    osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
  repeat with c in characters of "$(_as_quote "$text")"
    keystroke (c as text)
    delay $per
  end repeat
end tell
APPLESCRIPT
  else
    local i ch
    for (( i=0; i<${#text}; i++ )); do
      ch="${text:$i:1}"
      case "$ch" in
        '<') nv '<lt>' ;;
        ' ') nv '<Space>' ;;
        *)   nv "$ch" ;;
      esac
      sleep "$per"
    done
  fi
}

pause() { sleep "$(secs "$1")"; }

# wait_for <text> -- block until <text> shows up in the current buffer's tail.
# NOT a longer sleep: every pause here is multiplied by --speed, so a fixed wait
# for python to boot is exactly as wrong as the speed is low. Measured at
# --speed 0.3 the REPL chapter typed into a terminal that had not printed its
# prompt yet and the interpreter ate the first character -- "bfs(g, (0,0))"
# arrived as "fs(g, (0,0))" and the demo recorded a NameError.
wait_for() {
  local i n; n="${2:-60}"
  for i in $(seq 1 "$n"); do
    case "$(nvx "getline(line('$') > 3 ? line('$') - 3 : 1) . getline('$') . getline(line('$') - 1)")" in
      *"$1"*) return 0 ;;
    esac
    sleep 0.2
  done
  return 1
}

# ---------------------------------------------------------------------------
# the caption bar
# ---------------------------------------------------------------------------
# A floating window pinned to the top of the editor, so every step says what it
# is doing and which key is doing it. focusable=false and noautocmd, so it can
# never steal focus, take a click, or fire the config's own autocmds.
cat > "$WORK/caption.lua" <<'LUA'
-- The caption lives in the TABLINE, not a floating window. A float pinned to
-- row 0 sits ON TOP of the first line of your code -- in a 14-line demo file
-- that is 7% of the screen hidden behind the narration. 'showtabline=2' takes
-- a screen row of its own instead, so nothing is ever covered, and it survives
-- the <C-e> split without any repositioning logic.
vim.api.nvim_set_hl(0, "DemoCaption", { fg = "#0b0b0b", bg = "#d7af5f", bold = true })
vim.api.nvim_set_hl(0, "DemoKey",     { fg = "#d7af5f", bg = "#0b0b0b", bold = true })

_G.DrillDemoKey, _G.DrillDemoText = "", ""

function _G.DrillDemoTabline()
  local k, t = _G.DrillDemoKey, _G.DrillDemoText
  if k ~= "" then
    return "%#DemoKey#  " .. k .. "  %#DemoCaption#   " .. t .. "%#DemoCaption#%="
  end
  return "%#DemoCaption#  " .. t .. "%="
end

vim.o.showtabline = 2
vim.o.tabline = "%!v:lua.DrillDemoTabline()"

function _G.DrillDemoSay(k, text)
  _G.DrillDemoKey, _G.DrillDemoText = k, text
  vim.cmd("redrawtabline | redraw")
  return 1
end

-- Clicks are injected rather than made with a real pointer: a keystroke-display
-- app would not show a mouse anyway, and this way the demo needs no control of
-- the physical cursor. It is the same code path a real click takes -- a UI is
-- attached, so the screen grid these coordinates address is real.
--
-- Addressed by BUFFER LINE, not by grid row. screenpos() does the conversion,
-- so the tabline, any scrolling, and the <C-e> split cannot silently shift
-- every click down by a row.
function _G.DrillDemoClickLine(lnum, col)
  local p = vim.fn.screenpos(0, lnum, 1)
  if p.row == 0 then return 0 end            -- that line is not on screen
  vim.api.nvim_input_mouse("left", "press", "", 0, p.row - 1, col)
  vim.api.nvim_input_mouse("left", "release", "", 0, p.row - 1, col)
  return 1
end

-- first blank line in the buffer, so "click on a blank line" is never a claim
-- about a line that happens to have code on it today
function _G.DrillDemoBlank()
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l == "" then return i end
  end
  return 1
end

-- line number of the first line matching a plain substring, without touching
-- the / register the way search() would -- the find chapter asserts on that
function _G.DrillDemoFind(needle)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(needle, 1, true) then return i end
  end
  return 1
end
LUA

say() {   # say <key-label> <text>
  local k="${1//\'/}" t="${2//\'/}"
  nvx "luaeval('DrillDemoSay(_A[1], _A[2])', ['$k', '$t'])" >/dev/null 2>&1
}
# click <buffer-line> <screen-col>
click() { nvx "luaeval('DrillDemoClickLine(_A[1], _A[2])', [$1, $2])" >/dev/null 2>&1; }
blank_line() { nvx "luaeval('DrillDemoBlank()')" 2>/dev/null; }
# put the caret on the first line containing <text>, without using search()
goto() { nv "<Cmd>call cursor(luaeval(\"DrillDemoFind('$1')\"), ${2:-1})<CR>"; }
line_of() { nvx "luaeval(\"DrillDemoFind('$1')\")" 2>/dev/null; }
click_text()  { click "$(line_of "$1")" "$2"; }
click_blank() { click "$(blank_line)" "$1"; }

# step <key-label> <caption> [settle]
step() { say "$1" "$2"; pause "${3:-1.1}"; }

wants() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# part 1 -- the shell, before the editor is even open
# ---------------------------------------------------------------------------
FAKE_PROMPT=$'\033[1;32m~\033[0m $ '
shell_line() {                       # type a command at a fake prompt, then run it
  printf '%b' "$FAKE_PROMPT"
  local i
  for (( i=0; i<${#1}; i++ )); do printf '%s' "${1:$i:1}"; sleep "$(secs 0.04)"; done
  printf '\n'
  pause 0.4
}

demo_shell() {
  clear
  cat <<'BANNER'

   drill -- a terminal coding-drill environment where nothing helps you type

   no completion, no LSP, no AI, no plugins. you type it from memory,
   you run it, you see it pass or fail.

BANNER
  pause 2.2
  printf '   the shell side: three commands to open a file, two to run one, one timer\n\n'
  pause 1.6

  shell_line "d bfs            # ~/drill/scratch/bfs.py, in the isolated editor"
  shell_line "ds day1          # solves/    dt heap      # templates/"
  shell_line "r bfs            # python3 bfs.py, from anywhere"
  shell_line "ri bfs           # python3 -i bfs.py -- REPL with its names live"
  pause 0.8
  printf '\n'

  shell_line "t                # 25-minute timer, counts down in the window title"
  DRILL_TIMER_TAG=drill-demo-timer
  ( python3 - "$DRILL_TIMER_TAG" >/dev/null 2>&1 <<'PY' & ) 2>/dev/null
import sys, time
end = time.monotonic() + 1500
try: tty = open("/dev/tty", "w")
except OSError: sys.exit()
while time.monotonic() < end:
    left = end - time.monotonic()
    m, s = divmod(int(left + 0.5), 60)
    tty.write("\033]0;%02d:%02d drill\007" % (m, s)); tty.flush()
    time.sleep(0.5)
PY
  sleep 1
  printf '   timer: 25 min, id %s (counts down in the window title)\n' "$(pgrep -f drill-demo-timer | head -1)"
  printf '          stop it with:  t -k %s      (or just  t -k)\n\n' "$(pgrep -f drill-demo-timer | head -1)"
  pause 2.2
  shell_line "t -l             # is one running?"
  printf '   timer: running, id %s\n\n' "$(pgrep -f drill-demo-timer | head -1)"
  pause 1.4
  shell_line "t -k             # stop it -- and clear the title it froze"
  pkill -f drill-demo-timer 2>/dev/null
  printf '\033]0;\007'
  printf '   timer: stopped\n\n'
  pause 1.8
  printf '   an id that is not a live timer is refused, not obeyed -- a finished\n'
  printf '   timer%ss pid gets recycled, and t -k off old scrollback would fire at\n' "'"
  printf '   whatever holds it now.\n\n'
  pause 2.6
}

# ---------------------------------------------------------------------------
# the editor
# ---------------------------------------------------------------------------
start_editor() {
  cat > "$FILE" <<'PY'
# idea: breadth-first search over a grid, counting what it reaches
from collections import deque


def bfs(grid, start):
    rows, cols = len(grid), len(grid[0])
    seen = set()
    return len(seen)


g = [["1", "1", "0"],
     ["0", "1", "0"],
     ["0", "0", "1"]]
print(bfs(g, (0, 0)))
PY
  rm -f "$SOCK"
  nvim --listen "$SOCK" -i NONE -u "$CONFIG" \
       -c "luafile $WORK/caption.lua" "$FILE" &
  NVIM_PID=$!
  local i
  for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.15; done
  sleep 1.2
}

editor_alive() { nvim --server "$SOCK" --remote-expr 1 >/dev/null 2>&1; }

demo_typing() {
  step "" "you are already in insert mode -- no i, no Esc, ever" 2.0
  step "" "type it from memory. nothing completes, nothing suggests, no popup." 2.2
  goto "seen = set()" 1
  key Esc; nv 'o'
  type_text "q = deque([start])"
  key CR
  type_text "seen.add(start)"
  pause 1.4
  step "" "no popup appeared -- completion is absent at every source, not merely off" 2.4
}

demo_comment() {
  step "C-/" "comment or uncomment the line you are on" 1.6
  goto "rows, cols" 5
  key C-_ ; pause 1.3
  key C-_ ; pause 1.0
  step "C-/" "...or every line you have selected" 1.6
  goto "rows, cols" 1
  key S-Down; key S-Down; pause 0.6
  key C-_ ; pause 1.6
  key C-_ ; pause 1.2
  step "" "one indent for the whole block, blank lines untouched, round trip exact" 2.4
}

demo_indent() {
  step "Tab" "indent the selection -- Tab is indent only when something is selected" 1.8
  goto "rows, cols" 1
  key S-Down; key S-Down; pause 0.5
  key Tab; pause 1.1
  key Tab; pause 1.1
  step "S-Tab" "and back" 1.2
  key S-Tab; pause 0.9
  key S-Tab; pause 1.2
}

demo_select() {
  step "Shift+arrows" "select the way every other editor selects" 1.8
  goto "rows, cols" 5
  key S-Right; key S-Right; key S-Right; key S-Right; pause 1.2
  step "" "type over a selection and it is replaced -- and you are still typing" 2.0
  type_text "size"
  pause 1.4
  key C-z; pause 1.0
}

demo_clipboard() {
  step "C-c" "copy to the SYSTEM clipboard -- the selection stays put" 1.8
  goto 'g = [' 1
  key S-Down; key S-Down; key S-Down; pause 0.8
  key C-c; pause 1.4
  step "C-v" "paste it back" 1.4
  goto "print(bfs" 1
  key Esc; nv 'o'; key Esc
  key C-v; pause 1.6
  step "C-z" "undo" 1.0
  key C-z; key C-z; pause 1.2
}

demo_find() {
  step "C-f" "find -- opens the search, no colon needed" 1.6
  key C-f; pause 0.7
  type_text "seen"
  key CR; pause 1.8
  step "" "every match lit, and you are on the first one" 2.0
  step "" "n and N walk them with the highlight still on" 1.4
  key n; pause 1.2
  step "" "now go back to typing..." 1.3
  nv 'i'
  pause 1.6
  step "" "...and the highlight is gone. it used to stay lit until the NEXT search." 2.6
}

demo_mouse() {
  step "click" "click anywhere and the caret goes there, still typing" 1.8
  click_text "return len" 30; pause 1.3
  click_text "from collections" 22; pause 1.3
  step "click" "including where there is no text at all" 2.0
  click_blank 52; pause 1.4
  type_text "# lands exactly where you clicked"
  pause 1.8
  step "" "a BLANK line, way out to the right -- virtualedit=all puts the caret there" 2.6
  key C-z; pause 1.2
  step "" "and a click that drifts a cell mid-press is still a click, not a selection" 2.6
}

demo_autosave() {
  step "" "watch the [+] in the status line -- that is 'unsaved'" 2.2
  goto "rows, cols" 1
  key Esc; nv 'A'
  type_text "  # typed, not saved"
  pause 0.4
  step "" "...still [+]..." 0.7
  pause 1.5
  step "" "gone. the file wrote itself ~700ms after you stopped. no Ctrl+S." 2.8
  step "C-s" "Ctrl+S still works and is still instant -- it is just optional now" 2.2
  key C-s; pause 1.2
  key C-z; pause 1.0
}

demo_undo() {
  step "C-z" "undo" 1.2
  key C-z; pause 1.0
  key C-z; pause 1.0
  step "C-y" "redo -- and Ctrl+Shift+Z, if your terminal speaks CSI-u" 1.8
  key C-y; pause 1.0
  key CS-z; pause 1.4
}

demo_run() {
  step "C-r" "save and run it, in a split below" 1.8
  key C-r
  wait_for "Process exited" 60
  pause 2.4
  step "" "a fresh python every time, and one window reused -- splits never stack" 2.6
  # Focus is moved by command, not by pressing <C-w>k. <C-w> in INSERT mode is
  # "delete the word before the cursor", and this config leaves you in insert
  # everywhere -- so a demo that pressed it landed in the file window and ate a
  # word, then typed the "k" as text. It corrupted the file it was about to run.
  step "" "back up to the file" 1.2
  nv '<Cmd>wincmd k<CR>'
  pause 1.4
}

demo_repl() {
  step "C-e" "the interpreter. this is the whole interface to it." 1.8
  key C-e
  wait_for ">>>" 80        # python has to have printed its prompt first
  pause 1.2
  step "" "you land at the >>> prompt, already typing" 1.8
  type_text "bfs(g, (0, 0))"
  key CR; wait_for ">>>" 40; pause 1.6
  type_text "g"
  key CR; wait_for ">>>" 40; pause 1.8
  step "C-e" "and back to the file, still in insert, mid-word if you like" 2.0
  key C-e; pause 1.8
  step "" "the interpreter always has the code you can see: edit it and Ctrl+E" 2.2
  step "" "restarts python. leave it alone and you get the same session back." 2.6
}

demo_quit() {
  step "CS-q" "Ctrl+Shift+Q -- quit, with a confirmation" 1.8
  key CS-q; pause 2.4
  step "" "Cancel is the default, so a mistyped chord never quits" 2.4
  key c; pause 1.4
  step "" "...and you are back exactly where you were typing" 2.0
  step "CS-q" "for real this time" 1.6
  key CS-q; pause 1.8
  key q
  pause 1.5
}

# ---------------------------------------------------------------------------
# --check : does every chord actually arrive as a chord?
# ---------------------------------------------------------------------------
# The universal symptom of a chord that did not survive the trip is that it gets
# typed into the buffer as a LITERAL character. That is what happened to Ctrl+/
# under System Events -- the modifier was dropped and the comment chapter put
# "//" into a python file. So every check below is the same shape: note the
# line, press the chord, and see whether the buffer changed the way that chord
# should change it, and only that way.
preflight() {
  local fails=0
  printf 'demo.sh --check : keys via %s\n\n' "$KEYMODE"
  printf 'x = 1\n' > "$FILE"
  rm -f "$SOCK"
  # NOT >/dev/null. nvim needs a real screen: with stdout discarded it cannot
  # draw, and anything that has to be DRAWN to exist -- the quit confirmation
  # above all -- silently never appears. The first version of this preflight
  # redirected the output to keep the check tidy and then reported the quit
  # chord as broken, in an editor that had no way to show a prompt in the first
  # place. It runs attached, like the tour does; you see the editor flash open.
  nvim --listen "$SOCK" -i NONE -u "$CONFIG" -c "luafile $WORK/caption.lua" "$FILE" &
  NVIM_PID=$!
  local i
  for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.15; done
  sleep 1.2
  editor_alive || { echo "  FAIL  the editor did not start"; return 1; }

  ck() {                                   # ck <name> <got> <want>
    if [ "$2" = "$3" ]; then
      printf '  \033[32mok\033[0m    %-34s\n' "$1"
    else
      fails=$((fails + 1))
      printf '  \033[31mFAIL\033[0m  %-34s got %s, wanted %s\n' "$1" "'$2'" "'$3'"
    fi
  }

  ck "opens in insert" "$(nvx 'mode(1)')" "i"
  type_text "AB"; pause 0.3
  ck "plain typing" "$(nvx 'getline(1)')" "ABx = 1"

  key C-_ ; pause 0.5
  ck "Ctrl+/ comments (not '/')" "$(nvx 'getline(1)')" "# ABx = 1"
  key C-_ ; pause 0.5
  ck "Ctrl+/ uncomments" "$(nvx 'getline(1)')" "ABx = 1"

  nv '<Cmd>call cursor(1,1)<CR>'
  key S-Right; pause 0.4
  ck "Shift+Right selects" "$(nvx 'mode(1)')" "s"
  key Esc; pause 0.3

  key C-z; pause 0.5
  ck "Ctrl+Z undoes" "$(nvx 'getline(1)')" "x = 1"

  # Ctrl+Shift+Q raises a blocking prompt; 'c' cancels it. If the chord did not
  # survive, the 'q' and the 'c' land in the buffer instead and the line grows.
  #
  # Reset the mode and the line FIRST. The checks above end by Esc-ing out of
  # Select mode and undoing, and this check reported a false failure from that
  # state -- the chord itself is fine from a clean one, verified separately.
  # A preflight that cries wolf is worse than no preflight.
  #
  nv '<C-\><C-n>'
  nv '<Cmd>call setline(1, "x = 1")<CR>'
  nv '<Cmd>call cursor(1,1)<CR>'
  nv '<Cmd>startinsert<CR>'
  pause 0.5
  local before; before="$(nvx 'getline(1)')"
  key CS-q; pause 1.1
  key c;    pause 0.8
  ck "Ctrl+Shift+Q prompts (CSI-u)" "$(nvx 'getline(1)')" "$before"
  ck "...and Cancel came back alive" "$(editor_alive && echo yes || echo no)" "yes"

  nv '<Cmd>qa!<CR>'
  wait "$NVIM_PID" 2>/dev/null
  printf '\n'
  if [ "$fails" -eq 0 ]; then
    printf '  all chords arrive intact -- safe to record.\n\n'
    return 0
  fi
  printf '  %d chord(s) did not survive. Record with --keys socket instead:\n' "$fails"
  printf '      ./demo.sh --keys socket\n'
  printf '  (reliable everywhere, but your keycast app will not see the keys --\n'
  printf '   the on-screen captions still name every one.)\n\n'
  return 1
}

if [ "$CHECK" = 1 ]; then preflight; exit $?; fi

# ---------------------------------------------------------------------------
# run it
# ---------------------------------------------------------------------------
printf 'demo.sh: keys via %s' "$KEYMODE"
[ "$KEYMODE" = system ] && printf ' -- keep this terminal FRONTMOST and hands off the keyboard'
printf '\n'
pause 1.0
if [ "$KEYMODE" = system ]; then
  for n in 3 2 1; do printf '  starting in %d...\r' "$n"; sleep 1; done
  printf '                         \n'
fi

wants shell && demo_shell

NEEDS_EDITOR=0
for c in typing comment indent select clipboard find mouse autosave undo run repl quit; do
  wants "$c" && NEEDS_EDITOR=1
done

if [ "$NEEDS_EDITOR" = 1 ]; then
  start_editor
  QUIT_RUN=0
  for c in typing comment indent select clipboard find mouse autosave undo run repl quit; do
    wants "$c" || continue
    editor_alive || break
    "demo_$c"
    [ "$c" = quit ] && QUIT_RUN=1
  done
  if [ "$QUIT_RUN" = 0 ] && editor_alive; then
    say "" "end of the tour"
    pause 1.5
    nv '<Cmd>silent! wall<CR>'
    nv '<Cmd>qa!<CR>'
  fi
  wait "$NVIM_PID" 2>/dev/null
fi

clear
cat <<'END'

   that is the whole thing.

   github.com/jainal09/drill        KEYS.md for the full reference

END
