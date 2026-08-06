<p align="center">
  <img src="drill-icon.png" width="180" alt="Drill project icon">
</p>

<h1 align="center">drill</h1>

<p align="center">
  <strong>The LeetCode editor, living in your terminal.</strong><br>
  One command in. Zero setup. Nothing autocompletes — that's the point.
</p>

https://github.com/user-attachments/assets/6d69565f-ae38-4d8e-8063-c925359175d0

You can read code fine. You can explain the algorithm fine. But after a couple
of years of AI autocomplete, can you still *produce*
`heapq.heappush(h, (dist, node))` cold, in a 45-minute interview, in a shared
editor with no plugins? drill is the gym for exactly that muscle: a
frictionless Python scratchpad that feels like the LeetCode editor and refuses
to type a single character for you.

## Thirty seconds to typing

```sh
git clone https://github.com/jainal09/drill.git
cd drill && ./install.sh && exec $SHELL
```

```sh
d two-sum
```

You're in the editor, in a file that didn't exist a second ago, cursor blinking,
already in insert mode. No path to remember, no project to scaffold, no config
to answer. Just type.

## `Ctrl+E` — your code, live

The feature you'll press a hundred times a day. One keystroke drops you into a
**live Python interpreter with everything in your file already defined**. Call
your function with an edge case. Read a variable. Poke at the half-built thing.
`Ctrl+E` again — you're back in the file, exactly where you were, still typing.

It replaces the entire `print(x)` → save → `python main.py` → squint → delete
the print loop with one key each way. And it's never stale: edit the file and
the interpreter restarts with your new code; don't, and your session is still
there with everything you were inspecting still alive.

`Ctrl+R` is its one-shot sibling: save, run, land in the output. Any key
dismisses it.

## The imports are already done

`Counter`, `deque`, `defaultdict`, `heappush`, `lru_cache`, `bisect_left`,
`permutations`, `inf` — the whole interview toolkit is pre-imported into every
run, exactly the way the LeetCode judge has them baked in. Your file stays
import-free; you type the solution, not the preamble. Your own names always
win, tracebacks still point at your line, and `sys.argv` and
`__name__ == "__main__"` behave like plain `python3`.

## Zero vim required. All of vim included.

It runs on Neovim, but you will never see a vim mode. You open in insert, you
click anywhere — blank lines, past the end of a line — and type right there.
Every key does what your fingers already expect:

`Ctrl+S` save · `Ctrl+C/X/V` copy/cut/paste · `Ctrl+A` select all ·
`Ctrl+Z` undo · `Ctrl+Y` redo · `Ctrl+F` find · `Ctrl+/` comment ·
**Shift+arrows select** · `Tab`/`Shift+Tab` indent · `Delete` clears a selection

And underneath it is still real Neovim: `hjkl`, `dd`, `ciw`, macros and
`:%s/…` all work the moment you want them.

## Fast enough to keep a thought

Two files. No plugins, no plugin manager, no LSP, no startup spinner. From any
terminal, mid-thought, you're in the editor before the thought fades — and
everything **auto-saves** about 0.7s after you stop typing, plus instantly when
you switch away. Quit whenever; `d two-sum` brings it all back. You never lose
work, because there is no unsaved state to lose.

## Nothing helps you type

No autocomplete. No LSP, no Copilot, no snippets, no signature hints, no
auto-import. Not "turned off" — **absent, at every source, and a 556-case test
suite asserts it**. Syntax highlighting is the only thing on screen besides your
own keystrokes. Your `~/.config/nvim` and `~/.vimrc` are never touched; the
config loads with `nvim -u` and exists only inside drill.
[Prove it to yourself →](docs/verify.md)

## A timer, because interviews have clocks

```sh
t         # 25 minutes, counting down in the window title
t10       # the short version
t -k      # stop
```

Non-blocking, with a sound and a desktop notification at zero.

## The quality-of-life layer

- **Quit that can't misfire** — `Ctrl+Shift+Q` asks first, and Cancel is the
  default.
- **Find with training wheels** — `Ctrl+F` shows its own hints on screen
  (*n next · N previous · Esc back*), and the highlight clears itself the
  moment you type again.
- **Clicks that just work** — trackpad wobble doesn't turn clicks into
  selections; Option+click (Alt on Linux/WSL) and Ctrl+click are plain clicks,
  not vim surprises.
- **Folders when you want them** — `d graphs/bfs` nests freely,
  `d search` fuzzy-finds anything with fzf.
- **Run from anywhere** — `r day1` / `ri day1` find your file by name across
  all buckets; no paths.
- **A timer that won't kill the wrong process** — stale ids from scrollback
  are refused, not obeyed.

## Commands

| | |
|---|---|
| `d <name>` | edit `scratch/<name>.py` — bare `d` lists; `d <dir>/<name>` nests |
| `ds <name>` | same for `solves/` |
| `dt <name>` | same for `templates/` |
| `d search` | fuzzy-pick any file with fzf (`ds`/`dt search` too) |
| `r <file>` | run it, toolkit pre-imported; extra args go to the script |
| `ri <file>` | run it, then drop into a REPL with its names live |
| `t` / `t10` | 25- / 10-minute timer · `t -k` stop · `t -l` status |

## Install details

`./install.sh` touches exactly two things: `~/drill/`, and one four-line block
at the end of your shell rc (backed up first). `./install.sh --uninstall`
removes it. `DRILL_HOME=~/practice ./install.sh` puts it elsewhere.

Requires Neovim 0.9+, Python 3, fzf, and a clipboard provider — `pbcopy` is
already there on macOS; elsewhere any of `wl-clipboard`, `xclip`, `xsel` or
`win32yank`, and on WSL with none of them drill falls back to `clip.exe` and
PowerShell on its own. macOS, Linux and WSL; bash and zsh. `install.sh` checks for all of it,
prints the exact install command for your package manager, and asks before
running it. On WSL, read [docs/wsl.md](docs/wsl.md) — a few things there are
installed and still do not work, and it says which. Your practice files
(`scratch/`, `solves/`, `templates/`, `cheatsheet.py`, `log.md`) are gitignored,
so `git pull` stays clean forever.

## Going deeper

| | |
|---|---|
| [KEYS.md](KEYS.md) | every keybinding, every conflict, and how each is resolved |
| [docs/design.md](docs/design.md) | why the editor behaves the way it does — the mouse, autosave, search, quitting, and the five deliberate trade-offs |
| [docs/verify.md](docs/verify.md) | prove nothing is helping you, and that your own nvim is untouched |
| [docs/testing.md](docs/testing.md) | the 556-case gate that drives the real config with real keycodes |
| [docs/recording.md](docs/recording.md) | `demo.sh` — the self-driving tour that recorded the video above |
| [docs/wsl.md](docs/wsl.md) | WSL: the clipboard, the timer's sound and notification, and the one thing you have to check by hand |

## License

MIT
