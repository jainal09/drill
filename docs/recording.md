# Recording the demo

`./demo.sh` is the guided tour as a script: it drives the editor through every
feature by itself — typing, clicking, running, narrating — so the whole thing
can be screen-recorded with nobody at the keyboard.

Thirteen chapters: shell, typing, comment, indent, select, clipboard, find,
mouse, autosave, undo, run, repl, quit.

```sh
./demo.sh --list              # print the chapters
./demo.sh --only find,mouse   # run just those
./demo.sh --speed 0.5         # halve the pauses (2 doubles them)
```

## How the keys are sent

How the keys are sent matters if you are recording. `--keys system`, the
default where macOS permits it, presses real OS key events, so a keycast app
can show them — the terminal has to stay frontmost, because the keys go
wherever focus is. `--keys socket` sends straight into nvim over `--listen`:
reliable everywhere, ssh and Linux included, and needs no permissions, but the
keys never touch the OS so a keycast app shows nothing. Either way the
on-screen caption names the key being pressed.
