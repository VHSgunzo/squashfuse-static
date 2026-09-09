#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d); probe=$ROOT/.clean-checkout-probe.$$
trap 'rm -f "$probe"; rm -rf "$TMP"' EXIT HUP INT TERM
CLEAN=$TMP/clean; mkdir "$CLEAN" "$TMP/objects"
real_index=$(git -C "$ROOT" rev-parse --git-path index)
real_objects=$(git -C "$ROOT" rev-parse --git-path objects)
case $real_index in /*) :;; *) real_index=$ROOT/$real_index;; esac
case $real_objects in /*) :;; *) real_objects=$ROOT/$real_objects;; esac
index_before=$(git hash-object "$real_index")
objects_before=$(cd "$real_objects" && find . -type f | LC_ALL=C sort | cksum)
worktree_before=$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)
printf '%s\n' probe >"$probe"
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects GIT_INDEX_FILE=$TMP/index git -C "$ROOT" read-tree HEAD
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects GIT_INDEX_FILE=$TMP/index git -C "$ROOT" add -A -- .
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects GIT_INDEX_FILE=$TMP/index git -C "$ROOT" update-index --force-remove -- "${probe#"$ROOT/"}"
rm -f "$probe"
tree=$(GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects GIT_INDEX_FILE=$TMP/index git -C "$ROOT" write-tree)
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects git -C "$ROOT" archive "$tree" | tar -x -C "$CLEAN"
[ "$index_before" = "$(git hash-object "$real_index")" ] || { echo 'not ok - temporary checkout changed real index' >&2; exit 1; }
[ "$objects_before" = "$(cd "$real_objects" && find . -type f | LC_ALL=C sort | cksum)" ] || { echo 'not ok - temporary checkout changed real object store' >&2; exit 1; }
[ "$worktree_before" = "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)" ] || { echo 'not ok - temporary checkout changed worktree' >&2; exit 1; }
[ ! -e "$CLEAN/release" ] || { echo 'not ok - ignored release outputs entered clean tree' >&2; exit 1; }
git -C "$CLEAN" init -q; git -C "$CLEAN" add -A; git -C "$CLEAN" -c user.name=Test -c user.email=test@example.invalid commit -q -m fixture
count=0
for test in "$CLEAN"/tests/*.sh; do
    [ "$(basename "$test")" = clean-checkout.sh ] && continue
    sh "$test"; count=$((count + 1))
done
expected=0
for test in "$ROOT"/tests/*.sh; do [ "$(basename "$test")" = clean-checkout.sh ] && continue; expected=$((expected + 1)); done
[ "$count" -eq "$expected" ] || { printf 'not ok - ran %s of %s tests\n' "$count" "$expected" >&2; exit 1; }
printf 'ok - all %s tests pass from isolated prospective clean checkout\n' "$count"
