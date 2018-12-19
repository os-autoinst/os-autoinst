# Copyright © 2018 SUSE LLC
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

package consoles::sshVirtshSUT;

use strict;
use warnings;

use base 'consoles::console';

use testapi 'get_var';
use consoles::virtio_screen;

sub new {
    my ($class, $testapi_console, $args) = @_;

    my $self = $class->SUPER::new($testapi_console, $args);
    $self->{libvirt_domain} = $args->{libvirt_domain} // 'openQA-SUT-1';
    $self->{serial_port_no} = $args->{serial_port_no} // 1;
    return $self;
}

sub screen {
    my ($self) = @_;
    return $self->{screen};
}

sub disable {
    my ($self) = @_;

    if (my $shell = $self->{shell}) {
        $shell->close();
    }
    if (my $ssh = $self->{ssh}) {
        $ssh->disconnect;
        $self->{ssh} = $self->{chan} = $self->{screen} = undef;
    }
    return;
}

sub activate {
    my ($self) = @_;

    my $backend = $self->{backend};
    my ($ssh, $chan) = $backend->open_serial_console_via_ssh($self->{libvirt_domain}, $self->{serial_port_no});

    $self->{ssh}    = $ssh;
    $self->{screen} = consoles::virtio_screen->new($chan, $ssh->sock);
    return;
}

sub is_serial_terminal {
    return 1;
}

1;
