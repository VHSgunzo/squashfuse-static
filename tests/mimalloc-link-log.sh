#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../lib/build-env.sh
. "$ROOT/lib/build-env.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
cat >"$TMP/good.log" <<'EOF'
/bin/sh ./libtool --tag=CC --mode=link gcc -static-pie -o squashfuse hl.o libsquashfuse.la -lfuse3 -lmimalloc
gcc -static-pie -o .libs/squashfuse hl.o ./.libs/libsquashfuse.a -lfuse3 -lmimalloc
/bin/sh ./libtool --tag=CC --mode=link gcc -static-pie -o squashfuse_ll ll_main.o libsquashfuse_ll.la -lfuse3 -lmimalloc
gcc -static-pie -o .libs/squashfuse_ll ll_main.o ./.libs/libsquashfuse_ll.a -lfuse3 -lmimalloc
EOF
verify_mimalloc_link_log "$TMP/good.log" || fail 'normal final -lmimalloc link log rejected'
cat >"$TMP/early.log" <<'EOF'
gcc -static-pie -lmimalloc -o squashfuse hl.o -lfuse3
gcc -static-pie -lmimalloc -o squashfuse_ll ll_main.o -lfuse3
EOF
if verify_mimalloc_link_log "$TMP/early.log" >/dev/null 2>&1; then fail 'early mimalloc link accepted'; fi
cat >"$TMP/whole.log" <<'EOF'
gcc -static-pie -o squashfuse hl.o -Wl,--whole-archive -lmimalloc -Wl,--no-whole-archive
gcc -static-pie -o squashfuse_ll ll_main.o -Wl,--whole-archive -lmimalloc -Wl,--no-whole-archive
EOF
if verify_mimalloc_link_log "$TMP/whole.log" >/dev/null 2>&1; then fail 'whole-archive mimalloc link accepted'; fi
printf '%s\n' 'ok - verbose links prove conventional final -lmimalloc placement'
