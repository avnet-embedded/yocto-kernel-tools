#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# Assert that the bundled Kconfiglib evaluates conditional dependencies
# ("depends on X if Y") with the same semantics as the kernel's C kconfig:
#
#     "depends on X if Y"  ==  "depends on (X || (Y == n))"
#
# where the "(Y == n)" comparison is distributed down to the leaf symbols
# (kernel expr.c: expr_trans_compare(cond, E_EQUAL, &symbol_no)). This is
# correct for tristate operands in compound conditions, unlike a naive "!Y"
# (kconfiglib's NOT is 2 - val, so !m == m).
#
# Unlike the kernel Kconfig parse test (parse-only), this checks computed
# *values*, so it would catch a semantic regression even though the kernel
# Kconfig data would still parse.
#
# Exit 0 if all cases match, 1 otherwise.

import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_ktroot = os.path.abspath(os.path.join(_here, "..", "..", ".."))
sys.path.insert(0, os.path.join(_ktroot, "Kconfiglib"))

import kconfiglib  # noqa: E402

os.environ.setdefault("srctree", _here)
os.environ.setdefault("KERNELVERSION", "0.0.0")

N, M, Y = 0, 1, 2          # tristate values: n / m / y
_NAME = {N: "n", M: "m", Y: "y"}

# (description, {symbol: value}, target symbol, expected tristate value)
CASES = [
    # single bool condition: dep = X || (Y == n)
    ("bool cond, Y=n          -> dep ignored",      dict(Y=N, X=N), "T_BOOL",     Y),
    ("bool cond, Y=y X=n      -> X required, fails", dict(Y=Y, X=N), "T_BOOL",     N),
    ("bool cond, Y=y X=y      -> X required, ok",    dict(Y=Y, X=Y), "T_BOOL",     Y),

    # "X if X" tristate idiom: dep = A || (A == n)  -> caps at A
    ("tri X-if-X, A=m         -> capped at m",       dict(A=M),      "T_TRI",      M),
    ("tri X-if-X, A=n         -> dep ignored",       dict(A=N),      "T_TRI",      Y),
    ("tri X-if-X, A=y         -> ok",                dict(A=Y),      "T_TRI",      Y),

    # compound tristate condition: dep = X || ((A==n) && (B==n))
    # The decisive case: A=m,B=n,X=n. Faithful "(cond==n)" -> n (disabled).
    # A naive "!cond" would give !(A||B) = !m = m -> WRONG (capped, not disabled).
    ("compound, A=m B=n X=n   -> DISABLED (faithful)", dict(A=M, B=N, X=N), "T_COMPOUND", N),
    ("compound, A=m B=n X=y   -> X satisfies",         dict(A=M, B=N, X=Y), "T_COMPOUND", Y),
    ("compound, A=n B=n X=n   -> cond false, ignored", dict(A=N, B=N, X=N), "T_COMPOUND", Y),
]


def run():
    kconf_path = os.path.join(_here, "Kconfig")
    failures = 0
    for desc, assigns, target, expected in CASES:
        kc = kconfiglib.Kconfig(kconf_path, warn=False)
        kc.syms["MODULES"].set_value(Y)        # allow 'm' for tristate symbols
        for sym, val in assigns.items():
            kc.syms[sym].set_value(val)
        got = kc.syms[target].tri_value
        ok = got == expected
        failures += 0 if ok else 1
        print("  [{}] {:42s} {} expected={} got={}".format(
            "PASS" if ok else "FAIL", desc, target, _NAME[expected], _NAME[got]))
    return failures


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
