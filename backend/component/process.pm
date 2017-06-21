# Copyright (C) 2017 SUSE LLC
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

package backend::component::process;

use Mojo::Base 'backend::component';
use bmwqemu;
use POSIX ":sys_wait_h";
use Carp 'confess';
has 'process_id';
has 'max_kill_attempts'     => 5;
has 'kill_sleeptime'        => 1;
has 'sleeptime_during_kill' => 1;
has [qw(execute code)];

sub _fork {
    my ($self, $code) = @_;
    die "Can't spawn child without code" unless ref($code) eq "CODE";

    my $pid = fork;
    die "Cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        $code->();
        exit 0;
    }
    $self->process_id($pid);

    push @{$self->backend->{children}}, $pid if ($self->backend);

    return $self;
}

sub is_running {
    return $_[0]->process_id ? kill 0 => $_[0]->process_id : 0;
}

sub start {
    my $self = shift;
    die "Nothing to do" unless !!$self->execute || !!$self->code;

    $self->_fork(sub { exec($self->execute); }) if !!$self->execute;
    $self->_fork(
        sub {
            local $SIG{TERM} = sub { exit 0 };
            &{$self->code()}->();
        }) if !!$self->code;
    return $self;
}

sub stop {
    my $self = shift;
    return unless $self->is_running;

    my $ret;
    my $attempt = 0;
    do {
        sleep $self->sleeptime_during_kill if $self->sleeptime_during_kill;
        kill POSIX::SIGTERM => $self->process_id;
        $ret = waitpid($self->process_id, WNOHANG);
        $attempt++;
        $ret = $self->process_id if $attempt >= $self->max_kill_attempts + 1;    # At least 1 max kill attempts
    } until ($ret == $self->process_id);

    sleep $self->kill_sleeptime if $self->kill_sleeptime;

    if ($attempt > $self->max_kill_attempts + 1) {
        $self->_diag("Could not kill process id: " . $self->process_id);
    }
    else {
        $self->process_id(0);
    }

    return $self;
}

1;
