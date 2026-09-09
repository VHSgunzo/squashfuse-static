# squashfuse-static

Statically linked [squashfuse 0.6.3](https://github.com/vasi/squashfuse) binaries. The release matrix produces musl + mimalloc outputs; the existing direct Ubuntu path remains available for local glibc outputs. Both `squashfuse` and `squashfuse_ll` are built.

## Build locally

Prerequisites:

- Linux and Docker Engine with `docker run --platform` support.
- Internet access for pinned OCI images, Git repositories, and the `ppc64` cross-toolchain archive.
- Registered QEMU/binfmt handlers for non-native OCI platforms.
- Host `readelf` (binutils) and the matching `qemu-*-static` executable for validation and foreign smoke tests.
- For the optional real x86_64 mount smoke: a usable `/dev/fuse`, `mksquashfs`, `fusermount3`, and `mountpoint`.

```sh
git clone https://github.com/VHSgunzo/squashfuse-static.git
cd squashfuse-static
./scripts/build-matrix.sh x86_64
./scripts/build-matrix.sh aarch64
./scripts/build-matrix.sh riscv64
./scripts/build-matrix.sh loongarch64
./scripts/build-matrix.sh ppc64
./scripts/build-matrix.sh ppc64le
# Or build all six sequentially:
./scripts/build-matrix.sh all
```

The matrix mapping is exact:

| ARCH | OCI platform | Build mode |
| --- | --- | --- |
| `x86_64` | `linux/amd64` | native container |
| `aarch64` | `linux/arm64` | QEMU/native container |
| `riscv64` | `linux/riscv64` | QEMU/native container |
| `loongarch64` | `linux/loong64` | pinned LoongArch Alpine image |
| `ppc64` | `linux/amd64` | genuine `powerpc64-linux-musl` cross-toolchain |
| `ppc64le` | `linux/ppc64le` | QEMU/native container |

Each selected musl target builds and validates both outputs under its target work directory before publishing them as a pair. Pair publication stages adjacent temporary files, backs up any previous pair, and rolls back the first rename if the second rename or a signal interrupts the transaction. A failed or interrupted musl target build leaves its previously published pair unchanged; obsolete `-upx` files are removed only after the normal pair is replaced successfully. Every other target's outputs are preserved:

```text
release/squashfuse-musl-mimalloc-ARCH
release/squashfuse_ll-musl-mimalloc-ARCH
```

The musl build uses a target-isolated prefix under `build/sysroot/ARCH`; target pkg-config lookup does not include host `/usr/lib`. The `ppc64` build compiles mimalloc through a CMake toolchain, libfuse through a Meson cross file, all compression libraries with target tools, and squashfuse with distinct Autotools `--build` and `--host` triplets. `ppc64` is big-endian and is validated separately from little-endian `ppc64le`.

Same-target musl builds are serialized by a per-target lock in `release/`; different targets can proceed independently. Each canonical lock is atomically hard-linked from an adjacent private file that already contains its owner, so observers never see an empty lock. Normal exits and handled signals remove the canonical lock and private file. If the process is killed without running traps, remove a stale lock only after confirming that no build for that target is still running.

Direct `build.sh` use defaults `TARGET_ARCH` to `uname -m`. On Alpine it creates the musl + mimalloc pair. On Ubuntu/Debian it dispatches to the retained local glibc build behavior; glibc outputs are not part of CI or aggregate releases.

## Pinned musl matrix inputs

| Dependency | Logical version | Exact commit |
| --- | --- | --- |
| squashfuse | 0.6.3 | `1a211e20fff55e9ce4c74ad03f0aa26a7b760bd3` |
| mimalloc | 2.1.7 | `8c532c32c3c96e5ba1f2283e032f69ead8add00f` |
| libfuse | 3.18.2 | `033844748010a3b8265bf1c90b9ae8ffe4cd9ca7` |
| XZ | 5.8.2 | `9fc6f5cd8774ebef8d4e030f7081fb6984c0dc3f` |
| LZO | upstream no-tag revision | `0083878c235a89ef96a009d1ff0b500f3a364e4b` |
| zlib | 1.3.2 | `e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca` |
| LZ4 | 1.10.0 | `0774d05537f9762f838f7ab541b7765f1a729cb5` |
| Zstandard | 1.5.7 | `d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a` |

These pinning and reproducibility qualifications apply to the musl matrix only; the delegated direct glibc path remains outside this guarantee. Musl source checkout is detached and verifies exact `HEAD`. OCI images, GitHub Actions, the QEMU binfmt image, and the `ppc64` toolchain archive/checksum are pinned. Alpine package repository contents and toolchain package revisions are not frozen: `apk add` resolves live repository state. The musl builds therefore are not guaranteed to be byte-identical across time.

UPX and host `sstrip` are not used. Normal outputs are uncompressed static ELF files.

## Verify

```sh
for test in tests/*.sh; do sh "$test"; done
./scripts/validate-artifacts.sh ARCH
./scripts/smoke-test.sh ARCH
```

Validation requires a nonzero executable ELF64 with the exact machine and endianness and rejects both `PT_INTERP` and `DT_NEEDED`. The smoke test executes each binary natively or under the matching QEMU, requires the exact squashfuse 0.6.3 identity line, and recognizes squashfuse's documented nonzero usage exits (`254` and `2`). Foreign tests are version/parser checks; they never claim a FUSE mount passed. On native x86_64, a real read-through mount is attempted for both binaries only when `/dev/fuse` and all host tools are available; otherwise the output explicitly reports that the mount test was skipped. Fixture tests are self-contained and are not represented as real mounts.

## Release safety

Published releases are treated as immutable. An existing published release is a no-op only if it has the exact expected 12-asset manifest; a mismatch fails without mutation. A missing release is created as a verified-tag draft, all 12 assets are uploaded without clobbering historical assets, and the draft is published only after exact manifest verification.

Every create attempt places a unique ownership marker in the draft notes as part of the creation request. Failures clean up only a freshly read draft whose ID, tag, draft state, and per-attempt ownership marker all match; a competing publisher draft is never deleted. Publishing atomically clears the internal marker while changing the draft state, and the public read-back requires empty notes. Malformed metadata, ambiguous publication responses, failed state reads, or changed/public state leave the release intact for manual inspection. Release jobs are serialized by repository and tag as defense in depth, publication is tag-push-only, and only the release job receives `contents: write` and a GitHub token.
