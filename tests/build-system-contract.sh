#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
# shellcheck source=../lib/build-env.sh
. "$ROOT/lib/build-env.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/bin"
printf '%s\n' '#!/bin/sh' '[ "${1:-}" = -dumpmachine ] && printf "%s\n" x86_64-alpine-linux-musl' >"$TMP/bin/build-cc"
chmod +x "$TMP/bin/build-cc"
TARGET_ARCH=ppc64 TARGET_TRIPLET=powerpc64-linux-musl BUILD_MODE=cross-musl BUILD_CC=$TMP/bin/build-cc
CC=/bin/true CXX=/bin/true AR=/bin/true RANLIB=/bin/true STRIP=/bin/true
configure_build_environment "$TMP/project"
[ "$BUILD_TRIPLET" = x86_64-alpine-linux-musl ] || fail 'cross build triplet'
[ "$BUILD_TRIPLET" != "$TARGET_TRIPLET" ] || fail 'build and host triplets conflated'
BUILD=$ROOT/build.sh
[ "$(grep -Fc -- '--build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET"' "$BUILD")" -ge 3 ] || fail 'Autotools dependencies and squashfuse need explicit triplets'
grep -F 'autoreconf -fi' "$BUILD" >/dev/null || fail 'stale Autotools metadata is not refreshed'
grep -F -- '--cross-file="$MESON_CROSS_FILE"' "$BUILD" >/dev/null || fail 'libfuse does not use Meson cross file'
grep -F 'CMAKE_TOOLCHAIN_FILE' "$BUILD" >/dev/null || fail 'mimalloc does not use CMake target toolchain'
grep -F 'po4a' "$BUILD" >/dev/null || fail 'XZ source bootstrap prerequisite po4a is not installed'
if grep -F 'make -C lib PREFIX="$BUILD_PREFIX" install)' "$BUILD" >/dev/null; then fail 'LZ4 install target attempts a shared build under static flags'; fi
grep -F 'lib/pkgconfig/liblz4.pc' "$BUILD" >/dev/null || fail 'LZ4 target pkg-config metadata is not installed explicitly'
if grep -E 'rm -f .*release/\$binary-musl-mimalloc-\$TARGET_ARCH"([[:space:]]|$)' "$BUILD" >/dev/null; then
    fail 'build deletes the current release pair before replacement is ready'
fi
grep -F 'staged_release=$work/release' "$BUILD" >/dev/null || fail 'built pair is not staged under the target work directory'
grep -F 'RELEASE_DIR=$staged_release "$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"' "$BUILD" >/dev/null ||
    fail 'both staged artifacts are not validated before publication'
grep -F 'publish_release_pair ' "$BUILD" >/dev/null || fail 'build does not transactionally publish the artifact pair'
publish_line=$(grep -nF 'publish_release_pair ' "$BUILD" | cut -d: -f1)
upx_line=$(grep -nF '"$HERE/release/$binary-musl-mimalloc-$TARGET_ARCH-upx"' "$BUILD" | cut -d: -f1)
[ "$upx_line" -gt "$publish_line" ] || fail 'stale UPX outputs are removed before successful pair replacement'
grep -F 'acquire_target_lock "$target_lock"' "$BUILD" >/dev/null || fail 'same-target builds are not locked'
printf 'ok - Autotools, Meson and CMake receive deterministic target contracts\n'
