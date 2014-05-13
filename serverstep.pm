package serverstep;
use base "basetest";

# Use this class for server tests
sub is_applicable() {
    my $self = shift;
    return $self->SUPER::is_applicable && !$bmwqemu::envs->{NOINSTALL} && !$bmwqemu::envs->{LIVETEST} && ( $bmwqemu::envs->{DESKTOP} eq "textmode" );
}

1;
# vim: set sw=4 et:
