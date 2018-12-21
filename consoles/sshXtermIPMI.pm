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

package consoles::sshXtermIPMI;

use strict;
use warnings;
use autodie ':all';

use base 'consoles::localXvnc';

use testapi 'get_required_var';
require IPC::System::Simple;
use File::Which;

sub activate {
    my ($self) = @_;

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};

    my @command = $self->backend->ipmi_cmdline;
    push(@command, qw(sol activate));
    my $serial = $self->{args}->{serial};
    my $cstr   = join(' ', @command);
    $self->callxterm($cstr, "ipmitool:$testapi_console");
}

sub reset {
    my ($self) = @_;

    # Deactivate sol connection if it is activated
    if ($self->{activated}) {
        $self->backend->ipmitool("sol deactivate");
        $self->{activated} = 0;
    }
    return;
}

sub do_mc_reset {
    my ($self) = @_;

    if ($self->{activated}) {
        $self->backend->do_mc_reset;
        $self->{activated} = 0;
    }
    return;
}

1;
