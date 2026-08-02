#!/usr/bin/env python3
# ============================================================================
#  runwin_drive.py -- the lifecycle of the <C-r> output window.
#
#  pty-only: every case is about window counts and terminal-job state, and
#  headless nvim has neither a screen to split nor a job whose liveness means
#  anything to a user.
#
#  The rule under test: a FINISHED run window closes itself the moment you
#  leave it, and a still-running one does not. Before that rule existed you
#  could only dismiss the window from inside it -- go back to the file first
#  and it sat there for good, with <C-e> stacking a third window under it.
#
#  Emits "PASS\tname\tgot" / "FAIL\tname\tgot" on stdout for suite_runwin.sh.
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
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-runwin-test.sock")

FAST = "print('hello')\n"                       # exits immediately
SLOW = "name = input('who? ')\nprint('hi', name)\n"   # sits at a prompt

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


class Nvim:
    def __init__(self, path, body):
        with open(path, "w") as fh:
            fh.write(body)
        try:
            os.unlink(SOCK)
        except OSError:
            pass
        self.pid, self.fd = os.forkpty()
        if self.pid == 0:
            os.environ["TERM"] = "xterm-256color"
            os.environ.pop("NVIM", None)
            os.execvp("nvim", ["nvim", "--listen", SOCK, "-i", "NONE",
                               "-u", CONFIG, path])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        for _ in range(60):
            if os.path.exists(SOCK):
                break
            time.sleep(0.15)
        else:
            raise RuntimeError("nvim never created %s" % SOCK)
        time.sleep(1.5)
        self.drain()

    def drain(self):
        while True:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if not r:
                return
            try:
                if not os.read(self.fd, 65536):
                    return
            except OSError:
                return

    def send(self, s, w=0.6):
        """Typed at the real tty. <C-r> has to arrive as a keystroke, not over
        the socket: the whole point is where the CURSOR ends up afterwards."""
        os.write(self.fd, s.encode())
        time.sleep(w)
        self.drain()

    def q(self, expr):
        r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        return (r.stdout or r.stderr).rstrip("\n")

    def rs(self, keys):
        subprocess.run(["nvim", "--server", SOCK, "--remote-send", keys],
                       capture_output=True, stdin=subprocess.DEVNULL)

    def close(self):
        self.rs("<C-\\><C-n>:qa!<CR>")
        time.sleep(0.4)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("runwin_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2
    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "runwin_%d.py" % os.getpid())

    # ---- a program that has finished -------------------------------------
    v = Nvim(path, FAST)
    try:
        v.send("\x12", 2.5)                                  # <C-r>
        ok("run_opens_one_split", v.q("winnr('$')") == "2", v.q("winnr('$')"))
        ok("run_lands_you_in_it", v.q("&buftype") == "terminal", v.q("&buftype"))
        ok("run_job_has_finished", v.q("jobwait([b:terminal_job_id], 0)[0]") == "-3",
           v.q("jobwait([b:terminal_job_id], 0)[0]"))

        # THE case: go back to the file first. This used to leave the window
        # open with no key in the config able to dismiss it.
        v.rs("<C-\\><C-n><C-w>k")
        time.sleep(1.0)
        ok("leaving_closes_it", v.q("winnr('$')") == "1", v.q("winnr('$')"))
        ok("leaves_you_in_the_file", v.q("&buftype") == "", repr(v.q("&buftype")))
        ok("leaves_you_typing", v.q("mode(1)") == "i", v.q("mode(1)"))

        # ...and the old way still works: any key while you are standing in it
        v.send("\x12", 2.5)
        ok("second_run_opens_again", v.q("winnr('$')") == "2", v.q("winnr('$')"))
        v.send("j", 1.0)
        ok("key_in_the_pane_still_closes", v.q("winnr('$')") == "1", v.q("winnr('$')"))

        # <C-r> then <C-e> used to leave three windows, the file squeezed
        v.send("\x12", 2.5)
        v.send("\x05", 3.5)
        ok("run_then_repl_is_two_windows", v.q("winnr('$')") == "2", v.q("winnr('$')"))
        ok("run_then_repl_lands_in_repl", v.q("&buftype") == "terminal", v.q("&buftype"))
    finally:
        v.close()

    # ---- a program that is still running ---------------------------------
    # <C-r> on a script that calls input() puts you at its prompt. Closing that
    # on the way past would kill a program you are talking to.
    v = Nvim(path, SLOW)
    try:
        v.send("\x12", 2.5)
        ok("input_script_still_alive", v.q("jobwait([b:terminal_job_id], 0)[0]") == "-1",
           v.q("jobwait([b:terminal_job_id], 0)[0]"))
        v.rs("<C-\\><C-n><C-w>k")
        time.sleep(1.0)
        ok("running_pane_is_left_alone", v.q("winnr('$')") == "2", v.q("winnr('$')"))
    finally:
        v.close()
        try:
            os.unlink(path)
        except OSError:
            pass

    sys.stdout.write("\n".join(results) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
