# drill on WSL

Short version: `./install.sh` and go. It checks what is missing, prints the
exact command, and asks before running it. This page is the *why* behind the
few places WSL is not just Linux, and what was measured rather than assumed.

Everything here was verified on Ubuntu 22.04 under WSL2 with WSLg, in Windows
Terminal, against Neovim 0.11–0.12.

## The clipboard

Nvim finds a provider by itself. What WSLg gives you is the **Wayland and X
server**, not the clipboard clients — `wl-clipboard` and `xclip` are ordinary
packages you still have to install (`install.sh` offers them). Once one is
installed *and* WSLg is running, it is wired straight to the Windows clipboard
in both directions — copy in drill, paste in a browser, and back — and nothing
in drill overrides that.

The fallback appears whenever no supported provider is **usable** — which is
not the same as absent. That includes WSL with no WSLg, no X server and no
`win32yank.exe`; it also includes a WSLg session where the client packages were
never installed, or where `DISPLAY` is set but the server behind it does not
answer. `clipboard=unnamedplus` with no provider
does not fail loudly — it makes `Ctrl+C` copy nothing, `Ctrl+V` paste nothing,
and **`Ctrl+V` over a selection delete the selection and put nothing back**. So
on that box `nvimrc.lua` wires the register to `clip.exe` for copy and
`powershell.exe Get-Clipboard` for paste.

Two things to know about that path: every paste really asks Windows, which costs
about 0.4s (a cache would answer with what *you* last copied and silently ignore
the browser, which is most of what this register is for); and paste strips the
`\r` that `Get-Clipboard` returns, because nvim splits on `\n` only and every
line would otherwise keep a literal carriage return.

If you would rather have the fast native path on a display-less box, put
`win32yank.exe` on your PATH and nvim will find it with no config at all.

## The timer's sound and notification

This is where WSL is least like Linux, and both surprises are the same shape: a
tool that is **installed and does not work**.

```console
$ pw-play /usr/share/sounds/freedesktop/stereo/complete.oga
remote error: id=3 seq:7 res:-2 (No such file or directory): no node available
exit 1

$ notify-send drill test
GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown:
  The name org.freedesktop.Notifications was not provided by any .service files
exit 1
```

WSLg exposes PulseAudio, not PipeWire, and ships no notification daemon. So
`drill.sh` believes the **exit code**, not whether a process launched, and walks
each chain until something actually succeeds:

| | order |
|---|---|
| sound | `afplay` (macOS) → `paplay` / `pw-play` / `aplay` → PowerShell `SoundPlayer` → terminal bell |
| notification | `osascript` (macOS) → `notify-send` → Windows toast via PowerShell |

On this box `paplay` wins the sound chain (install `pulseaudio-utils`) and the
PowerShell toast wins the notification chain. If you run a notification daemon,
`notify-send` starts working and takes over — nothing needs changing.

The toast returning success means Windows *accepted* it. Whether it appears on
screen is still up to Focus Assist and your notification settings.

## Which `python3`

WSL appends the Windows PATH to yours. On a box with no Linux python installed,
`python3` resolves to the Store App Execution Alias under
`/mnt/c/.../WindowsApps` — a stub that opens the Microsoft Store instead of
running your file. It would do that inside a 15-row split, so `Ctrl+R` and
`Ctrl+E` would both look broken for a reason nothing on screen explains.

`install.sh` refuses to proceed on that, and `nvimrc.lua` walks past anything
under `/mnt` when picking an interpreter. On a healthy box neither does
anything.

## `Ctrl+Shift+Q`

Press it. It works — but not by the route it uses on a Mac, and that is worth
knowing if you ever wonder why `Ctrl+Q` also quits here.

`Ctrl+Shift+Q` only exists as a distinct key when the terminal negotiates CSI-u.
In the legacy encoding Shift is dropped from a control chord, so `Ctrl+Q` and
`Ctrl+Shift+Q` are the same byte — `0x11` — and nothing downstream can tell them
apart. **Windows Terminal 1.24 does not negotiate CSI-u with nvim**, so the
chord arrives as plain `<C-q>` and the `<C-S-q>` mapping is never reached.

So on WSL, `nvimrc.lua` also binds what actually arrives:

| | |
|---|---|
| insert mode, `Ctrl+Q` (and therefore `Ctrl+Shift+Q`) | the quit prompt |
| terminal mode — i.e. inside the REPL | the quit prompt, so you can leave without pressing `Ctrl+E` first |
| normal mode, `Ctrl+Q` | still visual block, untouched |

Two consequences. `Ctrl+Q` on its own quits from insert *and from inside the
interpreter* too — the prompt defaults to **Cancel**, so a slip costs one
keystroke. And insert-mode
`Ctrl+Q` is no longer vanilla vim's literal-insert; in a Python scratchpad where
`Ctrl+V` is already paste, that was close to unreachable anyway.

Gated on **WSL**, not on the protocol — there is no runtime signal for whether
CSI-u was negotiated (`vim.g.termfeatures` is `nil` even in a real TUI on 0.12),
so the binding is installed on every WSL session. If yours *does* speak CSI-u,
`Ctrl+Shift+Q` reaches its own mapping as normal and you additionally get bare
`Ctrl+Q` quitting from insert, losing literal-insert there. Off WSL none of it
applies and `Ctrl+Q` keeps every meaning it had.

**Normal mode is the gap.** `Ctrl+Q` in normal mode is visual block, and it is
the only way to reach one — `Ctrl+V` there is paste. So on a terminal without
CSI-u, pressing `Ctrl+Shift+Q` from normal mode gives you a visual block, not
the prompt. That is a deliberate trade: quitting from normal mode still has
`:qa!`, while visual block would have nothing left. If you are in normal mode
and want the prompt, press `i` first, or use `:qa!`.

**Nothing automated can check the CSI-u half.** `suite_quit.sh` writes
`ESC[113;6u` straight onto the pty, so it passes on a terminal where the chord
could never arrive; `demo.sh --check` cannot answer it either, and says so
rather than guessing — `--remote-send` consumes nvim's key *notation*, so it
delivers `<C-S-q>` to the mapping and never exercises the terminal encoding at
all. (An earlier version of this page said it collapsed the chord. It does not;
that claim was measured against a screenless nvim and is retracted.) Which is
why this needed a human to press it.

## Keep `DRILL_HOME` off `/mnt/c`

Writes to the Windows filesystem through DrvFs are far slower than to ext4, and
drill auto-saves about 0.7s after you stop typing. The default `~/drill` is on
ext4 and is where you want it.

## Alt, not Option

`KEYS.md` says Option+click because that is the macOS reflex it accommodates. On
WSL the same key is Alt, and the handling is identical — Alt+click and
Ctrl+click are both just clicks, not vim surprises.

## Running the tests

```sh
./tests/run.sh      # 722 cases
```

Needs a clipboard provider on PATH; `run.sh` warns up front if there is none,
because several cases assert the real `+` register and would otherwise look
like a broken keybinding. See [testing.md](testing.md).
