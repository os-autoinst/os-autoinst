# Copyright © 2020 SUSE LLC
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
#
#
# Simple serial terminal over SSH

package consoles::sshSerial;

use Mojo::Base -strict;

use base 'consoles::console';

use consoles::ssh_screen;

sub new {
    my ($class, $testapi_console, $args) = @_;

    return $class->SUPER::new($testapi_console, $args);
}

sub screen { shift->{screen} }

sub disable {
    my ($self) = @_;

    return unless $self->{ssh};
    bmwqemu::diag("Closing SSH connection with " . $self->{ssh}->hostname);
    $self->{ssh}->disconnect;
    $self->{ssh} = $self->{screen} = undef;
    return;
}

sub activate {
    my ($self)   = @_;
    my $hostname = $self->{args}->{hostname} || die('we need a hostname to ssh to');
    my $password = $self->{args}->{password} // $testapi::password;
    my $username = $self->{args}->{username} // 'root';
    my $pty_cols = $self->{args}->{pty_cols} // 2048;

    bmwqemu::diag("Connecting SSH serial console for $username\@$hostname");

    my $ssh = $self->backend->new_ssh_connection(
        hostname => $hostname,
        password => $password,
        username => $username
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
        ssh_channel    => $chan,
        logfile        => $self->{args}->{logfile} // "serial_terminal.txt"
    );
    $self->{ssh} = $ssh;
    return;
}

sub is_serial_terminal { 1 }

1;
