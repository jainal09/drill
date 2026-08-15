# Cmd on a Mac

drill's chords live on **Ctrl** — `Ctrl+C`, `Ctrl+V`, `Ctrl+Z` — and on a Mac
that looks like a mistake until you know the constraint: **a program running
in a terminal never sees the Cmd key.** The terminal emulator owns it. Cmd+C
is the terminal's own Copy, Cmd+V its Paste, Cmd+A selects the scrollback,
Cmd+Q quits the terminal itself — each one is handled (or swallowed) before
nvim gets a byte, and the classic terminal encoding has no way to spell a Cmd
chord at all. That is why every editor that lives in a terminal — vim, emacs,
nano, micro — is a Ctrl editor, even on a Mac.

Two Cmd habits survive that with **zero setup**, which is why they already
work in drill:

- **Cmd+V pastes.** The terminal pastes your clipboard into the session as
  input, drill speaks bracketed paste, so indented Python lands unstaircased —
  in the file and at the `>>>` prompt alike.
- **Shift+drag, then Cmd+C** copies with the terminal's own selection (Shift
  is the modifier this config deliberately leaves to the terminal).

Everything else — Cmd+Z, Cmd+A, Cmd+/ — dies at the terminal. The Ctrl set is
the one drill can promise everywhere.

## The part that is fixable

The CSI-u / kitty keyboard protocol *can* encode a Cmd chord (Cmd is the
"super" modifier, bit 8 — Cmd+Z is `ESC [ 122;9 u`), and nvim decodes those
sequences unconditionally — measured on this config: feeding the raw bytes
fires a `<D-z>` mapping with no protocol negotiation at all. The only missing
piece is a terminal willing to **send** them instead of eating the chord.

So drill binds every editor chord on Cmd too, same modes, same handlers:

| Forwarded chord | Does |
|---|---|
| `Cmd+S` | save |
| `Cmd+C` | copy the selection — **with no selection, the line** (VS Code habit; insert-mode `Cmd+C` is *not* Esc — that job stays on `Ctrl+C`) |
| `Cmd+X` | cut the selection |
| `Cmd+V` | paste — including in the REPL, where `Ctrl+V` is left to python |
| `Cmd+A` | select all |
| `Cmd+F` | find |
| `Cmd+Z` | undo |
| `Cmd+Shift+Z` | redo (the mac redo; `Ctrl+Y` still works everywhere) |
| `Cmd+/` | comment / uncomment |
| `Cmd+Q` | quit, with the same confirmation as `Ctrl+Shift+Q` |
| `Cmd+←` / `Cmd+→` | start / end of line |
| `Cmd+↑` / `Cmd+↓` | start / end of file |
| `Cmd+Shift+arrows` | the same four motions, selecting |
| `Cmd+Backspace` | delete to the start of the line |

The cursor chords ride nvim's own `<Home>`/`<End>`/`<C-Home>`/`<C-End>`,
which are already in drill's `keymodel`, so the shifted forms select exactly
like Shift+arrows and typing over that selection replaces it.

**Every other Cmd chord is swallowed.** This is load-bearing, not tidiness:
an *unmapped* forwarded chord does not die quietly in nvim — measured, a bare
`<D-w>` typed the literal text `<D-w>` into the buffer in insert, replaced
the selection with it in Select mode, and ate a character in normal mode. So
a reflexive Cmd+W or Cmd+B from a mac hand would spray key notation into
your file. drill floors every printable Cmd chord to a no-op — in the REPL
too, where the junk would have gone to python — and binds the useful ones on
top.

On a terminal that forwards nothing, all of this is inert and costs nothing.
`Ctrl+E` and `Ctrl+R` stay Ctrl-only on purpose: they are drill's own keys,
not system chords, and keeping them in one place keeps the muscle memory
portable.

**Check what your terminal actually sends** at any point with
`~/drill/tests/keycheck.sh` — run it in the window you drill in, press the
chord, read the bytes. A forwarded Cmd+Z reads `^[[122;9u`.

## iTerm2 — one extra step after install

1. Open **Settings → Profiles →** *your profile* **→ Keys → General**.
2. Set **"Left Command key"** to **Super**.
3. Open drill and press `Cmd+Z`. If it does not undo, run
   `~/drill/tests/keycheck.sh` in that window, press the chord, and read
   what actually arrived.

Per iTerm2's documentation this remap is live **only while the running
program uses the kitty keyboard protocol** — nvim negotiates it, your shell
does not — so inside drill, Cmd chords arrive as `<D-...>` keys, and at the
prompt Cmd is still ordinary macOS Cmd: Cmd+V pastes, Cmd+Q quits, nothing
about the rest of your terminal life changes. Needs iTerm2 3.5+; leave the
*Right* Command key alone and you keep a stock Cmd on one thumb at all times.

Prefer cherry-picking chords instead? **Settings → Profiles → Keys → Key
Mappings → +**, action **"Send Escape Sequence"**, one mapping per chord (the
leading ESC is added for you):

| Chord | Esc+ |
|---|---|
| Cmd+Z | `[122;9u` |
| Cmd+Shift+Z | `[90;9u` |
| Cmd+/ | `[47;9u` |
| Cmd+A | `[97;9u` |
| Cmd+C | `[99;9u` |
| Cmd+X | `[120;9u` |
| Cmd+V | `[118;9u` |
| Cmd+S | `[115;9u` |
| Cmd+F | `[102;9u` |
| Cmd+← / Cmd+→ | `[1;9D` / `[1;9C` |
| Cmd+↑ / Cmd+↓ | `[1;9A` / `[1;9B` |
| Cmd+Backspace | `[127;9u` |

(For a Cmd+Shift+arrow, the modifier is `10` instead of `9`.)

The cost of this second route: key mappings are per-profile, not per-program,
so a remapped chord sends those bytes at the shell prompt too. Map Cmd+Z and
Cmd+/ (which the shell never needed) and skip Cmd+C/Cmd+V (whose terminal
versions you probably want to keep) and the trade mostly disappears.

## kitty

kitty owns Cmd chords through its own keybindings; an **unmapped** chord is
reported to a program that speaks the keyboard protocol. So free the ones you
want drill to have, in `~/.config/kitty/kitty.conf`:

```
map cmd+z
map cmd+shift+z
map cmd+/
map cmd+a
```

A bare `map` with no action removes kitty's binding. Recent kitty can also
scope an unmap to particular windows (`map --when-focus-on ...`) if you want
a chord back at the shell — see kitty's mapping documentation.

## Ghostty

Unbind Ghostty's own use of a chord and it can reach the program
(`~/.config/ghostty/config`):

```
keybind = cmd+z=ignore
keybind = cmd+shift+z=ignore
```

`ignore` consumes Ghostty's default action so the chord is not taken; note
that macOS intercepts *menu* shortcuts before Ghostty sees them, so a few
chords (Cmd+C among them) may need their menu equivalent changed in System
Settings → Keyboard → Keyboard Shortcuts → App Shortcuts. `keycheck.sh` is
the arbiter of what actually got through.

## Terminal.app

Cannot do this. Apple's Terminal speaks no CSI-u at all — the same reason
`Ctrl+Shift+Z` and `Ctrl+Shift+Q` do not exist there — and its keyboard
mapping UI refuses plain Cmd chords. Use the Ctrl set, or a different
terminal.
