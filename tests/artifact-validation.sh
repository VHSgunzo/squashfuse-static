#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

mkdir "$TMP/good"
printf '%s\n' \
    '.global _start' \
    '.text' \
    '_start:' \
    '    mov $60, %rax' \
    '    xor %rdi, %rdi' \
    '    syscall' >"$TMP/static.s"
cc -nostdlib -static "$TMP/static.s" -o "$TMP/good/squashfuse-musl-mimalloc-x86_64"
cp "$TMP/good/squashfuse-musl-mimalloc-x86_64" "$TMP/good/squashfuse_ll-musl-mimalloc-x86_64"
RELEASE_DIR="$TMP/good" "$ROOT/scripts/validate-artifacts.sh" x86_64
printf 'ok - valid static x86_64 artifact pair accepted\n'

mkdir "$TMP/wrong"
cp "$TMP/good/squashfuse-musl-mimalloc-x86_64" "$TMP/wrong/squashfuse-musl-mimalloc-ppc64"
cp "$TMP/good/squashfuse_ll-musl-mimalloc-x86_64" "$TMP/wrong/squashfuse_ll-musl-mimalloc-ppc64"
if error=$(RELEASE_DIR="$TMP/wrong" "$ROOT/scripts/validate-artifacts.sh" ppc64 2>&1); then
    fail 'wrong-machine artifacts should fail'
fi
case $error in
    *"expected ELF64 PowerPC64 big endian"*) ;;
    *) fail "wrong-machine diagnostic: $error" ;;
esac
printf 'ok - wrong machine/endian pair rejected\n'

mkdir "$TMP/dynamic"
printf '%s\n' 'int main(void) { return 0; }' >"$TMP/main.c"
cc "$TMP/main.c" -o "$TMP/dynamic/squashfuse-musl-mimalloc-x86_64"
cp "$TMP/dynamic/squashfuse-musl-mimalloc-x86_64" "$TMP/dynamic/squashfuse_ll-musl-mimalloc-x86_64"
if error=$(RELEASE_DIR="$TMP/dynamic" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'PT_INTERP artifacts should fail'
fi
case $error in
    *'PT_INTERP'*) ;;
    *) fail "dynamic diagnostic: $error" ;;
esac
printf 'ok - dynamic artifact pair rejected\n'

mkdir "$TMP/needed"
printf '%s\n' '#include <stdio.h>' 'int main(void) { return puts("dynamic dependency"); }' >"$TMP/needed.c"
cc -shared -fPIC -Wl,--no-as-needed "$TMP/needed.c" -lc -o "$TMP/needed/squashfuse-musl-mimalloc-x86_64"
cp "$TMP/needed/squashfuse-musl-mimalloc-x86_64" "$TMP/needed/squashfuse_ll-musl-mimalloc-x86_64"
if ! LC_ALL=C readelf -d "$TMP/needed/squashfuse-musl-mimalloc-x86_64" | grep -E '\(NEEDED\)|0x0*1[[:space:]]' >/dev/null; then
    fail 'DT_NEEDED regression fixture has no NEEDED entry'
fi
if LC_ALL=C readelf -l "$TMP/needed/squashfuse-musl-mimalloc-x86_64" | grep -E 'INTERP|Requesting program interpreter' >/dev/null; then
    fail 'DT_NEEDED regression fixture unexpectedly has PT_INTERP'
fi
if error=$(RELEASE_DIR="$TMP/needed" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'DT_NEEDED artifacts without PT_INTERP should fail'
fi
case $error in
    *'DT_NEEDED'*) ;;
    *) fail "DT_NEEDED diagnostic: $error" ;;
esac
printf 'ok - DT_NEEDED artifact without PT_INTERP rejected\n'

: >"$TMP/good/squashfuse-musl-mimalloc-x86_64"
chmod +x "$TMP/good/squashfuse-musl-mimalloc-x86_64"
if error=$(RELEASE_DIR="$TMP/good" "$ROOT/scripts/validate-artifacts.sh" x86_64 2>&1); then
    fail 'zero-byte artifact should fail'
fi
case $error in
    *'nonzero executable'*) ;;
    *) fail "zero-byte diagnostic: $error" ;;
esac
printf 'ok - zero-byte artifact rejected\n'
