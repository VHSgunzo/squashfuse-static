#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

fail()
{
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

[ -r "$ROOT/lib/target.sh" ] || fail 'target contract helper is missing'
# shellcheck source=../lib/target.sh
# shellcheck disable=SC1091
. "$ROOT/lib/target.sh"

for helper in lib/target.sh lib/release.sh lib/source.sh tests/target-contract.sh tests/clean-checkout.sh
do
    if git -C "$ROOT" check-ignore --no-index -q -- "$helper"; then
        ignore_status=0
    else
        ignore_status=$?
    fi
    case $ignore_status in
        0) fail "$helper must be trackable" ;;
        1) ;;
        *) fail "git check-ignore failed for $helper (exit $ignore_status)" ;;
    esac
done
printf 'ok - required contract files are trackable\n'

assert_mapping()
{
    arch=$1
    expected=$2
    actual=$(target_triplet "$arch") || fail "$arch should be supported"
    [ "$actual" = "$expected" ] ||
        fail "$arch mapped to '$actual', expected '$expected'"
    printf 'ok - %s maps to %s\n' "$arch" "$expected"
}

assert_mapping x86_64 x86_64-linux-musl
assert_mapping aarch64 aarch64-linux-musl
assert_mapping riscv64 riscv64-linux-musl
assert_mapping loongarch64 loongarch64-linux-musl
assert_mapping ppc64 powerpc64-linux-musl
assert_mapping ppc64le powerpc64le-linux-musl

assert_glibc_mapping()
{
    arch=$1
    expected=$2
    actual=$(target_glibc_triplet "$arch") || fail "$arch should have a glibc multiarch mapping"
    [ "$actual" = "$expected" ] ||
        fail "$arch mapped to glibc triplet '$actual', expected '$expected'"
    printf 'ok - %s maps to glibc multiarch %s\n' "$arch" "$expected"
}

assert_glibc_mapping x86_64 x86_64-linux-gnu
assert_glibc_mapping aarch64 aarch64-linux-gnu
assert_glibc_mapping riscv64 riscv64-linux-gnu
assert_glibc_mapping loongarch64 loongarch64-linux-gnu
assert_glibc_mapping ppc64 powerpc64-linux-gnu
assert_glibc_mapping ppc64le powerpc64le-linux-gnu

if error=$(target_triplet unknown-arch 2>&1); then
    fail 'unknown architecture should fail'
fi
case $error in
    *"unsupported TARGET_ARCH 'unknown-arch'"*) ;;
    *) fail "unknown architecture error was not clear: $error" ;;
esac
printf 'ok - unknown architecture fails clearly\n'

TARGET_ARCH=aarch64
[ "$(resolve_target_arch)" = aarch64 ] || fail 'explicit TARGET_ARCH was not preserved'
unset TARGET_ARCH

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
fakebin=$test_tmp/bin
mkdir "$fakebin"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'case ${1:-} in' \
    '    -m) printf "%s\\n" x86_64 ;;' \
    '    -s) printf "%s\\n" Linux ;;' 'esac' >"$fakebin/uname"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" called >"$SIDE_EFFECT"' \
    'exit 77' >"$fakebin/apk"
chmod +x "$fakebin/uname" "$fakebin/apk"

# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' '[ "${1:-}" = -print-multiarch ] || exit 2' \
    'printf "%s\\n" "$COMPILER_MULTIARCH"' >"$fakebin/cc-multiarch"
chmod +x "$fakebin/cc-multiarch"

assert_glibc_libdir()
{
    arch=$1
    compiler_result=$2
    expected=$3
    actual=$(COMPILER_MULTIARCH=$compiler_result \
        target_glibc_libdir "$arch" "$fakebin/cc-multiarch") ||
        fail "could not select glibc libdir for $arch"
    [ "$actual" = "$expected" ] ||
        fail "$arch selected libdir '$actual', expected '$expected'"
}

assert_glibc_libdir x86_64 x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
assert_glibc_libdir aarch64 aarch64-linux-gnu /usr/lib/aarch64-linux-gnu
assert_glibc_libdir ppc64 powerpc64-linux-gnu /usr/lib/powerpc64-linux-gnu
assert_glibc_libdir ppc64le powerpc64le-linux-gnu /usr/lib/powerpc64le-linux-gnu
assert_glibc_libdir ppc64 '../host/lib' /usr/lib/powerpc64-linux-gnu
assert_glibc_libdir ppc64le x86_64-linux-gnu /usr/lib/powerpc64le-linux-gnu
[ "$(target_glibc_libdir aarch64 /bin/false)" = /usr/lib/aarch64-linux-gnu ] ||
    fail 'failed compiler query did not use deterministic target fallback'
printf 'ok - glibc libdir selection validates compiler output and never falls back to /usr/lib\n'

[ "$(PATH="$fakebin:$PATH" resolve_target_arch)" = x86_64 ] ||
    fail 'TARGET_ARCH did not default from uname -m'
printf 'ok - TARGET_ARCH defaults from uname -m\n'

[ -r "$ROOT/lib/source.sh" ] || fail 'squashfuse source helper is missing'
# shellcheck source=../lib/source.sh
# shellcheck disable=SC1091
. "$ROOT/lib/source.sh"
source_fixture=$test_tmp/squashfuse-source
mkdir "$source_fixture"
git -C "$source_fixture" init -q
printf '%s\n' old >"$source_fixture/revision"
git -C "$source_fixture" add revision
git -C "$source_fixture" -c user.name=Test -c user.email=test@example.invalid \
    commit -q -m old
git -C "$source_fixture" tag 0.1.0
expected_source_revision=$(git -C "$source_fixture" rev-parse HEAD)
printf '%s\n' new >"$source_fixture/revision"
git -C "$source_fixture" -c user.name=Test -c user.email=test@example.invalid \
    commit -q -am new
git -C "$source_fixture" tag 9.9.9
source_version=$(checkout_squashfuse_version "$source_fixture" 0.1.0) ||
    fail 'could not check out and describe requested squashfuse version'
[ "$(git -C "$source_fixture" rev-parse HEAD)" = "$expected_source_revision" ] ||
    fail 'squashfuse source was described before checking out the requested revision'
case $source_version in
    0.1.0.r0.g*) ;;
    *) fail "source version '$source_version' does not describe requested revision 0.1.0" ;;
esac
if checkout_squashfuse_version "$source_fixture" missing-revision >/dev/null 2>&1; then
    fail 'missing requested squashfuse revision should fail instead of describing current HEAD'
fi
grep -F 'checkout_squashfuse_version' "$ROOT/build.sh" >/dev/null ||
    fail 'build does not derive its source path/version after checkout'
printf 'ok - squashfuse version and source path revision are derived after checkout\n'

side_effect=$test_tmp/side-effect
if mismatch_error=$(PATH="$fakebin:$PATH" SIDE_EFFECT="$side_effect" TARGET_ARCH=ppc64 \
    "$ROOT/build.sh" 2>&1); then
    fail 'mismatched TARGET_ARCH should fail'
fi
case $mismatch_error in
    *"TARGET_ARCH 'ppc64' does not match build machine 'x86_64'"*) ;;
    *) fail "mismatched target error was not clear: $mismatch_error" ;;
esac
[ ! -e "$side_effect" ] || fail 'mismatched target reached package/build side effects'
printf 'ok - mismatched TARGET_ARCH fails before side effects\n'

if unsupported_error=$(PATH="$fakebin:$PATH" SIDE_EFFECT="$side_effect" \
    TARGET_ARCH=unknown-arch "$ROOT/build.sh" 2>&1); then
    fail 'unsupported TARGET_ARCH should fail'
fi
case $unsupported_error in
    *"unsupported TARGET_ARCH 'unknown-arch'"*) ;;
    *) fail "unsupported target error was not clear: $unsupported_error" ;;
esac
[ ! -e "$side_effect" ] || fail 'unsupported target reached package/build side effects'
printf 'ok - unsupported TARGET_ARCH fails before side effects\n'

TARGET_ARCH=ppc64
TARGET_TRIPLET=stale-triplet
export TARGET_ARCH TARGET_TRIPLET
caller_scratch=keep
resolve_target_contract || fail 'target contract could not be resolved'
[ "$TARGET_ARCH" = ppc64 ] || fail 'resolved TARGET_ARCH changed unexpectedly'
[ "$TARGET_TRIPLET" = powerpc64-linux-musl ] || fail 'resolved target triplet is wrong'
[ "$caller_scratch" = keep ] || fail 'target helper clobbered caller scratch state'
if env | grep -E '^TARGET_(ARCH|TRIPLET)=' >/dev/null; then
    fail 'target contract variables leaked into child environments'
fi
printf 'ok - resolved target variables stay local to the build script\n'

if grep -E '(WITH_UPX|VENDOR_UPX|UPX_VERSION|super-strip|sstrip|upx --force-overwrite)' \
    "$ROOT/build.sh" >/dev/null; then
    fail 'build.sh still mandates UPX or host sstrip post-processing'
fi
printf 'ok - build.sh has no mandatory host post-processing\n'

capture=$test_tmp/toolchain-env
build_error=$test_tmp/toolchain-error
probe_root=$test_tmp/project
mkdir -p "$probe_root/lib"
cp "$ROOT/build.sh" "$probe_root/build.sh"
cp "$ROOT/lib/target.sh" "$probe_root/lib/target.sh"
cp "$ROOT/lib/release.sh" "$probe_root/lib/release.sh"
cp "$ROOT/lib/source.sh" "$probe_root/lib/source.sh"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$fakebin/apt"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'env >"$TOOLCHAIN_CAPTURE"' 'exit 78' >"$fakebin/git"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" 1' >"$fakebin/nproc"
chmod +x "$fakebin/apt" "$fakebin/git" "$fakebin/nproc"
if PATH="$fakebin:$PATH" TOOLCHAIN_CAPTURE="$capture" TARGET_ARCH=x86_64 \
    CC=custom-cc CXX=custom-cxx AR=custom-ar RANLIB=custom-ranlib \
    STRIP=custom-strip CROSS_COMPILE=custom- \
    CMAKE_TOOLCHAIN_FILE=/toolchain.cmake CMAKE_PREFIX_PATH=/cmake-prefix \
    MESON_CROSS_FILE=/meson.cross PKG_CONFIG=custom-pkg-config \
    PKG_CONFIG_PATH=/pkg/path PKG_CONFIG_LIBDIR=/pkg/lib \
    PKG_CONFIG_SYSROOT_DIR=/pkg/sysroot CFLAGS=-caller-cflag \
    LDFLAGS=-caller-ldflag MAKEFLAGS=-caller-makeflag \
    "$probe_root/build.sh" >/dev/null 2>"$build_error"; then
    fail 'toolchain probe unexpectedly completed the build'
fi
if [ ! -r "$capture" ]; then
    sed -n '1,80p' "$build_error" >&2
    fail 'toolchain probe did not reach the build command'
fi
for expected in \
    'CC=custom-cc' 'CXX=custom-cxx' 'AR=custom-ar' 'RANLIB=custom-ranlib' \
    'STRIP=custom-strip' 'CROSS_COMPILE=custom-' \
    'CMAKE_TOOLCHAIN_FILE=/toolchain.cmake' 'CMAKE_PREFIX_PATH=/cmake-prefix' \
    'MESON_CROSS_FILE=/meson.cross' 'PKG_CONFIG=custom-pkg-config' \
    'PKG_CONFIG_PATH=/pkg/path' 'PKG_CONFIG_LIBDIR=/pkg/lib' \
    'PKG_CONFIG_SYSROOT_DIR=/pkg/sysroot'
do
    grep -Fx "$expected" "$capture" >/dev/null ||
        fail "externally supplied toolchain value was not preserved: $expected"
done
for variable in CFLAGS LDFLAGS MAKEFLAGS
do
    grep "^$variable=.*caller" "$capture" >/dev/null ||
        fail "externally supplied $variable was not preserved"
done
printf 'ok - externally supplied compiler and toolchain environment is preserved\n'

glibc_capture=$test_tmp/glibc-env
if PATH="$fakebin:$PATH" TOOLCHAIN_CAPTURE="$glibc_capture" \
    COMPILER_MULTIARCH=x86_64-linux-gnu TARGET_ARCH=x86_64 \
    CC="$fakebin/cc-multiarch" "$probe_root/build.sh" >/dev/null 2>&1; then
    fail 'glibc libdir probe unexpectedly completed the build'
fi
[ -r "$glibc_capture" ] || fail 'glibc libdir probe did not reach the build command'
grep -Fx 'TARGET_LIBDIR=/usr/lib/x86_64-linux-gnu' "$glibc_capture" >/dev/null ||
    fail 'selected target libdir was not exported to dependency builds'
grep -Fx 'PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig' \
    "$glibc_capture" >/dev/null ||
    fail 'pkg-config does not consistently use the selected target libdir'
if grep -F 'libdir="/usr/lib/"' "$probe_root/build.sh" >/dev/null; then
    fail 'build still silently falls back to the host /usr/lib directory'
fi
printf 'ok - glibc dependency archives and pkg-config use the selected target libdir\n'

fixture_root=$probe_root
rm -rf "$fixture_root/build" "$fixture_root/release"
mkdir -p "$fixture_root/release"
for asset in \
    squashfuse-musl-mimalloc-x86_64 \
    squashfuse_ll-musl-mimalloc-x86_64-upx \
    squashfuse-glibc-x86_64 squashfuse_ll-glibc-x86_64-upx \
    squashfuse-musl-mimalloc-aarch64 squashfuse_ll-glibc-ppc64le-upx \
    notes-x86_64.txt
do
    printf 'stale %s\n' "$asset" >"$fixture_root/release/$asset"
done
PATH="$fakebin:$PATH" TOOLCHAIN_CAPTURE="$capture" TARGET_ARCH=x86_64 \
    "$fixture_root/build.sh" >/dev/null 2>&1 || :
for removed in \
    squashfuse-musl-mimalloc-x86_64 \
    squashfuse_ll-musl-mimalloc-x86_64-upx \
    squashfuse-glibc-x86_64 squashfuse_ll-glibc-x86_64-upx
do
    [ ! -e "$fixture_root/release/$removed" ] ||
        fail "current-target stale release asset was not removed: $removed"
done
for preserved in \
    squashfuse-musl-mimalloc-aarch64 squashfuse_ll-glibc-ppc64le-upx \
    notes-x86_64.txt
do
    [ -e "$fixture_root/release/$preserved" ] ||
        fail "cleanup removed unrelated release asset: $preserved"
done
printf 'ok - cleanup removes only current-target release and legacy UPX assets\n'

[ -r "$ROOT/lib/release.sh" ] || fail 'release installation helper is missing'
# shellcheck source=../lib/release.sh
# shellcheck disable=SC1091
. "$ROOT/lib/release.sh"
release_test=$test_tmp/release-install
mkdir "$release_test"
source_binary=$release_test/squashfuse
printf 'new binary\n' >"$source_binary"
chmod +x "$source_binary"
printf 'old binary\n' >"$release_test/squashfuse-musl-mimalloc-x86_64"
install_release_binary "$source_binary" "$release_test" \
    squashfuse-musl-mimalloc-x86_64 || fail 'atomic release installation failed'
cmp -s "$source_binary" "$release_test/squashfuse-musl-mimalloc-x86_64" ||
    fail 'installed release binary differs from source'
[ -x "$release_test/squashfuse-musl-mimalloc-x86_64" ] ||
    fail 'installed release binary lost its executable mode'
set -- "$release_test"/.squashfuse-musl-mimalloc-x86_64.tmp.*
[ ! -e "$1" ] || fail 'successful atomic install left a temporary file'
printf 'ok - release binary installation uses an adjacent temporary file\n'

printf 'old binary\n' >"$release_test/squashfuse-musl-mimalloc-x86_64"
failing_bin=$test_tmp/failing-copy-bin
mkdir "$failing_bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'for destination do :; done' \
    'printf "%s\\n" partial >"$destination"' 'exit 79' >"$failing_bin/cp"
chmod +x "$failing_bin/cp"
if PATH="$failing_bin:$PATH" install_release_binary "$source_binary" \
    "$release_test" squashfuse-musl-mimalloc-x86_64; then
    fail 'release installation should fail when its copy fails'
fi
[ "$(sed -n '1p' "$release_test/squashfuse-musl-mimalloc-x86_64")" = \
    'old binary' ] || fail 'failed install replaced the existing release binary'
set -- "$release_test"/.squashfuse-musl-mimalloc-x86_64.tmp.*
[ ! -e "$1" ] || fail 'failed atomic install left a temporary file'
printf 'ok - failed atomic install preserves the prior output\n'

readme_opening=$(sed -n '3p' "$ROOT/README.md")
case $readme_opening in
    *'musl + mimalloc outputs'*'glibc outputs'*) ;;
    *) fail 'README opening does not distinguish musl + mimalloc outputs from glibc outputs' ;;
esac
printf 'ok - README opening distinguishes musl + mimalloc and glibc outputs\n'

for expected in \
    'TARGET_ARCH=x86_64' 'TARGET_ARCH=aarch64' \
    'x86_64, aarch64, riscv64, loongarch64, ppc64, ppc64le' \
    'native/emulated' 'next phase' \
    'squashfuse-musl-mimalloc-x86_64' \
    'squashfuse_ll-musl-mimalloc-x86_64'
do
    grep -F "$expected" "$ROOT/README.md" >/dev/null ||
        fail "README is missing target-contract documentation: $expected"
done
if grep -E 'release/[^[:space:]]+-upx' "$ROOT/README.md" >/dev/null; then
    fail 'README still advertises UPX release outputs'
fi
printf 'ok - README documents the native/emulated non-UPX target contract\n'
