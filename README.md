# squashfuse-static

Statically linked [squashfuse 0.6.3](https://github.com/vasi/squashfuse) binaries. The build produces separate musl + mimalloc outputs and glibc outputs, with both `squashfuse` and `squashfuse_ll` in each variant.

## Build locally

Clone the repository:

```sh
git clone https://github.com/VHSgunzo/squashfuse-static.git
cd squashfuse-static
```

Run a native x86_64 musl build:

```sh
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 \
  -e TARGET_ARCH=x86_64 alpine:latest /root/build.sh
```

Run an emulated aarch64 musl build (requires binfmt/QEMU support on an x86_64 host):

```sh
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 \
  -e TARGET_ARCH=aarch64 alpine:latest /root/build.sh
```

The existing glibc builds use the same target contract:

```sh
# x86_64
docker run --rm -it -v "$PWD:/root" --platform=linux/amd64 \
  -e TARGET_ARCH=x86_64 ubuntu:jammy bash /root/build.sh

# aarch64 (requires binfmt/QEMU support on an x86_64 host)
docker run --rm -it -v "$PWD:/root" --platform=linux/arm64 \
  -e TARGET_ARCH=aarch64 ubuntu:jammy bash /root/build.sh
```

`TARGET_ARCH` accepts exactly: `x86_64, aarch64, riscv64, loongarch64, ppc64, ppc64le`. If omitted, it defaults to `uname -m` for native convenience. In this phase the build is native/emulated only, so `TARGET_ARCH` must match `uname -m` inside the build environment. Automated matrix and true cross-build paths follow in the next phase.

Normal release outputs are not UPX-compressed and use the public target name, for example:

```text
release/squashfuse-musl-mimalloc-x86_64
release/squashfuse_ll-musl-mimalloc-x86_64
```

Precompiled binaries are also available from the [releases](https://github.com/VHSgunzo/squashfuse-static/releases).
