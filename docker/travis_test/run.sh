#!/bin/sh

set -e

INSTALL_FROM_CPAN="${INSTALL_FROM_CPAN:-0}"

sudo zypper --gpg-auto-import-keys -n ref --force && sudo zypper up -l -y

# Prepare dir and chdir into it before executing the wanted action
sudo cp -rd /opt/repo /opt/run
sudo chown -R $NORMAL_USER:users /opt/run

pushd /opt/run
[ "$INSTALL_FROM_CPAN" -eq 1 ] && \
  (cpanm --local-lib=~/perl5 local::lib && cpanm -n --installdeps . ) || \
  cpanm -n --mirror http://no.where/ --installdeps .

[ "$INSTALL_FROM_CPAN" -eq 1 ] && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
[ $? -eq 0 ] || echo "Missing dependencies. Please check output above"

./autogen.sh

/bin/bash -c "$*"
