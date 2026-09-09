#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
metadata_probe=$ROOT/.clean-checkout-metadata-probe.$$
trap 'rm -f "$metadata_probe"; rm -rf "$TMP"' EXIT HUP INT TERM
CLEAN=$TMP/clean
mkdir "$CLEAN"

real_index=$(git -C "$ROOT" rev-parse --git-path index)
real_objects=$(git -C "$ROOT" rev-parse --git-path objects)
case $real_index in /*) ;; *) real_index=$ROOT/$real_index ;; esac
case $real_objects in /*) ;; *) real_objects=$ROOT/$real_objects ;; esac
real_index_before=$(git hash-object "$real_index")
real_objects_before=$(cd "$real_objects" && find . -type f | LC_ALL=C sort | cksum)
real_worktree_before=$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)
printf '%s\n' "metadata isolation probe $$ $TMP" >"$metadata_probe"
mkdir "$TMP/objects"
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects \
    GIT_INDEX_FILE=$TMP/index git -C "$ROOT" read-tree HEAD
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects \
    GIT_INDEX_FILE=$TMP/index git -C "$ROOT" add -A -- .
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects \
    GIT_INDEX_FILE=$TMP/index git -C "$ROOT" update-index --force-remove -- \
    "${metadata_probe#"$ROOT/"}"
rm -f "$metadata_probe"
tree=$(GIT_OBJECT_DIRECTORY=$TMP/objects \
    GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects GIT_INDEX_FILE=$TMP/index \
    git -C "$ROOT" write-tree)
GIT_OBJECT_DIRECTORY=$TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects \
    git -C "$ROOT" archive "$tree" | tar -x -C "$CLEAN"
real_index_after=$(git hash-object "$real_index")
[ "$real_index_before" = "$real_index_after" ] || {
    printf '%s\n' 'not ok - clean-checkout reconstruction modified the real git index' >&2
    exit 1
}
real_objects_after=$(cd "$real_objects" && find . -type f | LC_ALL=C sort | cksum)
[ "$real_objects_before" = "$real_objects_after" ] || {
    printf '%s\n' 'not ok - clean-checkout reconstruction wrote to real .git/objects' >&2
    exit 1
}
real_worktree_after=$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)
[ "$real_worktree_before" = "$real_worktree_after" ] || {
    printf '%s\n' 'not ok - clean-checkout reconstruction modified the real worktree' >&2
    exit 1
}

[ ! -e "$CLEAN/release" ] || {
    printf '%s\n' 'not ok - clean checkout contains ignored release outputs' >&2
    exit 1
}
[ -r "$CLEAN/lib/target.sh" ] && [ -r "$CLEAN/lib/release.sh" ] || {
    printf '%s\n' 'not ok - clean checkout omitted a required helper' >&2
    exit 1
}

git -C "$CLEAN" init -q
git -C "$CLEAN" add -A
git -C "$CLEAN" -c user.name='Clean Checkout Test' \
    -c user.email='clean-checkout@example.invalid' commit -q -m fixture
sh "$CLEAN/tests/target-contract.sh"
printf '%s\n' 'ok - contract suite passes from the prospective clean checkout'
