# Copyright 2016-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# this is just a stupid console to track if we're connected to the host
# it is used in s390x backend for serial connection

package consoles::sshIucvconn;

use Mojo::Base 'consoles::network_console', -signatures;
use autodie ':all';

sub connect_remote ($self, $args) {
    my $hostname = $args->{hostname};
    my $zvmguest = $bmwqemu::vars{ZVM_GUEST};
    ($zvmguest) = $zvmguest =~ /(.*?)\..*$/;

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
    bmwqemu::diag("ssh iucvconn: grabbing serial console for guest: $zvmguest");
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

sub screen ($self) { }

1;
