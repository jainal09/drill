# drill keybindings

Editor config: `~/drill/nvimrc.lua` — loaded only via `nvim -u`, never globally.
Syntax highlighting only. No completion, no LSP, no snippets, no AI.

## Normal-editor keys

| Key | Does | Where |
|---|---|---|
| `Ctrl+S` | save | normal, insert, visual |
| `Ctrl+C` | copy to system clipboard | **selection only** |
| `Ctrl+C` | Esc | insert |
| `Ctrl+X` | cut to system clipboard | selection |
| `Ctrl+V` | paste (replaces the selection if there is one) | normal, insert, selection, command |
| `Ctrl+A` | select all | normal, insert |
| `Ctrl+F` | find (opens `/`) | normal, insert |
| `Ctrl+/` | comment / uncomment the line or the selected lines | normal, insert, visual, selection |
| `Ctrl+Z` | undo | normal, insert, visual |
| `Ctrl+Y` | redo | normal, insert, visual |
| `Ctrl+Q` | visual block (was `Ctrl+V`) | normal, visual |
| **Shift+arrows** | **select, like any other editor** | normal, insert |
| `Delete` / `Backspace` | delete the selection and keep typing | selection |
| Arrows | movement | everywhere |
| Mouse | select + scroll | everywhere |

Shift+arrows, Shift+Home/End and mouse drags all start a selection. Typing over
one replaces it and leaves you in insert, and none of it overwrites your
clipboard with the text it just replaced.

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

**`Ctrl+S` then `:qa!`** — save, quit everything, no prompts. Use this one.

| Command | Does |
|---|---|
| `:qa!` | quit everything, discard unsaved, kill a running REPL |
| `:wqa` | save all + quit — **refuses while `python3 -i` is still running** |
| `Ctrl+D` then `:wqa` | quit the REPL first, then this works cleanly |
| `:q` / `:wq` / `ZZ` | closes **one window** only — leaves the split behind |

`:wq` not quitting is not a bug: with a run split open you have two windows, and
`:wq` closes one. `:qa` is the "a"ll form.

`Ctrl+Z` is undo here, so the old panic-suspend out of nvim is gone by design.

To kill a running timer: `pkill -f drill-timer`.

## Shell

```
d <name>    edit ~/drill/scratch/<name>.py      bare = dir listing
dt <name>   edit ~/drill/templates/<name>.py    bare = dir listing
ds <name>   edit ~/drill/solves/<name>.py       bare = dir listing
r <file>    python3 <file>
ri <file>   python3 -i <file>   (REPL with the file's names live)
t / t10     25- / 10-minute timer, counts down in the window title
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

Two smaller traps, both found the hard way:

- A **literal trailing space is stripped from a mapping's right-hand side**,
  which silently made the space bar delete a selection and type nothing. Space,
  `<` and `|` are spelled `<Space>`, `<lt>`, `<Bar>`.
- Auto-insert is guarded by `jobwait(...) == -1`. Stepping into a *finished*
  run window in terminal mode is a trap: the next key just closes it.

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

**Mouse:** `mouse=a` means dragging selects in vim, not in the terminal. To use
your terminal's own selection, hold **Option** (macOS) or **Shift** (Linux)
while dragging.

## One trade-off

`selection=exclusive` is what makes shift+arrow selections land where the arrows
imply. The cost is that a manual `v` or `Ctrl+Q` selection now *excludes* the
character under the cursor, so block operations need one more `l` than you may
be used to.
