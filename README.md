<p align="center">
  <img src="drill-icon.png" width="180" alt="Drill project icon">
</p>

<h1 align="center">drill</h1>

<p align="center">
  A terminal coding-drill environment where <strong>nothing helps you type</strong>.
</p>

Two files: one Neovim config, one shell script. No plugins, no plugin manager,
no distro, no LSP, no completion, no AI. You type from memory, you run it, you
see it pass or fail.

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
- Stock Python 3 and Neovim. That's the whole dependency list.

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
```


https://github.com/user-attachments/assets/6d69565f-ae38-4d8e-8063-c925359175d0



`Ctrl+E` is the entire interface to the interpreter. It shows it, and pressing
it again hides it. **The interpreter always has the code you can see:** if you
edited the file, it restarts python with the new code; if you didn't, you get
the same session back with everything you were poking at still defined.

You are always typing. Land in the interpreter and you're at the `>>>` prompt;
come back and you're in insert. No `i`, no Esc, no mode-juggling. That's
deliberate — the point is fluency in *typing code*, not fluency in vim.

## Commands

| | |
|---|---|
| `d <name>` | edit `~/drill/scratch/<name>.py` — bare `d` opens the listing |
| `dt <name>` | same for `templates/` |
| `ds <name>` | same for `solves/` |
| `r <file>` | `python3 <file>` |
| `ri <file>` | `python3 -i <file>` — REPL with the file's names already live |
| `t` / `t10` | 25- / 10-minute timer, non-blocking, alerts at zero |

`r` and `ri` take a bare name and find it under `scratch/`, `solves/` or
`templates/`, so `ri day1` works from anywhere.

## The editor

Normal-editor keys, because fighting your muscle memory is not the skill being
practised here:

`Ctrl+S` save · `Ctrl+C/X/V` copy/cut/paste · `Ctrl+A` select all ·
`Ctrl+Z` undo · `Ctrl+Y` / `Ctrl+Shift+Z` redo · `Ctrl+F` find ·
`Ctrl+/` comment ·
**Shift+arrows select** · `Tab` / `Shift+Tab` indent · `Ctrl+Q` visual block

Everything else is still vim: `hjkl`, `dd`, `ciw`, `.`, macros, `:%s/…`.

Full reference, including all ten keybinding conflicts and how each is
resolved: **[KEYS.md](KEYS.md)**.

## Tests

Every keybinding is asserted by driving the real config in headless Neovim,
feeding real keycodes and diffing the resulting buffer. Nothing is mocked: if a
case passes, that keystroke does that thing in this config. A third suite
asserts the settings this README makes promises about — that completion really
is off at every source, and that `Ctrl+C` stays unmapped in normal and terminal
mode so SIGINT still reaches a running program.

```sh
./tests/run.sh            # 269 cases; exit 0 only if all pass
./tests/run.sh sel_       # just the select-mode cases
```

Run it before you push. It exists because four different "fixes" to `Ctrl+/`
shipped broken in a row, each one plausible and none of them ever actually
pressed. Three of the bugs it now guards against were invisible by inspection:

- `<C-/>` and `<C-_>` are **different keys** to Neovim (`80 FC 04 2F` vs `1F`),
  so a mapping written for one is never reached by the other. Which one your
  terminal sends depends on whether it negotiates the CSI-u keyboard protocol,
  so all three spellings are bound.
- `'<` and `'>` are only written when you **leave** visual/select mode. Read from
  inside a mapping they still describe the *previous* selection. Use `line("v")`
  and `line(".")`, which are live.
- In Lua, `vim.cmd("normal! \<C-g>")` passes the literal six characters
  `\<C-g>`; only Vimscript's `:execute` interprets that notation. In select mode
  it types them into your file.

`Ctrl+/` is bound in insert mode too, which matters more here than anywhere
else: this editor puts you in insert mode on every file, so a mapping bound only
to normal and visual is unreachable by design.

See [tests/NOTES.md](tests/NOTES.md) for the harness mechanics — in particular
why keys need `feedkeys` mode `xt`, and why the deferred `:startinsert` swallows
the first keystroke if you don't disarm it.

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
  KEYS.md         keybinding reference
  tests/          headless keybinding tests -- ./tests/run.sh
  templates/      pattern skeletons
  solves/         daily attempts
  scratch/        throwaway
  cheatsheet.py   yours to fill
  log.md          yours to fill
```

`templates/`, `cheatsheet.py` and `log.md` ship empty on purpose. Filling them
in yourself is part of the exercise.

## License

MIT
