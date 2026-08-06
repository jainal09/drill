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

The fallback only appears when that probe comes up **empty**: WSL with no WSLg,
no X server, and no `win32yank.exe`. `clipboard=unnamedplus` with no provider
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

```
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

## Which python3

WSL appends the Windows PATH to yours. On a box with no Linux python installed,
`python3` resolves to the Store App Execution Alias under
`/mnt/c/.../WindowsApps` — a stub that opens the Microsoft Store instead of
running your file. It would do that inside a 15-row split, so `Ctrl+R` and
`Ctrl+E` would both look broken for a reason nothing on screen explains.

`install.sh` refuses to proceed on that, and `nvimrc.lua` walks past anything
under `/mnt` when picking an interpreter. On a healthy box neither does
anything.

## `Ctrl+Shift+Q`

`Ctrl+Shift+Q` only exists as a distinct key when the terminal negotiates
CSI-u. In the legacy encoding Shift is dropped from a control chord, so
`Ctrl+Q` and `Ctrl+Shift+Q` are the same byte and nothing downstream can tell
them apart.

**Measured: Windows Terminal 1.24 does not negotiate CSI-u with nvim**, so the
chord arrives as plain `<C-q>`. Updating Windows Terminal does not fix that —
1.24 is already new enough to speak the protocol and simply does not. The WSL
`<C-q>` binding that makes the chord work lands with the quit checkpoint later
in this stack; until then the way out is `:qa!`.

**Nothing automated can check this.** `suite_quit.sh` writes `ESC[113;6u`
straight onto the pty, so it passes on a terminal where the chord could never
arrive, and `demo.sh --check` reaches the mapping over `--remote-send`, which
speaks nvim key notation rather than terminal bytes — neither one is pressing a
real key. That is why this needed a human.

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
./tests/run.sh      # 556 cases
```

Needs a clipboard provider on PATH; `run.sh` warns up front if there is none,
because several cases assert the real `+` register and would otherwise look
like a broken keybinding. See [testing.md](testing.md).
