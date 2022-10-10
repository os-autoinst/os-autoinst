# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
#
# Simple serial terminal over SSH

package consoles::sshSerial;

use Mojo::Base 'consoles::console', -signatures;
use consoles::ssh_screen;

sub new ($class, $testapi_console, $args) {
    return $class->SUPER::new($testapi_console, $args);
}

sub screen ($self) { $self->{screen} }

sub disable ($self) {
    return unless $self->{ssh};
    bmwqemu::diag("Closing SSH connection with " . $self->{ssh}->hostname);
    $self->{ssh}->disconnect;
    $self->{ssh} = $self->{screen} = undef;
    return;
}

sub activate ($self) {
    my $hostname = $self->{args}->{hostname} || die('we need a hostname to ssh to');
    my $password = $self->{args}->{password} // $testapi::password;
    my $username = $self->{args}->{username} // 'root';
    my $use_ssh_agent = $self->{args}->{use_ssh_agent} // 0;
    my $pty_cols = $self->{args}->{pty_cols} // 2048;
    my $port = $self->{args}->{port} // 22;

    bmwqemu::diag("Connecting SSH serial console for $username\@$hostname port $port");

    my $ssh = $self->backend->new_ssh_connection(
        hostname => $hostname,
        password => $password,
        username => $username,
        use_ssh_agent => $use_ssh_agent,
        port => $port,
    );
    my $chan = $ssh->channel()
      or $ssh->die_with_error('Cannot open SSH channel');


    # Enable echo, no ANSI color codes, $pty_cols character line width
    # (Sending commands longer than line width will break read-back check)
    $chan->pty('dumb', {echo => 1}, $pty_cols)
      or $ssh->die_with_error('PTY request failed');
    $chan->ext_data('merge');
    $chan->shell or $ssh->die_with_error('Failed to start remote shell');
    $chan->blocking(0);

    $self->{screen} = consoles::ssh_screen->new(
        ssh_connection => $ssh,
        ssh_channel => $chan,
        logfile => $self->{args}->{logfile} // "serial_terminal.txt"
    );
    $self->{ssh} = $ssh;
    return;
}

sub is_serial_terminal ($self) { 1 }

1;
