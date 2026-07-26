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
# $1 = subdir, $2 = name (no arg -> open the directory listing)
_drill_edit() {
  local dir="$DRILL/$1"
  if [ -z "$2" ]; then
    nvim -u "$DRILL/nvimrc.lua" "$dir"
  else
    nvim -u "$DRILL/nvimrc.lua" "$dir/${2%.py}.py"
  fi
}
d()  { _drill_edit scratch   "$1"; }
dt() { _drill_edit templates "$1"; }
ds() { _drill_edit solves    "$1"; }

# ---- run --------------------------------------------------------------
# accepts a path, a path without .py, or a bare name living under $DRILL
_drill_find() {
  local n="$1" sub
  [ -f "$n" ] && { printf '%s\n' "$n"; return; }
  [ -f "$n.py" ] && { printf '%s\n' "$n.py"; return; }
  for sub in scratch solves templates .; do
    [ -f "$DRILL/$sub/${n%.py}.py" ] && { printf '%s\n' "$DRILL/$sub/${n%.py}.py"; return; }
  done
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

_drill_timer() {
  pkill -f "drill-timer" 2>/dev/null        # only ever one running
  python3 -c "$_DRILL_TIMER_PY" "$1" drill-timer &
  disown 2>/dev/null
  echo "timer: $1 min (counts down in the window title; sound + notification at zero)"
}
t()   { _drill_timer 25; }
t10() { _drill_timer 10; }
