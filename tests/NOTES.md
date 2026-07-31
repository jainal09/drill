# Harness notes — driving `~/drill/nvimrc.lua` headlessly

Everything below was measured, not assumed. Probe scripts are `probe*.lua` in
this directory; their raw output is in `probe*.log`.

## The recipe that works

```lua
vim.wait(60)                       -- let the config's scheduled startinsert land
pcall(vim.cmd, 'stopinsert')       -- disarm it, deterministically
vim.api.nvim_feedkeys(
  vim.api.nvim_replace_termcodes('i' .. KEYS, true, false, true),
  'xt', false)                     -- ONE call. 'xt'. never 'xt!'.
vim.wait(60)                       -- let <Cmd>/vim.schedule work settle
```

## Why each piece

### 1. feedkeys mode must be `'xt'`, not `'x'`

`t` = "handle keys as if typed". Without it, `keymodel=startsel` +
`selectmode=key` produce **Visual** mode instead of **Select** mode, and the
entire config misbehaves (the printable-char loop never fires).

Measured (probe3/probe4, fixture `alpha`, keys `i<S-Right><S-Right><S-Right>Z`):

| mode   | mid-sequence `mode(1)` | resulting line |
|--------|------------------------|----------------|
| `'xt'` | `s`  (Select)          | `Zha`  correct |
| `'x'`  | `v`  (Visual)          | `alpha` wrong  |

### 2. Never use `'xt!'`

`!` means "do not end Insert mode". Headless nvim then never returns and the
20 s guard kills it (`rc=142`). Confirmed: probe3 T2 hung.

### 3. The leading `i` — this is the `startinsert` handling

`:startinsert` is `i`. The config's `BufEnter` autocmd calls
`vim.schedule(... startinsert ...)`, so by the time a `-c` command runs the
flag is **armed but `mode()` still reports `n`**. The first key you feed is
then silently swallowed by the transition into Insert.

Measured (probe4/probe5, feeding a single `l` on `alpha` at col 1):

| state                              | result            |
|------------------------------------|-------------------|
| armed by the config, no stopinsert | `col=1` — `l` eaten |
| armed, then `stopinsert`           | `col=2` — `l` ran   |
| never armed                        | `col=2` — `l` ran   |

So the harness does `stopinsert` (clears the armed flag) and then feeds a
literal `i`. That reproduces exactly the state the real user is in — typing at
the cursor — and it is idempotent: probe5 P1/P2 show `iABC` yields `ABCalpha`
whether or not the flag was armed.

`--start normal` skips the `i` (the `stopinsert` still makes it deterministic);
`--start append` uses `A` (equivalent to `:startinsert!`).

### 4. One feedkeys call, not several

`'x'` behaves like `:normal!` — it force-ends Insert mode when the typeahead
drains. Splitting a sequence across two `feedkeys` calls therefore drops you
back to Normal between them and the test stops matching reality.

### 5. Do not inject `<Cmd>...<CR>` probes into a sequence

If the sequence lands in Insert mode, the `<Cmd>` payload gets **typed into the
buffer as literal text** (visible in probe6.log). Use the `report.json` state
dump that `run_test.sh` writes instead.

### 6. `clipboard=unnamedplus` really is the macOS pasteboard

`getreg('+')` reads the actual system clipboard, so register state leaks
between runs. The driver clears `+` and `"` before feeding keys.

### 7. `timeout` does not exist on this Mac

No coreutils. `bin/timeout` is a 3-line perl `alarm` shim; `run_test.sh` puts
it on `PATH` so the mandated `timeout 20 nvim --headless … -c 'qa!'` shape
works verbatim.

### 8. The mouse cannot be tested this way at all

`--headless` attaches no UI, so there is no screen grid, and clicks have
nowhere to land. Measured: `nvim_input_mouse('left','press','',0,2,5)` returns
`true` and changes nothing — cursor stayed `(1,0)` across every click.

Attaching a UI from a second nvim over RPC does not work either: the embedded
child exits 1 as soon as `nvim_ui_attach` succeeds and the first `redraw`
notification goes out, with or without the drill config.

What does work is a real pty (`os.forkpty`) plus the real SGR escape sequences
a terminal sends — `ESC [ < btn ; col ; row M` press, `... m` release, `btn+32`
drag — decoded by nvim's own terminal input parser, exactly as under iTerm2.
State is read back over `--listen` + `--remote-expr` rather than by scraping
the screen. That is `mouse_drive.py` / `suite_mouse.sh`.

Two traps in there, both paid for:

* `'mousetime'` is 500 ms. The driver's `click()` deliberately waits longer
  than that between press and release, so two `click()` calls are two SINGLE
  clicks, never a double. `double_click()` writes all four sequences in one
  `write()`.
* read cursor/line state with `.rstrip('\n')`, **not** `.strip()` — the latter
  eats the leading indentation that half these cases exist to assert.

### 9. Bad probe keys to avoid

`ZZ` in Normal mode is write-and-quit — an early probe silently exited nvim
before it could log anything. `Q` raises `E354`.

---

## What the probes revealed about the config itself

**`<C-c>` in Select mode is broken today** (`nvimrc.lua:73`,
`map("s", "<C-c>", '<C-g>"+ygv<C-g>')`).

When Select mode was entered *from Insert mode* (which is the only way it
happens in this config — `<S-Arrow>` from `startinsert`), finishing the Visual
operator returns you to **Insert mode**, not Normal mode. Step-by-step from
probe6.log, fixture `alpha bravo`, selection `alpha`:

```
@after-C-g   mode=v      line=[alpha bravo]      -- Select -> Visual, fine
@after-yank  mode=i      line=[alpha bravo]      -- "+y  -> back to INSERT (!)
@after-gv    mode=i      line=[gvalpha bravo]    -- "gv" TYPED as literal text
```

Net effect of pressing `<C-c>` on a selection: the clipboard is correct
(`reg+ = alpha`) but the buffer becomes `gvalpha bravo`.

This is the same mechanism behind bug report #4: any Select-mode mapping whose
RHS continues after an operator will have its remaining characters typed into
the buffer, because the operator dropped back into Insert mode. `<C-x>`
(`'<C-g>"+d'`) escapes this only because nothing follows the operator — and
indeed it lands you in Insert mode, which is why `cut_ctrl_x_leaves_you_typing`
passes.
