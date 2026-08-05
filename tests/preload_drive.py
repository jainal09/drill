#!/usr/bin/env python3
# ============================================================================
#  preload_drive.py -- Ctrl+R and Ctrl+E go through the preload shim.
#
#  pty-only: both keys open a real :terminal, and what is under test is the
#  text that python printed into it -- headless nvim has no screen for a
#  terminal window to paint on. The claim: a file with NO import line prints
#  a Counter under Ctrl+R, and at the Ctrl+E prompt the file's names and the
#  toolkit's are live in the same expression.
#
#  Emits "PASS\tname\tgot" / "FAIL\tname\tgot" on stdout for suite_preload.sh.
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
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-preload-test.sock")

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
        os.write(self.fd, s.encode())
        time.sleep(w)
        self.drain()

    def q(self, expr):
        r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        return (r.stdout or r.stderr).rstrip("\n")

    def term_text(self):
        """Everything the current (terminal) buffer shows, one string."""
        return self.q("join(getline(1, '$'), ' ')")

    def wait_for(self, needle, tries=20, step=0.5):
        for _ in range(tries):
            text = self.term_text()
            if needle in text:
                return text
            time.sleep(step)
        return self.term_text()

    def close(self):
        subprocess.run(["nvim", "--server", SOCK, "--remote-send",
                        "<C-\\><C-n>:qa!<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(0.4)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("preload_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2
    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "preload_%d.py" % os.getpid())

    # ---- Ctrl+R: a run window whose program never typed an import ---------
    v = Nvim(path, 'print(Counter("aab"))\n')
    try:
        v.send("\x12", 2.5)                                  # <C-r>
        got = v.wait_for("Counter({'a': 2")
        ok("ctrl_r_has_the_toolkit", "Counter({'a': 2" in got, got[-120:])
    finally:
        v.close()

    # ---- Ctrl+E: the file's names and the toolkit share the prompt --------
    v = Nvim(path, "x = 40\n")
    try:
        v.send("\x05", 3.5)                                  # <C-e>
        v.wait_for(">>>")
        v.send("x + len(deque([1, 2]))\r", 2.0)
        got = v.wait_for("42")
        ok("ctrl_e_repl_has_both", "42" in got, got[-120:])
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
