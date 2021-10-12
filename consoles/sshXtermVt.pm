# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshXtermVt;

use Mojo::Base -strict;
use autodie ':all';

use base 'consoles::localXvnc';

use IO::Socket::INET;
use testapi 'get_var';
require IPC::System::Simple;

sub activate {
    my ($self) = @_;

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};
    my $ssh_args = $self->{args};
    my $gui = $self->{args}->{gui};

    my $hostname = $ssh_args->{hostname} || die('we need a hostname to ssh to');
    my $password = $ssh_args->{password} || $testapi::password;
    my $username = $ssh_args->{username} || 'root';
    my $sshcommand = $self->sshCommand($username, $hostname, $gui);
    my $serial = $self->{args}->{serial};

    # Wait that ssh server on SUT is live on network
    if (!$self->wait_for_ssh_port($hostname, timeout => (get_var('SSH_XTERM_WAIT_SUT_ALIVE_TIMEOUT') // 120))) {
        bmwqemu::diag("$hostname does not seems to have an active SSH server. Continuing anyway.");
    }
    $self->callxterm($sshcommand, "ssh:$testapi_console");

    if ($serial) {

        # ssh connection to SUT for iucvconn
        my ($ssh, $serialchan) = $self->backend->start_ssh_serial(
            hostname => $hostname,
            password => $password,
            username => 'root'
        );

        # start iucvconn
        bmwqemu::diag('ssh xterm vt: grabbing serial console');
        $ssh->blocking(1);
        if (!$serialchan->exec($serial)) {
            bmwqemu::fctwarn('ssh xterm vt: unable to grab serial console at this point: ' . ($ssh->error // 'unknown SSH error'));
        }
        $ssh->blocking(0);
    }
}

sub wait_for_ssh_port {
    my ($self, $hostname, %args) = @_;
    $args{timeout} //= 120;
    $args{port} //= 22;

    bmwqemu::diag("Wait for SSH on host $hostname (timeout: $args{timeout})");

    $args{timeout} = 1 unless $args{timeout} > 0;
    my $endtime = time() + $args{timeout};
    while (time() < $endtime) {
        my $sock = IO::Socket::INET->new(PeerAddr => $hostname, PeerPort => $args{port}, Proto => 'tcp', Timeout => 1);
        return 1 if defined $sock;
        sleep 1;
    }
    return 0;
}

# to be called on reconnect
sub kill_ssh {
    my ($self) = @_;

    $self->backend->stop_ssh_serial;
}

1;
