#!/usr/bin/perl -w
use strict;

BEGIN {
    my ($wd) = $0 =~ m-(.*)/-;
    push(@INC, $wd);
}
use rpc_hidclient;

init_usb_gadget();

#change_cd("/mounts/dist/install/openSUSE-13.2-GM/iso/openSUSE-13.2-NET-x86_64.iso");
#change_cd("/mounts/dist/install/openSUSE-13.2-GM/iso/openSUSE-13.2-NET-i586.iso");
while (<>) { chomp; send_key($_); }

#while (1) { print read_serial()||""; sleep 1; }

