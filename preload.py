# The LeetCode desk: run a drill file with the interview toolkit already
# imported. Counter, deque, heappush, permutations and friends are live
# without a single import line in the file, the way the judge's environment
# has them baked in. Typing the preamble is not the recall being drilled;
# using it is.
#
# r/ri and the editor's Ctrl+R / Ctrl+E all route through here when this file
# sits next to drill.sh; without it they fall back to plain python3. Stdlib
# only -- nothing to pip install, which is also why `requests` is not here.

import sys

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

if len(sys.argv) < 2:
    sys.exit("usage: python3 preload.py file.py [args...]")

_target = sys.argv[1]
sys.argv = sys.argv[1:]                   # the file sees itself as the program

with open(_target) as _fh:
    # compiled under the file's own name, so a traceback points at YOUR line,
    # not at this shim
    _code = compile(_fh.read(), _target, "exec")

# the file gets every toolkit name but none of this plumbing -- the underscore
# prefix is what keeps _target and _code out of your namespace
_ns = {_k: _v for _k, _v in globals().items() if not _k.startswith("_")}
_ns["__name__"] = "__main__"
_ns["__file__"] = _target
exec(_code, _ns)

# `python3 -i` lands the REPL in THIS module, so the file's names have to be
# splashed back up for ri to keep its promise that they are live
globals().update(_ns)
