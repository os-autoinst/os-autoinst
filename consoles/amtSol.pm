# Copyright © 2012-2020 SUSE LLC
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

package consoles::amtSol;

use Mojo::Base -strict;
use autodie ':all';

use base 'consoles::console';

require IPC::System::Simple;
use POSIX '_exit';
use bmwqemu;
use IO::Pipe;

sub activate {
    my ($self) = @_;

    $self->{serial_pipe} = IO::Pipe->new();

    setpgrp 0, 0;
    $self->{serialpid} = fork();

    if ($self->{serialpid}) {
        $self->{serial_pipe}->writer();
        bmwqemu::diag "started amtterm $self->{serialpid}";
        return;
    }

    local $SIG{TERM} = 'DEFAULT';

    # a child was born
    $self->{serial_pipe}->reader();

    my @cmd = ('/usr/sbin/amtterm');
    push(@cmd, ('-u', 'admin', '-p', $bmwqemu::vars{AMT_PASSWORD}));
    push(@cmd, ($bmwqemu::vars{AMT_HOSTNAME}));

    my $amt_console;
    $self->{consolepid} = open($amt_console, '-|', @cmd);
    $amt_console->blocking(0);

    my $s = IO::Select->new();
    $s->add($amt_console);
    $s->add($self->{serial_pipe});

    # Start serial grab
    while (1) {
        my @ready = $s->can_read;
        for my $fh (@ready) {
            if ($fh == $amt_console) {
                my $line = <$amt_console>;
                if (!$line) {
                    # impi_console is dead, restart it
                    $amt_console->close;
                    $s->remove($amt_console);
                    my $ret = waitpid($self->{consolepid}, 0);
                    bmwqemu::diag "SOL failed, reconnecting [$ret]\n";
                    sleep 1;
                    $self->{consolepid} = open($amt_console, '-|', @cmd);
                    $amt_console->blocking(0);
                    $s->add($amt_console);
                    next;
                }
                open(my $serial, '>>', $self->{args}->{serialfile});
                print $serial $line;
                close($serial);
            }
            else {
                kill(TERM => $self->{consolepid});
                $amt_console->close;
                waitpid($self->{consolepid}, 0);
                _exit(0);
            }
        }
    }
    _exit(0);
}

sub disable {
    my ($self) = @_;
    return unless $self->{serialpid};
    $self->{serial_pipe}->print("GO!\n");
    $self->{serial_pipe}->close;
    bmwqemu::diag "waiting for termination of amtterm $self->{serialpid}";
    my $ret = waitpid($self->{serialpid}, 0);
    $self->{serialpid} = undef;
    return $ret;
}

# we have no screen
sub screen { }

1;
