# Copyright © 2018-2021 SUSE LLC
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

use Mojo::Base -strict, -signatures;

use base 'consoles::console';

use testapi 'get_var';
use backend::svirt qw(SERIAL_TERMINAL_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE);
use consoles::ssh_screen;

sub new ($class, $testapi_console, $args) {
    my $self = $class->SUPER::new($testapi_console, $args);

    # TODO: inherit from consoles::sshVirtsh
    my $instance = get_var('VIRSH_INSTANCE', 1);
    $self->{libvirt_domain} = $args->{libvirt_domain} // "openQA-SUT-$instance";
    $self->{serial_port_no} = $args->{serial_port_no} // SERIAL_TERMINAL_DEFAULT_PORT;

    # QEMU on s390x fails to start when added <serial> device due arch limitation
    # on SCLP console, see "Multiple VT220 operator consoles are not supported"
    # error at
    # https://github.com/qemu/qemu/blob/master/hw/char/sclpconsole.c#L226
    # Therefore <console> must be used for s390x.
    # ATM there is only s390x using this console, let's make it the default.
    $self->{pty_dev} = $args->{pty_dev} // SERIAL_TERMINAL_DEFAULT_DEVICE;

    return $self;
}

sub screen { shift->{screen} }

sub disable ($self) {
    return unless $self->{ssh};
    $self->{ssh}->disconnect;
    $self->{ssh} = $self->{chan} = $self->{screen} = undef;
    return;
}

sub activate ($self) {
    my $backend = $self->{backend};
    bmwqemu::diag(sprintf("Activate console on libvirt_domain:%s devname:%s port:%s",
            $self->{libvirt_domain}, $self->{pty_dev}, $self->{serial_port_no}));
    my ($ssh, $chan) = $backend->open_serial_console_via_ssh(
        $self->{libvirt_domain}, devname => $self->{pty_dev}, port => $self->{serial_port_no}, blocking => 0);
    $self->{screen} = consoles::ssh_screen->new(ssh_connection => $ssh, ssh_channel => $chan);
    $self->{ssh}    = $ssh;
    return;
}

sub is_serial_terminal { 1 }

1;
