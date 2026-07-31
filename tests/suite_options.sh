#!/bin/bash
# ============================================================================
#  suite_options.sh -- config invariants.
#
#  The other two suites press keys and diff buffers. This one asserts the
#  settings the README makes promises about: that completion really is off at
#  every source, that the cursor is the same shape in both panes, and that the
#  mappings are registered in the modes they claim.
#
#    ./suite_options.sh          run everything
#    ./suite_options.sh cursor   only cases whose name contains "cursor"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"
FILTER="${1:-}"

OUT="$(timeout 20 nvim --headless -u "$CONFIG" -c 'lua
local function ok(name, cond, got)
  print(string.format("%s\t%s\t%s", cond and "PASS" or "FAIL", name, tostring(got)))
end

-- ---- cursor: same shape in the file and in the interpreter ---------------
local gc, tn, tspec, ispec = vim.o.guicursor, 0, nil, nil
for part in gc:gmatch("[^,]+") do
  local modes, args = part:match("^([^:]+):(.*)$")
  if modes then for m in modes:gmatch("[^%-]+") do
    if m == "t" then tn = tn + 1; tspec = args end
    if m == "i" then ispec = args end
  end end
end
ok("cursor_terminal_is_vertical_bar", tspec ~= nil and tspec:match("^ver25") ~= nil, tspec)
ok("cursor_exactly_one_terminal_entry", tn == 1, tn)
ok("cursor_terminal_keeps_blink", tspec ~= nil and tspec:match("blinkon500") ~= nil, tspec)
ok("cursor_terminal_keeps_highlight", tspec ~= nil and tspec:match("TermCursor") ~= nil, tspec)
ok("cursor_insert_matches_terminal_shape",
   ispec ~= nil and tspec ~= nil and ispec:match("^ver25") ~= nil and tspec:match("^ver25") ~= nil,
   tostring(ispec) .. " vs " .. tostring(tspec))

-- ---- completion is off at every source -----------------------------------
for _, o in ipairs({"completeopt","complete","omnifunc","completefunc","dictionary","thesaurus"}) do
  ok("completion_off_" .. o, vim.o[o] == "", vim.o[o])
end
ok("completion_infercase_off", vim.o.infercase == false, vim.o.infercase)
ok("completion_no_lsp_clients", #vim.lsp.get_clients() == 0, #vim.lsp.get_clients())

-- ---- no files left lying around ------------------------------------------
ok("no_swapfile", vim.o.swapfile == false, vim.o.swapfile)
ok("no_backup", vim.o.backup == false, vim.o.backup)
ok("no_writebackup", vim.o.writebackup == false, vim.o.writebackup)
ok("no_undofile", vim.o.undofile == false, vim.o.undofile)

-- ---- click to caret ------------------------------------------------------
-- the mouse has to reach nvim at all before any of suite_mouse.sh can pass
ok("mouse_all_modes", vim.o.mouse == "a", vim.o.mouse)
-- Bound in NORMAL (a still click leaves Normal mode typing) and in
-- VISUAL/SELECT (a click that jittered across a cell boundary becomes a
-- one-character selection; that has to collapse back to a caret, or a trackpad
-- click strands you in Select mode and the next letter replaces a character).
-- NOT in insert -- a click there already leaves you typing -- and NOT in
-- terminal, where a click is you reading python scrollback.
for _, m in ipairs({"n", "x", "s"}) do
  ok("click_bound_in_" .. m, vim.fn.maparg("<LeftRelease>", m) ~= "",
     vim.fn.maparg("<LeftRelease>", m))
end
for _, m in ipairs({"i", "t"}) do
  ok("click_free_in_" .. m, vim.fn.maparg("<LeftRelease>", m) == "",
     vim.fn.maparg("<LeftRelease>", m))
end
-- the DRAG must stay unmapped in visual/select: mapping it would break
-- drag-select outright, since the collapse decision belongs at the release
ok("leftdrag_unmapped_in_select", vim.fn.maparg("<LeftDrag>", "s") == "",
   vim.fn.maparg("<LeftDrag>", "s"))
-- the PRESS must stay unmapped: it is what actually moves the caret
ok("leftmouse_press_unmapped", vim.fn.maparg("<LeftMouse>", "n") == "",
   vim.fn.maparg("<LeftMouse>", "n"))
-- Option+click. iTerm2 reports it as the Alt bit (8) in the SGR modifier field
-- and vims built-in job for ALT-LeftMouse is a BLOCKWISE selection, so without
-- these the click drops you in a one-cell block instead of putting the caret
-- down. Option is dropped for the left button in every typing mode.
-- Ctrl is stripped for a louder reason: nvim maps <C-LeftMouse> to CTRL-] , a
-- tag jump, which with no tags file raises E426 and wedges the editor behind a
-- modal "Press ENTER" prompt. Shift is deliberately NOT stripped -- shift+click
-- extending a selection is standard everywhere.
for _, mod in ipairs({"M", "C"}) do
  for _, m in ipairs({"n", "i", "x", "s"}) do
    ok(mod .. "click_press_mapped_" .. m,
       vim.fn.maparg("<" .. mod .. "-LeftMouse>", m) == "<LeftMouse>",
       vim.fn.maparg("<" .. mod .. "-LeftMouse>", m))
    ok(mod .. "click_drag_mapped_" .. m,
       vim.fn.maparg("<" .. mod .. "-LeftDrag>", m) == "<LeftDrag>",
       vim.fn.maparg("<" .. mod .. "-LeftDrag>", m))
    ok(mod .. "click_release_mapped_" .. m,
       vim.fn.maparg("<" .. mod .. "-LeftRelease>", m) ~= "",
       vim.fn.maparg("<" .. mod .. "-LeftRelease>", m))
  end
  -- ...and not in the interpreter, where the mouse belongs to python
  ok(mod .. "click_free_in_terminal", vim.fn.maparg("<" .. mod .. "-LeftMouse>", "t") == "",
     vim.fn.maparg("<" .. mod .. "-LeftMouse>", "t"))
end
ok("shiftclick_left_alone", vim.fn.maparg("<S-LeftMouse>", "n") == "",
   vim.fn.maparg("<S-LeftMouse>", "n"))

-- ---- the selection model shift+arrows depends on ------------------------
ok("virtualedit_all", vim.o.virtualedit == "all", vim.o.virtualedit)
ok("selection_exclusive", vim.o.selection == "exclusive", vim.o.selection)
ok("selectmode_key_mouse", vim.o.selectmode == "key,mouse", vim.o.selectmode)
ok("keymodel_startsel_stopsel", vim.o.keymodel == "startsel,stopsel", vim.o.keymodel)
ok("clipboard_unnamedplus", vim.o.clipboard == "unnamedplus", vim.o.clipboard)

-- ---- mappings registered in the modes they claim -------------------------
for _, k in ipairs({"<C-_>", "<C-/>", "<C-S-/>"}) do
  for _, m in ipairs({"n", "i", "x", "s"}) do
    ok("comment_bound_" .. k .. "_" .. m, vim.fn.maparg(k, m) ~= "", vim.fn.maparg(k, m))
  end
  -- must NOT be bound in terminal mode, or it would stop reaching python
  ok("comment_free_in_terminal_" .. k, vim.fn.maparg(k, "t") == "", vim.fn.maparg(k, "t"))
end
for _, m in ipairs({"n", "v", "i"}) do
  ok("redo_ctrl_shift_z_bound_" .. m, vim.fn.maparg("<C-S-z>", m) ~= "", vim.fn.maparg("<C-S-z>", m))
  ok("undo_ctrl_z_bound_" .. m, vim.fn.maparg("<C-z>", m) ~= "", vim.fn.maparg("<C-z>", m))
end
-- Ctrl+C must stay unmapped in normal and terminal so SIGINT still lands
ok("ctrlc_free_in_normal", vim.fn.maparg("<C-c>", "n") == "", vim.fn.maparg("<C-c>", "n"))
ok("ctrlc_free_in_terminal", vim.fn.maparg("<C-c>", "t") == "", vim.fn.maparg("<C-c>", "t"))
' -c 'qa!' 2>&1)"

RC=$?
if [ $RC -ne 0 ] && [ -z "$OUT" ]; then
  echo "suite_options.sh: nvim failed to start (rc=$RC)" >&2
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
