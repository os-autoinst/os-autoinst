#!/bin/sh

cd /opt
# Do a clone to avoid writing to the host's volume when not running in Travis
# and also to avoid using files not checked into the repo.
git clone /opt/repo run

cd run
./autogen.sh
make
# 'coverage' executes all tests and checks code coverage against threshold
# in Makefile.am
make check coverage VERBOSE=1
