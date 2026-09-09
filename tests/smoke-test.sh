#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT HUP INT TERM
FIXTURE=$TMP/project
mkdir -p "$FIXTURE/lib" "$FIXTURE/scripts" "$FIXTURE/release"
cp "$ROOT/lib/matrix.sh" "$FIXTURE/lib/matrix.sh"
cp "$ROOT/scripts/smoke-test.sh" "$FIXTURE/scripts/smoke-test.sh"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$FIXTURE/scripts/validate-artifacts.sh"
for binary in squashfuse squashfuse_ll; do
cat >"$FIXTURE/release/$binary-musl-mimalloc-x86_64" <<'EOF'
#!/bin/sh
printf '%s\n\n' 'squashfuse 0.6.3 (c) 2012 Dave Vasilevsky'
printf 'Usage: %s [options] ARCHIVE MOUNTPOINT\n' "$0"
case $0 in *squashfuse_ll*) exit 2;; *) exit 254;; esac
EOF
chmod +x "$FIXTURE/release/$binary-musl-mimalloc-x86_64"
done
chmod +x "$FIXTURE/scripts/"*.sh
output=$(HOST_ARCH=x86_64 FUSE_MOUNT_SMOKE=0 RELEASE_DIR="$FIXTURE/release" "$FIXTURE/scripts/smoke-test.sh" x86_64)
case $output in *'version/parser smoke passed for x86_64'*) ;;
 *) printf 'not ok - smoke orchestration output:\n%s\n' "$output" >&2; exit 1;; esac
grep -F 'status=0' "$ROOT/scripts/smoke-test.sh" >/dev/null || { printf '%s\n' 'not ok - mount wait inherits stale version exit status' >&2; exit 1; }
printf 'ok - exact 0.6.3 output and expected nonzero usage exits are accepted\n'
