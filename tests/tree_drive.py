#!/usr/bin/env python3
# ============================================================================
#  tree_drive.py -- the sidebar is a mouse feature, so it is tested with one.
#
#  Ctrl+B / Cmd+B toggle an nvim-tree sidebar (explorer.lua), and everything
#  the feature promises is a gesture: click a file to open it, click a folder
#  to expand it, click [+ File] / [+ Folder] in the winbar toolbar, right-click
#  for a menu, ctrl-click to multi-select, drag a file onto a folder to move
#  it. None of that exists in headless nvim -- no screen grid, no winbar, no
#  mouse -- so this drives the REAL editor on a pty and writes real SGR mouse
#  sequences, exactly like mouse_drive.py.
#
#  Emits "PASS\tname\tgot" / "FAIL\tname\tgot" on stdout for suite_tree.sh.
# ============================================================================
import fcntl
import os
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time

CONFIG = os.environ.get("DRILL_CONFIG")
SOCK = os.environ.get("DRILL_SOCK", "/tmp/drill-tree-test.sock")

results = []


def ok(name, cond, got):
    results.append("%s\t%s\t%s" % ("PASS" if cond else "FAIL", name, got))


def main():
    if not CONFIG or not os.path.isfile(CONFIG):
        sys.stderr.write("tree_drive.py: DRILL_CONFIG not a file: %r\n" % CONFIG)
        return 2

    work = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
    root = os.path.join(work, "tree_%d" % os.getpid())
    os.makedirs(os.path.join(root, "sub"), exist_ok=True)
    for f in ("a.py", "b.py", "d.py", "e.py"):
        with open(os.path.join(root, f), "w") as fh:
            fh.write("print(1)\n")
    with open(os.path.join(root, "sub", "c.py"), "w") as fh:
        fh.write("print(2)\n")

    try:
        os.unlink(SOCK)
    except OSError:
        pass
    pid, fd = os.forkpty()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("NVIM", None)
        # cwd is the fixture: nvim-tree roots the tree at the working directory
        os.chdir(root)
        os.execvp("nvim", ["nvim", "--listen", SOCK, "-i", "NONE", "-u", CONFIG, "a.py"])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    for _ in range(60):
        if os.path.exists(SOCK):
            break
        time.sleep(0.15)
    time.sleep(1.5)

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
        """The short timeout IS an assertion: a gesture that wedges the editor
        behind a modal makes --remote-expr block, and this reports <WEDGED>
        instead of hanging the whole suite."""
        try:
            r = subprocess.run(["nvim", "--server", SOCK, "--remote-expr", expr],
                               capture_output=True, text=True, timeout=t,
                               stdin=subprocess.DEVNULL)
            return (r.stdout or r.stderr).rstrip("\n")
        except subprocess.TimeoutExpired:
            return "<WEDGED>"

    def press(seq, w=0.8):
        os.write(fd, seq.encode())
        time.sleep(w)
        drain()

    # SGR 1006 mouse reports, 1-based col/row. M = press, m = release,
    # button+32 = motion with the button held. Same wire format as
    # mouse_drive.py; modifiers ride the button bits (Ctrl adds 16).
    def click(col, row, button=0, w=0.8):
        press("\x1b[<%d;%d;%dM" % (button, col, row), 0.12)
        press("\x1b[<%d;%d;%dm" % (button, col, row), w)

    def drag(col1, row1, col2, row2, w=0.8):
        press("\x1b[<0;%d;%dM" % (col1, row1), 0.12)
        press("\x1b[<32;%d;%dM" % ((col1 + col2) // 2, (row1 + row2) // 2), 0.12)
        press("\x1b[<32;%d;%dM" % (col2, row2), 0.12)
        press("\x1b[<0;%d;%dm" % (col2, row2), w)

    def tree_win():
        return q('luaeval("(function() for _, w in ipairs(vim.api.nvim_list_wins()) do '
                 'if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == \\"NvimTree\\" '
                 'then return w end end return -1 end)()")')

    def tree_rows():
        w = tree_win()
        if w == "-1":
            return []
        return q('join(getbufline(winbufnr(win_id2win(%s)), 1, "$"), "\\n")' % w).split("\n")

    def row_of(name):
        """Screen row of the tree entry containing `name`: buffer row + 1,
        because the winbar toolbar occupies the window's first screen line."""
        for i, line in enumerate(tree_rows(), start=1):
            if name in line:
                return i + 1
        return -1

    def poll(path, want=True, t=6.0):
        deadline = time.time() + t
        while time.time() < deadline:
            if os.path.exists(path) == want:
                return True
            time.sleep(0.2)
        return os.path.exists(path) == want

    drain()
    try:
        # ---- the toggle ---------------------------------------------------
        ok("starts_typing_in_the_file", q("mode(1)") == "i", q("mode(1)"))

        press("\x02")                                    # Ctrl+B, from insert
        ok("ctrl_b_opens_sidebar", q("winnr('$')") == "2", q("winnr('$')"))
        ok("sidebar_is_nvimtree", tree_win() != "-1", tree_win())
        ok("focus_stays_in_file", q("&filetype") == "python", q("&filetype"))
        ok("still_typing_after_open", q("mode(1)") == "i", q("mode(1)"))

        tw = tree_win()
        ok("tree_virtualedit_off",
           q("getwinvar(win_id2win(%s), '&virtualedit')" % tw) == "none",
           q("getwinvar(win_id2win(%s), '&virtualedit')" % tw))
        ok("file_virtualedit_untouched", q("&virtualedit") == "all", q("&virtualedit"))
        wb = q("getwinvar(win_id2win(%s), '&winbar')" % tw)
        ok("toolbar_in_winbar", "[+ File]" in wb and "[+ Folder]" in wb, wb)

        press("\x1b[98;9u")                              # Cmd+B as CSI-u
        ok("cmd_b_closes_sidebar", q("winnr('$')") == "1", q("winnr('$')"))
        ok("typing_after_close", q("mode(1)") == "i", q("mode(1)"))
        press("\x1b[98;9u")
        ok("cmd_b_reopens_sidebar", q("winnr('$')") == "2", q("winnr('$')"))

        # ---- single click opens / expands ---------------------------------
        r = row_of("b.py")
        ok("tree_lists_fixture", r > 0, "row=%d rows=%r" % (r, tree_rows()))
        click(3, r)
        ok("click_opens_file", q("expand('%:t')") == "b.py", q("expand('%:t')"))
        ok("click_lands_typing", q("mode(1)") == "i", q("mode(1)"))

        r = row_of("sub")
        click(3, r)
        ok("click_expands_folder", row_of("c.py") > 0, "\n".join(tree_rows()))
        click(3, r)                                       # collapse it again
        ok("click_collapses_folder", row_of("c.py") == -1, "\n".join(tree_rows()))

        # ---- the toolbar buttons ------------------------------------------
        # park the tree cursor on a file at the root first -- the buttons
        # create "in here" for a folder row, "next to me" for a file row --
        # then click the button and type only a name
        click(3, row_of("b.py"))
        click(4, 1, w=0.6)                               # [+ File] in the winbar
        press("zz.py\r", 1.0)
        ok("toolbar_new_file_on_disk", poll(os.path.join(root, "zz.py")),
           str(os.path.exists(os.path.join(root, "zz.py"))))

        click(15, 1, w=0.6)                              # [+ Folder]
        press("newdir\r", 1.0)
        ok("toolbar_new_folder_on_disk",
           poll(os.path.join(root, "newdir")),
           str(os.path.isdir(os.path.join(root, "newdir"))))
        ok("no_modal_after_toolbar", q("mode(1)") != "<WEDGED>", q("mode(1)"))
    finally:
        subprocess.run(["nvim", "--server", SOCK, "--remote-send", "<C-\\><C-n>:qa!<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(0.4)
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        shutil.rmtree(root, ignore_errors=True)

    sys.stdout.write("\n".join(results) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
