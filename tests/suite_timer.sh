#!/bin/bash
# ============================================================================
#  suite_timer.sh -- t / t10 / t -k
#
#  drill.sh claims to work in bash AND zsh, and the timer code is the part most
#  likely to quietly disagree between them: zsh does not word-split unquoted
#  parameter expansions the way bash does, so the obvious `for p in $pids` loop
#  iterates per-PID in bash and ONCE with the whole blob in zsh. Every case here
#  therefore runs under both shells.
#
#  It never touches a timer you started: DRILL_TIMER_TAG is overridden to a
#  per-run tag, so the suite's timers and yours cannot see each other.
#
#    ./suite_timer.sh          run everything
#    ./suite_timer.sh kill     only cases whose name contains "kill"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
FILTER="${1:-}"
DRILL_SH="${DRILL_SH:-$REPO/drill.sh}"

[ -f "$DRILL_SH" ] || { echo "suite_timer.sh: no drill.sh at $DRILL_SH" >&2; exit 2; }

TAG="drill-timer-test-$$"
cleanup() { pkill -f "$TAG" 2>/dev/null; true; }
trap cleanup EXIT

PASS=0; FAIL=0
declare -a BAD=()

ok() {
  local name="$1" cond="$2" got="$3"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  if [ "$cond" = 1 ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name"); printf '\033[31mFAIL\033[0m  %s  -- %s\n' "$name" "$got"
  fi
}

# Asked inside the test shell, `pgrep -f "$TAG"` is the WRONG question: the tag
# is in that shell's own -c string, so it matches the shell itself and every
# check below would be answering about the wrong process. Filter to actual
# interpreters, the way drill.sh does -- but spelled out here rather than
# calling _drill_timer_pids, so the suite is not checking drill.sh against
# itself.
#
# The leading ( in "(python*|*/python*)" is LOAD-BEARING -- do not tidy it away.
# This heredoc lives inside $( ), and bash 3.2 (which is what /bin/bash is on
# macOS) finds the end of a command substitution by scanning for a balancing
# paren rather than by parsing. A case pattern contributes a lone ')', so the
# scan ended on the pattern below, the rest of the line was read as a command,
# and the whole suite died before its first case with
#
#   suite_timer.sh: line 52: syntax error near unexpected token `;;'
#
# The optional open paren POSIX allows on a case pattern balances the count.
# Nothing changes for bash 4+, zsh, or the meaning of the pattern.
_TIMER_PIDS=$(cat <<'PRE'
timer_pids() {
  pgrep -f "$DRILL_TIMER_TAG" 2>/dev/null | while IFS= read -r p; do
    case "$(ps -p "$p" -o comm= 2>/dev/null)" in (python*|*/python*) echo "$p" ;; esac
  done
}
PRE
)

# run <shell> <script>  -- source drill.sh under that shell and run the script
run() {
  local sh="$1" script="$2"
  DRILL_TIMER_TAG="$TAG" "$sh" -c "
    . '$DRILL_SH' >/dev/null 2>&1
    DRILL_TIMER_TAG='$TAG'
    $_TIMER_PIDS
    $script
  " 2>&1
}

for SH in bash zsh; do
  command -v "$SH" >/dev/null || { echo "skip: $SH not on PATH"; continue; }
  echo "===== $SH ====="
  pkill -f "$TAG" 2>/dev/null

  # ---- starting prints an id -------------------------------------------
  OUT="$(run "$SH" 't 2>/dev/null; sleep 0.4')"
  ID="$(printf '%s' "$OUT" | sed -n 's/.*id \([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$ID" ] && ok "${SH}_start_prints_an_id" 1 "" \
                || ok "${SH}_start_prints_an_id" 0 "no id in: $(printf '%s' "$OUT" | head -2)"
  case "$OUT" in *"t -k"*) ok "${SH}_start_tells_you_how_to_stop" 1 "" ;;
                 *) ok "${SH}_start_tells_you_how_to_stop" 0 "no 't -k' hint: $OUT" ;; esac
  # the printed id must be the real process, not a stale shell pid
  if [ -n "$ID" ] && ps -p "$ID" -o command= 2>/dev/null | grep -q "$TAG"; then
    ok "${SH}_printed_id_is_the_timer" 1 ""
  else
    ok "${SH}_printed_id_is_the_timer" 0 "pid $ID is not the timer process"
  fi
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- t -k <id> kills exactly that timer ------------------------------
  OUT="$(run "$SH" '
    t >/dev/null 2>&1; sleep 0.4
    id=$(timer_pids | head -1)
    t -k "$id"
    sleep 0.3
    timer_pids | grep -q . && echo STILL_RUNNING || echo GONE')"
  case "$OUT" in *GONE*) ok "${SH}_kill_by_id_stops_it" 1 "" ;;
                 *) ok "${SH}_kill_by_id_stops_it" 0 "$OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- t -k with no id kills the running one ---------------------------
  OUT="$(run "$SH" '
    t >/dev/null 2>&1; sleep 0.4
    t -k
    sleep 0.3
    timer_pids | grep -q . && echo STILL_RUNNING || echo GONE')"
  case "$OUT" in *GONE*) ok "${SH}_bare_kill_stops_it" 1 "" ;;
                 *) ok "${SH}_bare_kill_stops_it" 0 "$OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- a wrong id must be REFUSED, not obeyed --------------------------
  # This is the case that matters. A finished timer's pid gets recycled, so
  # `t -k <old id>` off your scrollback must not fire a kill at whatever holds
  # that pid now. Use this very shell's pid as the impostor: it exists, and it
  # is emphatically not a drill timer.
  OUT="$(run "$SH" '
    t >/dev/null 2>&1; sleep 0.4
    t -k $$ ; echo "rc=$?"
    sleep 0.2
    timer_pids | grep -q . && echo TIMER_SURVIVED || echo TIMER_DIED')"
  case "$OUT" in *"rc=1"*) ok "${SH}_wrong_id_returns_failure" 1 "" ;;
                 *) ok "${SH}_wrong_id_returns_failure" 0 "$OUT" ;; esac
  case "$OUT" in *"is not a running drill timer"*) ok "${SH}_wrong_id_says_why" 1 "" ;;
                 *) ok "${SH}_wrong_id_says_why" 0 "$OUT" ;; esac
  case "$OUT" in *TIMER_SURVIVED*) ok "${SH}_wrong_id_leaves_timer_alone" 1 "" ;;
                 *) ok "${SH}_wrong_id_leaves_timer_alone" 0 "$OUT" ;; esac
  # ...and the shell it named is still alive, i.e. we did not kill a stranger
  case "$OUT" in *TIMER_SURVIVED*|*TIMER_DIED*) ok "${SH}_wrong_id_did_not_kill_target" 1 "" ;;
                 *) ok "${SH}_wrong_id_did_not_kill_target" 0 "shell died: $OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- stopping when nothing runs -------------------------------------
  OUT="$(run "$SH" 't -k; echo "rc=$?"')"
  case "$OUT" in *"none running"*) ok "${SH}_kill_with_nothing_running" 1 "" ;;
                 *) ok "${SH}_kill_with_nothing_running" 0 "$OUT" ;; esac
  case "$OUT" in *"rc=1"*) ok "${SH}_kill_with_nothing_returns_failure" 1 "" ;;
                 *) ok "${SH}_kill_with_nothing_returns_failure" 0 "$OUT" ;; esac

  # ---- only ever one timer --------------------------------------------
  OUT="$(run "$SH" '
    t >/dev/null 2>&1; sleep 0.3
    t >/dev/null 2>&1; sleep 0.3
    timer_pids | wc -l | tr -d " "')"
  case "$OUT" in *1*) ok "${SH}_restart_replaces_not_stacks" 1 "" ;;
                 *) ok "${SH}_restart_replaces_not_stacks" 0 "count=$OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- t10 shares the flags -------------------------------------------
  OUT="$(run "$SH" '
    t10 >/dev/null 2>&1; sleep 0.4
    t10 -k
    sleep 0.3
    timer_pids | grep -q . && echo STILL_RUNNING || echo GONE')"
  case "$OUT" in *GONE*) ok "${SH}_t10_takes_the_same_flags" 1 "" ;;
                 *) ok "${SH}_t10_takes_the_same_flags" 0 "$OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2

  # ---- list, help, and a bad flag -------------------------------------
  OUT="$(run "$SH" 't -l')"
  case "$OUT" in *"none running"*) ok "${SH}_list_when_idle" 1 "" ;;
                 *) ok "${SH}_list_when_idle" 0 "$OUT" ;; esac
  OUT="$(run "$SH" 't >/dev/null 2>&1; sleep 0.4; t -l')"
  case "$OUT" in *"running, id"*) ok "${SH}_list_when_running" 1 "" ;;
                 *) ok "${SH}_list_when_running" 0 "$OUT" ;; esac
  pkill -f "$TAG" 2>/dev/null; sleep 0.2
  OUT="$(run "$SH" 't --nonsense; echo "rc=$?"')"
  case "$OUT" in *"rc=2"*) ok "${SH}_bad_flag_is_rejected" 1 "" ;;
                 *) ok "${SH}_bad_flag_is_rejected" 0 "$OUT" ;; esac
  case "$OUT" in *"unknown option"*) ok "${SH}_bad_flag_explains" 1 "" ;;
                 *) ok "${SH}_bad_flag_explains" 0 "$OUT" ;; esac
  # a bad flag must not have started a timer as a side effect
  sleep 0.2
  if pgrep -f "$TAG" >/dev/null 2>&1; then
    ok "${SH}_bad_flag_starts_nothing" 0 "a timer was started anyway"
  else
    ok "${SH}_bad_flag_starts_nothing" 1 ""
  fi
  echo
done

echo "=========================================================="
echo "DRILL_SH=$DRILL_SH  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
