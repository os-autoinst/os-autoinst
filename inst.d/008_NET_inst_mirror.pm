package NET_inst_mirror;
use base "basetest";
use bmwqemu;

sub is_applicable() {
    return !$bmwqemu::vars{ISO} || $bmwqemu::vars{ISO} =~ m/-NET-/;
}

sub run() {
}

1;
# vim: set sw=4 et:
