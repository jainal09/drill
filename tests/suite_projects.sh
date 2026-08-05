#!/bin/bash
# ============================================================================
#  suite_projects.sh -- d <dir> <name>, d search, and nested r resolution
#
#  drill.sh claims to work in bash AND zsh, so every case runs under both.
#  Nothing real is launched: nvim and fzf are stubs that record their argv
#  (and, for fzf, their stdin) into files the assertions read back, and
#  DRILL_HOME points at a throwaway directory so your practice files are
#  never touched.
#
#    ./suite_projects.sh          run everything
#    ./suite_projects.sh search   only cases whose name contains "search"
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
PATH="$DIR/bin:$PATH"; export PATH
FILTER="${1:-}"
DRILL_SH="${DRILL_SH:-$REPO/drill.sh}"

[ -f "$DRILL_SH" ] || { echo "suite_projects.sh: no drill.sh at $DRILL_SH" >&2; exit 2; }

WORK="$DIR/work/projects.$$"
STUB="$WORK/stub"              # nvim + fzf
STUB_NOFZF="$WORK/stub-nofzf"  # nvim only, for the missing-fzf cases
HOMEDIR="$WORK/home"
NVIM_LOG="$WORK/nvim.log"; FZF_IN="$WORK/fzf.in"; FZF_ARGS="$WORK/fzf.args"
mkdir -p "$STUB" "$STUB_NOFZF"
trap 'rm -rf "$WORK"' EXIT

cat > "$STUB/nvim" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$NVIM_LOG"
EOF
cat > "$STUB/fzf" <<'EOF'
#!/bin/sh
cat > "$FZF_IN"
printf '%s\n' "$@" > "$FZF_ARGS"
if [ -n "${FZF_PICK:-}" ]; then printf '%s\n' "$FZF_PICK"; exit 0; fi
exit 130
EOF
chmod +x "$STUB/nvim" "$STUB/fzf"
cp "$STUB/nvim" "$STUB_NOFZF/nvim"; chmod +x "$STUB_NOFZF/nvim"

reset_home() {
  rm -rf "$HOMEDIR"
  mkdir -p "$HOMEDIR/scratch" "$HOMEDIR/templates" "$HOMEDIR/solves"
}

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

# run <shell-binary> <PATH value> <script> -- source drill.sh, run the script.
# DRILL_HOME rides in as an env prefix because drill.sh reads it at SOURCE
# time; the stub log paths do too so the stubs know where to write. PATH is
# set INSIDE the child script, not as a prefix: zsh sources ~/.zshenv even
# for `zsh -c`, and a zshenv that prepends its own dirs would put the real
# nvim/fzf in front of the stubs.
run() {
  local sh="$1" path="$2" script="$3"
  : > "$NVIM_LOG"; : > "$FZF_IN"; : > "$FZF_ARGS"
  DRILL_HOME="$HOMEDIR" \
  NVIM_LOG="$NVIM_LOG" FZF_IN="$FZF_IN" FZF_ARGS="$FZF_ARGS" FZF_PICK="${FZF_PICK:-}" \
    "$sh" -c "PATH='$path'; export PATH; . '$DRILL_SH' >/dev/null 2>&1; $script" 2>&1
}

for SH in bash zsh; do
  SH_BIN="$(command -v "$SH")" || { echo "skip: $SH not on PATH"; continue; }
  echo "===== $SH ====="
  STUBPATH="$STUB:$PATH"
  # deterministic scrub: a dev box likely has real fzf on PATH
  NOFZFPATH="$STUB_NOFZF:/usr/bin:/bin"

  # ---- d <dir> <name> creates the folder and opens the file ------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd foo bar' >/dev/null
  if grep -qxF "$HOMEDIR/scratch/foo/bar.py" "$NVIM_LOG"; then
    ok "${SH}_two_args_opens_nested" 1 ""
  else
    ok "${SH}_two_args_opens_nested" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi
  [ -d "$HOMEDIR/scratch/foo" ] && ok "${SH}_two_args_creates_folder" 1 "" \
                                || ok "${SH}_two_args_creates_folder" 0 "scratch/foo missing"

  # ---- a slashed folder arg builds the whole chain ---------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd graph-prac/bfs recursive' >/dev/null
  if grep -qxF "$HOMEDIR/scratch/graph-prac/bfs/recursive.py" "$NVIM_LOG" \
     && [ -d "$HOMEDIR/scratch/graph-prac/bfs" ]; then
    ok "${SH}_slash_folder_plus_name" 1 ""
  else
    ok "${SH}_slash_folder_plus_name" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- the one-arg spelling is the same file ---------------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd graph-prac/bfs/iterative' >/dev/null
  if grep -qxF "$HOMEDIR/scratch/graph-prac/bfs/iterative.py" "$NVIM_LOG"; then
    ok "${SH}_one_arg_slash_creates_parents" 1 ""
  else
    ok "${SH}_one_arg_slash_creates_parents" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- flat d <name> is byte-identical to before -----------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd name' >/dev/null
  if grep -qxF "$HOMEDIR/scratch/name.py" "$NVIM_LOG" \
     && [ -z "$(find "$HOMEDIR/scratch" -mindepth 1 -type d)" ]; then
    ok "${SH}_one_arg_flat_unchanged" 1 ""
  else
    ok "${SH}_one_arg_flat_unchanged" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- bare d still opens the directory listing ------------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd' >/dev/null
  if [ "$(tail -1 "$NVIM_LOG")" = "$HOMEDIR/scratch" ]; then
    ok "${SH}_bare_opens_listing" 1 ""
  else
    ok "${SH}_bare_opens_listing" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- .py stripping composes with nesting -----------------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd foo bar.py' >/dev/null
  if grep -qxF "$HOMEDIR/scratch/foo/bar.py" "$NVIM_LOG" && ! grep -q 'bar\.py\.py' "$NVIM_LOG"; then
    ok "${SH}_nested_py_suffix_stripped" 1 ""
  else
    ok "${SH}_nested_py_suffix_stripped" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- dt shares the nesting -------------------------------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'dt pat heap' >/dev/null
  if grep -qxF "$HOMEDIR/templates/pat/heap.py" "$NVIM_LOG"; then
    ok "${SH}_dt_shares_nesting" 1 ""
  else
    ok "${SH}_dt_shares_nesting" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi

  # ---- d search pipes the relative file list to fzf --------------------
  reset_home
  mkdir -p "$HOMEDIR/scratch/heap-practice"
  : > "$HOMEDIR/scratch/heap-practice/heap-traverse.py"
  : > "$HOMEDIR/scratch/other.py"
  FZF_PICK="heap-practice/heap-traverse.py"
  run "$SH_BIN" "$STUBPATH" 'd search' >/dev/null
  if grep -qxF "heap-practice/heap-traverse.py" "$FZF_IN" && grep -qxF "other.py" "$FZF_IN"; then
    ok "${SH}_search_pipes_file_list" 1 ""
  else
    ok "${SH}_search_pipes_file_list" 0 "fzf stdin: $(tr '\n' ' ' < "$FZF_IN")"
  fi
  if grep -qxF "$HOMEDIR/scratch/heap-practice/heap-traverse.py" "$NVIM_LOG"; then
    ok "${SH}_search_opens_the_pick" 1 ""
  else
    ok "${SH}_search_opens_the_pick" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi
  FZF_PICK=""

  # ---- d search <query> pre-seeds the fzf query ------------------------
  reset_home
  : > "$HOMEDIR/scratch/heapify.py"
  run "$SH_BIN" "$STUBPATH" 'd search heap' >/dev/null
  if grep -qxF -- '--query' "$FZF_ARGS" && grep -qxF 'heap' "$FZF_ARGS"; then
    ok "${SH}_search_query_preseeds" 1 ""
  else
    ok "${SH}_search_query_preseeds" 0 "fzf argv: $(tr '\n' ' ' < "$FZF_ARGS")"
  fi

  # ---- Esc in fzf (exit 130) opens nothing, rc 0 -----------------------
  reset_home
  : > "$HOMEDIR/scratch/whatever.py"
  OUT="$(run "$SH_BIN" "$STUBPATH" 'd search; echo "rc=$?"')"
  COND=0
  [ ! -s "$NVIM_LOG" ] && case "$OUT" in *"rc=0"*) COND=1 ;; esac
  ok "${SH}_search_cancel_opens_nothing" "$COND" "$OUT / nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"

  # ---- missing fzf: say so, open nothing -------------------------------
  reset_home
  OUT="$(run "$SH_BIN" "$NOFZFPATH" 'd search; echo "rc=$?"')"
  case "$OUT" in
    *"needs fzf"*"rc=127"*|*"rc=127"*"needs fzf"*) ok "${SH}_search_missing_fzf_says_so" 1 "" ;;
    *) ok "${SH}_search_missing_fzf_says_so" 0 "$OUT" ;;
  esac
  [ -s "$NVIM_LOG" ] && ok "${SH}_search_missing_fzf_opens_nothing" 0 "nvim was launched" \
                     || ok "${SH}_search_missing_fzf_opens_nothing" 1 ""

  # ---- ds search looks in solves/ --------------------------------------
  reset_home
  : > "$HOMEDIR/solves/day1.py"
  FZF_PICK="day1.py"
  run "$SH_BIN" "$STUBPATH" 'ds search' >/dev/null
  if grep -qxF "$HOMEDIR/solves/day1.py" "$NVIM_LOG"; then
    ok "${SH}_ds_search_uses_solves" 1 ""
  else
    ok "${SH}_ds_search_uses_solves" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi
  FZF_PICK=""

  # ---- r resolves nested files, by path and by bare name ---------------
  reset_home
  mkdir -p "$HOMEDIR/scratch/proj"
  printf 'print("hi")\n' > "$HOMEDIR/scratch/proj/hello.py"
  OUT="$(run "$SH_BIN" "$STUBPATH" 'r proj/hello')"
  case "$OUT" in *hi*) ok "${SH}_r_runs_nested_path" 1 "" ;;
                 *) ok "${SH}_r_runs_nested_path" 0 "$OUT" ;; esac
  OUT="$(run "$SH_BIN" "$STUBPATH" 'r hello')"
  case "$OUT" in *hi*) ok "${SH}_r_bare_name_finds_nested" 1 "" ;;
                 *) ok "${SH}_r_bare_name_finds_nested" 0 "$OUT" ;; esac

  # ---- './search' escapes the reserved word ----------------------------
  reset_home
  run "$SH_BIN" "$STUBPATH" 'd ./search' >/dev/null
  if grep -q '/scratch/\./search\.py$' "$NVIM_LOG" && [ ! -s "$FZF_IN" ]; then
    ok "${SH}_dot_slash_escapes_reserved" 1 ""
  else
    ok "${SH}_dot_slash_escapes_reserved" 0 "nvim got: $(tr '\n' ' ' < "$NVIM_LOG")"
  fi
  echo
done

echo "=========================================================="
echo "DRILL_SH=$DRILL_SH  PASS=$PASS  FAIL=$FAIL"
[ $FAIL -gt 0 ] && { echo "failing: ${BAD[*]}"; exit 1; }
exit 0
