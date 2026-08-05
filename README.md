<p align="center">
  <img src="drill-icon.png" width="180" alt="Drill project icon">
</p>

<h1 align="center">drill</h1>

<p align="center">
  A terminal coding-drill environment where <strong>nothing helps you type</strong>.
</p>

Two files do the work: one Neovim config, one shell script. No plugins, no
plugin manager, no distro, no LSP, no completion, no AI. You type from memory,
you run it, you see it pass or fail. Everything else in the repo — the
installer, the demo script, the test gate — is never loaded while you drill.

```
type code  ->  Ctrl+E  ->  live python REPL  ->  Ctrl+E  ->  back in the file, still typing
```

## Why

I leaned on AI autocomplete for two years and my raw typing recall was gone. I
could read code fine and describe the algorithm fine, but I couldn't *produce*
`heapq.heappush(h, (dist, node))` without something finishing it for me. That's
a bad place to be in a 45-minute interview with a shared editor and no plugins.

So: 18 days of DSA in Python, in an environment where nothing can help. Not
"autocomplete turned off" — autocomplete *absent*, at every source, verified.

Every mainstream Neovim distro (LazyVim, NvChad, AstroNvim, kickstart) ships
completion on by default. That's the opposite of the requirement, so this is a
hand-written config that gets loaded explicitly with `nvim -u` and never
globally. **Your own `~/.config/nvim` and `~/.vimrc` are not touched.**

## What it refuses to do

- No autocomplete, no LSP, no Copilot, no AI, no snippet expansion
- No linter suggestions, no auto-import, no signature hints
- Syntax highlighting only — nothing else appears on screen while you type
- No plugin manager, no distro
- No swapfile, no backup, no undo file — the directory holds the `.py` you
  wrote and nothing else
- Stock Python 3 and Neovim. That's the whole dependency list.

**One deliberate exception.** `filetype plugin indent on` is set, so Neovim's
bundled Python indent plugin is live (`indentexpr` is `python#GetIndent`) — type
`def f():` and press Enter and the four spaces appear without you typing them.
It is the one thing here that helps you type, and it stays because indentation
is not the recall being drilled; `heapq.heappush(h, (dist, node))` is.
Everything else on that list is absent, not merely off, and the test suite
asserts it.

## Install

```sh
git clone https://github.com/jainal09/drill.git
cd drill
./install.sh
exec $SHELL
```

It touches exactly two things: `~/drill/`, and one four-line block at the end of
your shell rc (backed up first). Uninstall with `./install.sh --uninstall`.

To put it somewhere else: `DRILL_HOME=~/practice ./install.sh`.

Requires Neovim 0.9+ and Python 3. Works on macOS and Linux, bash and zsh.

## The loop

```sh
t              # start a 25-minute timer, counts down in the window title
ds day1        # open ~/drill/solves/day1.py in the isolated editor
               # ... type the whole thing from memory, no help ...
               # Ctrl+E to run it in a live interpreter, Ctrl+E to come back
t -k           # stop the timer
```


https://github.com/user-attachments/assets/6d69565f-ae38-4d8e-8063-c925359175d0



`./demo.sh` is that tour as a script: it drives the editor through every feature
by itself — typing, clicking, running, narrating — so the whole thing can be
screen-recorded with nobody at the keyboard. Thirteen chapters: shell, typing,
comment, indent, select, clipboard, find, mouse, autosave, undo, run, repl,
quit. `./demo.sh --list` prints them, `--only find,mouse` runs just those, and
`--speed 0.5` halves the pauses (`2` doubles them).

How the keys are sent matters if you are recording. `--keys system`, the default
where macOS permits it, presses real OS key events, so a keycast app can show
them — the terminal has to stay frontmost, because the keys go wherever focus
is. `--keys socket` sends straight into nvim over `--listen`: reliable
everywhere, ssh and Linux included, and needs no permissions, but the keys never
touch the OS so a keycast app shows nothing. Either way the on-screen caption
names the key being pressed.

`Ctrl+E` is the entire interface to the interpreter, and it is **directional**.
From the file it opens the interpreter and puts you at the prompt — or focuses
it, if it is already open. From inside the interpreter it hides it and puts you
back in the file, still typing. **The interpreter always has the code you can
see:** if you edited the file, it restarts python with the new code; if you
didn't, you get the same session back with everything you were poking at still
defined.

You are always typing. Opening a file puts you in insert immediately — including
a file that does not exist yet. Land in the interpreter and you're at the `>>>`
prompt; come back and you're in insert. No `i`, no Esc, no mode-juggling. That's
deliberate — the point is fluency in *typing code*, not fluency in vim.

`Ctrl+R` is the one-shot version: it saves, then runs a fresh `python3 <file>`
in a split below — no prompt, and the same window is reused each time rather
than stacking splits. You land *in* that output split: if the script is still
running — waiting on `input()`, say — you are at its prompt and can answer it,
and once it has exited any key dismisses the window, swallowed rather than
typed.

And if you go back to the file without dismissing it, it closes itself on the
way out. That is not tidiness: standing outside it there was no key in this
config that could close it, so it held fifteen rows until you resorted to `:q`
— and `Ctrl+E` then opened the interpreter *underneath* it, leaving three
windows with the file squeezed into what was left. A program still running is
exempt, because that is one you may still be talking to.

Out of the interpreter it is `Ctrl+E`, `Ctrl+\` `Ctrl+N`, or a click on the
file. Nothing else is bound in terminal mode, on purpose: `Ctrl+C`, `Ctrl+D` and
`Ctrl+W` all reach python untouched. That is also why `Ctrl+\` `Ctrl+N` is the
only way to scroll back through the output — the wheel goes to python too.

## Commands

| | |
|---|---|
| `d <name>` | edit `~/drill/scratch/<name>.py` — bare `d` opens the listing |
| `dt <name>` | same for `templates/` |
| `ds <name>` | same for `solves/` |
| `r <file>` | `python3 <file>` — anything after the name is passed to the script |
| `ri <file>` | `python3 -i <file>` — REPL with the file's names already live |
| `t` / `t10` | start a 25- / 10-minute timer, non-blocking; counts down in the window title, sound and a desktop notification at zero |
| `t -k [id]` | stop it. The id is optional — there is only ever one running |
| `t -l` | is one running? |
| `t -h` | the three lines above |

`r` and `ri` take a bare name and find it under `scratch/`, `solves/` or
`templates/`, so `ri day1` works from anywhere.

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

## The editor

Normal-editor keys, because fighting your muscle memory is not the skill being
practised here:

`Ctrl+S` save · `Ctrl+C/X/V` copy/cut/paste · `Ctrl+A` select all ·
`Ctrl+Z` undo · `Ctrl+Y` / `Ctrl+Shift+Z` redo · `Ctrl+F` find ·
`Ctrl+/` comment · `Ctrl+Q` visual block · `Ctrl+Shift+Q` quit ·
**Shift+arrows select** · **click anywhere** ·
`Tab` / `Shift+Tab` indent a selection ·
`Delete` / `Backspace` clear a selection and leave you typing

Everything else is still vim: `hjkl`, `dd`, `ciw`, `.`, macros, `:%s/…`.

### Click anywhere

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

### It saves itself

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

### Find, and the highlight going away

`Ctrl+F` opens the search, and the end of the status line — right above the
prompt — tells you what to do with it: *press Enter to search   Esc back to
typing* while you type
the pattern, then *n next   N previous   Esc back to search* once it has run.
`Esc` backs out one level at a time: from a finished search it reopens the
prompt with your term still in it, and from the prompt it puts you back where
you were typing, caret still on the match. `Ctrl+F` is a round trip you can
always get out of without touching `i`. That second hint is the one piece of vim this editor genuinely needs
you to know — `Ctrl+F` leaves you in Normal mode on purpose, so `n` and `N` are
live — and it is shown only while it is true. Start typing again and it goes,
on the same keystroke that clears the highlight, because `n` and `N` have gone
back to being letters. Cancel the search, or match nothing, and there is no
hint at all rather than a wrong one.

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

### Getting out

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

Full reference, including all twelve keybinding conflicts and how each is
resolved: **[KEYS.md](KEYS.md)**.

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

KEYS.md says which lines to delete for the old behaviour on the first two.

## Tests

Every keybinding is asserted by driving the **real** config with real keycodes
and diffing what comes out. Nothing is mocked: if a case passes, that keystroke
does that thing in this config.

```sh
./tests/run.sh            # 490 cases; exit 0 only if all pass
./tests/run.sh sel_       # just the select-mode cases
```

| Suite | Cases | What it drives |
|---|---|---|
| `suite_options.sh` | 84 | config invariants no key-driven test can see: completion off at every source, zero LSP clients, no swap/backup/undo files, the cursor shape in both panes, and every mapping registered in the modes it claims — including that `Ctrl+/` is *not* bound in terminal mode and `Ctrl+C` is *not* bound in normal or terminal, so SIGINT still reaches a running program |
| `suite_config.sh` | 30 | headless nvim: shift+arrow selection, `Tab`/`Shift+Tab`, cut/paste/select-all, undo/redo, `Ctrl+C` copying without losing the selection |
| `suite_mouse.sh` | 58 | pty: click to caret from every mode, into empty space and past EOF, jitter in both axes, real drags, double-click, Option/Ctrl+click, and clicks between the file and the interpreter |
| `suite_search.sh` | 36 | `Ctrl+F`, exactly when the highlight and hints appear and go, and the Esc chain — including that it resumes typing at the exact column. Headless **and** pty: the Esc chain cannot be seen headlessly, because feedkeys force-ends Insert as the typeahead drains |
| `suite_autosave.sh` | 8 | what is on **disk**, read back from the shell |
| `suite_quit.sh` | 21 | pty: the confirmation is drawn, Cancel and Esc both return you to typing, Quit writes the pending edit, and all of it again from inside the REPL |
| `suite_runwin.sh` | 12 | pty: the `Ctrl+R` output window — that it closes when you leave it, that any key still closes it from inside, that `Ctrl+R` then `Ctrl+E` is two windows and not three, and that a program still running is left alone |
| `suite_netrw.sh` | 10 | pty: the directory listing is not a file — `Ctrl+S` does not wedge it, `Ctrl+E`/`Ctrl+R` start nothing. Headless is useless here: it does not produce a netrw buffer at all |
| `suite_timer.sh` | 36 | not nvim at all — 18 assertions against `drill.sh` run under **bash and zsh**, which disagree about word splitting |
| `suite_comment.sh` | 65 × 3 | the comment toggle, a full pass per `Ctrl+/` spelling |

Run it before you push. It exists because four different "fixes" to `Ctrl+/`
shipped broken in a row, each one plausible and none of them ever actually
pressed. Three of the bugs it now guards against were invisible by inspection:

- `<C-/>` and `<C-_>` are **different keys** to Neovim (`80 FC 04 2F` vs `1F`),
  so a mapping written for one is never reached by the other. Which one your
  terminal sends depends on whether it negotiates the CSI-u keyboard protocol,
  so all three spellings are bound — and the suite runs three times, once each.
- `'<` and `'>` are only written when you **leave** visual/select mode. Read from
  inside a mapping they still describe the *previous* selection. Use `line("v")`
  and `line(".")`, which are live.
- In Lua, `vim.cmd("normal! \<C-g>")` passes the literal six characters
  `\<C-g>`; only Vimscript's `:execute` interprets that notation. In select mode
  it types them into your file.

`Ctrl+/` is bound in insert mode too, which matters more here than anywhere
else: this editor puts you in insert mode on every file, so a mapping bound only
to normal and visual is unreachable by design.

Two suites cannot run headless at all, and one is not nvim. `--headless`
attaches no UI, so there is no screen grid and `nvim_input_mouse` is a silent
no-op — measured: it returns `true` and the cursor stays at `(1,0)` across every
click. The mouse and quit suites therefore run the real editor on a real pty and
write the real SGR escape sequences a terminal sends (`ESC [ < btn ; col ; row
M`), reading state back over `--listen`. The quit confirmation is pty-only for a
second, independent reason: a blocking prompt can be neither answered by
headless `feedkeys` nor read by any API — it is only ever *drawn*, so those
cases assert against the painted screen.

The gate needs three things the editor itself does not: `python3` for the pty
suites, `zsh` because the timer suite runs `drill.sh` under both shells, and
`perl` — macOS ships no GNU `timeout`, so `tests/bin/timeout` is a three-line
`alarm` shim that `run.sh` puts on `PATH`.

Two diagnostics come with the mouse suite. `tests/mousecheck.sh` says whether
your terminal sends mouse events at all and decodes the modifier field;
`tests/mousetrace.sh` records every key nvim actually receives while you click.

See [tests/NOTES.md](tests/NOTES.md) for the harness mechanics — in particular
why keys need `feedkeys` mode `xt`, why the deferred `:startinsert` swallows the
first keystroke if you don't disarm it, and why a write from inside an autocmd
fires no `BufWritePost`, so a counter reads 0 while the file is demonstrably
being written.

## Verify it's really doing nothing

Don't take my word for it. In the editor, type a `heapq` snippet and watch for a
popup — there won't be one. Then force the issue:

| Press | Expected |
|---|---|
| `Ctrl+N` / `Ctrl+P` | nothing |
| `Ctrl+X` `Ctrl+O` | `E764: Option 'omnifunc' is not set` |
| `:lua =#vim.lsp.get_clients()` | `0` |
| `:set completeopt? complete? omnifunc?` | all empty |

And confirm it left your own setup alone: run plain `nvim` and check
`:set completeopt?` still shows the stock `menu,popup`.

## Layout

```
~/drill/
  nvimrc.lua      the isolated editor
  drill.sh        the shell commands
  demo.sh         the guided tour, for recording
  KEYS.md         keybinding reference
  tests/          the gate -- ./tests/run.sh
  templates/      pattern skeletons
  solves/         daily attempts
  scratch/        throwaway
  cheatsheet.py   yours to fill
  log.md          yours to fill
```

`install.sh` copies `nvimrc.lua`, `drill.sh` and `KEYS.md` into `DRILL_HOME` and
creates the directories; `tests/` and `demo.sh` stay in the clone, which is the
same directory unless you pointed `DRILL_HOME` somewhere else.

`templates/`, `cheatsheet.py` and `log.md` ship empty on purpose. Filling them
in yourself is part of the exercise.

The recommended install *is* a clone into `~/drill`, so your practice work ends
up sitting inside a git repo — `solves/`, `scratch/`, `templates/`,
`cheatsheet.py` and `log.md` are all in `.gitignore` and will not be committed.
That is also what keeps `git pull` clean after eighteen days of drilling.

## License

MIT
