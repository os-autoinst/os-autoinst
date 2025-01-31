#!/bin/sh

set -x

for testfile in $(find t -name "*.t"); do
    echo "===== $testfile"
    rm -rf cover_db
    ./tools/invoke-tests --coverage "$testfile"
    cover -report codecovbash
    perl tools/cover-by-test.pl "$testfile" cover_db/codecov.json cover-by-test
done
