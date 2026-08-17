# Verify it's really doing nothing

Don't take my word for it. In the editor, type a `heapq` snippet and watch for
a popup — there won't be one. Then force the issue:

| Press | Expected |
|---|---|
| `Ctrl+N` / `Ctrl+P` | nothing |
| `Ctrl+X` `Ctrl+O` | `E764: Option 'omnifunc' is not set` |
| `:lua =#vim.lsp.get_clients()` | `0` |
| `:set completeopt? complete? omnifunc?` | all empty |

And confirm it left your own setup alone: run plain `nvim` and check
`:set completeopt?` still shows the stock `menu,popup`.

## The contract

- No autocomplete, no LSP, no Copilot, no AI, no snippet expansion
- No linter suggestions, no auto-import, no signature hints
- Syntax highlighting only — nothing else appears on screen while you type
- No plugin manager, no distro. The one exception to "no plugins" is the
  optional `Ctrl+B` sidebar: three checkouts pinned to exact commits by
  `vendor.sh`, loaded only when you first press the key, and none of them
  touches what appears while you type
- No swapfile, no backup, no undo file — the directory holds the `.py` you
  wrote and nothing else
- Stock Python 3, Neovim and fzf — and fzf only powers `d search`, never the
  editor. That's the whole dependency list.

Every mainstream Neovim distro (LazyVim, NvChad, AstroNvim, kickstart) ships
completion on by default. That's the opposite of the requirement, so this is a
hand-written config that gets loaded explicitly with `nvim -u` and never
globally. **Your own `~/.config/nvim` and `~/.vimrc` are not touched.**

## Two deliberate exceptions

`filetype plugin indent on` is set, so Neovim's bundled Python indent plugin is
live (`indentexpr` is `python#GetIndent`) — type `def f():` and press Enter and
the four spaces appear without you typing them. And every run goes through
`preload.py`, so `Counter`, `deque`, `heappush`, `permutations` and the rest of
the interview toolkit are live with no import line in the file — the way the
LeetCode judge has them baked in. Both stay for the same reason: indentation
and the import preamble are not the recall being drilled;
`heapq.heappush(h, (dist, node))` is. Everything else on the list above is
absent, not merely off, and [the test suite](testing.md) asserts it.
