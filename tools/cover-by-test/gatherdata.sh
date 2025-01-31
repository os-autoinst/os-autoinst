#!/bin/bash

codecovdir=$1
dir=$2
sha=$3

pushd "$codecovdir"
files=($(find . -name "*.t"))
popd

for file in "${files[@]}"; do
    echo "======== $file"
    perl tools/cover-by-test/gatherdata.pl "$file" "$codecovdir/$file" "$dir"
done
