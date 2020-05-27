#!/bin/bash

# Used to install new dependencies.
# If there are new dependencies, they won't be installed in the docker
# container yet, so we just install all deps again.

DEPS=/tmp/deps.txt
NEWDEPS=/tmp/new-deps.txt
DIFFDEPS=/tmp/diff-deps.txt

list-deps() {
    rpm -qa --qf "%{NAME}-%{VERSION}\n" | grep -v ^gpg-pubkey | sort
}

list-deps > $DEPS

./tools/install-deps.sh

list-deps > $NEWDEPS

echo "Checking updated packages"
if diff $DEPS $NEWDEPS > $DIFFDEPS; then
    echo "NO DIFF"
else
    echo "=============== DIFF"
    cat $DIFFDEPS
fi

