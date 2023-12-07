#!/bin/bash

# This script is used for CI testing.
# Used to install new dependencies.
# If there are new dependencies, they won't be installed in the
# container yet, so we just install all deps again.

set -euo pipefail

OLDDEPS=/tmp/deps.txt
NEWDEPS=/tmp/new-deps.txt
DIFFDEPS=/tmp/diff-deps.txt

. ./tools/tools.sh

listdeps > $OLDDEPS

# shellcheck disable=SC2207
DEPS=($(getdeps_container))

user=${USER:-root}
[[ $user != root ]] && sudo=sudo || sudo=
$sudo zypper --no-refresh install -y -C "${DEPS[@]}"

listdeps > $NEWDEPS

echo "Checking updated packages"
if diff $OLDDEPS $NEWDEPS > $DIFFDEPS; then
    echo "NO DIFF"
else
    echo "=============== DIFF"
    cat $DIFFDEPS
    echo "=============== DIF END"
fi

