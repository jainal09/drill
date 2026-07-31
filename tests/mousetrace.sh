#!/bin/bash
# ============================================================================
#  mousetrace.sh -- record what nvim ACTUALLY receives when you click.
#
#  mousecheck.sh answers "does the terminal send mouse events at all". This
#  answers the next question: of the events it sends, what reaches nvim, how
#  does nvim decode them, and where does the caret end up.
#
#  It opens a throwaway file with the real drill config plus a logging overlay
#  that records EVERY key nvim sees (via vim.on_key, which does not change any
#  behaviour). Click around, quit, and it prints the log.
#
#  Nothing you own is touched: it works on a copy in a temp directory.
#
#    ./mousetrace.sh                 trace on a throwaway file
#    ./mousetrace.sh ~/drill/scratch/bfs.py   trace on a COPY of that file
# ============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${DRILL_CONFIG:-$(cd "$DIR/.." && pwd)/nvimrc.lua}"

[ -f "$CONFIG" ] || { echo "mousetrace.sh: no config at $CONFIG" >&2; exit 2; }
command -v nvim >/dev/null || { echo "mousetrace.sh: nvim not on PATH" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/drill-trace.XXXXXX")"
LOG="$WORK/trace.log"
FILE="$WORK/trace_me.py"
OVERLAY="$WORK/overlay.lua"

if [ -n "${1:-}" ] && [ -f "$1" ]; then
  cp "$1" "$FILE"                      # a COPY. your file is never opened.
else
  cat > "$FILE" <<'PY'
# Click around in this file, then quit and paste what it prints.
#
#   1. click on this line, near the end of it
#   2. click on the blank line below

#   3. click far out to the RIGHT of this short line
#   4. click wherever it normally feels broken
#
# to quit:  Ctrl+C  then  :q!  then Enter
def f(n):
    total = 0
    for i in range(n):
        total += i
    return total
PY
fi

cat > "$OVERLAY" <<'LUA'
-- Logging only. vim.on_key is a passive observer: it cannot change what any
-- key does, so the editor under trace behaves exactly as it normally would.
local path = vim.env.DRILL_TRACE_LOG
local fh = io.open(path, "a")
if not fh then return end
local function w(s) fh:write(s .. "\n"); fh:flush() end

local v = vim.version()
w("================ drill mouse trace ================")
w(string.format("nvim         : %d.%d.%d", v.major, v.minor, v.patch))
w("config       : " .. tostring(vim.env.MYVIMRC))
w("TERM         : " .. tostring(vim.env.TERM))
w("TERM_PROGRAM : " .. tostring(vim.env.TERM_PROGRAM) ..
  "  " .. tostring(vim.env.TERM_PROGRAM_VERSION))
w("screen       : " .. vim.o.columns .. " cols x " .. vim.o.lines .. " lines")
w("mouse        : " .. vim.inspect(vim.o.mouse))
w("virtualedit  : " .. vim.inspect(vim.o.virtualedit))
w("selectmode   : " .. vim.inspect(vim.o.selectmode))
w("mousemodel   : " .. vim.inspect(vim.o.mousemodel))
w("<LeftRelease> n : " .. vim.inspect(vim.fn.maparg("<LeftRelease>", "n")))
w("<M-LeftMouse> n : " .. vim.inspect(vim.fn.maparg("<M-LeftMouse>", "n")))
w("")
w("every key nvim receives, in order:")
w("---------------------------------------------------------------")

local n = 0
vim.on_key(function(key, typed)
  local raw = (typed ~= nil and typed ~= "") and typed or key
  if raw == nil or raw == "" then return end
  local okk, name = pcall(vim.fn.keytrans, raw)
  if not okk or name == nil then name = string.format("<raw %q>", raw) end
  n = n + 1
  local idx, lower = n, name:lower()
  local mouseish = lower:find("mouse") or lower:find("drag")
                or lower:find("release") or lower:find("scroll")
  -- read the RESULT after nvim has finished acting on the key
  vim.schedule(function()
    local line = string.format("%4d  %-20s mode=%-4s cursor=(%d,%d) virtcol=%d",
      idx, name, vim.fn.mode(1), vim.fn.line("."), vim.fn.col("."), vim.fn.virtcol("."))
    if mouseish then
      local okp, p = pcall(vim.fn.getmousepos)
      if okp and type(p) == "table" then
        line = line .. string.format("  << MOUSE  clicked line=%s col=%s coladd=%s screen=(%s,%s) winid=%s",
          tostring(p.line), tostring(p.column), tostring(p.coladd),
          tostring(p.screenrow), tostring(p.screencol), tostring(p.winid))
      end
    end
    w(line)
  end)
end)

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function() w("---------------------------------------------------------------")
                        w("total keys seen: " .. n) end,
})
LUA

export DRILL_TRACE_LOG="$LOG"
: > "$LOG"

cat <<EOF

  Opening the drill editor with a trace attached.

    - click around: on text, on a blank line, far right of a short line
    - click wherever it normally feels broken
    - then press  Ctrl+C  and type  :q!  and Enter

EOF
printf '  press Enter to start... '
read -r _

nvim -u "$CONFIG" -c "luafile $OVERLAY" "$FILE"

echo
echo "=============== PASTE EVERYTHING BELOW THIS LINE ==============="
cat "$LOG"
echo "=============== PASTE EVERYTHING ABOVE THIS LINE ==============="
echo
echo "(log kept at $LOG)"
