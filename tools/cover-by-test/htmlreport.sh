#!/bin/sh
set -x
dir=$1
sha=${2:-HEAD}

find "$dir" -name "*.json" | \
    grep -v .t.json$ | \
    xargs -n 1 perl tools/cover-by-test/file-to-html.pl "$dir" "$sha"

