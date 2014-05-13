package installstep;
use base "basetest";

use bmwqemu;

# using this as base class means only run when an install is needed
sub is_applicable() {
    my $self = shift;
    return $self->SUPER::is_applicable && !$bmwqemu::envs->{NOINSTALL} && !$bmwqemu::envs->{LIVETEST};
}

sub test_flags() {
    return { 'fatal' => 1 };
}

sub post_fail_hook() {
    my $self = shift;
    my @tags = ( @{ needle::tags("yast-still-running") }, @{ needle::tags("linuxrc-install-fail") } );
    if ( check_screen \@tags, 5 ) {
        send_key "ctrl-alt-f2";
        assert_screen "inst-console";
        if ( !$bmwqemu::envs->{NET} ) {
            type_string "dhcpcd eth0\n";
            type_string "ifconfig -a\n";
            type_string "cat /etc/resolv.conf\n";
        }
        type_string "save_y2logs /tmp/y2logs.tar.bz2\n";
        upload_logs "/tmp/y2logs.tar.bz2";
        $self->take_screenshot();
    }
}

1;
# vim: set sw=4 et:
