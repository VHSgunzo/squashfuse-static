#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$ROOT/build.sh
BUILD_ENV=$ROOT/lib/build-env.sh
VALIDATOR=$ROOT/scripts/validate-artifacts.sh
README=$ROOT/README.md

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

# Preserve static linkage at the linker while selecting GCC's static-PIE
# driver mode explicitly. Passing both GCC driver modes (-static -static-pie)
# produces a crashing ET_DYN executable with Alpine's LoongArch toolchain.
grep -F -- '-I$BUILD_PREFIX/include -static-pie' "$BUILD_ENV" >/dev/null || fail 'explicit static PIE compile flags are missing'
grep -F -- '-Wl,-static -static-pie' "$BUILD_ENV" >/dev/null || fail 'static linker plus explicit PIE flags are missing'
if grep -F -- '-I$BUILD_PREFIX/include -static -static-pie' "$BUILD_ENV" >/dev/null ||
   grep -F -- '-L$BUILD_PREFIX/lib --static -static-pie' "$BUILD_ENV" >/dev/null; then
    fail 'conflicting GCC -static and -static-pie driver modes remain'
fi
for flag in -Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants
do
    grep -F -- "$flag" "$BUILD_ENV" >/dev/null || fail "legacy CFLAGS lost $flag"
done
for flag in -Wl,--gc-sections -Wl,--strip-all
do
    grep -F -- "$flag" "$BUILD_ENV" >/dev/null || fail "legacy LDFLAGS lost $flag"
done
printf '%s\n' 'ok - explicit static PIE retains legacy optimization and link flags'

if grep -F -- '--whole-archive' "$BUILD" >/dev/null; then
    fail 'mimalloc is force-linked with --whole-archive'
fi
grep -F 'LIBS="-lmimalloc"' "$BUILD" >/dev/null || fail 'mimalloc is not a conventional configure LIBS dependency'
grep -F 'make V=1' "$BUILD" >/dev/null || fail 'final squashfuse link commands are not captured verbosely'
grep -F 'verify_mimalloc_link_log' "$BUILD" >/dev/null || fail 'verbose final link position is not verified'
grep -F 'mimalloc: warning:' "$VALIDATOR" >/dev/null || fail 'published binaries are not checked for mimalloc evidence'
printf '%s\n' 'ok - mimalloc uses conventional final linkage and is verified in the binary'

SUPER_STRIP_COMMIT=9c57e288d8b2e0f90c9a15a4223331d1e7b43515
grep -F "SUPER_STRIP_COMMIT=$SUPER_STRIP_COMMIT" "$BUILD" >/dev/null || fail 'super-strip commit is not pinned'
grep -F 'checkout_pinned_source . "$SUPER_STRIP_COMMIT"' "$BUILD" >/dev/null || fail 'super-strip checkout is not verified'
grep -F 'make CC="$BUILD_CC"' "$BUILD" >/dev/null || fail 'sstrip is not built for the build host'
grep -F "CFLAGS='-O2 -Ielfrw' CPPFLAGS= LDFLAGS=" "$BUILD" >/dev/null ||
    fail 'host sstrip compile does not isolate its required include and flags'
grep -F 'AR=ar RANLIB=ranlib' "$BUILD" >/dev/null || fail 'host sstrip archive tools can leak from target toolchain'
grep -F 'for staged_name in "$first_name" "$second_name"' "$BUILD" >/dev/null || fail 'both staged outputs are not selected for sstrip'
grep -F '"$SSTRIP" "$staged_binary"' "$BUILD" >/dev/null || fail 'staged outputs are not sstripped'
sstrip_line=$(grep -nF '"$SSTRIP" "$staged_binary"' "$BUILD" | cut -d: -f1)
validate_line=$(grep -nF 'RELEASE_DIR=$staged_release "$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"' "$BUILD" | cut -d: -f1)
[ "$sstrip_line" -lt "$validate_line" ] || fail 'staged pair is validated before sstrip'
grep -F 'Start of section headers:' "$VALIDATOR" >/dev/null || fail 'validator does not require removed section headers'
grep -F 'Type:' "$VALIDATOR" | grep -F 'DYN' >/dev/null || fail 'validator does not require ET_DYN'
printf '%s\n' 'ok - pinned host sstrip processes staged outputs before validation'

grep -F 'static PIE (`ET_DYN`)' "$README" >/dev/null || fail 'README omits explicit static PIE contract'
grep -F 'zero section headers' "$README" >/dev/null || fail 'README omits sstrip section-header contract'
grep -F 'normal final `-lmimalloc`' "$README" >/dev/null || fail 'README omits conventional mimalloc linkage'
grep -F '28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b' "$README" >/dev/null || fail 'README omits Alpine 3.24 digest'
printf '%s\n' 'ok - documentation states the restored binary contract'
