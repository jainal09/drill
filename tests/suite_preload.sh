#!/bin/bash
# ============================================================================
#  suite_preload.sh -- the LeetCode desk: preload.py under r / ri / Ctrl+R / Ctrl+E
#
#  The claim under test: a drill file with NO import lines can still use
#  Counter, deque, heappush and friends, exactly like the judge's environment
#  -- and a file that shadows a toolkit name, passes argv, checks __name__ or
#  exits with a code behaves as if the shim were not there. Everything runs
#  real python3 in a throwaway DRILL_HOME; the shell cases run under bash AND
#  zsh, and the two editor keys are driven on a real pty.
#
#    ./suite_preload.sh          run everything
#    ./suite_preload.sh ri       only cases whose name contains "ri"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
FILTER="${1:-}"
DRILL_SH="${DRILL_SH:-$REPO/drill.sh}"
CONFIG="${DRILL_CONFIG:-$REPO/nvimrc.lua}"

[ -f "$DRILL_SH" ] || { echo "suite_preload.sh: no drill.sh at $DRILL_SH" >&2; exit 2; }
[ -f "$REPO/preload.py" ] || { echo "suite_preload.sh: no preload.py at $REPO" >&2; exit 2; }
command -v python3 >/dev/null || { echo "suite_preload.sh: python3 not on PATH" >&2; exit 2; }

WORK="$DIR/work/preload.$$"
HOMEDIR="$WORK/home"
mkdir -p "$HOMEDIR/scratch" "$HOMEDIR/templates" "$HOMEDIR/solves"
cp "$REPO/preload.py" "$HOMEDIR/preload.py"
trap 'rm -rf "$WORK"' EXIT

printf 'print(Counter("aab"))\n' > "$HOMEDIR/scratch/counter.py"
cat > "$HOMEDIR/scratch/toolkit.py" <<'EOF'
h = []
heappush(h, 3); heappush(h, 1)
dd = defaultdict(list); dd["k"].append(heappop(h))
q = deque(accumulate([1, 2, 3]))
print("toolkit-ok", h[0], dd["k"][0], q[-1], inf > 10**9)
EOF
printf 'import sys\nprint(" ".join(sys.argv[1:]))\nprint(sys.argv[0].rsplit("/", 1)[-1])\n' \
  > "$HOMEDIR/scratch/args.py"
printf 'print(__name__)\n' > "$HOMEDIR/scratch/main.py"
printf 'Counter = 5\nprint(Counter)\n' > "$HOMEDIR/scratch/shadow.py"
printf 'x = 40\ndq = deque([1, 2])\n' > "$HOMEDIR/scratch/names.py"
printf 'import collections\nprint(collections.Counter("aa")["a"])\n' \
  > "$HOMEDIR/scratch/honest.py"
printf 'import sys\nsys.exit(3)\n' > "$HOMEDIR/scratch/bye.py"

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

run() {   # run <shell> <script> -- source drill.sh with the throwaway home
  local sh="$1" script="$2"
  DRILL_HOME="$HOMEDIR" "$sh" -c ". '$DRILL_SH' >/dev/null 2>&1; $script" 2>&1
}

for SH in bash zsh; do
  command -v "$SH" >/dev/null || { echo "skip: $SH not on PATH"; continue; }
  echo "===== $SH ====="

  OUT="$(run "$SH" 'r counter')"
  case "$OUT" in *"Counter({'a': 2"*) ok "${SH}_counter_without_import" 1 "" ;;
                 *) ok "${SH}_counter_without_import" 0 "$OUT" ;; esac

  OUT="$(run "$SH" 'r toolkit')"
  case "$OUT" in *"toolkit-ok 3 1 6 True"*) ok "${SH}_toolkit_names_live" 1 "" ;;
                 *) ok "${SH}_toolkit_names_live" 0 "$OUT" ;; esac

  OUT="$(run "$SH" 'r args x y')"
  case "$OUT" in *"x y"*"args.py"*) ok "${SH}_argv_reaches_the_file" 1 "" ;;
                 *) ok "${SH}_argv_reaches_the_file" 0 "$OUT" ;; esac

  OUT="$(run "$SH" 'r main')"
  case "$OUT" in *__main__*) ok "${SH}_name_is_main" 1 "" ;;
                 *) ok "${SH}_name_is_main" 0 "$OUT" ;; esac

  OUT="$(run "$SH" 'r shadow')"
  case "$OUT" in *5*) ok "${SH}_your_names_win" 1 "" ;;
                 *) ok "${SH}_your_names_win" 0 "$OUT" ;; esac

  # ri: the file's own names AND the toolkit are live at the >>> prompt
  OUT="$(run "$SH" 'printf "print(x + len(dq))\n" | ri names')"
  case "$OUT" in *42*) ok "${SH}_ri_has_file_and_toolkit" 1 "" ;;
                 *) ok "${SH}_ri_has_file_and_toolkit" 0 "$OUT" ;; esac

  OUT="$(run "$SH" 'r bye; echo "rc=$?"')"
  case "$OUT" in *"rc=3"*) ok "${SH}_exit_code_propagates" 1 "" ;;
                 *) ok "${SH}_exit_code_propagates" 0 "$OUT" ;; esac

  # without the shim (an install that predates it) r must be plain python3:
  # a file with real imports still runs, a bare toolkit name is an honest
  # NameError rather than silent magic from some stale cache
  mv "$HOMEDIR/preload.py" "$HOMEDIR/preload.py.away"
  OUT="$(run "$SH" 'r honest')"
  case "$OUT" in *2*) ok "${SH}_fallback_runs_plain_python" 1 "" ;;
                 *) ok "${SH}_fallback_runs_plain_python" 0 "$OUT" ;; esac
  OUT="$(run "$SH" 'r counter; echo "rc=$?"')"
  case "$OUT" in *NameError*rc=1*) ok "${SH}_fallback_is_really_plain" 1 "" ;;
                 *) ok "${SH}_fallback_is_really_plain" 0 "$OUT" ;; esac
  mv "$HOMEDIR/preload.py.away" "$HOMEDIR/preload.py"
  echo
done

echo "=== on a real pty: Ctrl+R and Ctrl+E route through the shim ==="
DRILL_SOCK="${TMPDIR:-/tmp}/drill-preload-$$.sock"
export DRILL_CONFIG="$CONFIG" DRILL_SOCK
PTY_OUT="$(timeout 180 python3 "$DIR/preload_drive.py" 2>/dev/null)"
rm -f "$DRILL_SOCK"
while IFS=$'\t' read -r verdict name got; do
  case "$verdict" in PASS|FAIL) ;; *) continue ;; esac
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  if [ "$verdict" = PASS ]; then
    PASS=$((PASS+1)); printf '\033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); BAD+=("$name"); printf '\033[31mFAIL\033[0m  %s  -- got: %s\n' "$name" "$got"
  fi
done <<< "$PTY_OUT"

echo
echo "=========================================================="
echo "DRILL_SH=$DRILL_SH  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
