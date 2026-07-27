#!/usr/bin/env bash
#
# Fail if an ELF references a glibc symbol version newer than the allowed floor.
#
# libCoD2x.so is LD_PRELOADed into the original 2006 cod2_lnxded binary, which
# itself needs no more than GLIBC_2.1.3. Server operators commonly run old
# distributions, and the auto-updater replaces libCoD2x.so in place - so raising
# the glibc requirement breaks their servers on the next update, with no build
# time warning.
#
# Building on a modern distribution does exactly that. glibc 2.34 merged
# libpthread into libc, so a build there emits pthread_* @ GLIBC_2.34 and every
# pre-2.34 host fails to load the library.
#
# Usage: check_glibc_floor.sh <elf> <max-version>
#    e.g. check_glibc_floor.sh bin/linux/libCoD2x.so GLIBC_2.25

set -euo pipefail

elf=${1:?usage: $0 <elf> <max-glibc-version, e.g. GLIBC_2.25>}
max=${2:?usage: $0 <elf> <max-glibc-version, e.g. GLIBC_2.25>}

if [ ! -r "$elf" ]; then
    echo "error: cannot read '$elf'" >&2
    exit 1
fi

mapfile -t versions < <(objdump -T "$elf" | grep -oE 'GLIBC_[0-9.]+' | sort -uV)

if [ "${#versions[@]}" -eq 0 ]; then
    echo "error: no GLIBC_* version references found in '$elf' - wrong file, or not a dynamic ELF?" >&2
    exit 1
fi

found=${versions[-1]}

echo "$elf references: ${versions[*]}"
echo "highest required: $found (allowed: $max)"

# sort -V orders GLIBC_2.9 before GLIBC_2.25, which is what we want.
newest=$(printf '%s\n%s\n' "$found" "$max" | sort -uV | tail -1)

if [ "$newest" != "$max" ]; then
    cat >&2 <<EOF

FAIL: glibc floor regressed from $max to $found.

This build would not load on hosts with glibc older than ${found#GLIBC_}.
Servers auto-update libCoD2x.so in place, so shipping this bricks them.

Build in a container whose glibc is old enough (see .github/workflows/build.yml),
or - if the bump is intentional and the compatibility cost is accepted - raise
the expected floor where this script is invoked.
EOF
    exit 1
fi

echo "OK: glibc floor intact."
