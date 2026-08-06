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
# Both run through the preload shim when it is installed: the file you typed
# stays import-free, but Counter, deque, heappush and friends are already
# there. Without the shim (an install that predates it) they are plain python3.
r() {
  local f; f="$(_drill_find "$1")"
  if [ -f "$DRILL/preload.py" ]; then python3 "$DRILL/preload.py" "$f" "${@:2}"
  else python3 "$f" "${@:2}"; fi
}
ri() {
  local f; f="$(_drill_find "$1")"
  if [ -f "$DRILL/preload.py" ]; then python3 -i "$DRILL/preload.py" "$f"
  else python3 -i "$f"; fi
}

# ---- timer ------------------------------------------------------------
_DRILL_TIMER_PY=$(cat <<'PY'
# drill-timer-proc-9f3c2a1e -- IDENTITY, not a comment. This whole script is
# argv[2] of the running python, so this line is in the process's command line
# and nothing else on the system has it. drill.sh matches on it to know which
# processes are really its timers; see _drill_timer_pids. Do not edit or remove
# without changing _DRILL_TIMER_MARKER to match.
import os, shutil, subprocess, sys, time

mins = float(sys.argv[1])
end = time.monotonic() + mins * 60
try:
    tty = open("/dev/tty", "w")
except OSError:
    tty = sys.stderr


def run(cmd):
    # Believe the EXIT CODE, not the launch. Measured on Ubuntu 22.04 under
    # WSLg: pw-play is installed and exits 1 ("no node available"), and
    # notify-send is installed and exits 1 (WSLg ships no notification daemon,
    # so nothing answers on the session bus). Treating either as success is
    # what made the bell below unreachable -- no sound AND no bell, which is
    # the one outcome a timer must never have. shutil.which is still the first
    # gate because it is free; it just is not proof of anything.
    if not shutil.which(cmd[0]):
        return False
    try:
        # a notify-send waiting on a dead bus would otherwise hang this
        # process for the rest of the session
        return subprocess.run(cmd, capture_output=True, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def first_file(paths):
    for p in paths:
        if os.path.exists(p):
            return p
    return None


# A player exiting non-zero on a file that is not there looks exactly like no
# player at all, and both send us to the bell -- so pick a file that exists
# first. sound-theme-freedesktop is not installed on minimal images, which is
# why this is a list and not the one path it used to be.
def play():
    if run(["afplay", "/System/Library/Sounds/Glass.aiff"]):
        return True
    # complete.oga stays first, as it always was: it is a short chime, roughly
    # the length of the Glass.aiff the mac leg plays, and this runs three times.
    # alarm-clock-elapsed.oga is an EIGHT-SECOND looping alarm -- measured -- so
    # it is a last resort, not a nicer-sounding upgrade.
    snd = first_file(["/usr/share/sounds/freedesktop/stereo/complete.oga",
                      "/usr/share/sounds/freedesktop/stereo/bell.oga",
                      "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
    if snd:
        for player in ("paplay", "pw-play"):   # both decode Ogg
            if run([player, snd]):
                return True
    # aplay decodes nothing. Handed a .oga it plays the COMPRESSED BYTES as raw
    # PCM -- measured on alsa-utils 1.2.6: "Playing raw data ... Unsigned 8 bit,
    # Rate 8000 Hz, Mono", exit 0. So an ALSA-only host got three bursts of
    # noise AND a success that suppressed every fallback below. Only ever give
    # it a WAV, and only one that exists.
    wav = first_file(["/usr/share/sounds/alsa/Front_Center.wav",
                      "/usr/share/sounds/sound-icons/prompt.wav"])
    if wav and run(["aplay", "-q", wav]):
        return True
    # WSL with no working Linux audio: Windows has both a player and its own
    # sounds, and interop is the one thing such a box still has.
    return run(["powershell.exe", "-NoProfile", "-NoLogo", "-Command",
                "(New-Object Media.SoundPlayer "
                "'C:\\Windows\\Media\\Alarm01.wav').PlaySync()"])


# ToastText02 built as raw XML: the templated DOM walk raises "Collection was
# modified" under Windows PowerShell 5.1. The AppId is PowerShell's own -- a
# toast from an unregistered AppId is silently dropped.
_TOAST = (
    "[void][Windows.UI.Notifications.ToastNotificationManager,"
    "Windows.UI.Notifications,ContentType=WindowsRuntime];"
    "$d=[Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,"
    "ContentType=WindowsRuntime]::new();"
    "$d.LoadXml('<toast><visual><binding template=\"ToastText02\">"
    "<text id=\"1\">drill</text><text id=\"2\">%s</text>"
    "</binding></visual></toast>');"
    "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("
    "'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0"
    "\\powershell.exe').Show("
    "[Windows.UI.Notifications.ToastNotification]::new($d))"
)


def notify(msg):
    # msg is always "<number> min done", so it needs no XML or PowerShell
    # quoting -- there is nothing in it to escape.
    return (run(["osascript", "-e",
                 'display notification "%s" with title "drill"' % msg])
            or run(["notify-send", "drill", msg])
            or run(["powershell.exe", "-NoProfile", "-NoLogo",
                    "-Command", _TOAST % msg]))


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

notify("%g min done" % mins)

for _ in range(3):
    if not play():
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

# Must match the marker line inside _DRILL_TIMER_PY above.
_DRILL_TIMER_MARKER='drill-timer-proc-9f3c2a1e'

# Every running timer, one PID per line. Written as a here-doc loop rather than
# `for p in $pids` on purpose: zsh does not word-split unquoted expansions the
# way bash does, so that form iterates ONCE with the whole newline-joined blob
# in zsh and per-PID in bash. This behaves the same in both.
#
# Identity is the MARKER, not the tag. The tag is public and short, so anything
# may legitimately carry it -- `python3 train.py --tag drill-timer` is a python
# process whose LAST argument is the tag, which is why neither an executable
# check nor an end-anchor is enough on its own. Both were tried; both accepted
# that process and would have handed its PID to `kill`. The marker lives inside
# the timer's own source, which is argv[2] of the running python, so only a
# real drill timer carries it.
#
# Still intersected with the tag anchored at the end, because the marker alone
# cannot tell YOUR timer from the test suite's -- they run the same script and
# differ only by tag. Two pgrep passes rather than `ps -o args=`: pgrep matches
# the whole command line, while ps truncates, and the timer's argv holds a ~2KB
# script -- the tag would be cut off the end of exactly the string being
# matched. It also means ps is not required at all.
_drill_timer_pids() {
  local p q mine
  mine="$(pgrep -f "$_DRILL_TIMER_MARKER" 2>/dev/null)"
  [ -n "$mine" ] || return 0
  pgrep -f "$DRILL_TIMER_TAG\$" 2>/dev/null | while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r q; do
      [ "$p" = "$q" ] && { printf '%s\n' "$p"; break; }
    done <<EOF
$mine
EOF
  done
}

# Without pgrep every lookup comes back empty, which reads as "no timer is
# running" -- so `t -k` would report success at doing nothing while the
# countdown kept repainting your title. Say the true thing instead.
_drill_timer_have_pgrep() {
  command -v pgrep >/dev/null 2>&1 && return 0
  echo "timer: pgrep not found, so a running timer cannot be found either" >&2
  echo "       (install procps / procps-ng)" >&2
  return 1
}

_drill_timer_stop() {
  local want="$1" pids p found="" killed=0
  _drill_timer_have_pgrep || return 1
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
    -l|--list)      local p; _drill_timer_have_pgrep || return 1
                    p="$(_drill_timer_pids)"
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
