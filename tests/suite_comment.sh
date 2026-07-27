#!/bin/bash
# Adversarial suite written by the VERIFIER. Runs against whatever config
# DRILL_CONFIG points at. KEY selects which Ctrl+/ spelling to feed.
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$H/run_test.sh"
K="${KEY:-<C-_>}"
FILTER="${1:-}"
PASS=0; FAIL=0; ERR=0
declare -a BAD=()

t() {
  local name="$1"; shift
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  "$R" --name "V_$name" "$@"
  case $? in
    0) PASS=$((PASS+1)) ;;
    1) FAIL=$((FAIL+1)); BAD+=("$name") ;;
    *) ERR=$((ERR+1));  BAD+=("$name(ERR)") ;;
  esac
}

echo "===== INSERT MODE (the default state of this editor) ====="
# cursor mid-line: must stay in INSERT (the trailing Z can only land from insert)
# and must stay on the SAME CHARACTER.
t ins_midline_stays_insert --ext py --content 'alpha bravo' --cursor 1:7 \
  --keys "${K}ZZZ" --expect '# alpha ZZZbravo'
t ins_col1 --ext py --content 'alpha bravo' --cursor 1:1 \
  --keys "${K}Z" --expect '# Zalpha bravo'
t ins_eol --ext py --content 'alpha' --start append \
  --keys "${K}Z" --expect '# alphaZ'
t ins_indented_midline --ext py --content '    x = 1' --cursor 1:5 \
  --keys "${K}Z" --expect '    # Zx = 1'
t ins_uncomment_midline --ext py --content '    # x = 1' --cursor 1:7 \
  --keys "${K}Z" --expect '    Zx = 1'
t ins_line2_not_line1 --ext py --content 'alpha\nbravo\ncharlie' --cursor 2:1 \
  --keys "${K}" --expect 'alpha\n# bravo\ncharlie'
t ins_last_line --ext py --content 'alpha\nbravo\ncharlie' --cursor 3:1 \
  --keys "${K}" --expect 'alpha\nbravo\n# charlie'
t ins_blank_line --ext py --content 'a\n\nb' --cursor 2:1 \
  --keys "${K}Z" --expect 'a\n# Z\nb'

echo
echo "===== SELECT MODE via shift+arrows ====="
# GROUND TRUTH from the pre-existing suite: '<S-Down><S-Down>Z' on
# alpha/bravo/charlie yields 'Zcharlie' -- i.e. the highlight covers lines 1-2
# and NOTHING of line 3. So Ctrl+/ must comment lines 1-2 only.
t sel_sdown_x2_comments_exactly_the_highlight --ext py \
  --content 'alpha\nbravo\ncharlie\ndelta' --keys "<S-Down><S-Down>${K}" \
  --expect '# alpha\n# bravo\ncharlie\ndelta'
t sel_sdown_x1_one_line_only --ext py \
  --content 'alpha\nbravo\ncharlie' --keys "<S-Down>${K}" \
  --expect '# alpha\nbravo\ncharlie'
t sel_sdown_then_sright_two_lines --ext py \
  --content 'alpha\nbravo\ncharlie' --keys "<S-Down><S-Right>${K}" \
  --expect '# alpha\n# bravo\ncharlie'
t sel_selection_survives_toggle --ext py \
  --content 'alpha\nbravo\ncharlie\ndelta' --keys "<S-Down><S-Down>${K}Z" \
  --expect 'Zcharlie\ndelta'
t sel_charwise_text_not_replaced --ext py --content 'alpha bravo' \
  --keys "<S-Right><S-Right><S-Right>${K}" --expect '# alpha bravo'
t sel_backwards_shift_up --ext py --content 'alpha\nbravo\ncharlie' --cursor 3:3 \
  --keys "<S-Up>${K}" --expect 'alpha\n# bravo\n# charlie'
t sel_backwards_shift_up_col1 --ext py --content 'alpha\nbravo\ncharlie' --cursor 3:1 \
  --keys "<S-Up><S-Up>${K}" --expect '# alpha\n# bravo\ncharlie'
t sel_roundtrip_bytes --ext py \
  --content 'alpha\nbravo\ncharlie' --keys "<S-Down><S-Right>${K}${K}" \
  --expect 'alpha\nbravo\ncharlie'
t sel_toggle_does_not_touch_clipboard --ext py --content 'alpha\nbravo' \
  --keys "<S-Down><S-Right>${K}" --expect '# alpha\n# bravo' --expect-reg '+='

echo
echo "===== THE USER'S BUG #4: stale range must be ignored ====="
# Select 1-2, LEAVE the selection, move away, toggle. Must hit the CURRENT line.
t stale_normal_v_then_move --ext py --start normal \
  --content 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8' \
  --keys "vj<Esc>6G${K}" --expect 'l1\nl2\nl3\nl4\nl5\n# l6\nl7\nl8'
t stale_normal_V_then_move --ext py --start normal \
  --content 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8' \
  --keys "Vj<Esc>7G${K}" --expect 'l1\nl2\nl3\nl4\nl5\nl6\n# l7\nl8'
t stale_normal_then_new_selection --ext py --start normal \
  --content 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8' \
  --keys "Vj<Esc>6GVj${K}" --expect 'l1\nl2\nl3\nl4\nl5\n# l6\n# l7\nl8'
t stale_select_then_new_selection --ext py \
  --content 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8' \
  --keys "<S-Down><S-Right><Esc><Esc>6G<S-Down><S-Right>${K}" \
  --expect 'l1\nl2\nl3\nl4\nl5\n# l6\n# l7\nl8'

echo
echo "===== NORMAL / VISUAL ====="
t nrm_fresh_buffer_single_line --ext py --start normal \
  --content 'x = 1\ny = 2\nz = 3' --cursor 2:1 --keys "${K}" \
  --expect 'x = 1\n# y = 2\nz = 3'
t vis_linewise_V --ext py --start normal --content 'alpha\nbravo\ncharlie' \
  --keys "Vj${K}" --expect '# alpha\n# bravo\ncharlie'
t vis_charwise_v --ext py --start normal --content 'alpha\nbravo\ncharlie' \
  --keys "vjl${K}" --expect '# alpha\n# bravo\ncharlie'
t vis_block_ctrl_q --ext py --start normal --content 'alpha\nbravo\ncharlie' \
  --keys "<C-q>j${K}" --expect '# alpha\n# bravo\ncharlie'
t selectall_ctrl_a --ext py --content 'a\n    b\nc' \
  --keys "<C-a>${K}" --expect '# a\n#     b\n# c'
t selectall_ctrl_a_roundtrip --ext py --content 'a\n    b\nc' \
  --keys "<C-a>${K}${K}" --expect 'a\n    b\nc'

echo
echo "===== BLANK LINES INSIDE A RANGE ====="
t blank_inside_untouched --ext py --start normal --content 'a\n\nb' \
  --keys "ggVG${K}" --expect '# a\n\n# b'
t blank_inside_roundtrip --ext py --start normal --content 'a\n\nb' \
  --keys "ggVG${K}${K}" --expect 'a\n\nb'
t whitespace_only_line_roundtrip --ext py --start normal --content 'a\n    \nb' \
  --keys "ggVG${K}${K}" --expect 'a\n    \nb'
t blank_does_not_block_uncomment --ext py --start normal --content '# a\n\n# b' \
  --keys "ggVG${K}" --expect 'a\n\nb'

echo
echo "===== MIXED BLOCKS ====="
t mixed_comments_everything --ext py --start normal --content 'a\n# b\nc' \
  --keys "ggVG${K}" --expect '# a\n# # b\n# c'
t mixed_converges_back --ext py --start normal --content 'a\n# b\nc' \
  --keys "ggVG${K}${K}" --expect 'a\n# b\nc'
t mixed_converges_back_reselect --ext py --start normal --content 'a\n# b\nc' \
  --keys "ggVG${K}<Esc>ggVG${K}" --expect 'a\n# b\nc'
t all_commented_uncomments --ext py --start normal --content '# a\n# b\n# c' \
  --keys "ggVG${K}" --expect 'a\nb\nc'

echo
echo "===== INDENTATION: minimum indent of the block ====="
t minindent_uniform --ext py --start normal \
  --content '    if x:\n        y = 1\n        z = 2' --keys "ggVG${K}" \
  --expect '    # if x:\n    #     y = 1\n    #     z = 2'
t minindent_roundtrip --ext py --start normal \
  --content '    if x:\n        y = 1\n        z = 2' --keys "ggVG${K}${K}" \
  --expect '    if x:\n        y = 1\n        z = 2'
t minindent_ragged --ext py --start normal \
  --content 'def f():\n        a = 1\n    b = 2\n        c = 3' --keys "jVG${K}" \
  --expect 'def f():\n    #     a = 1\n    # b = 2\n    #     c = 3'
t minindent_ragged_roundtrip --ext py --start normal \
  --content 'def f():\n        a = 1\n    b = 2\n        c = 3' --keys "jVG${K}${K}" \
  --expect 'def f():\n        a = 1\n    b = 2\n        c = 3'
t minindent_with_blank --ext py --start normal --content '    a\n\n    b' \
  --keys "ggVG${K}" --expect '    # a\n\n    # b'
t tabs_roundtrip --ext py --start normal --content '\tif x:\n\t\ty = 1' \
  --keys "ggVG${K}${K}" --expect '\tif x:\n\t\ty = 1'
t minindent_uncomment_restores --ext py --start normal \
  --content '    # if x:\n    #     y = 1' --keys "ggVG${K}" \
  --expect '    if x:\n        y = 1'

echo
echo "===== NASTY EDGE CASES ====="
t empty_buffer --ext py --content '' --keys "${K}hi" --expect '# hi'
t empty_buffer_roundtrip --ext py --content '' --keys "${K}${K}" --expect ''
t hash_only_line --ext py --start normal --content '#\nx' --keys "${K}" --expect '\nx'
t nospace_comment_uncomments --ext py --start normal --content '#foo\n#bar' \
  --keys "ggVG${K}" --expect 'foo\nbar'
t trailing_hash_is_not_a_comment --ext py --start normal --content 'x = 1  # tail' \
  --keys "${K}${K}" --expect 'x = 1  # tail'
t unicode_roundtrip --ext py --start normal --content 'x = "héllo→"\ny = 2' \
  --keys "ggVG${K}${K}" --expect 'x = "héllo→"\ny = 2'
t unicode_comment --ext py --start normal --content 'x = "héllo→"' \
  --keys "${K}" --expect '# x = "héllo→"'
t ten_toggles_stable --ext py --start normal --content '    a = 1\n        b = 2' \
  --keys "ggVG${K}${K}${K}${K}${K}${K}${K}${K}${K}${K}" \
  --expect '    a = 1\n        b = 2'
t undo_reverts_one_step --ext py --content 'a = 1\nb = 2' \
  --keys "${K}<Esc><C-z>" --expect 'a = 1\nb = 2'
t regex_metachar_in_line --ext py --start normal --content 'x = [a-z]*(1+2)?' \
  --keys "${K}${K}" --expect 'x = [a-z]*(1+2)?'
t percent_in_line --ext py --start normal --content 'x = "%s %%d"' \
  --keys "${K}${K}" --expect 'x = "%s %%d"'

echo
echo "===== FILETYPES ====="
t ft_lua --ext lua --start normal --content 'local x = 1\nlocal y = 2' \
  --keys "ggVG${K}" --expect '-- local x = 1\n-- local y = 2'
t ft_lua_roundtrip --ext lua --start normal --content 'local x = 1\n    local y = 2' \
  --keys "ggVG${K}${K}" --expect 'local x = 1\n    local y = 2'
t ft_txt_fallback --ext txt --start normal --content 'alpha' --keys "${K}" \
  --expect '# alpha'
t ft_txt_roundtrip --ext txt --start normal --content 'alpha' --keys "${K}${K}" \
  --expect 'alpha'

t mixed_tab_space_roundtrip --ext py --start normal --content '\tif x:\n        y = 1' \
  --keys "ggVG${K}${K}" --expect '\tif x:\n        y = 1'
t mixed_space_tab_roundtrip --ext py --start normal --content '        y = 1\n\tif x:' \
  --keys "ggVG${K}${K}" --expect '        y = 1\n\tif x:'
t shebang_converges --ext py --start normal --content '#!/usr/bin/env python3' \
  --keys "${K}${K}${K}${K}" --expect '# !/usr/bin/env python3'
t deep_indent_16 --ext py --start normal \
  --content '                deep = 1\n                    deeper = 2' --keys "ggVG${K}" \
  --expect '                # deep = 1\n                #     deeper = 2'
t trailing_ws_kept --ext py --start normal --content 'a = 1   \nb = 2' \
  --keys "ggVG${K}${K}" --expect 'a = 1   \nb = 2'
t only_blank_lines --ext py --start normal --content '\n\n' --keys "ggVG${K}${K}" --expect '\n\n'
t sel_then_unshifted_arrow_drops_sel --ext py --content 'alpha\nbravo\ncharlie' \
  --keys "<S-Down><S-Down><Right>${K}" --expect 'alpha\nbravo\n# charlie'
t docstring_hash_roundtrip --ext py --start normal --content 'y = "# not a comment"' \
  --keys "${K}${K}" --expect 'y = "# not a comment"'

echo
echo "=========================================================="
printf 'CONFIG=%s KEY=%s  PASS=%d  FAIL=%d  ERROR=%d\n' \
  "${DRILL_CONFIG:-default}" "$K" "$PASS" "$FAIL" "$ERR"
[ "${#BAD[@]}" -gt 0 ] && printf 'failing: %s\n' "${BAD[*]}"
[ "$FAIL" -eq 0 ] && [ "$ERR" -eq 0 ]
