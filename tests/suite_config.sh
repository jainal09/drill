#!/bin/bash
# ============================================================================
#  run_suite.sh -- regression suite for ~/drill/nvimrc.lua
#
#  Every case below asserts behaviour that was OBSERVED in the config as it
#  ships today (see NOTES.md).
#
#  usage:  ./suite_config.sh          run everything
#          ./suite_config.sh sel_     run cases whose name contains "sel_"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$DIR/run_test.sh"
FILTER="${1:-}"

PASS=0; FAIL=0; ERR=0; SKIP=0
declare -a FAILED=()

t() { # t <name> <args...>
  local name="$1"; shift
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then SKIP=$((SKIP+1)); return; fi
  "$R" --name "$name" "$@"
  case $? in
    0) PASS=$((PASS+1)) ;;
    1) FAIL=$((FAIL+1)); FAILED+=("$name") ;;
    *) ERR=$((ERR+1));  FAILED+=("$name (ERROR)") ;;
  esac
}

SEL5='<S-Right><S-Right><S-Right><S-Right><S-Right>'   # selects "alpha"

echo "=== select-mode basics (the printable-char loop, lines 149-153) ==="

t sel_printable_replaces \
   --content 'alpha bravo' --keys "${SEL5}Z" --expect 'Z bravo'

t sel_space_replaces \
   --content 'alpha bravo' --keys "${SEL5} " --expect '  bravo'

t sel_lt_replaces \
   --content 'alpha bravo' --keys "${SEL5}<" --expect '< bravo'

t sel_bar_replaces \
   --content 'alpha bravo' --keys "${SEL5}|" --expect '| bravo'

t sel_typing_does_not_clobber_clipboard \
   --content 'alpha bravo' --keys "${SEL5}Z" --expect 'Z bravo' --expect-reg '+='

echo
echo "=== shift+arrow selection across lines ==="

t sel_shift_down_two_lines_replace \
   --content 'alpha\nbravo\ncharlie' --keys '<S-Down><S-Down>Z' \
   --expect 'Zcharlie'

t sel_backspace_deletes_selection \
   --content 'alpha bravo' --keys "${SEL5}<BS>" --expect ' bravo'

echo
echo "=== Tab / Shift+Tab indent a selection ==="
# Bound in visual+select ONLY. Insert-mode Tab must go on typing indentation.

t tab_indents_the_highlighted_lines --ext py \
   --content 'a = 1\nb = 2\nc = 3' --keys '<S-Down><S-Down><Tab><Esc>' \
   --expect '    a = 1\n    b = 2\nc = 3'

# TWO tabs only reach both lines if the selection SURVIVED the first. This is
# the case vim's own :{range}> fails: an ex command drops Select mode.
t tab_twice_selection_survives --ext py \
   --content 'a = 1\nb = 2\nc = 3' --keys '<S-Down><S-Down><Tab><Tab><Esc>' \
   --expect '        a = 1\n        b = 2\nc = 3'

t shift_tab_unindents --ext py \
   --content '        a = 1\n        b = 2' --keys '<S-Down><S-Tab><Esc>' \
   --expect '    a = 1\n        b = 2'

t tab_then_shift_tab_roundtrips --ext py \
   --content 'a = 1\nb = 2' --keys '<S-Down><Tab><S-Tab><Esc>' --expect 'a = 1\nb = 2'

t shift_tab_floors_at_column_zero --ext py \
   --content 'a = 1\nb = 2' --keys '<S-Down><S-Tab><S-Tab><Esc>' --expect 'a = 1\nb = 2'

t tab_leaves_blank_lines_blank --ext py \
   --content 'a\n\nb\nc' --keys '<S-Down><S-Down><S-Down><Tab><Esc>' \
   --expect '    a\n\n    b\nc'

t tab_visual_linewise --ext py --start normal \
   --content 'a\nb\nc' --keys 'ggVj<Tab><Esc>' --expect '    a\n    b\nc'

# matches vim's own :> byte for byte -- a leading tab in an expandtab buffer is
# re-rendered as spaces, which is normalisation, not loss
t tab_mixed_indent_matches_vim --ext py \
   --content '\tif x:\n        y = 1\nz' --keys '<S-Down><S-Down><Tab><Esc>' \
   --expect '        if x:\n            y = 1\nz'

# REGRESSION GUARD: Tab must never stop typing indentation in insert mode
t insert_tab_still_types_indent --ext py \
   --content 'x' --cursor 1:1 --keys '<Tab>Z<Esc>' --expect '    Zx'

# ...and Shift+Tab in INSERT dedents the line you are on (i_CTRL-D).
# Unmapped it fell back to plain <Tab> and INDENTED -- the opposite of the
# label. Works from any column, and on the whitespace-only line the
# autoindent just gave you, which the selection engine deliberately skips.
t stab_insert_dedents_current_line --ext py \
   --content '        a = 1' --keys '<S-Tab><Esc>' --expect '    a = 1'

t stab_insert_works_mid_line --ext py \
   --content '    a = 1' --cursor 1:9 --keys '<S-Tab><Esc>' --expect 'a = 1'

t stab_insert_takes_autoindent_off --ext py \
   --content '    ' --keys '<S-Tab><Esc>' --expect ''

t stab_insert_floors_at_column_zero --ext py \
   --content 'a = 1' --keys '<S-Tab>Z<Esc>' --expect 'Za = 1'

echo "=== cut / paste / select-all ==="

t cut_ctrl_x_in_select \
   --content 'alpha bravo' --keys "${SEL5}<C-x>" --expect ' bravo' --expect-reg '+=alpha'

t cut_ctrl_x_leaves_you_typing \
   --content 'alpha bravo' --keys "${SEL5}<C-x>Z" --expect 'Z bravo'

t select_all_ctrl_a_then_type \
   --content 'alpha\nbravo\ncharlie' --keys '<C-a>Z' --expect 'Z'

# <C-x> leaves you in INSERT mode, so this exercises the i_<C-v> mapping.
t paste_ctrl_v_insert_roundtrip \
   --content 'alpha bravo' --keys "${SEL5}<C-x><C-v>" --expect 'alpha bravo'

# ...and this one exercises the s_<C-v> mapping (paste OVER a selection).
t paste_ctrl_v_over_selection \
   --content 'one two' --keys '<S-Right><S-Right><S-Right><C-x><S-Right><C-v>' \
   --expect 'onetwo'

echo
echo "=== undo ==="

t undo_ctrl_z_reverts_typing \
   --content 'alpha bravo' --keys "${SEL5}Z<Esc><C-z>" --expect 'alpha bravo'

# Ctrl+Shift+Z redo. Only distinguishable from Ctrl+Z under CSI-u: legacy
# terminals drop Shift from a control chord and send 0x1A for both.
t redo_ctrl_shift_z \
   --content 'base' --keys 'XY<C-z><C-S-z><Esc>' --expect 'XYbase'

t redo_ctrl_y_still_works \
   --content 'base' --keys 'XY<C-z><C-y><Esc>' --expect 'XYbase'

t undo_then_no_redo_stays_undone \
   --content 'base' --keys 'XY<C-z><Esc>' --expect 'base'

echo
echo "=== the same chords on Cmd (a mac terminal that forwards it) ==="
# <D-...> only ever arrives as CSI-u -- there is no legacy byte for a Cmd
# chord -- and nvim decodes those with no negotiation, so feeding the notation
# exercises exactly what a forwarding terminal delivers. docs/macos-cmd.md is
# the setup; these assert the editor side of the bargain.

t cmd_z_undoes \
   --content 'base' --keys 'XY<D-z><Esc>' --expect 'base'

t cmd_shift_z_redoes \
   --content 'base' --keys 'XY<D-z><D-S-z><Esc>' --expect 'XYbase'

t cmd_a_then_type_replaces_all \
   --content 'alpha\nbravo\ncharlie' --keys '<D-a>Z' --expect 'Z'

t cmd_slash_comments --ext py \
   --content 'a = 1' --keys '<D-/><Esc>' --expect '# a = 1'

t cmd_slash_roundtrips --ext py \
   --content 'a = 1' --keys '<D-/><D-/><Esc>' --expect 'a = 1'

t cmd_x_cuts \
   --content 'alpha bravo' --keys "${SEL5}<D-x>" --expect ' bravo' --expect-reg '+=alpha'

t cmd_c_copies_and_keeps_selection \
   --content 'alpha bravo' --keys "${SEL5}<D-c>Z" --expect 'Z bravo' --expect-reg '+=alpha'

# no selection: Cmd+C copies the LINE, the way VS Code and Sublime do.
# (Insert-mode Cmd+C is NOT Esc -- on a Mac that chord means Copy, full stop.)
t cmd_c_no_selection_copies_line \
   --content 'alpha bravo' --keys '<D-c><Esc>' --expect 'alpha bravo' \
   --expect-reg '+=alpha bravo'

t cmd_v_paste_roundtrip \
   --content 'alpha bravo' --keys "${SEL5}<D-x><D-v>" --expect 'alpha bravo'

t cmd_v_over_selection \
   --content 'one two' --keys '<S-Right><S-Right><S-Right><D-x><S-Right><D-v>' \
   --expect 'onetwo'

# the mac cursor chords ride the built-ins (<Home>/<End>/<C-Home>/<C-End>),
# which are all in 'keymodel', so the shifted forms select like shift+arrows
t cmd_left_is_line_start \
   --content 'alpha bravo' --cursor 1:6 --keys '<D-Left>Z<Esc>' --expect 'Zalpha bravo'

t cmd_right_is_line_end \
   --content 'alpha bravo' --cursor 1:3 --keys '<D-Right>Z<Esc>' --expect 'alpha bravoZ'

t cmd_up_is_start_of_file \
   --content 'alpha\nbravo' --cursor 2:3 --keys '<D-Up>Z<Esc>' --expect 'Zalpha\nbravo'

t cmd_down_is_end_of_file \
   --content 'alpha\nbravo\ncharlie' --keys '<D-Down>Z<Esc>' \
   --expect 'alpha\nbravo\ncharlieZ'

t cmd_shift_right_selects_to_eol \
   --content 'alpha bravo' --cursor 1:7 --keys '<S-D-Right>Z<Esc>' --expect 'alpha Z'

t cmd_bs_deletes_to_line_start \
   --content 'alpha bravo' --start append --keys '<D-BS>Z<Esc>' --expect 'Z'

# ...and every OTHER Cmd chord is floored to <Nop>. Unmapped, a forwarded
# <D-w> typed the literal text "<D-w>" into the buffer (measured over the
# wire), replaced a selection with it in Select, and ate a character in
# normal -- so one reflexive Cmd+W from a mac hand would spray notation
# into the file.
t cmd_floor_swallows_unbound_chords \
   --content 'alpha' --keys '<D-w><D-g><D-n>Z<Esc>' --expect 'Zalpha'

t cmd_floor_keeps_selection_intact \
   --content 'alpha bravo' --keys "${SEL5}<D-w>Z" --expect 'Z bravo'


echo
echo "=== <C-c> copies without losing the selection ==="
# REGRESSION: the '<C-g>"+ygv<C-g>' spelling yanked correctly and then typed the
# literal characters 'gv' into the buffer. y ends visual mode, so gv has to put
# it back -- and this config's deferred :startinsert can land mid-sequence, at
# which point 'gv' is just two letters. The fix is a Lua callback that never
# changes mode. Keep this case: it is cheap and it caught a real data bug.

t ctrlc_select_copies_and_keeps_selection \
   --content 'alpha bravo' --keys "${SEL5}<C-c>Z" --expect 'Z bravo' --expect-reg '+=alpha'

t ctrlc_does_not_mutate_buffer \
   --content 'alpha bravo' --keys "${SEL5}<C-c><Esc>" --expect 'alpha bravo'

# charwise + selection=exclusive: the copy must match exactly what d deletes
t ctrlc_visual_charwise_exclusive --start normal \
   --content 'alpha bravo' --keys '0v5l<C-c>d' --expect ' bravo' --expect-reg '+=alpha'

t ctrlc_visual_linewise --start normal \
   --content 'aa\nbb\ncc' --keys 'ggVj<C-c>d' --expect 'cc' --expect-reg '+=aa
bb'

t ctrlc_select_linewise \
   --content 'aa\nbb\ncc' --keys '<S-Down><S-Down><C-c>Z' --expect 'Zcc' --expect-reg '+=aa
bb'

echo
echo "=========================================================="
printf 'PASS=%d  FAIL=%d  ERROR=%d  SKIPPED=%d\n' "$PASS" "$FAIL" "$ERR" "$SKIP"
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf 'failing: %s\n' "${FAILED[*]}"
fi
[ "$FAIL" -eq 0 ] && [ "$ERR" -eq 0 ]
