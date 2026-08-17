# The file sidebar

`Ctrl+B` shows it, `Ctrl+B` hides it, and in both directions your caret stays
in your code — the tree is furniture, not a destination. On a Mac whose
terminal forwards Cmd ([docs/macos-cmd.md](macos-cmd.md)), `Cmd+B` does the
same thing and also works from inside the REPL, where `Ctrl+B` is
deliberately left alone (readline's backward-char, and tmux's prefix).

**It roots at the folder of the file you are in**, freshly on every open —
`d lld-prac main` shows the `lld-prac/` folder with `main.py` highlighted,
no matter which directory your shell happened to be in when you typed it.
(drill launches nvim from wherever you were; the shell's directory is a tree
of everything *except* your project.) Switch to a file elsewhere and the next
`Ctrl+B` roots there instead.

## The gestures

Everything is a mouse gesture; the keyboard is only for typing names.

- **Click a file** — opens it, in the file window. Never in the interpreter:
  the open logic refuses terminal windows outright.
- **Click a folder** — folds or unfolds it. One click. There is no
  double-click folklore anywhere in the tree.
- **`[+ File]` / `[+ Folder]`** — real buttons in the tree's top bar. Click,
  type a name at the prompt, Enter. The location is taken from the row your
  cursor is on: a folder row means *in here*, a file row means *next to me*.
- **Right-click** — a menu on the row you clicked: New file, New folder,
  Open, Open in split, Rename, Cut, Copy, Paste, Delete. Plain text labels
  on purpose — no nerd font required, anywhere in the sidebar.
- **Ctrl+click** — select several files (marked with `*`).
- **Drag a file onto a folder** — moves it into that folder. Drop it on a
  file instead and it moves next to that file. If the row you dragged was
  marked, the **whole marked selection moves** in one gesture.

A press that drifts a cell before the button comes up is a click that
jittered, not a drag — the same trackpad rule the rest of drill's mouse
handling lives by, so nothing ever moves by accident.

Inside the tree, drill's file keys say no the same way they do in the
directory listing: `Ctrl+S`, `Ctrl+E`, `Ctrl+R` do nothing there.

## What it costs when you don't use it

Nothing. This is drill's one exception to "no plugins", and it is built to
stay an exception:

- The three checkouts (nvim-tree, and volt+menu for the right-click menu)
  are **pinned to exact commits** by `vendor.sh` — a table of three SHAs and
  a loop, not a plugin manager. The same commits on every machine, every
  install, until a pin is bumped on purpose.
- **Nothing loads at startup.** The checkouts are not even on the runtime
  path until the first `Ctrl+B` of the session. Never press it and you run
  the config drill always had, byte for byte.
- The same change **sealed the accidental plugin door**: plugins in your
  `~/.local/share/nvim/site` used to load inside drill through `packpath`
  even though the README said "no plugins". They no longer do. Your own
  nvim setup outside drill is untouched either way.

## When it says no

- *"sidebar plugins are not fetched"* — run `./vendor.sh` in your drill
  directory (`~/drill` unless you moved it). `install.sh` does this for you;
  a `git pull` upgrade does not.
- *"the sidebar needs nvim 0.10+"* — everything else in drill still works;
  the pinned plugins are what need 0.10.
- `Cmd+B` does nothing — your terminal is not forwarding Cmd. One setting:
  [docs/macos-cmd.md](macos-cmd.md).
- **Right-click opens your terminal's own menu instead of drill's** — the
  terminal is eating the click before nvim sees it. In iTerm2 that is a
  Pointer binding, and it wins over mouse reporting: **Settings → Pointer →
  Bindings**, select the *Right button · single click → Open Context Menu*
  row, press **−** to remove it. With the binding gone, the click reaches
  drill whenever the editor is running, and iTerm2 still shows its own menu
  at the shell prompt, where nothing is listening for the mouse. (Ctrl-click
  in drill is multi-select, not the menu — that one is drill's on purpose.)
