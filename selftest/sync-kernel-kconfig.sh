#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Regenerate selftest/kconfig-test-data.tar.gz from a kernel source tree.
#
#   usage: sync-kernel-kconfig.sh <path-to-kernel-source>
#
# Kconfiglib parses ONLY Kconfig files -- it does not look at Makefiles, C
# source or headers. However, scripts/Kconfig.include runs a handful of
# $(shell,...) macros at parse time (cc-version.sh, ld-version.sh, ...) guarded
# by $(error-if,...) that abort the parse if the toolchain can't be probed. So
# the self-contained test data needs three things:
#
#   1. every Kconfig* file
#   2. the scripts/*.sh helpers invoked from scripts/Kconfig.include
#   3. scripts/dummy-tools/ (the kernel's fake gcc/ld) so no real toolchain
#      is required to parse
#
# The result (~13M of text, ~2M gzipped) lets run-selftest.sh stress the
# bundled Kconfiglib against a real kernel's full Kconfig structure with no
# kernel checkout and no compiler present.
set -eu

ksrc=${1:?usage: sync-kernel-kconfig.sh <kernel-source-dir>}
here=$(dirname "$(readlink -f "$0")")
out="$here/kconfig-test-data.tar.gz"
manifest="$here/kconfig-test-data.manifest"

[ -f "$ksrc/Kconfig" ] || { echo "ERROR: $ksrc does not look like a kernel source tree (no ./Kconfig)" >&2; exit 1; }

cd "$ksrc"
list=$(mktemp)
trap 'rm -f "$list"' EXIT

# 1. all Kconfig* files (prefer git for speed/cleanliness, fall back to find)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files | grep -E '(^|/)Kconfig' >> "$list"
else
    find . -type f -name 'Kconfig*' | sed 's|^\./||' >> "$list"
fi

# 2 + 3. the parse-time shell helpers and the dummy toolchain
for p in scripts/*.sh scripts/dummy-tools; do
    [ -e "$p" ] && find "$p" -type f >> "$list"
done

sort -u "$list" -o "$list"

tar -czf "$out" -T "$list"

ver=$(make -s kernelversion 2>/dev/null || echo unknown)
rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
stamp=$(date -u +%Y-%m-%dT%H:%MZ)
printf 'kernel %s (%s)\nsynced %s\n%s files, %s gzipped\n' \
    "$ver" "$rev" "$stamp" "$(wc -l < "$list")" "$(du -h "$out" | cut -f1)" > "$manifest"

echo "wrote $out ($(du -h "$out" | cut -f1)) from kernel $ver ($rev)"
echo "manifest: $manifest"
