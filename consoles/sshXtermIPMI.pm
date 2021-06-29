# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::localXvnc';

use testapi 'get_required_var';
require IPC::System::Simple;
use File::Which;

sub activate ($self) {
    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};

    my @command = $self->backend->ipmi_cmdline;
    push(@command, qw(sol activate));
    my $serial = $self->{args}->{serial};
    my $cstr   = join(' ', @command);

    # Try to deactivate IPMI SOL before activate
    eval { $self->backend->ipmitool("sol deactivate"); };
    my $ipmi_response = $@;
    if ($ipmi_response) {
        # IPMI response like SOL payload already de-activated is expected
        die "Unexpect IPMI response: $ipmi_response" unless
          ($ipmi_response =~ /SOL payload already de-activated/);
    }

    $self->callxterm($cstr, "ipmitool:$testapi_console");
}

sub reset ($self) {
    # Deactivate sol connection if it is activated
    if ($self->{activated}) {
        $self->backend->ipmitool("sol deactivate");
        $self->{activated} = 0;
    }
    return;
}

sub disable ($self) {
    # Try to deactivate IPMI SOL during disable
    $self->reset;
    $self->SUPER::disable;
}

sub do_mc_reset ($self) {
    if ($self->{activated}) {
        $self->backend->do_mc_reset;
        $self->{activated} = 0;
    }
    return;
}

1;
