# The LeetCode desk: run a drill file with the interview toolkit already
# imported. Counter, deque, heappush, permutations and friends are live
# without a single import line in the file, the way the judge's environment
# has them baked in. Typing the preamble is not the recall being drilled;
# using it is.
#
# r/ri and the editor's Ctrl+R / Ctrl+E all route through here when this file
# sits next to drill.sh; without it they fall back to plain python3 -- and
# plain python3 is the contract: names, argv, sys.path, tracebacks and exit
# codes must come out the same with or without the shim, toolkit aside.
# Stdlib only -- nothing to pip install, which is also why `requests` is
# not here.

import sys as _sys                        # plumbing, not toolkit: a file that
from os.path import (                     # wants sys must import it, exactly
    abspath as _abspath,                  # as it would under plain python3
    dirname as _dirname,
)

import bisect, collections, functools, heapq, itertools, math
from bisect import bisect_left, bisect_right, insort
from collections import Counter, OrderedDict, defaultdict, deque
from functools import lru_cache, reduce
from heapq import heapify, heappop, heappush, heappushpop, nlargest, nsmallest
from itertools import accumulate, chain, combinations, groupby, permutations, product
from math import ceil, comb, floor, gcd, inf, sqrt
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from functools import cache
except ImportError:                       # python < 3.9: same idea, spelled out
    cache = lru_cache(None)

if len(_sys.argv) < 2:
    _sys.exit("usage: python3 preload.py file.py [args...]")

_target = _sys.argv[1]
_sys.argv = _sys.argv[1:]                 # the file sees itself as the program

# plain python3 puts the SCRIPT's directory first on sys.path; the shim gets
# its own instead, which would break sibling imports in project folders (and
# let a drill file `import preload`). Hand the slot to the target.
_sys.path[0] = _dirname(_abspath(_target))

_code = None
try:
    with open(_target) as _fh:
        # compiled under the file's own name, so a traceback points at YOUR
        # line, not at this shim
        _code = compile(_fh.read(), _target, "exec")
except OSError as _e:
    # a typo'd `r name` should read exactly like plain python3: the one-line
    # error and exit 2. Not under -i though -- sys.exit there tracebacks INTO
    # the REPL, where plain python3 -i lands quietly after the same message.
    _sys.stderr.write("python3: can't open file %r: [Errno %s] %s\n"
                      % (_target, _e.errno, _e.strerror))
    if not _sys.flags.interactive:
        _sys.exit(2)

# the file gets every toolkit name but none of this plumbing -- the underscore
# prefix is what keeps the machinery out of your namespace
_ns = {_k: _v for _k, _v in globals().items() if not _k.startswith("_")}
_ns["__name__"] = "__main__"
_ns["__file__"] = _target

try:
    if _code is not None:
        exec(_code, _ns)
finally:
    # `python3 -i` lands the REPL in THIS module, so the file's names are
    # splashed back up for ri -- in a finally, because a file that raises
    # must still leave everything defined before the error inspectable at
    # the prompt, exactly as plain python3 -i does
    globals().update(_ns)
