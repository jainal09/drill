#!/bin/bash
# ============================================================================
#  suite_search.sh -- Ctrl+F and the search highlight.
#
#  'hlsearch' is ON by nvim default and this config never set it, so every match
#  stayed lit long after you had gone back to typing -- through the edit, the
#  next one, and the one after. These cases pin down exactly when the highlight
#  appears and when it goes.
#
#  The tricky part is not the behaviour, it is measuring it: clearing the
#  highlight from inside an autocmd silently does not take (the autocmd runs
#  inside a save/restore of the search state), so a test that only looks at
#  v:hlsearch from inside the callback reports a success that never happened.
#  Every case here reads v:hlsearch from OUTSIDE, after the keys have settled.
#
#    ./suite_search.sh          run everything
#    ./suite_search.sh clears   only cases whose name contains "clears"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/drill-search.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FIX="$WORK/f.py"
cat > "$FIX" <<'PY'
def bfs(grid, start):
    rows = len(grid)
    q = deque([start])
    seen = set()
    while q:
        node = q.popleft()
    return len(seen)
PY

cat > "$WORK/probe.lua" <<'LUA'
vim.wait(80)
pcall(vim.cmd, "stopinsert")
-- NO implicit leading "i". The config's startup :startinsert has already
-- fired and settled by now (the wait above), and stopinsert disarms it, so
-- each case starts in Normal and spells out its own keys. Prepending "i"
-- here would fire InsertEnter, whose DEFERRED clear then lands after the
-- search and wipes a highlight the user would really still be seeing --
-- a pure artifact of feeding every key in one burst.
vim.api.nvim_feedkeys(
  vim.api.nvim_replace_termcodes(vim.env.KEYS, true, false, true), "xt", false)
vim.wait(300)                       -- let the deferred clear land
-- leading newline: nvim's own "/pattern  [1/2]" echo has no trailing newline,
-- so without this the RESULT lands glued to the end of that line and no
-- line-anchored grep can see it.
-- What matters is whether anything is LIT ON SCREEN, which is not v:hlsearch
-- alone: nvim leaves v:hlsearch at 1 after a search you opened and cancelled
-- without ever having searched, but the / register is empty then, so nothing
-- is drawn. Asserting the raw flag called that a failure; asserting the pair
-- measures what the user can actually see.
local pat = vim.fn.getreg("/")
local lit = (vim.v.hlsearch == 1 and pat ~= "") and 1 or 0
io.stderr:write(string.format("\nRESULT\t%s\t%d\t%d\t%s\t%q\n",
  vim.env.CASE, lit, vim.fn.line("."), tostring(vim.v.hlsearch), pat))
LUA

PASS=0; FAIL=0
declare -a BAD=()

# t <name> <keys> <want-lit> [want-line]   -- "lit" = visibly highlighted
t() {
  local name="$1" keys="$2" want="$3" wantline="${4:-}"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  # A fresh shada-less nvim per case: the / register persists otherwise and a
  # later case inherits the previous pattern.
  # Rewrite the fixture per case: the config autosaves, so a case that types
  # leaves its edit on disk and the next case would open the mutated file.
  cat > "$FIX" <<'PY'
def bfs(grid, start):
    rows = len(grid)
    q = deque([start])
    seen = set()
    while q:
        node = q.popleft()
    return len(seen)
PY
  local out
  out="$(CASE="$name" KEYS="$keys" timeout 20 nvim --headless -i NONE -u "$CONFIG" \
          "$FIX" -c "luafile $WORK/probe.lua" -c 'qa!' 2>&1 |
        tr '\r' '\n' | grep -ao "RESULT.*" | tail -1)"
  local got line raw pat
  got="$(printf '%s' "$out" | cut -f3)"     # lit: anything drawn on screen?
  line="$(printf '%s' "$out" | cut -f4)"
  raw="$(printf '%s' "$out" | cut -f5)"     # raw v:hlsearch, for the message
  pat="$(printf '%s' "$out" | cut -f6)"
  local ok=1
  [ "$got" = "$want" ] || ok=0
  [ -n "$wantline" ] && [ "$line" != "$wantline" ] && ok=0
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name")
    printf '\033[31mFAIL\033[0m  %s  -- lit got=%s want=%s, line got=%s want=%s  (v:hlsearch=%s pattern=%s)\n' \
      "$name" "${got:-?}" "$want" "${line:-?}" "${wantline:-any}" "${raw:-?}" "${pat:-?}"
  fi
}

echo "=== the highlight appears, and lands you on the match ==="
t search_lights_the_matches      '<C-f>seen<CR>'          1 4
t search_jumps_to_the_match      '<C-f>popleft<CR>'       1 6
t next_match_keeps_it_lit        '<C-f>seen<CR>n'         1 7

echo
echo "=== ...and goes when you get back to typing ==="
# THE reported bug: find something, go into insert, highlight stayed lit.
t insert_clears_the_highlight    '<C-f>seen<CR>i'         0 4
t typing_clears_the_highlight    '<C-f>seen<CR>iXY'       0 4
t insert_after_n_clears          '<C-f>seen<CR>ni'        0 7
# append and open-line reach Insert by other doors; all of them must clear
t append_clears_the_highlight    '<C-f>seen<CR>a'         0 4
t openline_clears_the_highlight  '<C-f>seen<CR>o'         0 5

echo
echo "=== edge cases ==="
# a cancelled search must not light anything up
t cancelled_search_stays_dark    '<C-f>seen<Esc>'         0 1
t cancelled_keeps_prior_dark     '<C-f>seen<CR>iX<Esc><C-f><Esc>' 0
# a pattern with no match still lights (vim sets v:hlsearch) but must clear
t nomatch_then_insert_clears     '<C-f>zzzz<CR>i'         0 1
# the highlight must survive a plain cursor move -- you are still reading
t cursor_move_keeps_it_lit       '<C-f>seen<CR>j'         1 5

echo
echo "=========================================================="
echo "CONFIG=$CONFIG  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
