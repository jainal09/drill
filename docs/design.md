# Design notes

Why the editor behaves the way it does. None of this is needed to use drill —
it is the reasoning behind behaviour you might otherwise mistake for a bug, and
the record of the bugs that shaped it.

## `Ctrl+E`, precisely

`Ctrl+E` is the entire interface to the interpreter, and it is **directional**.
From the file it opens the interpreter and puts you at the prompt — or focuses
it, if it is already open. From inside the interpreter it hides it and puts you
back in the file, still typing. **The interpreter always has the code you can
see:** if you edited the file, it restarts python with the new code; if you
didn't, you get the same session back with everything you were poking at still
defined.

Out of the interpreter it is `Ctrl+E`, `Ctrl+\` `Ctrl+N`, or a click on the
file. Nothing else is bound in terminal mode, on purpose: `Ctrl+C`, `Ctrl+D` and
`Ctrl+W` all reach python untouched. That is also why `Ctrl+\` `Ctrl+N` is the
only way to scroll back through the output — the wheel goes to python too.

## `Ctrl+R` and the run window

`Ctrl+R` is the one-shot run: it saves, then runs a fresh `python3 <file>` in a
split below — no prompt, and the same window is reused each time rather than
stacking splits. You land *in* that output split: if the script is still
running — waiting on `input()`, say — you are at its prompt and can answer it,
and once it has exited any key dismisses the window, swallowed rather than
typed.

And if you go back to the file without dismissing it, it closes itself on the
way out. That is not tidiness: standing outside it there was no key in this
config that could close it, so it held fifteen rows until you resorted to `:q`
— and `Ctrl+E` then opened the interpreter *underneath* it, leaving three
windows with the file squeezed into what was left. A program still running is
exempt, because that is one you may still be talking to.

## Always typing

Opening a file puts you in insert immediately — including a file that does not
exist yet. Land in the interpreter and you're at the `>>>` prompt; come back
and you're in insert. No `i`, no Esc, no mode-juggling. That's deliberate — the
point is fluency in *typing code*, not fluency in vim.

## Click anywhere

A left click puts the caret exactly where you clicked and leaves you **typing**
there — including from Normal mode, which is one `Ctrl+C` away at all times.

**Anywhere means anywhere**, not just where there is already text. `mouse=a` on
its own only lets the caret sit on a real character, so a click on a blank line
snapped to column 1 and a click to the right of a short line snapped to its end.
A half-written drill file is mostly blank lines and 20-character lines — 9 of
the 22 lines in the scratch file this was found on were empty — so almost every
click landed nowhere near the pointer and the mouse read as broken.
`virtualedit=all` is what fixes it: click into empty space, type, and the gap
fills with spaces.

**A click that wobbles is still a click.** Your finger drifts a few pixels
between pressing and lifting, a character cell is about 8 pixels wide, and
`selectmode=mouse` turns any motion across a cell boundary into a selection — so
nearly every real trackpad click used to strand you in Select mode holding a
one-character selection you never asked for, where the next letter you typed
*replaced* a character instead of inserting one. Drifting down a *row* was
worse: the selection ran from the press column on one line to the same column on
the next, so one click plus one keystroke merged two lines into one. A mouse
selection ending within one cell of the press — in **both** axes — is now the
click it was, and the caret goes to the cell you pressed on, not the one you
drifted to. Two cells across or two rows down is still a drag, and double-click
still takes the word.

**Option+click and Ctrl+click are plain clicks too.** Vim gives `ALT-LeftMouse`
a *blockwise* selection, so an Option+click — which is how iTerm2 itself moves
the cursor at a shell prompt — put the caret down and then left you in a
one-cell block. `CTRL-LeftMouse` is a tag jump; with no tags file that raises
`E426` and wedges the editor behind a modal *"Press ENTER"* prompt, so one stray
Ctrl looked like the mouse had hung the whole thing. Both modifiers are now
dropped for the left button. Shift+click still extends a selection.

## Autosave

The file writes itself about 0.7s after you stop typing, and immediately when
you leave insert, switch away, lose focus or quit. `Ctrl+S` still works and is
still instant — it is just no longer something you have to remember.

The recipe everyone posts for this is an `InsertLeave` autocmd, and in this
config it would essentially never fire: `:startinsert` is the resting state and
you can drill for an hour without leaving insert once. The event that tracks
"the code changed" while you type is `TextChangedI`, which fires on every
keystroke — so it is debounced, and a burst of typing costs one write rather
than one per character. Measured in a pty, staying in insert, 30 characters
40ms apart: **2 writes, not 30.**

Only real files: the interpreter split, the directory listing and any buffer
with no filename are left alone (`:w` with no name is `E32`, which would pop an
error at you mid-keystroke).

## Find, and the highlight going away

`Ctrl+F` opens the search, and the end of the status line — right above the
prompt — tells you what to do with it: *press Enter to search   Esc back to
typing* while you type the pattern, then *n next   N previous   Esc back to
search* once it has run. `Esc` backs out one level at a time: from a finished
search it reopens the prompt with your term still in it, and from the prompt it
puts you back where you were typing, caret still on the match. `Ctrl+F` is a
round trip you can always get out of without touching `i`. That second hint is
the one piece of vim this editor genuinely needs you to know — `Ctrl+F` leaves
you in Normal mode on purpose, so `n` and `N` are live — and it is shown only
while it is true. Start typing again and it goes, on the same keystroke that
clears the highlight, because `n` and `N` have gone back to being letters.
Cancel the search, or match nothing, and there is no hint at all rather than a
wrong one.

Search is **case-sensitive** and incremental — `ignorecase` and `smartcase` are
both off, so `Ctrl+F` then `total` will not find `Total`. If you came from an
editor that quietly folds case until you type a capital, that will catch you.

`Ctrl+F` lights up every match and drops you on the first one, in Normal mode,
so `n` and `N` walk the matches with the highlight on. The moment you go back to
typing, it clears. `hlsearch` is on by nvim default and nothing here used to
turn it off, so matches stayed lit through the edit, the next one, and the one
after — and there was no way to clear it by hand either, because `:nohlsearch`
is a command and reaching the command line means leaving the insert mode you are
supposed to live in.

## Getting out

`Ctrl+Shift+Q`:

```
Quit drill?
(Q)uit, [C]ancel:
```

`Q` goes; `C` or `Esc` puts you straight back where you were typing. Cancel is
the **default**, so a mistyped chord can never be the thing that quits. It works
from inside the interpreter too, and there the prompt says that python is still
running and will be killed. Getting out was the last thing that still needed the
command line — `Esc`, then `:qa!` typed in full, every time.

**`Ctrl+Shift+Q` and `Ctrl+Shift+Z` only exist on a terminal that speaks the
CSI-u keyboard protocol.** In the legacy encoding Shift is dropped from a
control chord, so Ctrl+Q and Ctrl+Shift+Q are both `0x11`, and Ctrl+Z and
Ctrl+Shift+Z are both `0x1A` — genuinely indistinguishable. With CSI-u
negotiated they separate: `ESC[113;6u` fires `<C-S-q>` while a bare `0x11` still
fires `<C-q>`, which is what lets the quit chord coexist with `Ctrl+Q` for
visual block. Where the protocol is not spoken, `Ctrl+Shift+Q` does not fire and
`:qa!` still works, and `Ctrl+Shift+Z` falls back to `Ctrl+Z` and *undoes* —
which is why `Ctrl+Y` is kept as the redo that works everywhere.

## The timer refuses stale ids

Starting a timer prints its id and the command that stops it:

```
timer: 25 min, id 81975 (counts down in the window title; sound at zero)
       stop it with:  t -k 81975      (or just  t -k)
```

An id that is not a live drill timer is refused rather than obeyed. A finished
timer's pid goes back to the OS and gets handed out again, so `t -k 70147`
copied off scrollback ten minutes later could otherwise fire a kill at whatever
holds that pid now. Stopping also clears the countdown out of the window title —
the timer repaints it twice a second to hold it against p10k and nvim, so
killing one with plain `pkill` leaves the last frame frozen up there.

## What it costs

Five things behave worse here than in a stock editor, on purpose. They are not
buried in the config:

| | |
|---|---|
| auto-save | `:qa!` no longer discards anything. It used to mean "quit and throw away what I typed"; now what you typed is already on disk, so a botched drill is saved like any other. Delete the file, or `Ctrl+Z` your way back, if you want a clean slate. |
| `virtualedit=all` | at the end of a line the right arrow walks into the empty space past it instead of stopping. |
| `selection=exclusive` | a manual `v` or `Ctrl+Q` selection excludes the character under the cursor, so block operations need one more `l` than you may be used to. |
| `clipboard=unnamedplus` | every `d`, `x`, `c` and `dd` also overwrites the system clipboard. Use the black hole — `"_dd`, `"_x` — to delete without touching it. `Delete`, `Backspace` and typing over a selection are already black-holed. |
| the vim keys you give up | `Ctrl+R` (was redo — **and in insert too**, so `i_CTRL-R` to paste a register is gone; redo is `Ctrl+Y`), `Ctrl+A` (was increment-a-number), `Ctrl+E`/`Ctrl+Y` (were scroll), `Ctrl+F` (was page-forward), `Ctrl+V` (was blockwise — now `Ctrl+Q`), `Ctrl+Z` (was suspend). Still vim: `Ctrl+O`/`Ctrl+I` jumplist, `Ctrl+D`/`Ctrl+U` half-page, `Ctrl+X` decrement. |

[KEYS.md](../KEYS.md) says which lines to delete for the old behaviour on the
first two.

## The preload contract

All four ways to run — `r`, `ri`, `Ctrl+R`, `Ctrl+E` — go through `preload.py`
first: `Counter`, `deque`, `defaultdict`, `heappush`, `permutations`,
`lru_cache`, `bisect_left`, `inf` and the rest of the toolkit are already
imported, so the file you type stays import-free, like on LeetCode. Your own
names always win — assign over one and it is yours — a traceback still points
at your line, and `sys.argv` and `__name__ == "__main__"` behave exactly as
plain `python3`. Delete `preload.py` and every run is plain `python3` again.

## Layout, in full

```
~/drill/
  nvimrc.lua      the isolated editor
  drill.sh        the shell commands
  preload.py      the interview toolkit, pre-imported into every run
  demo.sh         the guided tour, for recording
  KEYS.md         keybinding reference
  tests/          the gate -- ./tests/run.sh
  templates/      pattern skeletons
  solves/         daily attempts
  scratch/        throwaway -- nest folders freely: scratch/graph-prac/bfs/...
  cheatsheet.py   yours to fill
  log.md          yours to fill
```

`install.sh` copies `nvimrc.lua`, `drill.sh`, `preload.py` and `KEYS.md` into
`DRILL_HOME` and creates the directories; `tests/` and `demo.sh` stay in the
clone, which is the same directory unless you pointed `DRILL_HOME` somewhere
else.

`templates/`, `cheatsheet.py` and `log.md` ship empty on purpose. Filling them
in yourself is part of the exercise.

The recommended install *is* a clone into `~/drill`, so your practice work ends
up sitting inside a git repo — `solves/`, `scratch/`, `templates/`,
`cheatsheet.py` and `log.md` are all in `.gitignore` and will not be committed.
That is also what keeps `git pull` clean after eighteen days of drilling.
