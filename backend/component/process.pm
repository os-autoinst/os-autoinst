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
BEGIN { $| = 1 }

use bmwqemu;
use POSIX ":sys_wait_h";
use Carp 'confess';
use Symbol 'gensym';
use IPC::Open3;
use IO::Handle;
use IO::Pipe;

use constant DEBUG => $ENV{OSAUTOINST_PROCESS_DEBUG};
has 'process_id';
has [qw(execute code process_control_id write_stream read_stream error_stream)];
has max_kill_attempts     => 5;
has kill_sleeptime        => 1;
has sleeptime_during_kill => 1;
has args                  => sub { [] };

sub _fork {
    my ($self, $code, @args) = @_;
    die "Can't spawn child without code" unless ref($code) eq "CODE";

    my $input_pipe      = IO::Pipe->new();
    my $output_pipe     = IO::Pipe->new();
    my $output_err_pipe = IO::Pipe->new();

    my $pid = fork;
    die "Cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        my $stdout = $output_pipe->writer();
        my $stderr = $output_err_pipe->writer();
        my $stdin  = $input_pipe->reader();
        open STDERR, ">&", $stderr or die $!;
        open STDOUT, ">&", $stdout or die $!;
        open STDIN,  ">&", $stdin  or die $!;
        exit $code->(@args);
    }
    $self->process_id($pid);
    $self->read_stream($output_pipe->reader());
    $self->error_stream($output_err_pipe->reader());
    $self->write_stream($input_pipe->writer());

    push @{$self->backend->{children}}, $pid if ($self->backend);

    return $self;
}

sub write {
    my ($self, @data) = @_;
    return unless $self->write_stream;
    $self->write_stream->syswrite($_) for @data;
    return $self;
}

sub getline { return unless $_[0]->read_stream; shift->read_stream->getline; }

sub err_getline { return unless $_[0]->error_stream; shift->error_stream->getline; }

sub _pipe {

    my ($self, @args) = @_;
    warn 'Pipe: ' . (join ', ', map { "'$_'" } @args) . "\n" if DEBUG;

    my ($wtr, $rdr, $err);
    $err = gensym;
    my $pid = open3($wtr, $rdr, $err, @args);

    die "Cannot create pipe: $!" unless defined $pid;
    $self->process_id($pid);

    $self->read_stream(IO::Handle->new_from_fd($rdr, "r"));
    $self->write_stream(IO::Handle->new_from_fd($wtr, "w"));
    $self->error_stream(IO::Handle->new_from_fd($err, "r"));

    return $self;
}

sub is_running {
    return $_[0]->process_id ? kill 0 => $_[0]->process_id : 0;
}

sub start {
    my $self = shift;
    return $self if $self->is_running;
    die "Nothing to do" unless !!$self->execute || !!$self->code;

    $self->_fork(
        sub {
            local $SIG{TERM} = sub { exit 0 };
            &{$self->code()}->(@{$self->args});
        }) if !!$self->code;

    $self->_pipe($self->execute, (@{$self->args}) x !!($self->args && ref($self->args) eq "ARRAY")) if !!$self->execute;

    return $self;
}

sub stop {
    my $self = shift;
    return $self unless $self->is_running;

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
        delete $self->{process_id};
    }

    return $self;
}

sub restart {
    my $self = shift;

    if ($self->is_running) {
        $self->stop->start();
    }
    else {
        $self->start();
    }

    return $self;
}
1;
