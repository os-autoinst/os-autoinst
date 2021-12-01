# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::ttyConsole;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::console';

require IPC::System::Simple;

sub trigger_select ($self) {
    $self->screen->send_key({key => $self->console_key});
    return;
}

sub screen ($self) {
    return $self->backend->console('sut');
}

1;
