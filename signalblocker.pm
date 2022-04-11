# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package signalblocker;
use Mojo::Base -base, -signatures;

use bmwqemu;
use POSIX ':signal_h';

# OpenCV forks a lot of threads and the signals we may get (TERM from the
# parent, CHLD from children) would be delivered to an undefined thread.
# But as those threads do not have a perl interpreter, the perl signal
# handler would crash. We need to block those signals in those threads, so
# that they get delivered only to those threads which can handle it.

sub new ($class, @args) {
    # block signals
    my %old_sig = %SIG;
    $SIG{TERM} = 'IGNORE';
    $SIG{INT} = 'IGNORE';
    $SIG{HUP} = 'IGNORE';
    my $sigset = POSIX::SigSet->new(SIGCHLD, SIGTERM);
    die "Could not block SIGCHLD and SIGTERM\n" unless defined sigprocmask(SIG_BLOCK, $sigset, undef);

    # create the actual object holding the information to restore the previous state
    my $self = $class->SUPER::new(@args);
    $self->{_old_sig} = \%old_sig;
    $self->{_sigset} = $sigset;
    return $self;
}

sub DESTROY ($self) {
    # set back signal handling to default to be able to terminate properly
    die "Could not unblock SIGCHLD and SIGTERM\n" unless defined sigprocmask(SIG_UNBLOCK, $self->{_sigset}, undef);
    %SIG = %{$self->{_old_sig}};
}

1;
