#!/usr/bin/env python3
# ============================================================================
#  quit_drive.py -- Ctrl+Shift+Q and its confirmation.
#
#  Needs a pty for two separate reasons, either one sufficient:
#    * <C-S-q> only exists at all under the CSI-u keyboard protocol. In the
#      legacy encoding Shift is dropped from a control chord, so Ctrl+Q and
#      Ctrl+Shift+Q are both 0x11. The key has to arrive as the real escape
#      sequence ESC[113;6u, which means a real terminal.
#    * the confirmation is a blocking prompt. Headless feedkeys cannot answer
#      one, and it is drawn on the screen rather than exposed to any API.
#
#  Emits one "PASS\tname\tgot" or "FAIL\tname\tgot" line per case on stdout,
#  for suite_quit.sh to count.
# ============================================================================
import fcntl
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

CONFIG = os.environ.get("DRILL_CONFIG")
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-quit-test.sock")
FIXTURE = "x = 1\ny = 2\nz = 3\n"

# CSI-u: ESC [ <codepoint> ; <mods> u    mods = 1 + shift(1) + ctrl(4) = 6
CSQ = "\x1b[113;6u"

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


class Nvim:
    def __init__(self, path):
        self.path = path
        self.buf = []
        with open(path, "w") as fh:
            fh.write(FIXTURE)
        try:
            os.unlink(SOCK)
        except OSError:
            pass
        self.pid, self.fd = os.forkpty()
        if self.pid == 0:
            os.environ["TERM"] = "xterm-256color"
            os.environ.pop("NVIM", None)
            # -i NONE: no shada, so the / register and marks cannot leak between runs
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

    def drain(self, t=0.2):
        while True:
            r, _, _ = select.select([self.fd], [], [], t)
            if not r:
                return
            try:
                b = os.read(self.fd, 65536)
                if not b:
                    return
                self.buf.append(b.decode("latin-1"))
            except OSError:
                return

    def screen(self):
        """Everything painted so far, escape sequences stripped. The prompt is
        only ever drawn -- there is no API that exposes it."""
        raw = "".join(self.buf)
        raw = re.sub(r"\x1b\[[0-9;:?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[>=]", "", raw)
        return " ".join(raw.split())

    def send(self, s, w=0.5):
        os.write(self.fd, s.encode())
        time.sleep(w)
        self.drain()

    def q(self, expr):
        r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                           capture_output=True, text=True)
        return (r.stdout or r.stderr).rstrip("\n")

    def alive(self):
        """Can we still talk to the editor? os.kill(pid,0) SUCCEEDS on a
        zombie, so an exited-but-unreaped nvim reads as alive -- that produced
        two false failures before this was written. The socket is refused the
        moment nvim is actually gone."""
        try:
            os.waitpid(self.pid, os.WNOHANG)
        except (ChildProcessError, OSError):
            pass
        r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", "1"],
                           capture_output=True, text=True)
        return r.stdout.strip() == "1"

    def kill(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("quit_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2

    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "quit_%d.py" % os.getpid())

    # ---- the prompt, and cancelling it -----------------------------------
    v = Nvim(path)
    try:
        ok("starts_in_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        v.send(CSQ, 0.8)
        s = v.screen()
        ok("prompt_is_shown", "Quit drill?" in s, s[-70:])
        ok("prompt_offers_both_choices", "uit" in s[-120:] and "ancel" in s[-120:], s[-70:])
        # the chord must not leak a character into the file
        ok("chord_types_nothing", v.q("getline(1)") == "x = 1", repr(v.q("getline(1)")))
        ok("waits_for_an_answer", v.alive(), "editor gone before answering")

        v.send("c", 0.9)
        ok("cancel_keeps_editor_alive", v.alive(), "editor quit on Cancel")
        ok("cancel_returns_to_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        v.send("W", 0.5)
        ok("cancel_leaves_you_typing", v.q("getline(1)") == "Wx = 1",
           repr(v.q("getline(1)")))

        # Esc is the other way out, and must not be the way OUT out
        v.send(CSQ, 0.7)
        v.send("\x1b", 0.9)
        ok("esc_also_cancels", v.alive(), "Esc quit the editor")
        ok("esc_returns_to_insert", v.q("mode(1)") == "i", v.q("mode(1)"))

        # ---- the dialog must not be drawn over ---------------------------
        # The search hint is a float, and the first version of it sat on the
        # last text row -- exactly where nvim expands the message area for a
        # multi-line prompt. The quit dialog came out mangled: the hint drawn
        # truncated across it, and a stale line repainted over the choices.
        v.send("\x1b", 0.3)
        v.send("/", 0.6)
        v.send("x", 0.4)
        v.send("\r", 0.9)                        # a real search, hint now up
        v.buf.clear()
        v.send(CSQ, 1.3)
        s = v.screen()
        ok("dialog_draws_its_question", "Quit drill?" in s, s[-80:])
        ok("dialog_draws_the_choices", "(Q)uit" in s and "[C]ancel" in s, s[-80:])
        ok("nothing_drawn_over_the_dialog",
           "previous" not in s and "press Enter" not in s, s[-80:])
        v.send("c", 0.9)
        ok("still_alive_after_that_cancel", v.alive(), "editor quit")

        # ---- and quitting for real ---------------------------------------
        # Type, then answer INSIDE the autosave debounce window, so the only
        # thing that can get these bytes to disk is the :wall on the way out.
        v.send("UNSAVED", 0.2)
        v.send(CSQ, 0.7)
        v.send("q", 1.5)
        ok("quit_exits", not v.alive(), "editor still answering")
        on_disk = open(path).read().splitlines()[0]
        ok("quit_writes_pending_edit", on_disk == "WUNSAVEDx = 1", repr(on_disk))
    finally:
        v.kill()

    # ---- from inside the interpreter -------------------------------------
    v = Nvim(path)
    try:
        v.send("\x05", 3.0)                       # <C-e>
        ok("repl_is_open", v.q("mode(1)") == "t", v.q("mode(1)"))
        v.buf.clear()
        v.send(CSQ, 0.9)
        s = v.screen()
        ok("prompt_reaches_terminal_mode", "Quit drill?" in s, s[-70:])
        ok("prompt_warns_python_dies", "python is still running" in s, s[-90:])
        v.send("c", 0.9)
        ok("cancel_from_repl_keeps_alive", v.alive(), "quit from the REPL on Cancel")
        v.send(CSQ, 0.7)
        v.send("q", 1.8)
        ok("quit_from_repl_exits", not v.alive(), "editor still answering")
    finally:
        v.kill()
        try:
            os.unlink(path)
        except OSError:
            pass

    sys.stdout.write("\n".join(results) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
