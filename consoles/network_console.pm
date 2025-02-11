# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::network_console;

use Mojo::Base 'consoles::console', -signatures;
use Feature::Compat::Try;
use Scalar::Util 'blessed';

sub activate ($self) {
    try {
        local $SIG{__DIE__} = undef;
        $self->connect_remote($self->{args});
        return $self->SUPER::activate;
    }
    catch ($e) {
        die $e unless blessed $e && $e->can('rethrow');
        return {error => $e->error};
    }
}

# to be overwritten
sub connect_remote ($self, $args) { }

1;
