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
-- the hint float, if one is up
local hint = ""
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative ~= "" then
    hint = vim.trim(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)[1] or "")
  end
end
io.stderr:write(string.format("\nRESULT\t%s\t%d\t%d\t%s\t%q\t%s\t%s\n",
  vim.env.CASE, lit, vim.fn.line("."), tostring(vim.v.hlsearch), pat, hint,
  vim.fn.maparg("<Esc>", "n") ~= "" and "bound" or "free"))
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
echo "=== the hint that tells you n / N are live ==="
# th <name> <keys> <expected hint text>
th() {
  local name="$1" keys="$2" want="$3"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  cat > "$FIX" <<'PY'
def bfs(grid, start):
    rows = len(grid)
    q = deque([start])
    seen = set()
    while q:
        node = q.popleft()
    return len(seen)
PY
  local out got
  out="$(CASE="$name" KEYS="$keys" timeout 20 nvim --headless -i NONE -u "$CONFIG" \
          "$FIX" -c "luafile $WORK/probe.lua" -c 'qa!' 2>&1 |
        tr '\r' '\n' | grep -ao "RESULT.*" | tail -1)"
  got="$(printf '%s' "$out" | cut -f7)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name")
    printf '\033[31mFAIL\033[0m  %s  -- hint got=%s want=%s\n' "$name" "'$got'" "'$want'"
  fi
}

th hint_appears_after_a_search    '<C-f>seen<CR>'      'n  next     N  previous     Esc  back to search'
th hint_survives_n                '<C-f>seen<CR>n'     'n  next     N  previous     Esc  back to search'
th hint_absent_when_nothing_matched '<C-f>zzzz<CR>'    ''
th hint_absent_after_a_cancel     '<C-f>seen<Esc>'     ''
th hint_absent_at_rest            'jk'                 ''

echo
echo "=== Esc goes back to the search input, but only while that is true ==="
# te <name> <keys> <bound|free>
te() {
  local name="$1" keys="$2" want="$3"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  cat > "$FIX" <<'PY'
def bfs(grid, start):
    rows = len(grid)
    q = deque([start])
    seen = set()
    while q:
        node = q.popleft()
    return len(seen)
PY
  local out got
  out="$(CASE="$name" KEYS="$keys" timeout 20 nvim --headless -i NONE -u "$CONFIG" \
          "$FIX" -c "luafile $WORK/probe.lua" -c 'qa!' 2>&1 |
        tr '\r' '\n' | grep -ao "RESULT.*" | tail -1)"
  got="$(printf '%s' "$out" | cut -f8)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name")
    printf '\033[31mFAIL\033[0m  %s  -- <Esc> got=%s want=%s\n' "$name" "'$got'" "'$want'"
  fi
}

# A PERMANENT Normal-mode <Esc> mapping would swallow the Esc that cancels a
# pending count or operator, which is still plain vim here. It exists only
# while there is a search to go back to.
te esc_free_at_rest               'jk'                 free
te esc_bound_after_a_search       '<C-f>seen<CR>'      bound
te esc_bound_after_n              '<C-f>seen<CR>n'     bound
te esc_free_when_nothing_matched  '<C-f>zzzz<CR>'      free
te esc_free_after_a_cancel        '<C-f>seen<Esc>'     free
# TWO cases are NOT asserted here, both for the same reason: feedkeys 'xt'
# delivers every key in one burst and force-ends Insert as the typeahead
# drains, so by the time this probe looks, mode is back to Normal and the
# deferred show has landed. Headless cannot tell either case from the broken
# one. Both are measured in a pty instead:
#   * the hint goes when you start typing again  -- after <C-f>seen<CR> then i
#     the float is gone, and stays gone while typing.
#   * a ":" command raises no search hint. This one matters more than it looks:
#     an autocmd PATTERN is matched as a FILE pattern, where "?" means "any
#     single character", so pattern={"/","?"} fired for EVERY one-character
#     cmdtype -- ":" commands, input() prompts, and the confirm() dialog behind
#     <C-S-q>, which is how the quit dialog ended up with "press Enter to
#     search" repainted across it. The cmdtype is checked in the callback now,
#     and suite_quit.sh asserts the dialog draws clean.

echo
echo "=== on a real pty: the Esc chain, which headless cannot see ==="
# feedkeys delivers every key in one burst and force-ends Insert as the
# typeahead drains, so headless cannot tell "it went back to typing" from
# "it never left". These run against a real terminal instead.
if command -v python3 >/dev/null; then
  DRILL_SOCK="${TMPDIR:-/tmp}/drill-search-$$.sock"
  export DRILL_CONFIG="$CONFIG" DRILL_SOCK
  PTY_OUT="$(timeout 180 python3 "$DIR/search_drive.py")"
  RC=$?
  rm -f "$DRILL_SOCK"
  # a dead driver must be a loud failure, not a quiet skip: it prints its
  # results once, at the very end, so a crash, hang or timeout means EMPTY
  # output and zero cases counted -- the suite would pass with the Esc chain
  # unguarded. Same guard as suite_quit.sh / suite_runwin.sh.
  if [ $RC -ne 0 ] || [ -z "$PTY_OUT" ]; then
    echo "suite_search.sh: pty driver failed (rc=$RC)" >&2
    [ -n "$PTY_OUT" ] && echo "$PTY_OUT" >&2
    exit 2
  fi
  while IFS=$'\t' read -r verdict name got; do
    case "$verdict" in PASS|FAIL) ;; *) continue ;; esac
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
    if [ "$verdict" = PASS ]; then
      PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
    else
      FAIL=$((FAIL+1)); BAD+=("$name"); printf '\033[31mFAIL\033[0m  %s  -- got: %s\n' "$name" "$got"
    fi
  done <<< "$PTY_OUT"
else
  echo "suite_search.sh: python3 not on PATH -- the pty cases cannot run" >&2
  exit 2
fi

echo
echo "=========================================================="
echo "CONFIG=$CONFIG  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
