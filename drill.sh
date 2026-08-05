# drill.sh -- shell commands for the drill environment. Works in bash and zsh.
#
# Sourced from the END of your shell rc, and it has to stay last: `d` is an
# oh-my-zsh function, `r` is a zsh builtin and `ri` is Ruby's. Sourcing after
# them is what makes these win.

DRILL="${DRILL_HOME:-$HOME/drill}"

# Free Ctrl+S / Ctrl+Q from XOFF/XON terminal flow control so nvim can bind
# them. Interactive shells with a real tty only -- stty errors otherwise.
case $- in
  *i*) [ -t 0 ] && stty -ixon 2>/dev/null ;;
esac

unalias d dt ds r ri t t10 2>/dev/null

# ---- edit -------------------------------------------------------------
# $1 = subdir; the rest name the file (no name -> open the directory listing)
#   d foo              scratch/foo.py
#   d proj file        scratch/proj/file.py   -- folders created as needed
#   d graph-prac/bfs iterative                -- args are joined with /
#   d search [query]   fuzzy-pick a file with fzf. 'search' is reserved: a
#                      file literally named search.py is still `d ./search`
_drill_edit() {
  local dir="$DRILL/$1" name
  shift
  if [ "$#" -eq 0 ] || [ -z "${1:-}" ]; then
    nvim -u "$DRILL/nvimrc.lua" "$dir"
    return
  fi
  if [ "$1" = "search" ]; then
    shift
    _drill_search "$dir" "$*"
    return
  fi
  name="$1"; shift
  while [ "$#" -gt 0 ]; do name="$name/$1"; shift; done
  name="${name%/}"                     # tolerate a trailing-slash typo
  case "/$name/" in                    # d/dt/ds GUARANTEE their bucket: a
    *"/../"*)                          # '..' would write outside it
      echo "drill: '..' would leave $1/ -- names stay inside their folder" >&2
      return 2 ;;
  esac
  name="${name%.py}.py"
  case "$name" in
    */*) mkdir -p "$dir/${name%/*}" || return ;;
  esac
  nvim -u "$DRILL/nvimrc.lua" "$dir/$name"
}
d()  { _drill_edit scratch   "$@"; }
dt() { _drill_edit templates "$@"; }
ds() { _drill_edit solves    "$@"; }

# ---- search -----------------------------------------------------------
# `d search` -> fuzzy-pick a .py under scratch/ and open it; dt/ds likewise.
# $1 = directory, $2 = optional starting query. Esc / no match opens nothing.
_drill_search() {
  local dir="$1" pick
  if ! command -v fzf >/dev/null 2>&1; then
    echo "drill: 'd search' needs fzf -- brew install fzf (or apt install fzf)" >&2
    return 127
  fi
  [ -d "$dir" ] || { echo "drill: no directory $dir" >&2; return 1; }
  pick="$(cd "$dir" && find . -name '*.py' -type f | sed 's|^\./||' | sort |
          fzf --query "${2:-}" --prompt 'drill> ' --preview 'head -40 -- {}')"
  [ -n "$pick" ] || return 0
  nvim -u "$DRILL/nvimrc.lua" "$dir/$pick"
}

# ---- run --------------------------------------------------------------
# accepts a path, a path without .py, or a bare name living under $DRILL --
# bare names of files nested in project folders are found by a recursive
# walk, scratch/ first
_drill_find() {
  local n="$1" sub f esc
  [ -f "$n" ] && { printf '%s\n' "$n"; return; }
  [ -f "$n.py" ] && { printf '%s\n' "$n.py"; return; }
  for sub in scratch solves templates .; do
    [ -f "$DRILL/$sub/${n%.py}.py" ] && { printf '%s\n' "$DRILL/$sub/${n%.py}.py"; return; }
  done
  case "$n" in
    */*) ;;   # a path that did not resolve above stays as typed
    *)  # -name takes a GLOB, and d happily creates names like two-sum[easy]
        # -- escape [ * ? \ so the walk finds the literal file instead of
        # pattern-matching its way to a sibling (] alone is already literal)
        esc="$(printf '%s' "${n%.py}" | sed 's/[[*?\\]/\\&/g')"
        for sub in scratch solves templates; do
          f="$(find "$DRILL/$sub" -type f -name "${esc}.py" 2>/dev/null | sort | head -1)"
          [ -n "$f" ] && { printf '%s\n' "$f"; return; }
        done ;;
  esac
  printf '%s\n' "$n"
}
r()  { python3    "$(_drill_find "$1")" "${@:2}"; }
ri() { python3 -i "$(_drill_find "$1")"; }

# ---- timer ------------------------------------------------------------
_DRILL_TIMER_PY=$(cat <<'PY'
import shutil, subprocess, sys, time

mins = float(sys.argv[1])
end = time.monotonic() + mins * 60
try:
    tty = open("/dev/tty", "w")
except OSError:
    tty = sys.stderr


def run(cmd):
    if not shutil.which(cmd[0]):
        return False
    try:
        subprocess.run(cmd, capture_output=True)
        return True
    except OSError:
        return False


while True:
    left = end - time.monotonic()
    if left <= 0:
        break
    m, s = divmod(int(left + 0.5), 60)
    tty.write("\033]0;%02d:%02d drill\007" % (m, s))
    tty.flush()
    time.sleep(0.5)          # repaint fast: reclaims the title from p10k/nvim

tty.write("\033]0;TIME UP\007\a\n*** TIME UP -- %g min ***\n" % mins)
tty.flush()

msg = "%g min done" % mins
(run(["osascript", "-e", 'display notification "%s" with title "drill"' % msg])
 or run(["notify-send", "drill", msg]))

for _ in range(3):
    if not (run(["afplay", "/System/Library/Sounds/Glass.aiff"])
            or run(["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"])):
        tty.write("\a")      # no sound player: the terminal bell is the fallback
        tty.flush()
        time.sleep(0.4)
PY
)

# The tag is the last argument handed to the python process, which is the only
# thing that makes one findable in `ps` later. Overridable so the test suite can
# run a timer of its own without going anywhere near yours.
: "${DRILL_TIMER_TAG:=drill-timer}"

# Killing a timer leaves the last countdown frozen in the window title -- the
# timer repaints it twice a second, and once it is gone nothing else does.
_drill_timer_clear_title() { printf '\033]0;\007'; }

# Every running timer, one PID per line. Written as a here-doc loop rather than
# `for p in $pids` on purpose: zsh does not word-split unquoted expansions the
# way bash does, so that form iterates ONCE with the whole newline-joined blob
# in zsh and per-PID in bash. This behaves the same in both.
_drill_timer_pids() { pgrep -f "$DRILL_TIMER_TAG" 2>/dev/null; }

_drill_timer_stop() {
  local want="$1" pids p found="" killed=0
  pids="$(_drill_timer_pids)"
  if [ -z "$pids" ]; then
    echo "timer: none running"
    return 1
  fi

  if [ -n "$want" ]; then
    # NEVER kill a bare id on trust. A finished timer's pid is returned to the
    # OS and handed out again, so `t -k 70147` typed from scrollback ten minutes
    # later could land on something else entirely. Only ids that are a drill
    # timer *right now* are eligible.
    while IFS= read -r p; do
      [ -n "$p" ] && [ "$p" = "$want" ] && found="$p"
    done <<EOF
$pids
EOF
    if [ -z "$found" ]; then
      printf 'timer: %s is not a running drill timer (running: %s)\n' \
        "$want" "$(printf '%s' "$pids" | tr '\n' ' ')" >&2
      return 1
    fi
    kill "$found" 2>/dev/null && killed=1
  else
    while IFS= read -r p; do
      [ -n "$p" ] && kill "$p" 2>/dev/null && killed=$((killed + 1))
    done <<EOF
$pids
EOF
  fi

  _drill_timer_clear_title
  [ "$killed" -gt 0 ] && echo "timer: stopped" || { echo "timer: nothing to stop"; return 1; }
  return 0
}

_drill_timer() {
  _drill_timer_stop >/dev/null 2>&1          # only ever one running
  # stdio goes to /dev/null, and that is not cosmetic: a background child keeps
  # the inherited descriptors open, so any command substitution around this --
  # `id=$(t)`, or a test capturing the output -- would block for the full 25
  # minutes waiting for the pipe to close. The countdown, the bell and the
  # TIME UP line are all written to /dev/tty by the script itself, so nothing
  # is lost by detaching these.
  python3 -c "$_DRILL_TIMER_PY" "$1" "$DRILL_TIMER_TAG" >/dev/null 2>&1 &
  local id=$!
  disown 2>/dev/null
  echo "timer: $1 min, id $id (counts down in the window title; sound at zero)"
  echo "       stop it with:  t -k $id      (or just  t -k)"
}

# t / t10 take the same flags, so whichever one you started with, the muscle
# memory for stopping it is the same.
_drill_timer_cmd() {
  local mins="$1"; shift
  case "${1:-}" in
    "")             _drill_timer "$mins" ;;
    -k|--kill|stop) shift; _drill_timer_stop "${1:-}" ;;
    -l|--list)      local p; p="$(_drill_timer_pids)"
                    [ -n "$p" ] && printf 'timer: running, id %s\n' \
                      "$(printf '%s' "$p" | tr '\n' ' ')" || echo "timer: none running" ;;
    -h|--help)      echo "usage: t | t10        start a 25- / 10-minute timer"
                    echo "       t -k [id]      stop it (id optional -- there is only one)"
                    echo "       t -l           is one running?" ;;
    *)              echo "timer: unknown option '$1' (try: t -k [id], t -l, t -h)" >&2
                    return 2 ;;
  esac
}
t()   { _drill_timer_cmd 25 "$@"; }
t10() { _drill_timer_cmd 10 "$@"; }
