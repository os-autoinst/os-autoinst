package consoles::remoteVnc;
use base 'consoles::vnc_base';
use strict;
use warnings;
use testapi qw/get_var/;

sub init() {
    my ($self) = @_;
    $self->{name} = 'remote-vnc';
}

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;

    return $self->SUPER::activate(
        $testapi_console,
        {
            hostname => get_var("PARMFILE")->{Hostname},
            password => get_var("DISPLAY")->{PASSWORD},
            port     => 5901,
            ikvm     => 0,
        });
}

# override
sub select() {
}

1;
