#!/bin/bash
# ============================================================================
#  suite_autosave.sh -- the file writes itself.
#
#  Every other suite asserts what is in the BUFFER. This one asserts what is on
#  DISK, which is the only thing that means anything for autosave: a test that
#  reads the buffer back passes whether or not a single byte was written.
#
#  Each case types into a real file, waits past the debounce, and cats the file
#  from the shell -- not from nvim.
#
#    ./suite_autosave.sh          run everything
#    ./suite_autosave.sh writes   only cases whose name contains "writes"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/drill-autosave.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The debounce is 700ms in the config; wait comfortably past it, then quit.
cat > "$WORK/probe.lua" <<'LUA'
local writes = 0
vim.api.nvim_create_autocmd("BufWritePost", { callback = function() writes = writes + 1 end })
vim.wait(80)
pcall(vim.cmd, "stopinsert")
vim.api.nvim_feedkeys(
  vim.api.nvim_replace_termcodes(vim.env.KEYS, true, false, true), "xt", false)
vim.wait(tonumber(vim.env.SETTLE) or 1500)   -- past AUTOSAVE_MS, with room to spare
-- Report what is on DISK right now, BEFORE quitting. Quitting fires the
-- VimLeavePre save, so the final file cannot tell "the debounce already
-- wrote it" apart from "the exit save caught it" -- only a mid-run read can.
local fh = io.open(vim.env.TARGET, "rb")
local data = fh and fh:read("*a") or ""
if fh then fh:close() end
io.stderr:write("\nDISKNOW\t" .. data:gsub("\n", "\\n") .. "\nWRITES\t" .. writes .. "\n")
LUA

PASS=0; FAIL=0
declare -a BAD=()

report() {
  local name="$1" ok="$2" got="$3" want="$4"
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name")
    printf '\033[31mFAIL\033[0m  %s\n        on disk: %s\n        wanted : %s\n' \
      "$name" "$got" "$want"
  fi
}

# t <name> <starting-file-content> <keys> <expected-DISK-content> [settle_ms]
t() {
  local name="$1" start="$2" keys="$3" want="$4" settle="${5:-1500}"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  local f="$WORK/$name.py"
  printf '%b' "$start" > "$f"
  KEYS="$keys" SETTLE="$settle" TARGET="$f" timeout 25 nvim --headless -i NONE \
    -u "$CONFIG" "$f" -c "luafile $WORK/probe.lua" -c 'qa!' >/dev/null 2>&1
  local got; got="$(cat "$f")"
  local wanted; wanted="$(printf '%b' "$want")"
  [ "$got" = "$wanted" ] && report "$name" 1 "" "" || report "$name" 0 "$(printf '%q' "$got")" "$(printf '%q' "$wanted")"
}

# tmid <name> <start> <keys> <expected-disk-content-AT-settle> <settle_ms>
# Asserts what is on disk PART WAY THROUGH, before the exit save can mask it.
tmid() {
  local name="$1" start="$2" keys="$3" want="$4" settle="$5"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  local f="$WORK/$name.py"
  printf '%b' "$start" > "$f"
  local out
  out="$(KEYS="$keys" SETTLE="$settle" TARGET="$f" timeout 25 nvim --headless -i NONE \
          -u "$CONFIG" "$f" -c "luafile $WORK/probe.lua" -c 'qa!' 2>&1 |
        tr '\r' '\n' | grep -ao "DISKNOW.*" | tail -1)"
  local got; got="$(printf '%s' "$out" | cut -f2)"
  [ "$got" = "$want" ] && report "$name" 1 "" "" || report "$name" 0 "$got" "$want"
}

echo "=== it writes itself, with no Ctrl+S ==="
t autosave_writes_typed_text      'x = 1\n' 'ccy = 2'        'y = 2\n'
t autosave_writes_an_append       'x = 1\n' 'Ay'             'x = 1y\n'
t autosave_writes_a_new_line      'x = 1\n' 'oz = 3'         'x = 1\nz = 3\n'
t autosave_writes_a_deletion      'x = 1\ny = 2\n' 'dd'      'y = 2\n'

echo
echo "=== the debounce is NOT asserted here, deliberately ==="
# It cannot be, headlessly. feedkeys 'xt' force-ends Insert when the typeahead
# drains, which fires InsertLeave and saves at once, so the bytes hit the disk
# immediately no matter what the timer does -- and 'xt!' (stay in Insert) hangs
# headless nvim outright (NOTES.md #2). Worse, a write performed INSIDE an
# autocmd fires no nested autocommands, so a BufWritePost counter reads 0 while
# the file is demonstrably being written.
# Coalescing is therefore measured in a real pty instead, staying in Insert the
# whole time: 30 keystrokes produced 2 writes, not 30. See NOTES.md #11.

echo
echo "=== Ctrl+S still works, and is still instant ==="
tmid ctrl_s_writes_immediately     'x = 1\n' 'ccy = 2<C-s>' 'y = 2\n' 150

echo
echo "=== quitting saves the last few characters ==="
# the debounce would otherwise lose whatever you typed in the final 700ms
t quitting_writes_the_last_keys   'x = 1\n' 'ccy = 2'        'y = 2\n'   150

echo
echo "=== it must not fight the rest of the config ==="
# the comment toggle is a buffer-API edit -- it still has to reach the disk
t autosave_writes_a_comment_toggle 'x = 1\n' '<C-_>'         '# x = 1\n'
# an unmodified buffer must not be rewritten (:update, not :write)
t autosave_leaves_clean_file_alone 'x = 1\n' 'jk'            'x = 1\n'

echo
echo "=========================================================="
echo "CONFIG=$CONFIG  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
