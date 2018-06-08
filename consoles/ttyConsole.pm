# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package consoles::ttyConsole;
use base 'consoles::console';
use strict;
use warnings;
require IPC::System::Simple;
use autodie ':all';
use testapi 'check_var';

# to be overloaded
sub trigger_select {
    my ($self) = @_;
    my $key;

    # Special keys like Ctrl-Alt-Fx are not passed to the VM by xfreerdp.
    # That means switch from graphical to console is not possible on Hyper-V.
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        $key = "alt-f" . $self->{args}->{tty};
    }
    else {
        $key = "ctrl-alt-f" . $self->{args}->{tty};
    }

    $self->screen->send_key({key => $key});
    return;
}

sub screen {
    my ($self) = @_;
    return $self->backend->console('sut');
}

1;
