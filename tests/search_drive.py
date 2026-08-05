#!/usr/bin/env python3
# ============================================================================
#  search_drive.py -- the parts of Ctrl+F that headless cannot see.
#
#  suite_search.sh asserts most of the search behaviour headlessly. Three
#  things it cannot, all for the same reason: feedkeys delivers every key in
#  one burst and force-ends Insert as the typeahead drains, so by the time a
#  headless probe looks, the mode is back to Normal and any deferred work has
#  landed. Headless cannot tell "it correctly went back to typing" from "it
#  never left". Those cases live here, on a real pty with real timing:
#
#    * Esc backs out ONE LEVEL AT A TIME -- from a finished search to the
#      prompt, and from the prompt back to where you were typing.
#    * the hint text that is only on screen while the prompt is open.
#    * that the caret stays on the match through all of it.
#
#  Emits "PASS\tname\tgot" / "FAIL\tname\tgot" on stdout.
# ============================================================================
import fcntl
import os
import select
import signal
import struct
import subprocess
import sys
import termios
import time

CONFIG = os.environ.get("DRILL_CONFIG")
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-search-test.sock")
FIXTURE = "seen = 1\nx = 2\nseen = 3\ny = 4\n"

HINT = ("luaeval('(function() for _,w in ipairs(vim.api.nvim_list_wins()) do "
        "local c = vim.api.nvim_win_get_config(w) if c.relative ~= \"\" then "
        "return (vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w),0,-1,false)[1] "
        "or \"\") end end return \"\" end)()')")

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("search_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2
    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "search_%d.py" % os.getpid())
    with open(path, "w") as fh:
        fh.write(FIXTURE)

    try:
        os.unlink(SOCK)
    except OSError:
        pass
    pid, fd = os.forkpty()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("NVIM", None)
        os.execvp("nvim", ["nvim", "--listen", SOCK, "-i", "NONE", "-u", CONFIG, path])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 16, 80, 0, 0))
    for _ in range(60):
        if os.path.exists(SOCK):
            break
        time.sleep(0.15)
    time.sleep(1.6)

    def drain(t=0.25):
        while True:
            r, _, _ = select.select([fd], [], [], t)
            if not r:
                return
            try:
                if not os.read(fd, 65536):
                    return
            except OSError:
                return

    def q(expr, t=5):
        try:
            r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                               capture_output=True, text=True, timeout=t,
                               stdin=subprocess.DEVNULL)
            return (r.stdout or "").strip()
        except subprocess.TimeoutExpired:
            return "<blocked>"

    def send(s, w=0.8):
        os.write(fd, s.encode())
        time.sleep(w)
        drain()

    drain()
    try:
        ok("opens_typing", q("mode(1)") == "i", q("mode(1)"))
        send("\x06", 0.9)                                  # <C-f>
        ok("prompt_hint_names_esc", "back to typing" in q(HINT), repr(q(HINT)))
        send("seen", 0.5)
        send("\r", 1.2)
        ok("search_lands_on_the_match", q('line(".")') == "3", q('line(".")'))
        ok("after_search_you_are_in_normal", q("mode(1)") == "n", q("mode(1)"))
        ok("hint_names_n_N_and_esc",
           "next" in q(HINT) and "previous" in q(HINT) and "back to search" in q(HINT),
           repr(q(HINT)))

        # Esc backs out one level at a time
        send("\x1b", 1.0)
        ok("esc_1_reopens_the_prompt", q("mode(1)") == "c", q("mode(1)"))
        send("\x1b", 1.2)
        ok("esc_2_returns_you_to_typing", q("mode(1)") == "i", q("mode(1)"))
        ok("caret_stayed_on_the_match", q('line(".")') == "3", q('line(".")'))
        ok("highlight_is_off_again", q("v:hlsearch") == "0", q("v:hlsearch"))
        ok("esc_is_unbound_again", q('maparg("<Esc>","n")') == "", q('maparg("<Esc>","n")'))
        send("Z", 0.7)
        ok("and_it_really_types", q('getline(".")') == "Zseen = 3", repr(q('getline(".")')))

        # and a search cancelled outright also puts you back to typing
        send("\x1b", 0.4)
        send("i", 0.5)
        send("\x06", 0.9)
        send("\x1b", 1.2)
        ok("cancelled_search_returns_to_typing", q("mode(1)") == "i", q("mode(1)"))
    finally:
        subprocess.run(["nvim", "--server", SOCK, "--remote-send", "<C-\\><C-n>:qa!<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(0.4)
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass

    sys.stdout.write("\n".join(results) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
