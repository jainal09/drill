# Testing

Every keybinding is asserted by driving the **real** config with real keycodes
and diffing what comes out. Nothing is mocked: if a case passes, that keystroke
does that thing in this config.

```sh
./tests/run.sh            # 556 cases; exit 0 only if all pass
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
| `suite_projects.sh` | 40 | also not nvim — nested `d <dir> <name>` and `d search` against stubbed `nvim`/`fzf` binaries in a scratch `DRILL_HOME`, under **bash and zsh** — including that `..` cannot leave the bucket and bracketed names resolve literally |
| `suite_preload.sh` | 26 | the LeetCode desk: import-free files using the toolkit under `r`/`ri` in **bash and zsh** — shadowing, argv, `__name__`, exit codes, sibling imports in project folders, names still live at the prompt after a raise, a typo'd name getting python's own error, the plain-python3 fallback — plus a pty pass proving `Ctrl+R` and `Ctrl+E` route through the shim |
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

## Why some suites need a pty

Two suites cannot run headless at all, and one is not nvim. `--headless`
attaches no UI, so there is no screen grid and `nvim_input_mouse` is a silent
no-op — measured: it returns `true` and the cursor stays at `(1,0)` across every
click. The mouse and quit suites therefore run the real editor on a real pty and
write the real SGR escape sequences a terminal sends (`ESC [ < btn ; col ; row
M`), reading state back over `--listen`. The quit confirmation is pty-only for a
second, independent reason: a blocking prompt can be neither answered by
headless `feedkeys` nor read by any API — it is only ever *drawn*, so those
cases assert against the painted screen.

## What the gate needs

The gate needs four things the editor itself does not: `python3` for the pty
suites, `zsh` because the timer suite runs `drill.sh` under both shells, a
**clipboard provider** because several cases assert the real `+` register (with
none, they fail for a reason that has nothing to do with the mapping they are
named after — `run.sh` warns up front rather than letting that look like a
regression), and `perl` *only where there is no `timeout(1)` at all*, i.e.
macOS. `tests/bin/timeout` is that `alarm` shim; `run.sh` puts it on `PATH`
first, so on Linux it hands over to the real `timeout` rather than shadowing it
with something weaker.

CI runs the same script on `ubuntu-latest` under `xvfb` with `xclip`, so the
clipboard cases are real there too — see `.github/workflows/tests.yml`.

## One known flake, on WSL only

Roughly one full-suite run in three **on WSL**, one of the six cases in
`suite_config.sh` that assert register `+` fails — observed so far as
`ctrlc_select_linewise`, `ctrlc_visual_linewise` and `cut_ctrl_x_in_select`,
and there is no reason the other three are immune. It is always the same
signature: **the buffer is correct and `+` reads back empty**.

They pass when run alone (10/10, 3/3, 3/3 for the three above), and the
instrumented mapping shows `getregion` returning the right text every time — so
the selection and the keybinding are fine. What intermittently fails is the
write to the *system* clipboard under the load of a 556-case run.

It is not the provider. It reproduces with `wl-copy` (WSLg's default pick) and
again with `WAYLAND_DISPLAY` unset to force `xclip`, and in the same run one
register case passes while another fails. It predates the WSL port — it flaked on
unmodified `main` before any of this — and **CI has never hit it**, where a
single `xclip` under `xvfb` is evidently steadier than a WSLg session.

It is deliberately not papered over. A retry would hide a real clipboard
regression, and giving these cases a stub provider would break the one rule the
suite has: nothing here mocks anything. If you see this signature — buffer right, `+` empty — re-run that single case
before believing it. For example:

```sh
./tests/run_test.sh --name check --content 'aa\nbb\ncc' \
  --keys '<S-Down><S-Down><C-c>Z' --expect 'Zcc' --expect-reg '+=aa
bb'
```

If it passes alone, you saw the flake. If it fails alone, you have a real bug.

## Diagnostics

Two diagnostics come with the mouse suite. `tests/mousecheck.sh` says whether
your terminal sends mouse events at all and decodes the modifier field;
`tests/mousetrace.sh` records every key nvim actually receives while you click.

See [tests/NOTES.md](../tests/NOTES.md) for the harness mechanics — in
particular why keys need `feedkeys` mode `xt`, why the deferred `:startinsert`
swallows the first keystroke if you don't disarm it, and why a write from
inside an autocmd fires no `BufWritePost`, so a counter reads 0 while the file
is demonstrably being written.
