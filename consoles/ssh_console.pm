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
package consoles::ssh_console;
use 5.018;
use warnings;
use autodie;
use Scalar::Util 'blessed';
use Cwd;
use consoles::serial_screen;

use base 'consoles::console';

our $VERSION;

sub new {
    my ($class, $testapi_console, $args) = @_;
    my $self = $class->SUPER::new($testapi_console, $args);
    $self->{hostname}       = $args->{hostname};
    $self->{password}       = $args->{password};
    $self->{username}       = $args->{username};
    $self->{preload_buffer} = '';
    return $self;
}

sub screen {
    my ($self) = @_;
    return $self->{screen};
}

sub disable {
    my ($self) = @_;
    if ($self->{shell}) {
        $self->{shell}->close();
        $self->{ssh}->disconnect;
        $self->{ssh}    = undef;
        $self->{screen} = undef;
    }
}

sub activate {
    my ($self, $args) = @_;

    my $hostname = $self->{hostname} || die('we need a hostname to ssh to');
    my $password = $self->{password};
    my $username = $self->{username};

    $self->{ssh} = $self->backend->new_ssh_connection(hostname => $hostname, password => $password, username => $username);
    my $chan = $self->{shell} = $self->{ssh}->channel();
    $chan->pty(1);
    $chan->shell();
    print $chan "PS1='# '\n";
    print $chan "exec 2>&1\n";

    $self->{screen} = consoles::serial_screen->new($chan, $self->{ssh}->sock);
    return;
}

sub is_serial_terminal {
    return 1;
}

1;
