#!/bin/sh

set -e

# Prepare dir and chdir into it before executing the wanted action
sudo cp -rd /opt/repo /opt/run
sudo chown -R $NORMAL_USER:users /opt/run

pushd /opt/run
./autogen.sh

/bin/bash -c "$*"
