#!/bin/sh

checkout_squashfuse_version()
(
    source_dir=$1
    requested_version=$2
    cd "$source_dir" || exit 1
    [ "$requested_version" = git ] ||
        git checkout --quiet "$requested_version" || exit 1
    description=$(git describe --long --tags) || exit 1
    printf '%s\n' "$description" |
        sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
)
