# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::amtSol;

use Mojo::Base 'consoles::console', -signatures;
use autodie ':all';
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

sub disable ($self) {
    return unless $self->{serialpid};
    $self->{serial_pipe}->print("GO!\n");
    $self->{serial_pipe}->close;
    bmwqemu::diag "waiting for termination of amtterm $self->{serialpid}";
    my $ret = waitpid($self->{serialpid}, 0);
    $self->{serialpid} = undef;
    return $ret;
}

# we have no screen
sub screen ($self) { }

1;
