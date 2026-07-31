#!/usr/bin/env python3
# ============================================================================
#  mouse_drive.py -- the mouse half of the test harness.
#
#  The other suites drive nvim with --headless + feedkeys. That CANNOT test the
#  mouse: --headless attaches no UI, so there is no screen grid, and
#  nvim_input_mouse() on a gridless nvim is silently a no-op. Measured: every
#  click reported cursor=(1,0), unmoved.
#
#  So this one runs the real editor on a real pty and writes the real SGR mouse
#  escape sequences a terminal sends -- ESC [ < btn ; col ; row M for a press,
#  ... m for a release, btn+32 for a drag. nvim's own terminal input parser
#  decodes them, exactly as it does under iTerm2. State is read back over
#  --listen / --remote-expr rather than by scraping the screen.
#
#  Emits one "PASS\tname\tgot" or "FAIL\tname\tgot" line per case, for
#  suite_mouse.sh to count. Prints nothing else on stdout.
#
#  Requires: python3 (already a drill dependency), nvim 0.9+.
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
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-mouse-test.sock")
ROWS, COLS = 24, 80

# 7 lines, 4-space indents, and a deliberately short first line so "click past
# the end of the line" has somewhere to land.
FIXTURE = (
    "def f(n):\n"
    "    total = 0\n"
    "    for i in range(n):\n"
    "        total += i\n"
    "    return total\n"
    "\n"
    "print(f(10))\n"
)

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


class Nvim:
    """The real editor, on a real pty."""

    def __init__(self, path):
        self.path = path
        try:
            os.unlink(SOCK)
        except OSError:
            pass
        self.pid, self.fd = os.forkpty()
        if self.pid == 0:                      # child: become nvim
            os.environ["TERM"] = "xterm-256color"
            os.environ.pop("NVIM", None)       # do not inherit a parent session
            os.execvp("nvim", ["nvim", "--listen", SOCK, "-u", CONFIG, path])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ,
                    struct.pack("HHHH", ROWS, COLS, 0, 0))
        for _ in range(60):                    # wait for the socket to appear
            if os.path.exists(SOCK):
                break
            time.sleep(0.15)
        else:
            raise RuntimeError("nvim never created %s" % SOCK)
        time.sleep(1.2)                        # ...and for the config to settle
        self._drain()

    def _drain(self):
        """Throw away whatever nvim painted. Nothing here reads the screen."""
        while True:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if not r:
                return
            try:
                if not os.read(self.fd, 65536):
                    return
            except OSError:
                return

    def send(self, seq, wait=0.30):
        os.write(self.fd, seq.encode())
        time.sleep(wait)
        self._drain()

    def q(self, expr):
        """Ask the live nvim, over the socket. rstrip('\\n') ONLY -- .strip()
        would eat the leading indentation these cases exist to check."""
        r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                           capture_output=True, text=True)
        return (r.stdout or r.stderr).rstrip("\n")

    # ---- mouse ------------------------------------------------------------
    # SGR (1006) encoding, which is what every modern terminal sends and what
    # nvim negotiates: row/col are 1-based, M is press, m is release, and a
    # drag is the button number + 32.
    def click(self, col, row, button=0):
        self.send("\x1b[<%d;%d;%dM" % (button, col, row), 0.20)
        self.send("\x1b[<%d;%d;%dm" % (button, col, row), 0.40)

    def drag(self, col1, row1, col2, row2):
        self.send("\x1b[<0;%d;%dM" % (col1, row1), 0.20)
        self.send("\x1b[<32;%d;%dM" % (col2, row2), 0.20)
        self.send("\x1b[<0;%d;%dm" % (col2, row2), 0.45)

    def jitter_click(self, col, row, drift=1, button=0):
        """A click as a HAND makes it: press, a motion report a cell or two
        away because the finger drifted, then release. A script clicks
        perfectly still and a hand never does -- which is exactly why this
        failure survived every earlier synthetic test."""
        self.send("\x1b[<%d;%d;%dM" % (button, col, row), 0.20)
        self.send("\x1b[<%d;%d;%dM" % (button + 32, col + drift, row), 0.20)
        self.send("\x1b[<%d;%d;%dm" % (button, col + drift, row), 0.45)

    def double_click(self, col, row):
        """Both clicks in ONE write, no pause. 'mousetime' is 500ms by
        default, and this file's click() deliberately waits longer than that
        between press and release -- two polite clicks are two SINGLE clicks,
        not a double. Sending them back to back is also the honest test: it
        puts the second press right after the release mapping has fired."""
        press, release = "\x1b[<0;%d;%dM" % (col, row), "\x1b[<0;%d;%dm" % (col, row)
        self.send(press + release + press + release, 0.60)

    def normal(self):
        """Back to a known state: Normal mode, top of file."""
        self.send("\x1b", 0.25)
        self.send("gg0", 0.25)

    def undo(self):
        self.send("\x1b", 0.20)
        self.send("u", 0.30)
        self.send("\x1b", 0.20)

    def reset(self):
        """Hard reset to the fixture, then Normal mode at the top.

        Cases must not depend on each other. `u` is not enough: a case that
        ends in SELECT mode can have its next keystroke swallowed as a
        replacement instead of a command, and one such slip silently rewrites
        the line the following case measures. :e! cannot be raced -- it is sent
        over the socket, not typed.

        The file is REWRITTEN first, and that is not belt-and-braces: the
        config autosaves, so by now the previous case's edits are on disk and
        :e! would faithfully reload them. Reloading is only a reset if there is
        something pristine to reload.

        And the autosave has to be allowed to FINISH before the rewrite. It is
        debounced ~700ms, so the previous case still has a write pending; if it
        lands between the rewrite and the :e! it puts the stale buffer straight
        back on disk and :e! dutifully reloads that. Symptom when this was not
        waited out: a different, moving set of cases failed on each run."""
        time.sleep(0.9)                        # outlast the autosave debounce
        with open(self.path, "w") as fh:
            fh.write(FIXTURE)
        subprocess.run(["nvim", "--server", SOCK, "--remote-send",
                        "<C-\\><C-n>:e!<CR>"], capture_output=True)
        time.sleep(0.6)
        self._drain()
        self.normal()

    def close(self):
        subprocess.run(["nvim", "--server", SOCK, "--remote-send",
                        "<C-\\><C-n>:qa!<CR>"], capture_output=True)
        time.sleep(0.5)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("mouse_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2

    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "mouse_%d.py" % os.getpid())
    with open(path, "w") as fh:
        fh.write(FIXTURE)

    v = Nvim(path)
    try:
        # The number column is 4 wide ('number' is on, numberwidth defaults to
        # 4), so screen column 4+N is text column N. Every click below is
        # written as screen coordinates, the way a real terminal reports them.
        GUT = 4

        # ---- the point of the whole feature ------------------------------
        # Normal mode is one <C-c> away at all times. Before <LeftRelease> was
        # bound, the caret moved but the mode did not, and the next letter ran
        # as a command: clicking line 4 and typing "x" DELETED a character.
        v.normal()
        v.click(GUT + 8, 4)                    # "        total += i", col 8
        ok("normal_click_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("normal_click_lands_on_clicked_line", v.q('line(".")') == "4", v.q('line(".")'))
        ok("normal_click_lands_on_clicked_col", v.q('col(".")') == "8", v.q('col(".")'))
        v.send("x", 0.30)
        got = v.q("getline(4)")
        ok("normal_click_then_letter_TYPES", got == "       x total += i", repr(got))
        v.reset()

        # ---- past the end of the line ------------------------------------
        # This is what 'virtualedit' bought and it is the whole complaint: the
        # caret has to stop at the column you POINTED at, not at the last
        # character that happens to exist. col(".") is a BYTE index and cannot
        # express empty space, so it still reads 9 out there -- virtcol(".") is
        # the one that answers the question.
        v.normal()
        v.click(GUT + 40, 1)                   # "def f(n):" is 9 characters
        ok("past_eol_caret_at_clicked_col", v.q('virtcol(".")') == "40", v.q('virtcol(".")'))
        v.send("#", 0.30)
        got = v.q("getline(1)")
        ok("past_eol_types_at_clicked_col",
           got == "def f(n):" + " " * 30 + "#", repr(got))
        v.reset()

        # ---- a blank line, clicked way out to the right ------------------
        # The case that made the mouse look broken: a half-written drill file
        # is mostly blank lines, and every click on one used to snap to column
        # 1, nowhere near the pointer.
        v.normal()
        v.click(GUT + 26, 6)                   # line 6 of the fixture is EMPTY
        ok("blank_line_caret_at_clicked_col", v.q('virtcol(".")') == "26", v.q('virtcol(".")'))
        ok("blank_line_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        v.send("Z", 0.30)
        got = v.q("getline(6)")
        ok("blank_line_types_at_clicked_col", got == " " * 25 + "Z", repr(got))
        v.reset()

        # ---- the empty space under the code ------------------------------
        v.normal()
        v.click(GUT + 30, 18)                  # far below a 7-line file
        ok("below_eof_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("below_eof_lands_on_last_line", v.q('line(".")') == "7", v.q('line(".")'))
        ok("below_eof_caret_at_clicked_col", v.q('virtcol(".")') == "30", v.q('virtcol(".")'))
        v.send("!", 0.30)
        got = v.q("getline(7)")
        ok("below_eof_types_at_clicked_col",
           got == "print(f(10))" + " " * 17 + "!", repr(got))
        v.reset()

        # ---- the gutter is still a click ---------------------------------
        v.normal()
        v.click(2, 2)                          # on the line NUMBER, not the text
        ok("gutter_click_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("gutter_click_lands_on_that_line", v.q('line(".")') == "2", v.q('line(".")'))
        ok("gutter_click_col_1", v.q('col(".")') == "1", v.q('col(".")'))

        # ---- what must NOT have broken -----------------------------------
        # A drag is in SELECT mode by the time the button comes up, so the
        # Normal-mode release mapping is never reached for one. If it ever is,
        # the selection dies and this case fails.
        v.normal()
        v.drag(GUT + 5, 2, GUT + 10, 2)        # over "total" on line 2
        ok("drag_still_selects", v.q("mode(1)") == "s", v.q("mode(1)"))
        v.send("Q", 0.40)
        got = v.q("getline(2)")
        ok("drag_then_typing_replaces", got == "    Q = 0", repr(got))
        v.reset()

        v.normal()
        v.double_click(GUT + 6, 2)             # inside "total" on line 2
        m = v.q("mode(1)")
        ok("double_click_still_selects_word", m in ("s", "v", "S", "V"), m)

        # Insert mode never needed the mapping and must be untouched by it.
        v.reset()
        v.send("i", 0.25)
        v.click(GUT + 6, 3)
        ok("insert_click_stays_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("insert_click_lands_on_clicked_col", v.q('col(".")') == "6", v.q('col(".")'))

        # ---- the jittered click ------------------------------------------
        # THE regression that matters. A trackpad click drifts a few pixels, a
        # cell is ~8px, and selectmode=mouse turns any drift across a cell
        # boundary into a selection -- so the caret was right but you were
        # stranded in Select mode and the next letter REPLACED a character.
        # Fixture line 4 is "        total += i"; screen col 14 == text col 10.
        v.reset()
        v.jitter_click(GUT + 10, 4, drift=1)           # drifted one cell right
        ok("jitter_right_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("jitter_right_caret_at_press_cell", v.q('virtcol(".")') == "10", v.q('virtcol(".")'))
        v.send("Z", 0.35)
        got = v.q("getline(4)")
        ok("jitter_right_TYPES_not_replaces", got == "        tZotal += i", repr(got))
        v.reset()

        v.jitter_click(GUT + 10, 4, drift=-1)          # drifted one cell left
        ok("jitter_left_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("jitter_left_caret_at_press_cell", v.q('virtcol(".")') == "10", v.q('virtcol(".")'))
        v.reset()

        # drifted away and back: ends on the press cell, so the selection is
        # zero-width -- still a click, and it used to strand you just the same.
        v.send("\x1b[<0;%d;4M" % (GUT + 10), 0.20)
        v.send("\x1b[<32;%d;4M" % (GUT + 14), 0.15)
        v.send("\x1b[<32;%d;4M" % (GUT + 10), 0.15)
        v.send("\x1b[<0;%d;4m" % (GUT + 10), 0.45)
        ok("jitter_roundtrip_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("jitter_roundtrip_caret", v.q('virtcol(".")') == "10", v.q('virtcol(".")'))
        v.reset()

        # ...and in empty space, where the whole point is the virtual column
        v.jitter_click(GUT + 36, 6, drift=1)           # line 6 is EMPTY
        ok("jitter_blank_line_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("jitter_blank_line_caret", v.q('virtcol(".")') == "36", v.q('virtcol(".")'))
        v.send("Z", 0.35)
        got = v.q("getline(6)")
        ok("jitter_blank_line_types", got == " " * 35 + "Z", repr(got))
        v.reset()

        # VERTICAL jitter: the pointer drifted down a ROW, not across a column.
        # Worst case of the lot -- the selection runs from the press column on
        # line 4 to the same column on line 5, so it covers the tail of one line
        # and the head of the next, and one keystroke used to merge them:
        # "        total += i" + "    return total" became "        toZ total".
        v.send("\x1b[<0;%d;4M" % (GUT + 10), 0.20)
        v.send("\x1b[<32;%d;5M" % (GUT + 10), 0.20)
        v.send("\x1b[<0;%d;5m" % (GUT + 10), 0.45)
        ok("vjitter_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("vjitter_caret_on_press_line", v.q('line(".")') == "4", v.q('line(".")'))
        ok("vjitter_caret_at_press_cell", v.q('virtcol(".")') == "10", v.q('virtcol(".")'))
        v.send("Z", 0.35)
        ok("vjitter_line4_intact", v.q("getline(4)") == "        tZotal += i",
           repr(v.q("getline(4)")))
        ok("vjitter_line5_intact", v.q("getline(5)") == "    return total",
           repr(v.q("getline(5)")))
        v.reset()

        # A deliberate drag DOWN A ROW but well across must still select.
        v.send("\x1b[<0;%d;4M" % (GUT + 20), 0.20)
        v.send("\x1b[<32;%d;5M" % (GUT + 4), 0.20)
        v.send("\x1b[<0;%d;5m" % (GUT + 4), 0.45)
        ok("real_downward_drag_still_selects", v.q("mode(1)") == "s", v.q("mode(1)"))
        v.reset()

        # ---- Ctrl+click must not wedge the editor ------------------------
        # nvim maps <C-LeftMouse> to CTRL-] (tag jump). No tags file exists here
        # and never will, so it raised E426 and hung the editor behind a modal
        # "Press ENTER or type command to continue" prompt.
        v.click(GUT + 8, 4, button=16)
        ok("ctrl_click_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("ctrl_click_caret", v.q('virtcol(".")') == "8", v.q('virtcol(".")'))
        # if a modal prompt were up, the buffer would not accept a keystroke
        v.send("K", 0.35)
        ok("ctrl_click_not_wedged", v.q("getline(4)") == "       K total += i",
           repr(v.q("getline(4)")))
        v.reset()
        v.jitter_click(GUT + 10, 4, drift=1, button=16)
        ok("ctrl_jitter_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        v.reset()

        # Option held AND jittering -- the two failure modes at once.
        v.jitter_click(GUT + 10, 4, drift=1, button=8)
        ok("alt_jitter_enters_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("alt_jitter_caret", v.q('virtcol(".")') == "10", v.q('virtcol(".")'))
        v.reset()

        # A DELIBERATE drag must survive all of that: two cells is already a
        # real selection, and so is anything crossing a line.
        v.jitter_click(GUT + 5, 2, drift=2)
        ok("two_cell_drag_still_selects", v.q("mode(1)") == "s", v.q("mode(1)"))
        v.reset()
        v.send("\x1b[<0;%d;2M" % (GUT + 5), 0.20)
        v.send("\x1b[<32;%d;4M" % (GUT + 6), 0.20)
        v.send("\x1b[<0;%d;4m" % (GUT + 6), 0.45)
        ok("multiline_drag_still_selects", v.q("mode(1)") == "s", v.q("mode(1)"))
        v.reset()

        # ---- Option+click is just a click --------------------------------
        # Captured off a real iTerm2: the press arrives as ESC[<8;col;row M --
        # button 0 with the Alt bit (8) set. Vim's built-in job for
        # ALT-LeftMouse is a BLOCKWISE selection, which put the caret in the
        # right place and then left you in a one-cell block: mode(1) returned
        # the raw byte 0x13/0x16, not a letter, and the next key you typed was
        # a block operator. These cases are the reason the M- maps exist.
        ALT = 8
        v.reset()
        v.click(GUT + 8, 4, button=ALT)
        m = v.q("mode(1)")
        ok("alt_click_enters_insert", m == "i", repr(m))
        ok("alt_click_not_blockwise", m not in ("\x16", "\x13"), repr(m))
        ok("alt_click_lands_on_clicked_line", v.q('line(".")') == "4", v.q('line(".")'))
        ok("alt_click_lands_on_clicked_col", v.q('col(".")') == "8", v.q('col(".")'))
        v.send("x", 0.30)
        got = v.q("getline(4)")
        ok("alt_click_then_letter_TYPES", got == "       x total += i", repr(got))
        v.reset()

        v.normal()
        v.click(GUT + 40, 1, button=ALT)       # past the end, Option held
        ok("alt_click_past_eol_appends", v.q('col(".")') == "10", v.q('col(".")'))

        # Option+DRAG must select the same charwise run a plain drag does, not
        # a rectangle -- otherwise a click that jiggles silently becomes a block.
        v.normal()
        v.send("\x1b[<%d;%d;%dM" % (ALT, GUT + 5, 2), 0.20)
        v.send("\x1b[<%d;%d;%dM" % (ALT + 32, GUT + 10, 2), 0.20)
        v.send("\x1b[<%d;%d;%dm" % (ALT, GUT + 10, 2), 0.45)
        m = v.q("mode(1)")
        ok("alt_drag_is_charwise_select", m == "s", repr(m))
        v.send("Q", 0.40)
        got = v.q("getline(2)")
        ok("alt_drag_then_typing_replaces", got == "    Q = 0", repr(got))
        v.reset()

        # ---- across the interpreter split --------------------------------
        v.send("\x05", 3.0)                    # <C-e>
        ok("ctrl_e_opens_repl_in_terminal_mode", v.q("mode(1)") == "t", v.q("mode(1)"))
        v.click(GUT + 8, 3)                    # up into the file
        ok("click_file_from_repl_is_insert", v.q("mode(1)") == "i", v.q("mode(1)"))
        ok("click_file_from_repl_is_file_buf", v.q("&buftype") == "", v.q("&buftype"))
        v.click(GUT + 6, 20)                   # back down into the interpreter
        ok("click_repl_from_file_is_terminal", v.q("mode(1)") == "t", v.q("mode(1)"))

        # Reading scrollback: <C-\><C-n> in the REPL puts you in terminal-NORMAL
        # ("nt"). Clicking around in there is you reading python's output, so the
        # mapping must leave it alone -- being yanked back to the prompt is the
        # opposite of what the click asked for. This is why it guards on buftype.
        subprocess.run(["nvim", "--server", SOCK, "--remote-send", "<C-\\><C-n>"],
                       capture_output=True)
        time.sleep(0.5)
        v.click(GUT + 6, 20)
        ok("repl_scrollback_click_stays_normal", v.q("mode(1)") == "nt", v.q("mode(1)"))
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
