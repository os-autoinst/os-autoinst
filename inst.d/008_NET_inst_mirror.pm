package NET_inst_mirror;
use base "basetest";
use bmwqemu;

sub is_applicable() {
    return !$ENV{ISO} || $ENV{ISO} =~ m/-NET-/;
}

sub run() {
}

1;
