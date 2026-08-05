#!/usr/bin/env bash
# Install the drill environment. Touches exactly two things:
#   1. $DRILL_HOME (default ~/drill)
#   2. one line at the end of your shell rc
# It does NOT touch ~/.config/nvim or ~/.vimrc. That is the whole point.
set -euo pipefail

DRILL_HOME="${DRILL_HOME:-$HOME/drill}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEGIN_MARK="# >>> drill >>>"
END_MARK="# <<< drill <<<"

say()  { printf '%s\n' "$*"; }
bail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---- which rc file? ---------------------------------------------------
rc_file() {
  case "$(basename "${SHELL:-/bin/sh}")" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) if [ -f "$HOME/.bashrc" ]; then printf '%s\n' "$HOME/.bashrc"
          else printf '%s\n' "$HOME/.bash_profile"; fi ;;
    *)    printf '' ;;
  esac
}

# ---- uninstall --------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  RC="$(rc_file)"
  if [ -n "$RC" ] && [ -f "$RC" ] && grep -qF "$BEGIN_MARK" "$RC"; then
    cp "$RC" "$RC.pre-drill-uninstall.bak"
    # delete the marked block, leave everything else byte-for-byte alone
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      index($0,b){skip=1} !skip{print} index($0,e){skip=0}' \
      "$RC" > "$RC.tmp" && mv "$RC.tmp" "$RC"
    say "removed the drill block from $RC (backup: $RC.pre-drill-uninstall.bak)"
  else
    say "no drill block found in your shell rc"
  fi
  say "your files in $DRILL_HOME were left alone -- delete them yourself if you want them gone"
  exit 0
fi

# ---- dependencies -----------------------------------------------------
command -v nvim    >/dev/null 2>&1 || bail "neovim not found. brew install neovim (or apt install neovim)"
command -v python3 >/dev/null 2>&1 || bail "python3 not found"
command -v fzf     >/dev/null 2>&1 || bail "fzf not found. brew install fzf (or apt install fzf) -- 'd search' needs it"

NVIM_VER="$(nvim --version | head -1 | sed 's/^NVIM v//')"
NVIM_MAJOR="${NVIM_VER%%.*}"
NVIM_REST="${NVIM_VER#*.}"
NVIM_MINOR="${NVIM_REST%%.*}"
if [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -lt 9 ]; then
  bail "neovim $NVIM_VER is too old, need 0.9+ (the config is Lua and uses nvim_win_hide)"
fi

# ---- files ------------------------------------------------------------
mkdir -p "$DRILL_HOME/templates" "$DRILL_HOME/solves" "$DRILL_HOME/scratch"

for f in nvimrc.lua drill.sh preload.py KEYS.md; do
  [ -f "$SRC/$f" ] || bail "missing $f next to install.sh"
  if [ -f "$DRILL_HOME/$f" ] && ! cmp -s "$SRC/$f" "$DRILL_HOME/$f"; then
    cp "$DRILL_HOME/$f" "$DRILL_HOME/$f.bak"
    say "kept your old $f as $f.bak"
  fi
  cp "$SRC/$f" "$DRILL_HOME/$f"
done

# yours to fill -- never clobbered
[ -e "$DRILL_HOME/cheatsheet.py" ] || : > "$DRILL_HOME/cheatsheet.py"
[ -e "$DRILL_HOME/log.md" ]       || : > "$DRILL_HOME/log.md"

# ---- shell rc ---------------------------------------------------------
RC="$(rc_file)"
if [ -z "$RC" ]; then
  say ""
  say "unrecognised shell ($SHELL). Add this to your rc file by hand, at the END:"
  say "    source $DRILL_HOME/drill.sh"
elif grep -qF "$BEGIN_MARK" "$RC" 2>/dev/null; then
  say "shell rc already has the drill block, leaving $RC alone"
else
  [ -f "$RC" ] && cp "$RC" "$RC.pre-drill.bak"
  {
    printf '\n%s\n' "$BEGIN_MARK"
    printf '%s\n' "# must stay LAST: d/r/ri collide with oh-my-zsh, a zsh builtin and Ruby"
    printf 'source %s\n' "$DRILL_HOME/drill.sh"
    printf '%s\n' "$END_MARK"
  } >> "$RC"
  say "added 4 lines to the end of $RC $([ -f "$RC.pre-drill.bak" ] && echo "(backup: $RC.pre-drill.bak)")"
fi

cat <<EOF

  installed to $DRILL_HOME

  run 'exec \$SHELL' (or open a new terminal) to load the commands

  d  <name>     edit $DRILL_HOME/scratch/<name>.py      bare 'd'  -> dir listing
  d  <dir> <name>  nested: scratch/<dir>/<name>.py, folders created as needed
  d  search     fuzzy-pick a file with fzf ('dt search' / 'ds search' likewise)
  dt <name>     edit $DRILL_HOME/templates/<name>.py    bare 'dt' -> dir listing
  ds <name>     edit $DRILL_HOME/solves/<name>.py       bare 'ds' -> dir listing
  r  <file>     python3 <file>, Counter/deque/heappush... pre-imported
  ri <file>     python3 -i <file>   -> REPL with the file's names live
  t  / t10      25- / 10-minute timer, counts down in the window title

  in the editor: Ctrl+E shows and hides the interpreter, Ctrl+S saves,
                 Ctrl+R runs. Full list: $DRILL_HOME/KEYS.md

EOF
