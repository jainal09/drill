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
"autocomplete turned off" â€” autocomplete *absent*, at every source, verified.

Every mainstream Neovim distro (LazyVim, NvChad, AstroNvim, kickstart) ships
completion on by default. That's the opposite of the requirement, so this is a
hand-written config that gets loaded explicitly with `nvim -u` and never
globally. **Your own `~/.config/nvim` and `~/.vimrc` are not touched.**

## What it refuses to do

- No autocomplete, no LSP, no Copilot, no AI, no snippet expansion
- No linter suggestions, no auto-import, no signature hints
- Syntax highlighting only â€” nothing else appears on screen while you type
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

`Ctrl+E` is the entire interface to the interpreter. It shows it, and pressing
it again hides it. **The interpreter always has the code you can see:** if you
edited the file, it restarts python with the new code; if you didn't, you get
the same session back with everything you were poking at still defined.

You are always typing. Land in the interpreter and you're at the `>>>` prompt;
come back and you're in insert. No `i`, no Esc, no mode-juggling. That's
deliberate â€” the point is fluency in *typing code*, not fluency in vim.

## Commands

| | |
|---|---|
| `d <name>` | edit `~/drill/scratch/<name>.py` â€” bare `d` opens the listing |
| `dt <name>` | same for `templates/` |
| `ds <name>` | same for `solves/` |
| `r <file>` | `python3 <file>` |
| `ri <file>` | `python3 -i <file>` â€” REPL with the file's names already live |
| `t` / `t10` | 25- / 10-minute timer, non-blocking, alerts at zero |

`r` and `ri` take a bare name and find it under `scratch/`, `solves/` or
`templates/`, so `ri day1` works from anywhere.

## The editor

Normal-editor keys, because fighting your muscle memory is not the skill being
practised here:

`Ctrl+S` save Â· `Ctrl+C/X/V` copy/cut/paste Â· `Ctrl+A` select all Â·
`Ctrl+Z/Y` undo/redo Â· `Ctrl+F` find Â· **Shift+arrows select** Â·
`Ctrl+Q` visual block

Everything else is still vim: `hjkl`, `dd`, `ciw`, `.`, macros, `:%s/â€¦`.

Full reference, including all seven keybinding conflicts and how each is
resolved: **[KEYS.md](KEYS.md)**.

## Verify it's really doing nothing

Don't take my word for it. In the editor, type a `heapq` snippet and watch for a
popup â€” there won't be one. Then force the issue:

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
