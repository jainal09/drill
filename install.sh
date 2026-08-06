#!/usr/bin/env bash
# Install the drill environment. Touches exactly two things on its own:
#   1. $DRILL_HOME (default ~/drill)
#   2. one line at the end of your shell rc
# It does NOT touch ~/.config/nvim or ~/.vimrc. That is the whole point.
#
# The one exception is packages: when something drill needs is missing it
# prints the exact command and ASKS before running it. --yes skips the asking,
# and a non-tty stdin never asks -- it prints the command and leaves it to you.
set -euo pipefail

DRILL_HOME="${DRILL_HOME:-$HOME/drill}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEGIN_MARK="# >>> drill >>>"
END_MARK="# <<< drill <<<"
ASSUME_YES=0

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

# ---- arguments --------------------------------------------------------
UNINSTALL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --uninstall) UNINSTALL=1 ;;
    -y|--yes)    ASSUME_YES=1 ;;
    -h|--help)   say "usage: ./install.sh [--yes] [--uninstall]"
                 say "       --yes        install missing packages without asking"
                 say "       --uninstall  remove the drill block from your shell rc"
                 exit 0 ;;
    *)           bail "unknown option '$1' (try --help)" ;;
  esac
  shift
done

# ---- uninstall --------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
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
# Two kinds of missing, and the second is the reason this section is longer
# than one line per command. HARD: drill does not run at all. FEATURE:
# something the README promises silently does nothing -- and a feature that
# quietly no-ops is a worse bug than one that errors. The clipboard is the
# example that made this necessary: nvim with `clipboard=unnamedplus` and no
# provider does not warn you, it just makes Ctrl+V over a selection DELETE the
# selection and paste nothing.

OS="$(uname -s)"
WSL=0
if [ "$OS" = "Linux" ] && { [ -n "${WSL_DISTRO_NAME:-}" ] ||
     grep -qi microsoft /proc/version 2>/dev/null; }; then WSL=1; fi

# brew is probed LAST on Linux. A linuxbrew install is usually a personal
# extra, while the clipboard, sound and process packages want to come from the
# distro that owns the session bus and /usr/share/sounds.
PM=""
if [ "$OS" = "Darwin" ]; then
  command -v brew >/dev/null 2>&1 && PM=brew || true
else
  for c in apt-get dnf zypper pacman apk brew; do
    if command -v "$c" >/dev/null 2>&1; then PM="$c"; break; fi
  done
fi

# A table, not a guess. The clipboard, sound and process packages are named
# differently on nearly every distro, and printing an install line that fails
# is worse than printing none. Empty = this manager has no name we know for it.
pkg_for() {
  case "$PM" in
    brew)    case "$1" in python3) echo python ;; fzf) echo fzf ;;
                          clipboard) echo xclip ;; esac ;;
    apt-get) case "$1" in python3) echo python3 ;; fzf) echo fzf ;;
                          clipboard) echo "wl-clipboard xclip" ;;
                          sound) echo pulseaudio-utils ;;
                          notify) echo libnotify-bin ;; pgrep) echo procps ;; esac ;;
    dnf)     case "$1" in python3) echo python3 ;; fzf) echo fzf ;;
                          clipboard) echo "wl-clipboard xclip" ;;
                          sound) echo pulseaudio-utils ;;
                          notify) echo libnotify ;; pgrep) echo procps-ng ;; esac ;;
    zypper)  case "$1" in python3) echo python3 ;; fzf) echo fzf ;;
                          clipboard) echo "wl-clipboard xclip" ;;
                          sound) echo pulseaudio-utils ;;
                          notify) echo libnotify-tools ;; pgrep) echo procps ;; esac ;;
    pacman)  case "$1" in python3) echo python ;; fzf) echo fzf ;;
                          clipboard) echo "wl-clipboard xclip" ;;
                          sound) echo libpulse ;;
                          notify) echo libnotify ;; pgrep) echo procps-ng ;; esac ;;
    apk)     case "$1" in python3) echo python3 ;; fzf) echo fzf ;;
                          clipboard) echo xclip ;; sound) echo pulseaudio-utils ;;
                          notify) echo libnotify ;; pgrep) echo procps ;; esac ;;
  esac
}

install_cmd() {   # install_cmd <packages...> -> the command that installs them
  case "$PM" in
    brew)    printf 'brew install %s' "$*" ;;
    apt-get) printf 'sudo apt-get install -y %s' "$*" ;;
    dnf)     printf 'sudo dnf install -y %s' "$*" ;;
    zypper)  printf 'sudo zypper install -y %s' "$*" ;;
    pacman)  printf 'sudo pacman -S --needed --noconfirm %s' "$*" ;;
    apk)     printf 'sudo apk add %s' "$*" ;;
  esac
}

# neovim is handled apart from the table because the distro package is
# routinely too old to be worth offering: Ubuntu 22.04 ships 0.6.1, which the
# 0.9 gate below then rejects. Telling someone to install a version this very
# script refuses is worse than telling them nothing -- so ask apt what its
# candidate actually is rather than hardcoding a verdict about apt.
nvim_pkg() {
  case "$PM" in
    apt-get)
      case "$(apt-cache policy neovim 2>/dev/null | awk '/Candidate:/{print $2}')" in
        ""|"(none)"|0.[0-8]|0.[0-8].*) echo "" ;;
        *) echo neovim ;;
      esac ;;
    "") echo "" ;;
    *)  echo neovim ;;
  esac
}
NVIM_BY_HAND="install neovim 0.9+ by hand: 'snap install nvim --classic',
    or the AppImage from https://github.com/neovim/neovim/releases"

MISSING=""        # packages we can name -- offered as one install command
NOTES=""          # one human line per missing thing, always printed
HARD=0            # a HARD miss blocks the install even after we try to fix it

need() {          # need <hard|feature> <package-key> <what it costs you>
  local p
  p="$(pkg_for "$2")"
  [ -n "$p" ] && MISSING="$MISSING $p"
  NOTES="$NOTES
    - $3"
  [ "$1" = hard ] && HARD=1
  return 0        # the test above is the last command; without this, `set -e`
}                 # would kill the script on every FEATURE-level miss

check_deps() {
  MISSING=""; NOTES=""; HARD=0
  local c p have cand

  # ---- neovim, and the version gate
  if ! command -v nvim >/dev/null 2>&1; then
    p="$(nvim_pkg)"
    if [ -n "$p" ]; then MISSING="$MISSING $p"; NOTES="$NOTES
    - neovim -- the editor itself"
    else NOTES="$NOTES
    - neovim -- the editor itself. $NVIM_BY_HAND"; fi
    HARD=1
  else
    # sed alone, NOT `head -1 | sed`. head exits after the first line and closes
    # the pipe; if nvim is still writing it takes SIGPIPE, the pipeline status
    # becomes 141, and `set -o pipefail` + `set -e` abort the installer with no
    # message at all. nvim --version is smaller than the pipe buffer so the race
    # is unlikely -- but the failure mode is a silent abort, so do not race it.
    cand="$(nvim --version | sed -n '1s/^NVIM v//p')"
    # DIGITS only. A nightly prints 0.11.0-dev-1234+gabcdef, and `-dev` inside
    # an arithmetic test is a fatal error under `set -e` -- the version check
    # would abort the install instead of passing it.
    local maj min rest
    maj="$(printf '%s' "${cand%%.*}" | tr -cd '0-9')"
    rest="${cand#*.}"; min="$(printf '%s' "${rest%%.*}" | tr -cd '0-9')"
    if [ "${maj:-0}" -eq 0 ] && [ "${min:-0}" -lt 9 ]; then
      NOTES="$NOTES
    - neovim $cand is too old, need 0.9+ (the config is Lua and uses nvim_win_hide).
      $NVIM_BY_HAND"
      HARD=1
    fi
  fi

  # ---- python3, and on WSL it has to be a REAL one. WSL appends the Windows
  # PATH, so with no Linux python installed `python3` resolves to the Store App
  # Execution Alias under /mnt/c/.../WindowsApps -- which opens the Microsoft
  # Store instead of running your file, inside a 15-row terminal split, and
  # Ctrl+E and Ctrl+R are both simply dead.
  p="$(command -v python3 2>/dev/null || true)"
  case "$p" in
    "")     need hard python3 "python3 -- r, ri, Ctrl+R and Ctrl+E all shell out to it" ;;
    /mnt/*) need hard python3 "python3 is $p, the Windows Store alias, not an interpreter -- install a Linux python3" ;;
  esac

  command -v fzf >/dev/null 2>&1 ||
    need feature fzf "fzf -- 'd search' has nothing to fuzzy-pick with"

  if [ "$OS" != "Darwin" ]; then
    # macOS has pbcopy/pbpaste built in and nvim always finds them. Everywhere
    # else the provider is a separate package. On WSL clip.exe + powershell.exe
    # count: nvimrc.lua falls back to them when nothing else is installed.
    have=0
    for c in wl-copy xclip xsel win32yank.exe; do
      command -v "$c" >/dev/null 2>&1 && { have=1; break; }
    done
    if [ "$have" -eq 0 ] && [ "$WSL" -eq 1 ] &&
       command -v clip.exe >/dev/null 2>&1 && command -v powershell.exe >/dev/null 2>&1; then
      have=1
    fi
    [ "$have" -eq 1 ] || need feature clipboard \
      "no clipboard provider -- Ctrl+C/X/V do nothing, and Ctrl+V over a selection deletes it"

    # The timer's sound and notification at zero. On WSL, powershell.exe is a
    # backstop for both -- measured on Ubuntu 22.04 under WSLg, `pw-play` is
    # installed and fails ("no node available") and `notify-send` is installed
    # and fails (WSLg ships no notification daemon, so there is nothing on the
    # session bus to answer). Presence is not proof either works, which is why
    # the timer tries each in turn and believes the EXIT CODE. All this check
    # can honestly say is whether there is anything at all to try.
    WIN_FALLBACK=0
    [ "$WSL" -eq 1 ] && command -v powershell.exe >/dev/null 2>&1 && WIN_FALLBACK=1

    have="$WIN_FALLBACK"
    for c in paplay pw-play aplay; do
      command -v "$c" >/dev/null 2>&1 && { have=1; break; }
    done
    [ "$have" -eq 1 ] || need feature sound \
      "no sound player -- the timer falls back to the terminal bell"

    [ "$WIN_FALLBACK" -eq 1 ] || command -v notify-send >/dev/null 2>&1 ||
      need feature notify "no notify-send -- the timer has no desktop notification"
  fi

  command -v pgrep >/dev/null 2>&1 || need feature pgrep \
    "no pgrep -- 't -k' and 't -l' cannot find a running timer"
}

check_deps
if [ -n "$NOTES" ]; then
  say ""
  say "  missing:"
  printf '%s\n' "$NOTES"
  CMD=""
  # unquoted on purpose: $MISSING is a space-separated list, one arg per package
  [ -n "$MISSING" ] && CMD="$(install_cmd $MISSING)"
  if [ -n "$CMD" ]; then
    say ""
    say "      $CMD"
    say ""
    RUN=0
    if [ "$ASSUME_YES" -eq 1 ]; then
      RUN=1
    elif [ -t 0 ]; then
      printf '  run it now? [y/N] '
      read -r ans || ans=""
      case "$ans" in y|Y|yes|YES) RUN=1 ;; esac
    else
      say "  (stdin is not a tty, so nothing was asked and nothing was run --"
      say "   run the line above yourself, or re-run install.sh with --yes)"
    fi
    if [ "$RUN" -eq 1 ]; then
      sh -c "$CMD" || bail "that install failed -- run it by hand and re-run ./install.sh"
      check_deps                      # believe the probes, not the exit code
      [ -n "$NOTES" ] && { say ""; say "  still missing:"; printf '%s\n' "$NOTES"; }
    fi
  fi
  say ""
fi
[ "$HARD" -eq 0 ] || bail "drill cannot run without the items marked above"

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
