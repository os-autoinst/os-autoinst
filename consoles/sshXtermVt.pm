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

package consoles::sshXtermVt;

use strict;
use warnings;
use autodie ':all';

use base 'consoles::localXvnc';

use testapi 'get_var';
require IPC::System::Simple;

sub activate {
    my ($self) = @_;

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};
    my $ssh_args        = $self->{args};
    my $gui             = $self->{args}->{gui};

    my $hostname = $ssh_args->{hostname} || die('we need a hostname to ssh to');
    my $password = $ssh_args->{password} || $testapi::password;
    my $username = $ssh_args->{username} || 'root';
    my $sshcommand = $self->sshCommand($username, $hostname, $gui);
    my $serial     = $self->{args}->{serial};

    $self->callxterm($sshcommand, "ssh:$testapi_console");

    if ($serial) {

        # ssh connection to SUT for iucvconn
        my $serialchan = $self->backend->start_ssh_serial(
            hostname => $hostname,
            password => $password,
            username => 'root'
        );

        # start iucvconn
        $serialchan->exec($serial);
    }
}

# to be called on reconnect
sub kill_ssh {
    my ($self) = @_;

    $self->backend->stop_ssh_serial;
}

1;
