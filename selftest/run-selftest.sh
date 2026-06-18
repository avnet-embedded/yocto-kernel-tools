#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# kern-tools self-test. Two independent checks, both hermetic (no kernel
# checkout, no compiler required):
#
#   1. Parser stress test -- unpack the synced kernel Kconfig test data and
#      confirm the bundled Kconfiglib can parse the whole thing via
#      symbol_why.py --selftest. This catches "the kernel grew a Kconfig
#      construct our Kconfiglib can't parse" (e.g. v7.0's "depends on X if Y")
#      regardless of whether we anticipated it. Refresh the data with
#      ./sync-kernel-kconfig.sh.
#
#   2. Semantic assertions -- run a tiny synthetic fixture through Kconfiglib and
#      check computed values, so a *semantic* regression (right parse, wrong
#      value) is caught even though the data would still parse.
#
# Exit 0 only if both pass.
set -u

here=$(dirname "$(readlink -f "$0")")
ktroot=$(dirname "$here")
sw="$ktroot/tools/symbol_why.py"
rc=0

echo "== kern-tools self-test =="

# ---- 1. kernel Kconfig parse -------------------------------------------------
testdata="$here/kconfig-test-data.tar.gz"
if [ -f "$testdata" ]; then
    echo "[1/2] kernel Kconfig parse ($(head -1 "$here/kconfig-test-data.manifest" 2>/dev/null))"
    tmp=$(mktemp -d)
    tar -xzf "$testdata" -C "$tmp"
    (
        cd "$tmp" || exit 1
        # Use the bundled dummy-tools so no real toolchain is needed.
        srctree=. ARCH=x86 SRCARCH=x86 KERNELVERSION=0.0.0 \
            CC=scripts/dummy-tools/gcc LD=scripts/dummy-tools/ld \
            HOSTCC=scripts/dummy-tools/gcc \
            python3 "$sw" --selftest --ksrc="."
    )
    if [ $? -eq 0 ]; then
        echo "      -> PASS"
    else
        echo "      -> FAIL (bundled Kconfiglib cannot parse the kernel Kconfig data)"
        rc=1
    fi
    rm -rf "$tmp"
else
    echo "[1/2] SKIP: no test data ($testdata). Generate it with ./sync-kernel-kconfig.sh <kernel-src>"
fi

# ---- 2. conditional-dependency semantics ------------------------------------
echo "[2/2] conditional-dependency semantics"
if python3 "$here/fixtures/conditional_dep/test_conditional_dep.py"; then
    echo "      -> PASS"
else
    echo "      -> FAIL (conditional-dep values diverge from kernel kconfig semantics)"
    rc=1
fi

echo "== self-test $( [ $rc -eq 0 ] && echo PASSED || echo FAILED ) =="
exit $rc
