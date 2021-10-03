# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::remoteVnc;

use Mojo::Base -strict;

use base 'consoles::vnc_base';

use testapi 'get_var';

sub init {
    my ($self) = @_;
    $self->{name} = 'remote-vnc';
}

sub activate {
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
sub select { }

1;
