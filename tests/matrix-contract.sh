#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_row()
{
    arch=$1 expected_platform=$2 expected_image=$3 expected_mode=$4
    expected_machine=$5 expected_endian=$6 expected_qemu=$7
    [ "$(matrix_platform "$arch")" = "$expected_platform" ] || fail "$arch OCI platform"
    [ "$(matrix_image "$arch")" = "$expected_image" ] || fail "$arch image"
    [ "$(matrix_build_mode "$arch")" = "$expected_mode" ] || fail "$arch build mode"
    [ "$(elf_machine "$arch")" = "$expected_machine" ] || fail "$arch ELF machine"
    [ "$(elf_endian "$arch")" = "$expected_endian" ] || fail "$arch ELF endian"
    [ "$(qemu_command "$arch")" = "$expected_qemu" ] || fail "$arch QEMU command"
}
ALPINE='docker.io/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b'
LOONG_ALPINE='docker.io/loongarch64/alpine:3.21@sha256:ba4698dc340db5079eea01b7ea3488452a9a1c3cb8aad11033ea2cc978f49ffc'
assert_row x86_64 linux/amd64 "$ALPINE" native-emulated 'Advanced Micro Devices X86-64' little native
assert_row aarch64 linux/arm64 "$ALPINE" native-emulated AArch64 little qemu-aarch64-static
assert_row riscv64 linux/riscv64 "$ALPINE" native-emulated RISC-V little qemu-riscv64-static
assert_row loongarch64 linux/loong64 "$LOONG_ALPINE" native-emulated LoongArch little qemu-loongarch64-static
assert_row ppc64 linux/amd64 "$ALPINE" cross-musl PowerPC64 big qemu-ppc64-static
assert_row ppc64le linux/ppc64le "$ALPINE" native-emulated PowerPC64 little qemu-ppc64le-static
[ "$(HOST_ARCH=aarch64 qemu_command x86_64)" = qemu-x86_64-static ] || fail 'foreign x86 runner'
arches='x86_64 aarch64 riscv64 loongarch64 ppc64 ppc64le'
[ "$(supported_arches)" = "$arches" ] || fail 'supported architecture order'
expected='squashfuse-musl-mimalloc-aarch64
squashfuse-musl-mimalloc-loongarch64
squashfuse-musl-mimalloc-ppc64
squashfuse-musl-mimalloc-ppc64le
squashfuse-musl-mimalloc-riscv64
squashfuse-musl-mimalloc-x86_64
squashfuse_ll-musl-mimalloc-aarch64
squashfuse_ll-musl-mimalloc-loongarch64
squashfuse_ll-musl-mimalloc-ppc64
squashfuse_ll-musl-mimalloc-ppc64le
squashfuse_ll-musl-mimalloc-riscv64
squashfuse_ll-musl-mimalloc-x86_64'
[ "$(expected_artifact_manifest)" = "$expected" ] || fail 'complete 12-artifact manifest'
[ "$(expected_artifacts ppc64)" = 'squashfuse-musl-mimalloc-ppc64
squashfuse_ll-musl-mimalloc-ppc64' ] || fail 'per-architecture pair'
if validate_matrix_arch invalid >/dev/null 2>&1; then fail 'invalid arch accepted'; fi
printf 'ok - exact six-architecture matrix and 12-artifact contract\n'
