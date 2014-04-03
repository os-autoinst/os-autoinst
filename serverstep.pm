package serverstep;
use base "basetest";

# Use this class for server tests
sub is_applicable() {
    my $self = shift;
    return $self->SUPER::is_applicable && !$ENV{NOINSTALL} && !$ENV{LIVETEST} && ( $ENV{DESKTOP} eq "textmode" );
}

1;
