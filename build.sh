#!/bin/sh
set -e
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE"

WITH_UPX=1
VENDOR_UPX=1

platform="$(uname -s)"
platform_arch="$(uname -m)"
export MAKEFLAGS="-j$(nproc)"

if [ "$platform" == "Linux" ]
    then
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
        exit 1
fi

unset build_libc
if [ -x "$(which apt 2>/dev/null)" ]
    then
        build_libc='-glibc'
        export DEBIAN_PRIORITY=critical
        export DEBIAN_FRONTEND=noninteractive
        apt update && apt install --yes --quiet \
            --option Dpkg::Options::=--force-confold --option Dpkg::Options::=--force-confdef \
            build-essential pkg-config git fuse3 po4a meson ninja-build \
            libzstd-dev liblz4-dev liblzo2-dev liblzma-dev zlib1g-dev \
            libfuse3-dev libsquashfuse-dev autoconf libtool upx wget autopoint
elif [ -x "$(which apk 2>/dev/null)" ]
    then
        build_libc='-musl-mimalloc'
        apk add musl-dev gcc git gettext-dev automake po4a cmake linux-headers \
            autoconf libtool help2man make zstd-dev lz4-dev upx g++ \
            zlib-dev lzo-dev xz-dev sed findutils fuse3-dev meson ninja-build # \
            # mimalloc-dev
fi

if [ "$WITH_UPX" == 1 ]
    then
        if [[ "$VENDOR_UPX" == 1 || ! -x "$(which upx 2>/dev/null)" ]]
            then
                upx_ver=4.2.4
                case "$platform_arch" in
                   x86_64) upx_arch=amd64 ;;
                   aarch64) upx_arch=arm64 ;;
                esac
                wget https://github.com/upx/upx/releases/download/v${upx_ver}/upx-${upx_ver}-${upx_arch}_linux.tar.xz
                tar xvf upx-${upx_ver}-${upx_arch}_linux.tar.xz
                mv upx-${upx_ver}-${upx_arch}_linux/upx /usr/bin/
                rm -rf upx-${upx_ver}-${upx_arch}_linux*
        fi
fi

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
export CC=gcc

if (echo "$build_libc"|grep -qo mimalloc)
    then
        echo "= build mimalloc lib"
        (git clone https://github.com/microsoft/mimalloc.git && cd mimalloc
        git checkout v2.1.7
        mkdir build && cd build
        (export CFLAGS="$CFLAGS -D__USE_ISOC11"
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DMI_BUILD_OBJECT=OFF \
            -DMI_BUILD_TESTS=OFF \
            -DMI_LIBC_MUSL=ON \
            -DMI_SECURE=OFF \
            -DMI_SKIP_COLLECT_ON_EXIT=ON && \
        make mimalloc-static)
        mv -fv libmimalloc.a /usr/lib/)
#         for lib in /usr/lib/libmimalloc.*
#             do ln -vsf "$(echo "$lib"|sed 's|libmimalloc|libmimalloc-insecure|')" "$lib"
#         done

        export CFLAGS="$CFLAGS -lmimalloc"
fi

echo "= build static deps"
([ -d "/usr/lib/$platform_arch-linux-gnu" ] && \
    libdir="/usr/lib/$platform_arch-linux-gnu/"||\
    libdir="/usr/lib/"

echo "= build lzma lib"
(git clone https://git.tukaani.org/xz.git && cd xz
./autogen.sh
./configure --enable-static --disable-shared
make
mv -fv src/liblzma/.libs/liblzma.a $libdir)

echo "= build lzo2 lib"
(git clone https://github.com/nemequ/lzo.git && cd lzo
./configure --enable-static --disable-shared
make
mv -fv src/.libs/liblzo2.a $libdir)

echo "= build zlib lib"
(git clone https://github.com/madler/zlib.git  && cd zlib
./configure
make libz.a
mv -fv libz.a $libdir)

echo "= build lz4 lib"
(git clone https://github.com/lz4/lz4.git && cd lz4
make liblz4.a
mv -fv lib/liblz4.a $libdir)

echo "= build zstd lib"
(git clone https://github.com/facebook/zstd.git && cd zstd/lib
make libzstd.a
mv -fv libzstd.a $libdir)

echo "= build fuse lib"
(git clone https://github.com/libfuse/libfuse.git && cd libfuse
git checkout fuse-3.17.2
mkdir build && cd build
meson setup .. --default-library=static -Dexamples=false
ninja
mv -fv lib/libfuse3.a $libdir))

echo "= download squashfuse"
git clone https://github.com/vasi/squashfuse.git
squashfuse_version="$(cd squashfuse && git describe --long --tags|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
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
    do [[ ! -L "$bin" && -f "$bin" ]] && \
        mv -fv "$bin" "${HERE}"/release/"$(basename "${bin}")${build_libc}-${platform_arch}"
done)

echo "= build super-strip"
(cd build && git clone https://github.com/aunali1/super-strip.git && cd super-strip
make
mv -fv sstrip /usr/bin/)

echo "= super-strip release binaries"
sstrip release/*-"${platform_arch}"

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        find release -name "*-${platform_arch}"|\
        xargs -I {} upx --force-overwrite {} -o {}-upx
fi

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rfv build
fi

echo "= squashfuse done"
