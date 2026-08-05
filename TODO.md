# TODO

## WSL port — every feature available under WSL, no macOS regression

drill runs on macOS today and `README.md` already claims Linux, but on a stock
WSL2 box several headline features break *quietly*, which is worse than failing
loudly:

| Feature | Promised | Actual on stock WSL |
|---|---|---|
| `Ctrl+C/X/V` system clipboard | `README.md`, `KEYS.md` | **broken** — `clipboard=unnamedplus` with no provider; `Ctrl+V` over a selection deletes and pastes nothing |
| timer sound + desktop notification | `README.md` | **silent** — `afplay`/`osascript` absent, `paplay`/`notify-send` not installed |
| `d two-sum` at all | `README.md` | `install.sh` says `apt install neovim` → Ubuntu ships **0.6.1**, which its own 0.9 gate then rejects |
| `demo.sh` | `docs/recording.md` | every keystroke shells out to `bc`, which Ubuntu/WSL does not ship |
| `./tests/run.sh` | `docs/testing.md` | 4 clipboard cases fail; `tests/bin/timeout` shadows real GNU `timeout` |

"Stock WSL2 box" is not reproducible on its own, so: every row above was
measured on **Ubuntu 22.04 (jammy) under WSL2**, kernel
`6.18.33.2-microsoft-standard-WSL2`, WSLg present, **Windows Terminal
1.24.11911.0**, zsh with oh-my-zsh. Neovim **0.12.4** locally (linuxbrew) and
**0.11.0** in CI — both well past the 0.9 gate, so none of these are
version-too-old artifacts. Where a row depends on a package being absent
(`bc`, `paplay`, `notify-send`) that is the default state of that image, not a
box someone stripped.

**The rule that keeps macOS safe:** every change is additive and
capability-probed, never `if not mac`. The existing macOS branch stays *first*
in every chain with its exact semantics. `pbcopy`, `afplay` and `osascript` all
exist on a Mac, so every new branch below is dead code there.

Landed as a stack of PRs, one per checkpoint, each based on the previous.

### Checkpoints

- [x] **0 — `wsl/00-todo`** · this checklist, plus a baseline `./tests/run.sh`
      run on unmodified `main` so "no regression" has something to measure against
- [x] **1 — `wsl/01-install`** · `install.sh`: package-manager detect, prompted
      auto-install (`--yes`, non-interactive when stdin is not a tty), a nvim
      version parse that survives `-dev` strings, and correct nvim install hints
      per platform. (`drill.sh`'s only `apt install` line is for fzf, which has
      no version gate and is not stale — nothing to do there.)
      *Gate: `install.sh` into a temp `DRILL_HOME`.*
- [x] **2 — `wsl/02-clipboard`** · `nvimrc.lua`: native provider first, a
      `clip.exe` + `powershell Get-Clipboard` shim only when no *usable*
      provider is found — "usable" being the load-bearing word, since an
      installed `xclip` with no display is discovered and still cannot copy
      anything, and an empty clipboard is not the same as an absent provider;
      and resolve `python3` past the `/mnt/.../WindowsApps` Store alias
      that WSL's PATH interop otherwise hands us.
      *Gate: `suite_config.sh` clipboard cases green; copy/paste both directions by hand.*
- [x] **3 — `wsl/03-timer`** · `drill.sh`: `run()` reported success for a
      process that merely launched, so a player that exits non-zero silenced
      the bell fallback too — check the exit code, add a timeout. Extend the
      sound chain (`paplay`/`pw-play`/`aplay`/PowerShell) and the notification
      chain (`notify-send`/PowerShell toast), and guard `pgrep`.

      Scope grew once the suite could run here: **`pgrep -f "$TAG"` matches any
      process that merely *mentions* the tag**, so `t` was stopping strangers —
      including the test shell that holds the tag in its own `-c` string, which
      is why 30 of 36 timer cases failed on Linux before any of this. Confirm
      each candidate is an interpreter with `ps -o comm=` instead.
      *Gate: `suite_timer.sh` 36/36 (was 6/36); sound and notification both fire.*
- [x] **4 — `wsl/04-demo-tests`** · `demo.sh` `bc` → `awk`; `tests/bin/timeout`
      delegates to real GNU `timeout` when one exists instead of shadowing it;
      `tests/run.sh` says so loudly when no clipboard provider is on PATH, and
      counts failing *suites* rather than summing exit codes — it called 30
      broken timer cases "2 FAILING CASE(S)", small enough to read as a flake.

      Also: `demo.sh --check` failed its `Ctrl+Shift+Q` case on every Linux box
      and told you to record with `--keys socket`, which is the mode it was
      already in. `--remote-send` collapses `<C-S-q>` to `<C-q>`, whose
      literal-insert then eats the cancelling `c` — the exact Shift-drop that
      made CSI-u necessary. Socket mode cannot ask that question, so it skips
      it and says why.
      *Gate: full `./tests/run.sh` 556/556; `./demo.sh --check` clean.*
- [x] **5 — `wsl/05-ci-docs`** · `.github/workflows/tests.yml` running the suite
      on `ubuntu-latest` under `xvfb` with `xclip`, so the clipboard cases are
      real; `docs/wsl.md`; requirement lines in `README.md`, `KEYS.md`,
      `docs/testing.md`.
      *Gate: CI green on the PR itself.*

### Measured by a human, and then fixed

`Ctrl+Shift+Q` did not work on WSL. Nothing automated could have told us:
`suite_quit.sh` writes `ESC[113;6u` straight onto the pty, so it passes on a
terminal where the chord could never arrive, and `demo.sh --check` cannot send
CSI-u over `--remote-send` at all. It took pressing the key.

Windows Terminal 1.24 is new enough to speak CSI-u and does not negotiate it
with nvim, so the chord arrives as the legacy `0x11` — plain `<C-q>` — and the
`<C-S-q>` mapping is never reached. On WSL the config now also binds
insert-mode `<C-q>`, which is what actually arrives: you press the documented
chord and it works. Normal-mode `<C-q>` stays visual block, and off WSL nothing
changes. Written up in [docs/wsl.md](docs/wsl.md).

### Not in scope, deliberately

`preload.py` (already pure stdlib and fully portable), every `tests/suite_*.sh`
and `tests/*_drive.py` (`os.forkpty` + `termios`/`fcntl` + SGR-1006 is
Linux-native already), and the whole AppleScript block in `demo.sh`, which is
already gated behind `uname = Darwin` and whose `--keys socket` sibling is what
runs everywhere else.
