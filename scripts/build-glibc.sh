#!/bin/sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$HERE"

# shellcheck source=lib/target.sh
. "$HERE/lib/target.sh"
# shellcheck source=lib/release.sh
. "$HERE/lib/release.sh"
# shellcheck source=lib/source.sh
. "$HERE/lib/source.sh"
resolve_target_contract
validate_native_target

SQUASHFUSE_VERSION=0.6.3

MIMALLOC_VERSION=2.1.7
LIBFUSE_VERSION=3.18.2

XZ_VERSION=git              # 5.8.2
LZO_VERSION=git             # no tags
ZLIB_VERSION=git            # 1.3.2
LZ4_VERSION=git             # 1.10.0
ZSTD_VERSION=git            # 1.5.7

NO_CLEANUP=${NO_CLEANUP:-0}

platform="$(uname -s)"
MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }-j$(nproc)"
export MAKEFLAGS

if [ "$platform" = Linux ]
    then
        CFLAGS="${CFLAGS:+$CFLAGS }-static"
        LDFLAGS="${LDFLAGS:+$LDFLAGS }--static"
        export CFLAGS LDFLAGS
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
        exit 1
fi

mkdir -p release
echo "= remove only previous ${TARGET_ARCH} release outputs"
for release_name in squashfuse squashfuse_ll
do
    rm -f \
        "$HERE/release/${release_name}-musl-mimalloc-${TARGET_ARCH}" \
        "$HERE/release/${release_name}-musl-mimalloc-${TARGET_ARCH}-upx" \
        "$HERE/release/${release_name}-glibc-${TARGET_ARCH}" \
        "$HERE/release/${release_name}-glibc-${TARGET_ARCH}-upx"
done

unset build_libc
if command -v apt >/dev/null 2>&1
    then
        build_libc='-glibc'
        export DEBIAN_PRIORITY=critical
        export DEBIAN_FRONTEND=noninteractive
        apt update && apt install --yes --quiet \
            --option Dpkg::Options::=--force-confold --option Dpkg::Options::=--force-confdef \
            build-essential pkg-config git fuse3 po4a meson ninja-build \
            libzstd-dev liblz4-dev liblzo2-dev liblzma-dev zlib1g-dev \
            libfuse3-dev libsquashfuse-dev autoconf libtool autopoint
elif command -v apk >/dev/null 2>&1
    then
        build_libc='-musl-mimalloc'
        apk add musl-dev gcc git gettext-dev automake po4a cmake linux-headers \
            autoconf libtool help2man make zstd-dev lz4-dev g++ \
            zlib-dev lzo-dev xz-dev sed findutils fuse3-dev meson ninja-build # \
            # mimalloc-dev
fi

CC=${CC:-gcc}
export CC
if [ "$build_libc" = -glibc ]; then
    TARGET_LIBDIR=$(target_glibc_libdir "$TARGET_ARCH" "$CC")
    PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-$TARGET_LIBDIR/pkgconfig:/usr/share/pkgconfig}
else
    TARGET_LIBDIR=/usr/lib
fi
export TARGET_LIBDIR PKG_CONFIG_LIBDIR

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

# if [ -d release ]
#     then
#         echo "= removing previous release directory"
#         rm -rf release
# fi

echo "=  create build and release directory"
mkdir -p build
mkdir -p release

(cd build

export CFLAGS="$CFLAGS -Os -g0 -ffunction-sections -fdata-sections -fvisibility=hidden -fmerge-all-constants"
export LDFLAGS="$LDFLAGS -Wl,--gc-sections -Wl,--strip-all"

if (echo "$build_libc"|grep -qo mimalloc)
    then
        echo "= build mimalloc lib"
        (git clone https://github.com/microsoft/mimalloc.git && cd mimalloc
        [ "$MIMALLOC_VERSION" = git ] || git checkout "v$MIMALLOC_VERSION"
        mkdir build && cd build
        (CFLAGS="$CFLAGS -D__USE_ISOC11" cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DMI_BUILD_OBJECT=OFF \
            -DMI_BUILD_TESTS=OFF \
            -DMI_LIBC_MUSL=ON \
            -DMI_SECURE=OFF \
            -DMI_SKIP_COLLECT_ON_EXIT=ON && \
        make mimalloc-static)
        cp -fv libmimalloc.a "$TARGET_LIBDIR/")
#         for lib in /usr/lib/libmimalloc.*
#             do ln -vsf "$(echo "$lib"|sed 's|libmimalloc|libmimalloc-insecure|')" "$lib"
#         done

        export CFLAGS="$CFLAGS -lmimalloc"
fi

echo "= build static deps"
(

echo "= build lzma lib"
(git clone https://git.tukaani.org/xz.git && cd xz
[ "$XZ_VERSION" = git ] || git checkout "v$XZ_VERSION"
./autogen.sh
./configure --enable-static --disable-shared
make
cp -fv src/liblzma/.libs/liblzma.a "$TARGET_LIBDIR/")

echo "= build lzo2 lib"
(git clone https://github.com/nemequ/lzo.git && cd lzo
[ "$LZO_VERSION" = git ] || git checkout "$LZO_VERSION"
./configure --enable-static --disable-shared
make
cp -fv src/.libs/liblzo2.a "$TARGET_LIBDIR/")

echo "= build zlib lib"
(git clone https://github.com/madler/zlib.git  && cd zlib
[ "$ZLIB_VERSION" = git ] || git checkout "v$ZLIB_VERSION"
./configure
make libz.a
cp -fv libz.a "$TARGET_LIBDIR/")

echo "= build lz4 lib"
(git clone https://github.com/lz4/lz4.git && cd lz4
[ "$LZ4_VERSION" = git ] || git checkout "v$LZ4_VERSION"
make liblz4.a
cp -fv lib/liblz4.a "$TARGET_LIBDIR/")

echo "= build zstd lib"
(git clone https://github.com/facebook/zstd.git && cd zstd/lib
[ "$ZSTD_VERSION" = git ] || git checkout "v$ZSTD_VERSION"
make libzstd.a
cp -fv libzstd.a "$TARGET_LIBDIR/")

echo "= build fuse lib"
(git clone https://github.com/libfuse/libfuse.git && cd libfuse
[ "$LIBFUSE_VERSION" = git ] || git checkout "fuse-$LIBFUSE_VERSION"
mkdir build && cd build
meson setup .. --default-library=static -Dexamples=false
ninja
cp -fv lib/libfuse3.a "$TARGET_LIBDIR/"))

echo "= download squashfuse"
git clone https://github.com/vasi/squashfuse.git
squashfuse_version=$(checkout_squashfuse_version squashfuse "$SQUASHFUSE_VERSION")
squashfuse_dir="${HERE}/build/squashfuse-${squashfuse_version}"
mv "squashfuse" "${squashfuse_dir}"
echo "= squashfuse v${squashfuse_version}"

echo "= build squashfuse"
(cd "${squashfuse_dir}"
./autogen.sh
./configure
make DESTDIR="${squashfuse_dir}/install" LDFLAGS="$LDFLAGS" install)

echo "= extracting squashfuse binaries and libraries"
for bin in "${squashfuse_dir}"/install/usr/local/bin/*
do
    if [ ! -L "$bin" ] && [ -f "$bin" ]; then
        install_release_binary "$bin" "$HERE/release" \
            "$(basename "$bin")${build_libc}-${TARGET_ARCH}"
    fi
done)

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rfv build
fi

echo "= squashfuse done"
