# TODO

Feature ideas indexed for later. Nothing here is implemented yet.

## LeetCode-style preloaded imports

Every drill program should run — and drop into the REPL — with the usual
interview toolkit already imported, the way LeetCode's environment has it baked
in. Nothing appears in the code you type; the magic happens at run time.

Candidates to preload:

- `collections` — `Counter`, `deque`, `defaultdict`
- `itertools` — `permutations`, `combinations`
- `heapq`, `math`, `functools`, `bisect`

Likely mechanism when built: drill already owns every execution path — `r`/`ri`
in `drill.sh`, `Ctrl+R` / `Ctrl+E` in `nvimrc.lua` — so a preamble can be
injected there (e.g. `PYTHONSTARTUP` for the `-i`/REPL paths, or a small runner
that does the imports and then execs the file). Stdlib only, no pip installs.

The reference doc that prompted this also covers `requests`, but that is
third-party — decide at implementation time whether it fits drill's
stock-Python value.
