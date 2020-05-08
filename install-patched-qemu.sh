#!/bin/bash

set -x

zypper -n addrepo http://download.opensuse.org/repositories/devel:/openQA:/ci/openSUSE_Leap_15.1 qemu
zypper -n --gpg-auto-import-keys --no-gpg-checks refresh
zypper -n in --from qemu qemu qemu-x86 qemu-tools qemu-ipxe qemu-sgabios qemu-kvm qemu-seabios

