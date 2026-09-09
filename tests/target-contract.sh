#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/target.sh
. "$ROOT/lib/target.sh"
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
for helper in lib/target.sh lib/release.sh lib/build-env.sh lib/matrix.sh lib/ppc64-toolchain.sh lib/source-pins.sh scripts/build-matrix.sh scripts/build-ppc64.sh scripts/validate-artifacts.sh scripts/smoke-test.sh scripts/publish-release.sh; do
    if git -C "$ROOT" check-ignore --no-index -q -- "$helper"; then status=0; else status=$?; fi
    case $status in 0) fail "$helper must be trackable";; 1) :;; *) fail "git check-ignore failed for $helper (exit $status)";; esac
done
printf 'ok - required matrix helpers are trackable\n'
for row in 'x86_64 x86_64-linux-musl' 'aarch64 aarch64-linux-musl' 'riscv64 riscv64-linux-musl' 'loongarch64 loongarch64-linux-musl' 'ppc64 powerpc64-linux-musl' 'ppc64le powerpc64le-linux-musl'; do
    arch=${row%% *}; expected=${row#* }
    [ "$(target_triplet "$arch")" = "$expected" ] || fail "$arch target triplet"
done
for row in 'x86_64 x86_64-linux-gnu' 'aarch64 aarch64-linux-gnu' 'riscv64 riscv64-linux-gnu' 'loongarch64 loongarch64-linux-gnu' 'ppc64 powerpc64-linux-gnu' 'ppc64le powerpc64le-linux-gnu'; do
    arch=${row%% *}; expected=${row#* }
    [ "$(target_glibc_triplet "$arch")" = "$expected" ] || fail "$arch glibc triplet"
done
printf 'ok - six musl and retained glibc target mappings\n'
if error=$(target_triplet unknown 2>&1); then fail 'unknown target accepted'; fi
case $error in *"unsupported TARGET_ARCH 'unknown'"*) :;; *) fail 'unclear unknown target error';; esac
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/bin"
printf '%s\n' '#!/bin/sh' 'case ${1:-} in -m) printf "%s\n" x86_64;; -s) printf "%s\n" Linux;; esac' >"$TMP/bin/uname"
printf '%s\n' '#!/bin/sh' 'printf reached >"$SIDE_EFFECT"' >"$TMP/bin/apk"
chmod +x "$TMP/bin/"*
if PATH="$TMP/bin:$PATH" SIDE_EFFECT="$TMP/effect" TARGET_ARCH=ppc64 "$ROOT/build.sh" >/dev/null 2>&1; then fail 'native target mismatch accepted'; fi
[ ! -e "$TMP/effect" ] || fail 'target mismatch reached package side effect'
TARGET_ARCH=ppc64 TARGET_TRIPLET=stale; export TARGET_ARCH TARGET_TRIPLET
resolve_target_contract
[ "$TARGET_TRIPLET" = powerpc64-linux-musl ] || fail 'contract did not refresh triplet'
if env | grep -E '^TARGET_(ARCH|TRIPLET)=' >/dev/null; then fail 'target contract leaked to child'; fi
printf 'ok - validation precedes side effects and contract variables remain local\n'
if grep -E '(WITH_UPX|VENDOR_UPX|UPX_VERSION|super-strip|sstrip|upx --force-overwrite)' "$ROOT/build.sh" >/dev/null; then fail 'mandatory unsafe postprocessing remains'; fi
printf 'ok - no UPX or host sstrip postprocessing\n'
