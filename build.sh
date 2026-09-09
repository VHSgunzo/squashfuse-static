#!/bin/sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"
# shellcheck source=lib/target.sh
. "$HERE/lib/target.sh"
# shellcheck source=lib/release.sh
. "$HERE/lib/release.sh"
# shellcheck source=lib/build-env.sh
. "$HERE/lib/build-env.sh"
# shellcheck source=lib/source-pins.sh
. "$HERE/lib/source-pins.sh"
resolve_target_contract
validate_build_mode

SQUASHFUSE_VERSION=0.6.3
LIBFUSE_VERSION=3.18.2
SQUASHFUSE_COMMIT=1a211e20fff55e9ce4c74ad03f0aa26a7b760bd3 # 0.6.3
MIMALLOC_COMMIT=8c532c32c3c96e5ba1f2283e032f69ead8add00f # 2.1.7
LIBFUSE_COMMIT=033844748010a3b8265bf1c90b9ae8ffe4cd9ca7 # 3.18.2
XZ_COMMIT=9fc6f5cd8774ebef8d4e030f7081fb6984c0dc3f # 5.8.2
LZO_COMMIT=0083878c235a89ef96a009d1ff0b500f3a364e4b # no tags
ZLIB_COMMIT=e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca # 1.3.2
LZ4_COMMIT=0774d05537f9762f838f7ab541b7765f1a729cb5 # 1.10.0
ZSTD_COMMIT=d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a # 1.5.7
SUPER_STRIP_COMMIT=9c57e288d8b2e0f90c9a15a4223331d1e7b43515 # master after 3.0a
NO_CLEANUP=${NO_CLEANUP:-0}

[ "$(uname -s)" = Linux ] || { printf '%s\n' '= Linux is required for static binaries' >&2; exit 1; }
if command -v apt-get >/dev/null 2>&1 && ! command -v apk >/dev/null 2>&1; then
    export TARGET_ARCH
    exec "$HERE/scripts/build-glibc.sh"
fi
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache musl-dev gcc g++ git gettext-dev automake autoconf libtool \
        make cmake linux-headers pkgconf meson ninja python3 bash perl curl tar gzip \
        po4a help2man
fi
configure_build_environment "$HERE"
validate_compiler_target
MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }-j$(nproc)"; export MAKEFLAGS
work=$BUILD_ROOT/work-$TARGET_ARCH
mkdir -p "$HERE/release"
target_lock=$HERE/release/.build-$TARGET_ARCH.lock
target_lock_owner=$$
lock_acquired=false
lock_attempted=false
cleanup_target_build()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$lock_acquired" = true ]; then
        release_target_lock "$target_lock" "$target_lock_owner"
    elif [ "$lock_attempted" = true ]; then
        # Covers a signal after atomic lock creation but before acquisition returns.
        release_target_lock "$target_lock" "$target_lock_owner"
    fi
    exit "$result"
}
trap cleanup_target_build EXIT
trap 'exit 1' HUP INT TERM
lock_attempted=true
acquire_target_lock "$target_lock" "$target_lock_owner"
lock_acquired=true
rm -rf "$work" "$BUILD_PREFIX"
staged_release=$work/release
mkdir -p "$staged_release" "$BUILD_PREFIX/include" "$BUILD_PREFIX/lib/pkgconfig"

case $TARGET_ARCH in
    x86_64) cmake_processor=x86_64; meson_cpu_family=x86_64; meson_cpu=x86_64 ;;
    aarch64) cmake_processor=aarch64; meson_cpu_family=aarch64; meson_cpu=aarch64 ;;
    riscv64) cmake_processor=riscv64; meson_cpu_family=riscv64; meson_cpu=riscv64 ;;
    loongarch64) cmake_processor=loongarch64; meson_cpu_family=loongarch64; meson_cpu=loongarch64 ;;
    ppc64) cmake_processor=ppc64; meson_cpu_family=ppc64; meson_cpu=ppc64 ;;
    ppc64le) cmake_processor=ppc64le; meson_cpu_family=ppc64; meson_cpu=ppc64le ;;
esac
cmake_toolchain=$BUILD_ROOT/toolchain-$TARGET_ARCH.cmake
cat >"$cmake_toolchain" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $cmake_processor)
set(CMAKE_C_COMPILER "$CC")
set(CMAKE_CXX_COMPILER "$CXX")
set(CMAKE_AR "$AR")
set(CMAKE_RANLIB "$RANLIB")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH "$BUILD_PREFIX")
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
MESON_CROSS_FILE=$BUILD_ROOT/meson-$TARGET_ARCH.ini
cat >"$MESON_CROSS_FILE" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'pkg-config'
[host_machine]
system = 'linux'
cpu_family = '$meson_cpu_family'
cpu = '$meson_cpu'
endian = '$(case $TARGET_ARCH in ppc64) printf big;; *) printf little;; esac)'
[properties]
needs_exe_wrapper = $(case $BUILD_MODE in cross-musl) printf true;; *) printf false;; esac)
EOF
export MESON_CROSS_FILE
cd "$work"

echo '= build pinned host super-strip'
git clone https://github.com/aunali1/super-strip.git
(cd super-strip; checkout_pinned_source . "$SUPER_STRIP_COMMIT"; \
    make CC="$BUILD_CC" AR=ar RANLIB=ranlib CFLAGS='-O2 -Ielfrw' CPPFLAGS= LDFLAGS=)
SSTRIP=$work/super-strip/sstrip
[ -x "$SSTRIP" ] || { printf '%s\n' 'host sstrip build did not produce an executable' >&2; exit 1; }

echo '= build pinned mimalloc'
git clone https://github.com/microsoft/mimalloc.git
(cd mimalloc; checkout_pinned_source . "$MIMALLOC_COMMIT"; cmake -S . -B build \
    -DCMAKE_TOOLCHAIN_FILE="$cmake_toolchain" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_SHARED=OFF -DMI_BUILD_TESTS=OFF -DMI_LIBC_MUSL=ON \
    -DMI_SECURE=OFF -DMI_SKIP_COLLECT_ON_EXIT=ON; \
    cmake --build build --target mimalloc-static; cp build/libmimalloc.a "$BUILD_PREFIX/lib/"; cp -R include/. "$BUILD_PREFIX/include/")

echo '= build pinned compression libraries'
git clone https://git.tukaani.org/xz.git
(cd xz; checkout_pinned_source . "$XZ_COMMIT"; ./autogen.sh; ./configure --build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET" --prefix="$BUILD_PREFIX" --enable-static --disable-shared --disable-doc; make; make install)
git clone https://github.com/nemequ/lzo.git
(cd lzo; checkout_pinned_source . "$LZO_COMMIT"; autoreconf -fi; ./configure --build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET" --prefix="$BUILD_PREFIX" --enable-static --disable-shared; make; make install)
git clone https://github.com/madler/zlib.git
(cd zlib; checkout_pinned_source . "$ZLIB_COMMIT"; CHOST="$TARGET_TRIPLET" ./configure --static --prefix="$BUILD_PREFIX"; make libz.a; make install)
git clone https://github.com/lz4/lz4.git
(cd lz4; checkout_pinned_source . "$LZ4_COMMIT"; make -C lib CC="$CC" AR="$AR" RANLIB="$RANLIB" liblz4.a; \
    cp lib/liblz4.a "$BUILD_PREFIX/lib/"; \
    cp lib/lz4.h lib/lz4frame.h lib/lz4frame_static.h lib/lz4hc.h "$BUILD_PREFIX/include/"; \
    { printf 'prefix=%s\n' "$BUILD_PREFIX"; printf '%s\n' 'libdir=${prefix}/lib' 'includedir=${prefix}/include' '' 'Name: liblz4' 'Description: fast lossless compression algorithm library' 'Version: 1.10.0' 'Libs: -L${libdir} -llz4' 'Cflags: -I${includedir}'; } >"$BUILD_PREFIX/lib/pkgconfig/liblz4.pc")
git clone https://github.com/facebook/zstd.git
(cd zstd; checkout_pinned_source . "$ZSTD_COMMIT"; make -C lib CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" libzstd.a; make -C lib PREFIX="$BUILD_PREFIX" install-static install-includes)

echo "= build pinned libfuse ${LIBFUSE_VERSION}"
git clone https://github.com/libfuse/libfuse.git
(cd libfuse; checkout_pinned_source . "$LIBFUSE_COMMIT"; meson setup build --cross-file="$MESON_CROSS_FILE" --prefix="$BUILD_PREFIX" --libdir=lib --default-library=static -Dexamples=false -Dtests=false; meson compile -C build; meson install -C build)

echo "= build pinned squashfuse ${SQUASHFUSE_VERSION}"
git clone https://github.com/vasi/squashfuse.git
(cd squashfuse; checkout_pinned_source . "$SQUASHFUSE_COMMIT"; autoreconf -fi; \
    PKG_CONFIG='pkg-config --static' ./configure --build="$BUILD_TRIPLET" --host="$TARGET_TRIPLET" --prefix="$BUILD_PREFIX" --enable-static --disable-shared \
        LIBS="-lmimalloc"; \
    make V=1 >"$work/squashfuse-link.log" 2>&1 || { cat "$work/squashfuse-link.log"; exit 1; }; \
    cat "$work/squashfuse-link.log"; verify_mimalloc_link_log "$work/squashfuse-link.log"; \
    make DESTDIR="$work/install" install)
first_name=squashfuse-musl-mimalloc-$TARGET_ARCH
second_name=squashfuse_ll-musl-mimalloc-$TARGET_ARCH
install_release_binary "$work/install$BUILD_PREFIX/bin/squashfuse" "$staged_release" "$first_name"
install_release_binary "$work/install$BUILD_PREFIX/bin/squashfuse_ll" "$staged_release" "$second_name"
for staged_name in "$first_name" "$second_name"
do
    staged_binary=$staged_release/$staged_name
    before_size=$(wc -c <"$staged_binary")
    "$SSTRIP" "$staged_binary"
    after_size=$(wc -c <"$staged_binary")
    printf '= sstrip %s: %s -> %s bytes\n' "$staged_name" "$before_size" "$after_size"
done
RELEASE_DIR=$staged_release "$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"
publish_release_pair \
    "$staged_release/$first_name" "$first_name" \
    "$staged_release/$second_name" "$second_name" \
    "$HERE/release"
for binary in squashfuse squashfuse_ll; do
    rm -f "$HERE/release/$binary-musl-mimalloc-$TARGET_ARCH-upx"
done
"$HERE/scripts/validate-artifacts.sh" "$TARGET_ARCH"
if [ "$NO_CLEANUP" != 1 ]; then rm -rf "$work" "$BUILD_PREFIX" "$cmake_toolchain" "$MESON_CROSS_FILE"; fi
printf '= squashfuse %s done for %s\n' "$SQUASHFUSE_VERSION" "$TARGET_ARCH"
