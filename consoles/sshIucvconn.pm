# Copyright © 2016-2021 SUSE LLC
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

# this is just a stupid console to track if we're connected to the host
# it is used in s390x backend for serial connection

package consoles::sshIucvconn;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::network_console';

use testapi 'get_var';

sub connect_remote ($self, $args) {
    my $hostname = $args->{hostname};
    my $zvmguest = get_var('ZVM_GUEST');

    # ssh connection to SUT for agetty
    my $ttyconn = $self->backend->new_ssh_connection(hostname => $hostname, password => $args->{password}, username => 'root');

    # start agetty to ensure that iucvconn is not killed
    my $chan = $ttyconn->channel() || $ttyconn->die_with_error();
    $chan->blocking(0);
    $chan->pty(1);
    if (!$chan->exec('smart_agetty hvc0')) {
        bmwqemu::fctwarn('Unable to execute "smart_agetty hvc0" at this point: ' . ($ttyconn->error // 'unknown SSH error'));
    }

    # Save objects to prevent unexpected closings
    $self->{ttychan} = $chan;
    $self->{ttyconn} = $ttyconn;

    # ssh connection to SUT for iucvconn
    my ($ssh, $serialchan) = $self->backend->start_ssh_serial(hostname => $args->{hostname}, password => $args->{password}, username => 'root');
    # start iucvconn
    bmwqemu::diag('ssh iucvconn: grabbing serial console');
    $ssh->blocking(1);
    if (!$serialchan->exec("iucvconn $zvmguest lnxhvc0")) {
        bmwqemu::fctwarn('ssh iucvconn: unable to grab serial console at this point: ' . ($ssh->error // 'unknown SSH error'));
    }
    $ssh->blocking(0);
}

# to be called on reconnect
sub kill_ssh ($self) {
    $self->backend->stop_ssh_serial;
}

# we have no screen
sub screen { }

1;
