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
| `Shift+Tab` | unindent the selected lines — or, in insert, the line you are on | selection, insert |
| `Ctrl+Q` | visual block (was `Ctrl+V`) | normal, visual |
| `Ctrl+Shift+Q` | **quit, with a confirmation** | normal, insert, **and inside the REPL** — except on a terminal with no CSI-u, where **normal mode is not covered**; see below |
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

**Backspace out of the empty space walks you home.** A click past the end of a
line parks the caret where there are no characters under it, and vim's own
backspace out there inched back one ghost column per press with the text
untouched — thirty presses of nothing visible before the first real character
would go, which read as "backspace does not move the cursor back". Now one
press snaps the caret to the end of the real text, and the next one deletes
for real. On a blank line it snaps to column 1 first, then joins upward.
Backspace anywhere else — mid-word, after typing into the padded gap, at a
line start — is vim's own, untouched.

**Option+click is the same click.** (Alt+click on Linux and WSL — same key, same
handling; the explanation below is macOS because that is the habit it
accommodates.) macOS habit — it is how iTerm2 moves the
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
Normal mode, so **`n`** walks forward and **`N`** walks back, with the highlight
still on. The right-hand end of the status line says so while it is true:
*press Enter to search   Esc back to typing* while you are typing the pattern
(in the directory listing, where Esc has nowhere to type, just the first
half), then
*n next   N previous   Esc back to search* once it has run — right above the
prompt, where you are already looking. It borrows the end of the ruler for as
long as it is up.

**`Esc` backs out one level at a time.** From a finished search it reopens the
prompt, prefilled with the term you just used, so refining it is one key rather
than retyping it. From the prompt it drops the search and puts you back exactly
where you were typing — caret still on the match, highlight gone. So `Ctrl+F`
is a round trip you can always get out of without touching `i` or the command
line.

Like the hint, that mapping exists only while there is a search to go back to:
at rest `Esc` is plain vim's `Esc`, and it has to stay that way — a permanent
mapping would swallow the `Esc` that cancels a pending count or operator. Both disappear the moment you go back to typing — the same keystroke that
clears the highlight — because by then `n` and `N` are just letters again. A
search you cancel, or one that matches nothing, gets no hint rather than a
wrong one. The
moment you go back to typing, the highlight clears — `hlsearch` is on by nvim
default and nothing here used to turn it off, so matches stayed lit through the
edit, the next one, and the one after, until you happened to run another search.

`Ctrl+A` selects the file in **Select** mode, so the next thing you type —
a letter, `Delete`, `Backspace` — replaces the lot and leaves you typing.

## macOS: the same keys on Cmd

Every chord above lives on Ctrl because a program running in a terminal never
sees the Cmd key — the terminal emulator owns it (Cmd+C *is* the terminal's
Copy, Cmd+Q quits the terminal), which is why every terminal editor is a Ctrl
editor on a Mac. Two habits work regardless, with zero setup: **Cmd+V already
pastes** — the terminal pastes, bracketed, into the file and the REPL alike —
and **Shift+drag then Cmd+C** copies through the terminal's own selection.

A terminal that *forwards* Cmd chords gets the whole set on Cmd too — iTerm2
3.5+ is one setting (scoped so your shell prompt keeps normal Cmd), kitty and
Ghostty unmap theirs per chord, Terminal.app cannot do it at all. Forwarded,
you get `Cmd+S/C/X/V/A/F/Z//` plus **`Cmd+Shift+Z`** for redo, **`Cmd+Q`**
for the quit prompt, **`Cmd+arrows`** for line/file ends (shifted: selecting)
and **`Cmd+Backspace`** to delete to the line start — with two deliberate
mac-isms: insert-mode `Cmd+C` copies the *line* rather than acting as Esc
(that job stays on `Ctrl+C`), and `Cmd+V` also pastes inside the REPL, where
`Ctrl+V` is left to python. Every *other* Cmd chord is deliberately
swallowed: unmapped, a forwarded `Cmd+W` would type the literal text `<D-w>`
into your file (measured). Setup recipes:
[docs/macos-cmd.md](docs/macos-cmd.md), and `tests/keycheck.sh` prints what
your terminal actually sends when you press one.

## Still vim

Everything else is untouched: `hjkl`, `w/b/e`, `dd`, `yy`, `p`, `ciw`, `.`,
macros, marks, `:%s/…`, visual mode, text objects. `u` still undoes.

**`Ctrl+R` does not redo here** — it saves and runs the file, in normal *and*
insert mode, so `i_CTRL-R` (`Ctrl+R "` to paste a register) is gone too. Redo is
`Ctrl+Y`, or `Ctrl+Shift+Z` on a terminal that speaks CSI-u.

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
`Ctrl+W k` and mouse clicks follow the same rule — *leaving the file*. They do
not work leaving the **interpreter**: only `Ctrl+E` and `Ctrl+Shift+Q` — plus
`Cmd+V` and `Cmd+Q` where the terminal forwards Cmd (see
[docs/macos-cmd.md](docs/macos-cmd.md)) — do anything in terminal mode, and
every other forwarded Cmd chord is floored to `<Nop>` so a stray one cannot
spray notation at python. `Ctrl+W` is untouched and still reaches python as a
word-erase, so you stay put. Out of the REPL it is `Ctrl+E`, `Ctrl+\`
`Ctrl+N`, or a click.

**The interpreter always has the code you can see.** Edited the file since it
started? `Ctrl+E` restarts python with the new code. Didn't touch it? Same
session, so whatever you were poking at in the REPL is still there. There is no
reload key because there is nothing to reload.

**The toolkit is already imported.** Every run — `Ctrl+R`, `Ctrl+E`, `r`, `ri`
— goes through `preload.py`, so `Counter`, `deque`, `defaultdict`, `heappush`,
`permutations`, `lru_cache`, `bisect_left`, `inf` and friends are live with no
import line in the file, the way the LeetCode judge has them. Your own names
win over the toolkit's, a traceback still points at your line, and `sys.argv`
and `__name__ == "__main__"` behave exactly as plain `python3`. Delete
`~/drill/preload.py` and every run is plain `python3` again.

**The run split gets out of your way.** `Ctrl+R` drops you *in* the output, so
any key dismisses it and you carry on — and if you go back to the file first
instead, it closes itself the moment you leave it. What it will not do is close
a program that is still running: `Ctrl+R` on a script that calls `input()` puts
you at its prompt, and that window stays until the program is done with you.

**The split is yours to resize.** Drag the statusline between the file and the
interpreter (the mouse is on) and you come up typing on the other side of the
drag, not stranded in Normal mode. The height you set sticks for the rest of
the session — `Ctrl+E` hides and re-shows at *your* size — and a fresh start
is back to the default 15 rows.

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

## The directory listing

`d` / `dt` / `ds` with no argument opens the listing instead of a file. It is
not a buffer you type in, and the keys that only make sense on a file now say
so by doing nothing: `Ctrl+S` has nothing to save, `Ctrl+E` and `Ctrl+R` have
nothing to run. Clicking a filename opens it — that is netrw's own handler, and
it is left alone.

Both of those used to misbehave, for the same reason: **netrw's `buftype` is
empty**, so a guard written as `buftype ~= ""` does not exclude it. `Ctrl+S`
raised a Lua traceback and left the editor stuck behind a modal *"Press ENTER
or type command to continue"*, and `Ctrl+E` opened a split running
`python3 -i ''` — the listing has no filename, `expand("%:p")` is `""`, and an
empty string is *truthy* in Lua, so the "nothing to run" guard never fired.

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
`Ctrl+Q` for visual block.

**On a terminal that speaks no CSI-u the chord arrives as plain `Ctrl+Q`**, so
on WSL insert-mode and terminal-mode `Ctrl+Q` are bound to the same prompt. The
binding is gated on **being on WSL**, not on the protocol — there is no runtime
way to ask whether CSI-u was negotiated — so a WSL session whose terminal *does*
speak CSI-u gets it too, and bare `Ctrl+Q` quits from insert there as well even
though `Ctrl+Shift+Q` arrives as its own key. From insert, which is where
this editor keeps you, you press the documented chord and it works. Two costs:
plain `Ctrl+Q` then quits from insert as well (Cancel is still the default) and
stops being vanilla vim's literal-insert.

**Normal mode is not covered there.** `Ctrl+Q` in normal mode is visual block
and is the only route to one — `Ctrl+V` is paste — so binding it to the prompt
would leave no way to ask for a block at all, while quitting still has `:qa!`.
The trade is deliberate: from normal mode on such a terminal, `Ctrl+Shift+Q`
gives you a visual block, so press `i` first or use `:qa!`. None of this applies
off WSL. See [docs/wsl.md](docs/wsl.md).

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
d <name>          edit ~/drill/scratch/<name>.py      bare = dir listing
d <dir> <name>    nested: scratch/<dir>/<name>.py, folders created as needed
                  (same file as d <dir>/<name>; dt and ds nest too)
d search [query]  fuzzy-pick a file with fzf; Esc picks nothing
dt <name>         edit ~/drill/templates/<name>.py    bare = dir listing
ds <name>         edit ~/drill/solves/<name>.py       bare = dir listing
r <file>          python3 <file>, toolkit pre-imported (nested names resolve)
ri <file>         python3 -i <file>   (REPL: the file's names + toolkit live)
t / t10           25- / 10-minute timer, counts down in the window title
t -k [id]         stop it (id optional -- there is only ever one)
t -l              is one running?
```

`search` is a reserved word to `d`/`dt`/`ds`: a file literally named
`search.py` is still reachable as `d ./search`, from the bare-`d` listing, or
from the search itself.

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
    Insert-mode `Shift+Tab` is the one later addition: it dedents the current
    line via vim's own `i_CTRL-D` rather than this engine — the engine's
    blank-lines-stay-blank rule (right for a block) would skip the
    whitespace-only line the autoindent just gave you, which mid-typing is
    exactly the line you want dedented.

11. **Clearing the search highlight from an autocmd silently does nothing.** An
    autocmd body runs inside a save/restore of the search state, so writing
    `v:hlsearch` from an `InsertEnter` callback is put back on the way out —
    measured, the flag read 0 inside the callback and 1 again by `InsertLeave`.
    `:nohlsearch` has the same problem. `vim.schedule` lands the write after
    that context unwinds, where it sticks.

12. **The usual auto-save recipe never fires here.** Every autosave snippet
    hangs off `InsertLeave`, and in a config where `:startinsert` is the resting
    state you can drill for an hour without leaving insert once. `TextChangedI`
    is the event that tracks typing — which fires per keystroke, so it is
    debounced 700ms with a generation counter. Measured: 30 keystrokes, 2
    writes.

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

That register needs a *provider*, and nvim finds one by itself: `pbcopy`/
`pbpaste` on macOS, `wl-copy`/`xclip`/`xsel`/`win32yank` elsewhere. On WSL,
WSLg supplies the display server but not those clients — they are packages you
install. With none of them present nvim does say `clipboard: No provider`, but
only once and only in the message area: what you actually notice is `Ctrl+C`
copying nothing and `Ctrl+V` over a selection deleting it and putting nothing
back. `install.sh` checks. On WSL
with no display, drill falls back to `clip.exe` and `powershell.exe` on its own
— see [docs/wsl.md](docs/wsl.md).

**Consequence to know:** with `unnamedplus`, *every* `d`, `x`, `c` and `dd` also
overwrites the system clipboard. To delete without touching it, use the
black-hole register: `"_dd`, `"_x`. `Delete`, `Backspace` and typing over a
selection are already black-holed.

**Mouse:** `mouse=a` means clicking and dragging go to vim, not to the terminal.
Hold **Shift** while dragging to use your terminal's own selection — Shift is
the one modifier this config deliberately leaves alone. **Option no longer works
for that on macOS**: iTerm2 reports Option+drag to nvim rather than handling it
itself, so the config now strips Option from the left button (see above) and an
Option+drag is just a drag.

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
