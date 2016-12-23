#!/bin/sh

set -ex

if test -n "$SETUP_FOR_TRAVIS" ; then
  # for recent opencv
  sudo add-apt-repository -y ppa:kubuntu-ppa/backports
  sudo apt-get -y update
  sudo apt-get -y install libdbus-1-dev libssh2-1-dev libopencv-dev libtheora-dev libcv-dev libhighgui-dev tesseract-ocr libsndfile1-dev libfftw3-dev qemu-system
  cpanm -nq --installdeps --with-feature=coverage .
  find . -type f | xargs -n1 sed -i -e 's,#!/usr/bin/perl,#!/usr/bin/env perl,'
fi

mkdir --parent --verbose m4
aclocal --install -Im4
autoreconf --verbose --install --symlink --force

./configure "$@"
