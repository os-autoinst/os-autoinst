# Copyright 2018-2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshVirtshSUT;

use Mojo::Base 'consoles::console', -signatures;
use backend::svirt qw(SERIAL_TERMINAL_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE);
use consoles::ssh_screen;

sub new ($class, $testapi_console, $args) {
    my $self = $class->SUPER::new($testapi_console, $args);

    # TODO: inherit from consoles::sshVirtsh
    my $instance = $bmwqemu::vars{VIRSH_INSTANCE} // 1;
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

sub screen ($self) { $self->{screen} }

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
    $self->{ssh} = $ssh;
    return;
}

sub is_serial_terminal ($self) { 1 }

1;
