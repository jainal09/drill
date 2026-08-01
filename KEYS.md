# drill keybindings

Editor config: `~/drill/nvimrc.lua` — loaded only via `nvim -u`, never globally.
Syntax highlighting only. No completion, no LSP, no snippets, no AI.

## Normal-editor keys

| Key | Does | Where |
|---|---|---|
| `Ctrl+S` | save now (the file also saves itself) | normal, insert, visual |
| `Ctrl+C` | copy to system clipboard | **selection only** |
| `Ctrl+C` | Esc | insert |
| `Ctrl+X` | cut to system clipboard | selection |
| `Ctrl+V` | paste (replaces the selection if there is one) | normal, insert, selection, command |
| `Ctrl+A` | select all | normal, insert |
| `Ctrl+F` | find (opens `/`); the highlight clears when you type again | normal, insert |
| `Ctrl+/` | comment / uncomment the line or the selected lines | normal, insert, visual, selection |
| `Ctrl+Z` | undo | normal, insert, visual |
| `Ctrl+Y` | redo | normal, insert, visual |
| `Ctrl+Shift+Z` | redo (needs a terminal that speaks CSI-u) | normal, insert, visual |
| `Tab` | indent the selected lines | **selection only** |
| `Shift+Tab` | unindent the selected lines | **selection only** |
| `Ctrl+Q` | visual block (was `Ctrl+V`) | normal, visual |
| `Ctrl+Shift+Q` | **quit, with a confirmation** | normal, insert, **and inside the REPL** |
| **Shift+arrows** | **select, like any other editor** | normal, insert |
| `Delete` / `Backspace` | delete the selection and keep typing | selection |
| Arrows | movement | everywhere |
| **Click** | **put the caret there and keep typing** | everywhere |
| Mouse drag | select | everywhere |
| Mouse wheel | scroll | everywhere |

Shift+arrows, Shift+Home/End and mouse drags all start a selection. Typing over
one replaces it and leaves you in insert, and none of it overwrites your
clipboard with the text it just replaced.

A left click puts the caret exactly where you clicked and leaves you **typing**
there — including from Normal mode, which is one `Ctrl+C` away at all times.

**Anywhere means anywhere**, not just where there is already text. `mouse=a`
alone only lets the caret sit on a real character, so a click on a blank line
snaps to column 1 and a click to the right of a short line snaps to its end —
and a half-written drill file is mostly blank lines and 20-character lines, so
nearly every click lands nowhere near the pointer and the mouse reads as
broken. `virtualedit=all` is what fixes that: click into empty space and the
caret stays where you put it. Type there and the gap fills with spaces, so
clicking out to an indent level on a blank line and writing does what you meant.

**A click that wobbles is still a click.** Your finger drifts a few pixels
between pressing and lifting, a character cell is about 8 pixels wide, and a
mouse drag starts a selection — so nearly every real trackpad click used to
drift across a cell boundary and strand you in Select mode holding a
one-character selection you never asked for. The caret looked right, but the
next letter you typed *replaced* a character instead of inserting one. Now a
mouse selection ending within one cell of where the button went down — in
**both** axes — is treated as the click it was, and the caret goes to the cell
you **pressed** on, not the one you drifted to.

Both axes, because drifting down a *row* was the worse half: the selection then
ran from the press column on one line to the same column on the next, so one
click plus one keystroke merged two lines into one. A click that looked like it
did nothing destroyed a line and a half.

Dragging still selects — two cells or more, or two rows or more, is a real drag
— and double-click still takes the word. The one thing you cannot do any more
is drag-select exactly one character; use shift+arrows or double-click for that.

**Ctrl+click is also just a click.** vim maps it to `CTRL-]`, a tag jump; with
no tags file that raises `E426` and then wedges the editor behind a modal
*"Press ENTER or type command to continue"* prompt — one stray Ctrl and the
mouse looks like it hung the editor. Shift+click is left alone and still
extends a selection, as it does everywhere else.

*The one cost of `virtualedit=all`:* at the end of a line the right arrow now
walks into the empty space past it instead of stopping. Delete the
`vim.opt.virtualedit` line to get the old behaviour back, at the price of the
click snapping again.

**Option+click is the same click.** macOS habit — it is how iTerm2 moves the
cursor at a shell prompt — but vim gives `ALT-LeftMouse` a different job, a
*blockwise* selection, so it used to put the caret in the right place and then
leave you stuck in a one-cell block where the next key was a block operator
instead of a letter. Option is now ignored for the left button: click, drag and
release all behave as if you had not held it. `Ctrl+Q` is still how you ask for
a block on purpose. Shift+click still extends a selection, as it does anywhere
else.

**Auto-save.** You do not have to press `Ctrl+S`. The file writes itself about
0.7s after you stop typing, and again the moment you leave insert, switch away,
or quit. `Ctrl+S` still works and is still instant — it is just no longer
something you have to remember.

Only real files: the interpreter split, the directory listing and any buffer
with no filename are left alone. A burst of typing costs one write, not one per
keystroke (measured: 30 keystrokes, 2 writes).

**The one consequence, and it is a real one:** `:qa!` no longer discards
anything. It used to mean "quit and throw away what I typed"; now what you typed
is already on disk, so a botched drill is saved like any other. If you want a
clean slate, delete the file or `Ctrl+Z` your way back before quitting. To turn
auto-save off, delete the two `nvim_create_autocmd` blocks under
"Auto-save" in `nvimrc.lua` — `Ctrl+S` alone works exactly as it always did.

**Find** (`Ctrl+F`) lights up every match and drops you on the first one, in
Normal mode, so `n` and `N` walk the matches with the highlight still on. The
moment you go back to typing, the highlight clears — `hlsearch` is on by nvim
default and nothing here used to turn it off, so matches stayed lit through the
edit, the next one, and the one after, until you happened to run another search.

`Ctrl+A` selects the file in **Select** mode, so the next thing you type —
a letter, `Delete`, `Backspace` — replaces the lot and leaves you typing.

## Still vim

Everything else is untouched: `hjkl`, `w/b/e`, `dd`, `yy`, `p`, `ciw`, `.`,
macros, marks, `:%s/…`, visual mode, text objects. `u` and `Ctrl+R` still
undo/redo alongside `Ctrl+Z`/`Ctrl+Y`.

## Run and interpret

| Key | Does | Modes |
|---|---|---|
| `Ctrl+E` | **show / hide the interpreter** | normal, insert, **and inside the REPL** |
| `Ctrl+R` | save + run in a split below | normal and insert |
| `F5` / `Space r` | same as `Ctrl+R` | normal only |
| `F6` / `Space i` | same as `Ctrl+E` | normal only |

`Ctrl+E` is the whole loop:

```
type code  ->  Ctrl+E  ->  typing at >>>  ->  Ctrl+E  ->  back in the file, in INSERT
```

You never press `i`, and you never press Esc. Landing in a live interpreter puts
you at the prompt; landing back on the file puts you in insert. `Ctrl+W j` /
`Ctrl+W k` and mouse clicks follow the same rule.

**The interpreter always has the code you can see.** Edited the file since it
started? `Ctrl+E` restarts python with the new code. Didn't touch it? Same
session, so whatever you were poking at in the REPL is still there. There is no
reload key because there is nothing to reload.

`Ctrl+R` and `Ctrl+E` work mid-typing with no Esc first, which is why they're
preferred over `F5`/`F6` — macOS also claims those for dictation and focus.

Costs: `Ctrl+R` was normal-mode redo (use `Ctrl+Y`), `Ctrl+E` was scroll-down.

### Inside the interpreter

| Key | Does |
|---|---|
| `Ctrl+E` | hide it and go back to the code — **python keeps running** |
| `Ctrl+C` | interrupt (deliberately unmapped, so it reaches python) |
| `Ctrl+D` | quit the interpreter |
| `Ctrl+\` `Ctrl+N` | vim-native way out of terminal mode, e.g. to scroll the output |

To scroll back through output, `Ctrl+\` `Ctrl+N` first — otherwise the wheel
goes to python.

## Exiting

**`Ctrl+Shift+Q`** — asks *"Quit drill?"*, then saves everything and goes. Use
this one. `Q` quits, `C` or `Esc` cancels and puts you straight back where you
were typing, and Cancel is the default so a mistyped chord can never be the one
that quits. It works from inside the interpreter too, and says so when python is
still running (it gets killed — that is what you want, and it is why the old
escape hatch was `:qa!` rather than `:wqa`, which *refuses* while a terminal job
is live).

It exists for the same reason `Ctrl+Shift+Z` does: in the legacy encoding Shift
is dropped from a control chord, so `Ctrl+Q` and `Ctrl+Shift+Q` are the same
byte. With CSI-u they are different keys — which is what lets this coexist with
`Ctrl+Q` for visual block. **On a terminal that speaks no CSI-u it will not
fire**; `:qa!` still works there.

| Command | Does |
|---|---|
| `:qa!` | quit everything and kill a running REPL (with auto-save on there is nothing left to discard) |
| `:wqa` | save all + quit — **refuses while `python3 -i` is still running** |
| `Ctrl+D` then `:wqa` | quit the REPL first, then this works cleanly |
| `:q` / `:wq` / `ZZ` | closes **one window** only — leaves the split behind |

`:wq` not quitting is not a bug: with a run split open you have two windows, and
`:wq` closes one. `:qa` is the "a"ll form.

`Ctrl+Z` is undo here, so the old panic-suspend out of nvim is gone by design.

To stop a running timer: **`t -k`**. Starting one prints its id, so `t -k <id>`
works too — and an id that is not a live drill timer is refused rather than
killed, because a finished timer's pid gets recycled onto something else and
`t -k` off old scrollback would otherwise fire at a stranger. `t -l` says
whether one is running. Stopping also clears the countdown out of the window
title, which `pkill` on its own does not.

## Shell

```
d <name>    edit ~/drill/scratch/<name>.py      bare = dir listing
dt <name>   edit ~/drill/templates/<name>.py    bare = dir listing
ds <name>   edit ~/drill/solves/<name>.py       bare = dir listing
r <file>    python3 <file>
ri <file>   python3 -i <file>   (REPL with the file's names live)
t / t10     25- / 10-minute timer, counts down in the window title
t -k [id]   stop it (id optional -- there is only ever one)
t -l        is one running?
```

## Conflicts, and how each is resolved

Every one of these was a real collision, not a hypothetical.

1. **`Ctrl+S` freezing the terminal (XOFF).** `stty -ixon` runs from `drill.sh`,
   which your shell rc sources on every interactive shell. One flag frees both
   `Ctrl+S` (XOFF) and `Ctrl+Q` (XON).
2. **`Ctrl+V` was visual block.** Block moved to `Ctrl+Q`, same as Windows gvim.
   The mapping is `noremap`, so `Ctrl+Q` reaches the *original* `Ctrl+V`.
3. **`Ctrl+Z` was suspend.** Mapped to undo in normal, insert and visual — every
   mode that could reach nvim's suspend. The editor cannot be backgrounded by accident.
4. **`Ctrl+C` must not break SIGINT.** Remapped *only* in selection and insert.
   Normal mode and terminal mode are deliberately left alone, so `Ctrl+C` still
   interrupts a running program.
5. **`Ctrl+X` was the completion trigger.** Completion is off at every source
   (`completeopt`, `complete`, `omnifunc`, `completefunc`, `dictionary` all empty),
   so `Ctrl+X` is free for cut.
6. **On a Mac the big key labelled `delete` sends `<BS>`, not `<Del>`.** `<Del>`
   is fn+delete. Mapping only `<Del>` meant `Ctrl+A` then delete did nothing at
   all — `<BS>` in visual mode just walks the selection back one character. Both
   are mapped now.
7. **`:startinsert` is ignored inside a mapping invoked from insert mode.** Nvim
   restores the mapping's original mode on the way out and clobbers it. Since
   `Ctrl+E` is pressed mid-typing, every auto-insert is deferred past the end of
   the mapping with `vim.schedule`.
8. **`Ctrl+/` has no legacy control byte, so it arrives as one of two different
   keys.** `Ctrl+A` folds to `0x01` and `Ctrl+[` to `0x1B`, but `/` has no such
   pairing — `0x2F & 0x1F` is `0x0F`, which is already `Ctrl+O`. So a terminal
   sends `Ctrl+/` either as `0x1F` (nvim spells that `<C-_>`) or, once the CSI-u
   keyboard protocol is negotiated, as `ESC [ 47 ; 5 u` (`<C-/>`). Nvim treats
   those as **two different keys** — `"\31"` versus `"\128\252\4/"` — so a
   mapping written for one is never reached by the other, and an *unmapped*
   `<C-/>` degrades to a bare `/`, which the printable-key Select map below then
   types over your selection. All three spellings are bound, in four modes each.

9. **`Ctrl+Shift+Z` only exists under CSI-u.** The legacy encoding drops Shift
   from a control chord, so `Ctrl+Shift+Z` and `Ctrl+Z` are both `0x1A` and are
   genuinely indistinguishable. With the protocol negotiated they separate into
   `"\128\252\2\26"` and `"\26"`, so the redo mapping is real. On a terminal
   without it, `Ctrl+Shift+Z` falls back to `Ctrl+Z` and *undoes* — which is why
   `Ctrl+Y` is kept as the redo that works everywhere.

10. **`Tab` indents a selection, but only a selection.** In insert mode `Tab`
    has to go on inserting indentation, and in normal mode it is the jumplist,
    so the mapping is confined to visual and select. The obvious implementation,
    vim's own `:{range}>`, is wrong here: an ex command **drops Select mode**, so
    the first `Tab` works and a second silently shifts only the cursor's line.
    Measured — two tabs on a two-line selection indented one line by 8 and the
    other by 4. It uses the buffer API instead, same rule as `Ctrl+/`: change the
    lines, never the mode. Output is byte-identical to `:>` otherwise.

Two smaller traps, both found the hard way:

- A **literal trailing space is stripped from a mapping's right-hand side**,
  which silently made the space bar delete a selection and type nothing. Space,
  `<` and `|` are spelled `<Space>`, `<lt>`, `<Bar>`.
- Auto-insert is guarded by `jobwait(...) == -1`. Stepping into a *finished*
  run window in terminal mode is a trap: the next key just closes it.

## Cursor

One shape everywhere you type. Nvim's default is a vertical bar in insert
(`i-ci-ve:ver25`) but a **block** in terminal mode, so the caret changed shape
every time `Ctrl+E` moved you between the file and the interpreter. In an editor
whose premise is that you are always typing, that reads as two different states.

Only the shape is changed — the blink and the `TermCursor` highlight are kept,
because they are what tell you python is still live. The `t:` entry is rewritten
rather than appended: appending leaves two `t:` parts and relies on later-wins,
which `:help guicursor` documents only for `a`, not for a repeated mode.

## Colours

`colorscheme habamax`, built in — no plugin. Neovim's *default* scheme paints
keywords, numbers and types all the same near-white (`#e0e2ea`) and only bolds
keywords, which reads as "highlighting is broken". Swap the argument in
`nvimrc.lua` for any of: `wildcharm`, `retrobox`, `sorbet`, `slate`, `desert`.

Regex syntax only: keywords, strings, numbers, builtins and comments get colour.
Plain variable names do not — that needs LSP or treesitter, both excluded here.

## Clipboard

`clipboard=unnamedplus`. Shares one clipboard with the browser in both
directions. Bracketed paste is native, so pasting indented Python does not
staircase.

**Consequence to know:** with `unnamedplus`, *every* `d`, `x`, `c` and `dd` also
overwrites the system clipboard. To delete without touching it, use the
black-hole register: `"_dd`, `"_x`. `Delete`, `Backspace` and typing over a
selection are already black-holed.

**Mouse:** `mouse=a` means clicking and dragging go to vim, not to the terminal.
To use your terminal's own selection, hold **Option** (macOS) or **Shift**
(Linux) while dragging.

**In the directory listing** (bare `d` / `dt` / `ds`) the mouse belongs to netrw,
not to this config: netrw installs its own click handler, so clicking a name
*opens* it rather than moving a caret. That is netrw's behaviour and it is left
alone — a listing is not a file you type in.

If clicks do nothing at all, run **`~/drill/tests/mousecheck.sh`** in the window
you drill in. It turns mouse reporting on by hand and prints the raw bytes your
terminal sends, which says immediately whether the click ever left the terminal
(nothing arrives → inside **tmux** you need `set -g mouse on`, and a few
terminals have reporting off by default) or arrived carrying a modifier you did
not mean to press. An SGR click reads `^[[<0;COL;ROWM`; the number before the
first `;` is the button plus its modifiers, where **4 is Shift, 8 is Option and
16 is Ctrl** — so `^[[<8;…` is an Option+click, not a plain one.

## One trade-off

`selection=exclusive` is what makes shift+arrow selections land where the arrows
imply. The cost is that a manual `v` or `Ctrl+Q` selection now *excludes* the
character under the cursor, so block operations need one more `l` than you may
be used to.
