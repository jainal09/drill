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
import re
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

    # Everything nvim paints, kept: the right-click menu is a floating window
    # with no API to ask "what does it say", so those cases read the pty
    # stream itself, escape-stripped -- same technique as quit_drive.py.
    painted = []

    def drain():
        while True:
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r:
                return
            try:
                data = os.read(fd, 65536)
                if not data:
                    return
                painted.append(data.decode("utf-8", "replace"))
            except OSError:
                return

    def screen_since_mark():
        raw = "".join(painted)
        txt = re.sub(r"\x1b\[[0-9;:?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[>=]", "", raw)
        return re.sub(r"\s+", " ", txt)

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

        # ---- the right-click menu -----------------------------------------
        def floats():
            return q('len(filter(map(getwininfo(), '
                     '"nvim_win_get_config(v:val.winid).relative"), "v:val != \'\'"))')

        r = row_of("d.py")
        del painted[:]
        click(3, r, button=2, w=1.0)                     # right-click d.py
        ok("right_click_draws_menu", floats() != "0", floats())
        seen = screen_since_mark()
        ok("menu_lists_drill_items",
           "New file" in seen and "Rename" in seen and "Delete" in seen,
           seen[-300:])

        # the float sits at the click: border corner one row below the mouse,
        # text one more in. "Open" is the 4th text line (file, folder,
        # separator, Open).
        click(7, r + 5, w=1.2)
        ok("menu_open_item_opens_file", q("expand('%:t')") == "d.py", q("expand('%:t')"))
        ok("menu_gone_after_item_click", floats() == "0", floats())
        ok("typing_after_menu_open", q("mode(1)") == "i", q("mode(1)"))

        # outside the tree the stock right-click survives: the built-in
        # popup_setpos menu, not drill's -- then Esc dismisses it
        del painted[:]
        click(60, 5, button=2, w=1.0)
        seen = screen_since_mark()
        ok("file_right_click_stays_stock", "New file" not in seen, seen[-200:])
        press("\x1b", 0.5)
        ok("no_wedge_after_stock_menu", q("mode(1)") != "<WEDGED>", q("mode(1)"))

        # ---- ctrl-click multi-select --------------------------------------
        def mark_count():
            return q('luaeval("#require(\\"nvim-tree.api\\").marks.list()")')

        click(3, row_of("b.py"), button=16, w=0.6)       # Ctrl = +16 in SGR
        ok("ctrl_click_marks_one", mark_count() == "1", mark_count())
        click(3, row_of("d.py"), button=16, w=0.6)
        ok("ctrl_click_marks_two", mark_count() == "2", mark_count())

        # ---- drag and drop ------------------------------------------------
        # e.py is NOT marked: dragging it onto sub/ moves it alone, and the
        # marked pair stays marked
        drag(3, row_of("e.py"), 3, row_of("sub"), w=1.5)
        ok("drag_moves_file_into_folder",
           poll(os.path.join(root, "sub", "e.py")) and
           poll(os.path.join(root, "e.py"), want=False),
           "sub/e.py=%s root/e.py=%s" % (os.path.exists(os.path.join(root, "sub", "e.py")),
                                         os.path.exists(os.path.join(root, "e.py"))))
        ok("marks_survive_unmarked_drag", mark_count() == "2", mark_count())

        # b.py IS marked: dragging it takes d.py along
        drag(3, row_of("b.py"), 3, row_of("sub"), w=1.5)
        ok("drag_marked_pair_moves_both",
           poll(os.path.join(root, "sub", "b.py")) and
           poll(os.path.join(root, "sub", "d.py")) and
           poll(os.path.join(root, "b.py"), want=False) and
           poll(os.path.join(root, "d.py"), want=False),
           str(sorted(os.listdir(os.path.join(root, "sub")))))
        ok("marks_clear_after_marked_drag", mark_count() == "0", mark_count())

        # a press that drifts one cell before the button comes up is a CLICK
        # that jittered, not a drag -- same contract as mouse_drive.py
        ra = row_of("a.py")
        press("\x1b[<0;3;%dM" % ra, 0.12)
        press("\x1b[<32;4;%dM" % ra, 0.12)
        press("\x1b[<0;4;%dm" % ra, 1.0)
        ok("jitter_drag_is_a_click", q("expand('%:t')") == "a.py", q("expand('%:t')"))
        ok("jitter_moved_nothing", os.path.exists(os.path.join(root, "a.py")),
           str(os.listdir(root)))

        # ---- three windows: tree + file + interpreter ---------------------
        # <C-e> opens the REPL botright, spanning the full width UNDER the
        # tree -- the IDE layout. The tree must survive it.
        press("\x05", 3.5)
        ok("repl_opens_under_tree", q("winnr('$')") == "3", q("winnr('$')"))
        ok("repl_lands_at_prompt", q("mode(1)") == "t", q("mode(1)"))
        ok("tree_survives_repl", tree_win() != "-1", tree_win())

        # a file opened from the tree must land in the FILE window -- the
        # window_picker excludes terminals -- never in the interpreter
        click(3, row_of("zz.py"), w=1.2)
        ok("tree_open_lands_in_file_window",
           q("expand('%:t')") == "zz.py" and q("&buftype") == "",
           "%s buftype=%r" % (q("expand('%:t')"), q("&buftype")))
        ok("repl_survives_tree_open", q("winnr('$')") == "3", q("winnr('$')"))

        # drill's own keys pressed IN the tree: never a traceback behind a
        # modal, never a stray window -- the netrw contract, kept here too
        click(3, row_of("sub"), w=0.8)                   # focus the tree
        press("\x13", 1.0)                               # Ctrl+S
        ok("ctrl_s_in_tree_no_wedge", q("mode(1)") != "<WEDGED>", q("mode(1)"))
        ok("ctrl_s_in_tree_no_window", q("winnr('$')") == "3", q("winnr('$')"))
        press("\x05", 2.0)                               # Ctrl+E from the tree
        ok("ctrl_e_in_tree_no_wedge", q("mode(1)") != "<WEDGED>", q("mode(1)"))
        ok("ctrl_e_in_tree_no_extra_window", q("winnr('$')") == "3", q("winnr('$')"))

        # Ctrl+B from inside the tree still closes it, and you land typing
        press("\x02", 1.0)
        ok("ctrl_b_in_tree_closes_it", q("winnr('$')") == "2", q("winnr('$')"))
        ok("typing_after_tree_close_with_repl",
           q("mode(1)") in ("i", "t"), q("mode(1)"))

        # ---- the tree roots where your file lives -------------------------
        # `d lld-prac main` runs nvim from wherever the shell was, so rooting
        # at the CWD showed a tree of everything EXCEPT the project. The root
        # must be the folder of the file under the caret, each time it opens.
        def tree_root():
            return q('luaeval("require(\\"nvim-tree.api\\")'
                     '.tree.get_nodes().absolute_path")')

        subprocess.run(["nvim", "--server", SOCK, "--remote-send",
                        "<C-\\><C-n><C-w>k:e sub/c.py<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(1.0)
        press("\x02", 1.2)
        ok("tree_roots_at_files_folder",
           tree_root().endswith("/sub"), tree_root())
        ok("file_listed_under_new_root", row_of("c.py") > 0,
           "\n".join(tree_rows()))

        press("\x02", 0.8)                               # close it again
        subprocess.run(["nvim", "--server", SOCK, "--remote-send",
                        "<C-\\><C-n><C-w>k:e zz.py<CR>"],
                       capture_output=True, stdin=subprocess.DEVNULL)
        time.sleep(1.0)
        press("\x02", 1.2)
        ok("tree_root_follows_reopen",
           tree_root().rstrip("/").endswith(os.path.basename(root)),
           tree_root())
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
