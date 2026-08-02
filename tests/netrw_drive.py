#!/usr/bin/env python3
# ============================================================================
#  netrw_drive.py -- the directory listing must not be mistaken for a file.
#
#  `d` / `dt` / `ds` with no argument opens netrw. The trap that makes this
#  worth its own suite: **netrw's buftype is EMPTY**. Measured in a real
#  terminal -- buftype '', modifiable 0, filetype 'netrw', expand("%:p") '' --
#  so every guard written as `buftype ~= ""` sails straight through it. Two
#  bugs came from exactly that:
#
#    Ctrl+S  raised a Lua traceback and left the editor behind a modal
#            "Press ENTER or type command to continue".
#    Ctrl+E  opened a split running `python3 -i ''`, because expand("%:p") is
#            "" there and "" is TRUTHY in Lua, so `if not f then return end`
#            at the call site never fired.
#
#  PTY, NOT HEADLESS, and that is the whole point of this file. Headless nvim
#  opened on a directory does not produce a netrw buffer at all: measured,
#  filetype "", modifiable true, and expand("%:p") returning the real directory
#  path. Every guard therefore behaves differently and the suite reports a
#  reality that no user is ever in. The first version of this suite was
#  headless and "failed" four cases for that reason alone.
#
#  Emits "PASS\tname\tgot" / "FAIL\tname\tgot" on stdout for suite_netrw.sh.
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
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-netrw-test.sock")

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("netrw_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2

    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    listing = os.path.join(work, "netrw_%d" % os.getpid())
    os.makedirs(listing, exist_ok=True)
    with open(os.path.join(listing, "a.py"), "w") as fh:
        fh.write("print(1)\n")

    try:
        os.unlink(SOCK)
    except OSError:
        pass
    pid, fd = os.forkpty()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("NVIM", None)
        os.execvp("nvim", ["nvim", "--listen", SOCK, "-i", "NONE", "-u", CONFIG, listing])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    for _ in range(60):
        if os.path.exists(SOCK):
            break
        time.sleep(0.15)
    time.sleep(1.8)

    def drain():
        while True:
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r:
                return
            try:
                if not os.read(fd, 65536):
                    return
            except OSError:
                return

    def q(expr, t=4):
        """A short timeout IS an assertion here: if a key ever wedges the
        editor behind a modal again, --remote-expr blocks and this reports it
        rather than hanging the suite."""
        try:
            r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                               capture_output=True, text=True, timeout=t,
                               stdin=subprocess.DEVNULL)
            return (r.stdout or r.stderr).rstrip("\n")
        except subprocess.TimeoutExpired:
            return "<WEDGED>"

    def press(seq, w=1.2):
        os.write(fd, seq.encode())
        time.sleep(w)
        drain()

    drain()
    try:
        # the invariant every one of these bugs came from
        ok("listing_buftype_is_empty", q("&buftype") == "", repr(q("&buftype")))
        ok("listing_filetype_is_netrw", q("&filetype") == "netrw", q("&filetype"))
        ok("listing_is_unmodifiable", q("&modifiable") == "0", q("&modifiable"))
        ok("listing_has_no_filename", q("expand('%:p')") == "", repr(q("expand('%:p')")))

        # Ctrl+S: a no-op, not a traceback behind a modal
        press("\x13")
        ok("ctrl_s_does_not_wedge", q("winnr('$')") == "1", q("winnr('$')"))
        ok("ctrl_s_opens_no_window", q("winnr('$')") == "1", q("winnr('$')"))

        # Ctrl+E / Ctrl+R: there is nothing to run, so nothing should start
        press("\x05", 2.5)
        ok("ctrl_e_starts_no_interpreter", q("winnr('$')") == "1", q("winnr('$')"))
        press("\x12", 2.5)
        ok("ctrl_r_starts_no_process", q("winnr('$')") == "1", q("winnr('$')"))
        ok("still_in_the_listing", q("&filetype") == "netrw", q("&filetype"))

        n = q("len(filter(map(range(1, bufnr('$')), "
              "'getbufvar(v:val + 1, \"&buftype\")'), 'v:val ==# \"terminal\"'))")
        ok("no_terminal_buffer_spawned", n == "0", n)
    finally:
        subprocess.run(["nvim", "--server", SOCK, "--remote-send", "<C-\\><C-n>:qa!<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(0.4)
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.unlink(os.path.join(listing, "a.py"))
            os.rmdir(listing)
        except OSError:
            pass

    sys.stdout.write("\n".join(results) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
