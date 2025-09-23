#!/bin/sh

dir=$1
sha=${2:-HEAD}
echo "$0 $dir $sha"

set -x

mkdir "$dir"
echo "$sha" > "$dir/sha"

for testfile in $(find t -name "*.t"); do
    echo "===== $testfile"
    rm -rf cover_db
    ./tools/invoke-tests --coverage "$testfile"
    cover -report codecovbash
    mkdir -p "$(dirname "$dir/$testfile")"
    mv cover_db/codecov.json "$dir/$testfile"
#    perl tools/cover-by-test.pl "$testfile" cover_db/codecov.json "$dir"
done
