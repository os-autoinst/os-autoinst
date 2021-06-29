# Copyright © 2012-2021 SUSE LLC
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

package consoles::ipmiSol;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::console';

require IPC::System::Simple;
use POSIX '_exit';
use bmwqemu;
use IO::Pipe;

sub activate ($self) {
    $self->{serial_pipe} = IO::Pipe->new();

    setpgrp 0, 0;
    $self->{serialpid} = fork();

    if ($self->{serialpid}) {
        $self->{serial_pipe}->writer();
        bmwqemu::diag "started ipmiconsole $self->{serialpid}";
        return;
    }

    local $SIG{TERM} = 'DEFAULT';

    # a child was born
    $self->{serial_pipe}->reader();

    my @cmd = ('/usr/sbin/ipmiconsole', '-h', $bmwqemu::vars{IPMI_HOSTNAME});
    push(@cmd, ('-u', $bmwqemu::vars{IPMI_USER}, '-p', $bmwqemu::vars{IPMI_PASSWORD}));

    # zypper in dumponlyconsole, check devel:openQA for a patched freeipmi version that doesn't grab the terminal
    push(@cmd, '--dumponly');

    # our supermicro boards need workarounds to get SOL ;(
    push(@cmd, qw(-W nochecksumcheck));

    my $ipmi_console;
    $self->{consolepid} = open($ipmi_console, '-|', @cmd);
    $ipmi_console->blocking(0);

    my $s = IO::Select->new();
    $s->add($ipmi_console);
    $s->add($self->{serial_pipe});

    # Start serial grab
    while (1) {
        my @ready = $s->can_read;
        for my $fh (@ready) {
            if ($fh == $ipmi_console) {
                my $line = <$ipmi_console>;
                if (!$line) {
                    # impi_console is dead, restart it
                    $ipmi_console->close;
                    $s->remove($ipmi_console);
                    my $ret = waitpid($self->{consolepid}, 0);
                    bmwqemu::diag "SOL failed, reconnecting [$ret]\n";
                    sleep 1;
                    $self->{consolepid} = open($ipmi_console, '-|', @cmd);
                    $ipmi_console->blocking(0);
                    $s->add($ipmi_console);
                    next;
                }
                open(my $serial, '>>', $self->{args}->{serialfile});
                print $serial $line;
                close($serial);
            }
            else {
                kill(TERM => $self->{consolepid});
                $ipmi_console->close;
                waitpid($self->{consolepid}, 0);
                _exit(0);
            }
        }
    }
    _exit(0);
}

sub disable ($self) {
    return unless $self->{serialpid};
    $self->{serial_pipe}->print("GO!\n");
    $self->{serial_pipe}->close;
    bmwqemu::diag "waiting for termination of ipmiconsole $self->{serialpid}";
    my $ret = waitpid($self->{serialpid}, 0);
    $self->{serialpid} = undef;
    return $ret;
}

# we have no screen
sub screen { }

1;
