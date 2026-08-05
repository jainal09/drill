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

**The rule that keeps macOS safe:** every change is additive and
capability-probed, never `if not mac`. The existing macOS branch stays *first*
in every chain with its exact semantics. `pbcopy`, `afplay` and `osascript` all
exist on a Mac, so every new branch below is dead code there.

Landed as a stack of PRs, one per checkpoint, each based on the previous.

### Checkpoints

- [x] **0 — `wsl/00-todo`** · this checklist, plus a baseline `./tests/run.sh`
      run on unmodified `main` so "no regression" has something to measure against
- [ ] **1 — `wsl/01-install`** · `install.sh`: package-manager detect, prompted
      auto-install (`--yes`, non-interactive when stdin is not a tty), a nvim
      version parse that survives `-dev` strings, and correct nvim install hints
      per platform. Same stale `apt install` hint in `drill.sh` too.
      *Gate: `install.sh` into a temp `DRILL_HOME`.*
- [ ] **2 — `wsl/02-clipboard`** · `nvimrc.lua`: native provider first, a
      `clip.exe` + `powershell Get-Clipboard` shim only when the probe comes up
      empty; and resolve `python3` past the `/mnt/.../WindowsApps` Store alias
      that WSL's PATH interop otherwise hands us.
      *Gate: `suite_config.sh` clipboard cases green; copy/paste both directions by hand.*
- [ ] **3 — `wsl/03-timer`** · `drill.sh`: `run()` currently reports success for
      a process that merely launched, so a missing sound file silences the bell
      fallback too — check the exit code and add a timeout. Then extend the
      sound chain (`paplay`/`pw-play`/`aplay`/PowerShell) and the notification
      chain (`notify-send`/PowerShell toast), and guard `pgrep`.
      *Gate: `suite_timer.sh` green; `t 0.05` gives sound and a notification.*
- [ ] **4 — `wsl/04-demo-tests`** · `demo.sh` `bc` → `awk`; `tests/bin/timeout`
      delegates to real GNU `timeout` when one exists instead of shadowing it;
      `tests/run.sh` says so loudly when no clipboard provider is on PATH.
      *Gate: full `./tests/run.sh` 556/556; `./demo.sh --check`.*
- [ ] **5 — `wsl/05-ci-docs`** · `.github/workflows/tests.yml` running the suite
      on `ubuntu-latest` under `xvfb` with `xclip`, so the four clipboard cases
      are real; `docs/wsl.md`; requirement lines in `README.md`, `KEYS.md`,
      `docs/testing.md`.
      *Gate: CI green on the PR itself.*

### Open question, to be measured not assumed

`Ctrl+Shift+Q` only exists when the terminal negotiates CSI-u. Windows Terminal
≥1.22 does; older builds use win32-input-mode and the chord never fires, leaving
`:qa!` as the only way out. `suite_quit.sh` synthesises `ESC[113;6u` straight
onto the pty, so **the suite cannot catch this** — it has to be pressed by hand
in Windows Terminal. Finding gets recorded in `docs/wsl.md` at checkpoint 5.

### Not in scope, deliberately

`preload.py` (already pure stdlib and fully portable), every `tests/suite_*.sh`
and `tests/*_drive.py` (`os.forkpty` + `termios`/`fcntl` + SGR-1006 is
Linux-native already), and the whole AppleScript block in `demo.sh`, which is
already gated behind `uname = Darwin` and whose `--keys socket` sibling is what
runs everywhere else.
