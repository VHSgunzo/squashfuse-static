#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/matrix.sh
. "$ROOT/lib/matrix.sh"
arch=${1:-}
validate_matrix_arch "$arch" || exit 2
RELEASE_DIR=${RELEASE_DIR:-$ROOT/release}
"$ROOT/scripts/validate-artifacts.sh" "$arch"
runner=$(qemu_command "$arch")
if [ "$runner" != native ]; then
    command -v "$runner" >/dev/null 2>&1 || { printf "required emulator '%s' is unavailable\n" "$runner" >&2; exit 1; }
fi
run_target()
{
    if [ "$runner" = native ]; then "$@"; else "$runner" "$@"; fi
}
for binary in squashfuse squashfuse_ll; do
    artifact=$RELEASE_DIR/$binary-musl-mimalloc-$arch
    set +e
    output=$(run_target "$artifact" --version 2>&1)
    status=$?
    set -e
    case $binary:$status in squashfuse:254|squashfuse_ll:2) ;;
        *) printf '%s --version returned %s, expected usage exit\n' "$artifact" "$status" >&2; exit 1;;
    esac
    first_line=$(printf '%s\n' "$output" | sed -n '1p')
    [ "$first_line" = 'squashfuse 0.6.3 (c) 2012 Dave Vasilevsky' ] || {
        printf '%s did not report exact squashfuse 0.6.3 identity: %s\n' "$artifact" "$first_line" >&2; exit 1; }
    printf '%s\n' "$output" | grep -F 'Usage:' >/dev/null || { printf '%s did not reach its argument parser\n' "$artifact" >&2; exit 1; }
done
printf '= version/parser smoke passed for %s\n' "$arch"

# A real kernel FUSE mount is meaningful only for native x86_64 and when every
# host prerequisite is available. Foreign targets never claim a mount pass.
if [ "$arch" != x86_64 ] || [ "$runner" != native ]; then
    printf '= FUSE mount smoke not applicable to foreign/non-x86 target %s\n' "$arch"
    exit 0
fi
if [ "${FUSE_MOUNT_SMOKE:-auto}" = 0 ]; then
    printf '%s\n' '= FUSE mount smoke explicitly disabled for fixture-only testing'
    exit 0
fi
if [ ! -c /dev/fuse ] || [ ! -r /dev/fuse ] || [ ! -w /dev/fuse ] || \
   ! command -v mksquashfs >/dev/null 2>&1 || \
   ! command -v fusermount3 >/dev/null 2>&1 || ! command -v mountpoint >/dev/null 2>&1; then
    printf '%s\n' '= FUSE mount smoke skipped: /dev/fuse or host tools unavailable'
    exit 0
fi
TMP=$(mktemp -d)
pid=
cleanup()
{
    if mountpoint -q "$TMP/mnt" 2>/dev/null; then fusermount3 -u "$TMP/mnt" || :; fi
    [ -z "$pid" ] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }
    rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP/input" "$TMP/mnt"
printf '%s\n' 'real squashfuse mount smoke' >"$TMP/input/message.txt"
mksquashfs "$TMP/input" "$TMP/image.squashfs" -noappend -quiet -processors 1
for binary in squashfuse squashfuse_ll; do
    artifact=$RELEASE_DIR/$binary-musl-mimalloc-x86_64
    "$artifact" -f "$TMP/image.squashfs" "$TMP/mnt" >"$TMP/$binary.log" 2>&1 & pid=$!
    mounted=false
    attempts=0
    while [ "$attempts" -lt 50 ]; do
        if mountpoint -q "$TMP/mnt"; then mounted=true; break; fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 0.1
        attempts=$((attempts + 1))
    done
    if [ "$mounted" != true ]; then
        status=0
        wait "$pid" 2>/dev/null || status=$?
        pid=
        printf '%s failed real FUSE mount (status %s):\n' "$binary" "${status:-unknown}" >&2
        sed -n '1,40p' "$TMP/$binary.log" >&2
        exit 1
    fi
    cmp "$TMP/input/message.txt" "$TMP/mnt/message.txt"
    fusermount3 -u "$TMP/mnt"
    status=0
    wait "$pid" 2>/dev/null || status=$?
    pid=
    [ "${status:-0}" -eq 0 ] || { printf '%s exited %s after unmount\n' "$binary" "$status" >&2; exit 1; }
    unset status
 done
printf '%s\n' '= real x86_64 FUSE mount smoke passed for both binaries'
