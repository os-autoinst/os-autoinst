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
use base 'Mojo::EventEmitter';
use bmwqemu;
use POSIX ":sys_wait_h";
use Carp 'confess';
use Symbol 'gensym';
use IPC::Open3;
use IO::Handle;
use IO::Pipe;
use IO::Select;

use constant DEBUG => $ENV{OSAUTOINST_PROCESS_DEBUG};
has 'process_id';
has [qw(execute code write_stream read_stream error_stream channel_in channel_out exit_status)];
has max_kill_attempts     => 5;
has kill_sleeptime        => 1;
has sleeptime_during_kill => 1;
has args                  => sub { [] };
has separate_err          => 1;
has autoflush             => 1;
has error                 => sub { [] };
has set_pipes             => 1;

sub _open {
    my ($self, @args) = @_;
    warn 'Open: ' . (join ', ', map { "'$_'" } @args) . "\n" if DEBUG;

    my ($wtr, $rdr, $err);
    $err = gensym;
    my $pid = open3($wtr, $rdr, ($self->separate_err) ? $err : undef, @args);

    die "Cannot create pipe: $!" unless defined $pid;
    $self->process_id($pid);

    return $self unless $self->set_pipes();

    $self->read_stream(IO::Handle->new_from_fd($rdr, "r"));
    $self->write_stream(IO::Handle->new_from_fd($wtr, "w"));
    $self->error_stream(($self->separate_err) ? IO::Handle->new_from_fd($err, "r") : $self->write_stream);

    return $self;
}

sub _fork {
    my ($self, $code, @args) = @_;
    die "Can't spawn child without code" unless ref($code) eq "CODE";

    # STDIN/STDOUT/STDERR redirect.
    my ($input_pipe, $output_pipe, $output_err_pipe);

    # Separated handles that could be used for internal comunication.
    my ($channel_in, $channel_out);

    # Internal pipes to retrieve error/return
    my $return_pipe       = IO::Pipe->new();
    my $internal_err_pipe = IO::Pipe->new();

    if ($self->set_pipes) {
        $input_pipe      = IO::Pipe->new();
        $output_pipe     = IO::Pipe->new();
        $output_err_pipe = IO::Pipe->new();
        $channel_in      = IO::Pipe->new();
        $channel_out     = IO::Pipe->new();
    }

    my $pid = fork;
    die "Cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        local $SIG{TERM} = sub { exit 1 };

        my $return       = $return_pipe->writer();
        my $internal_err = $internal_err_pipe->writer();
        $return->autoflush(1);
        $internal_err->autoflush(1);

        # Set pipes to redirect STDIN/STDOUT/STDERR + channels if desired
        if ($self->set_pipes()) {
            my $stdout = $output_pipe->writer();
            my $stderr = ($self->separate_err) ? $output_err_pipe->writer() : $stdout;
            my $stdin  = $input_pipe->reader();
            open STDERR, ">&", $stderr or !!$internal_err->write($!) or die $!;
            open STDOUT, ">&", $stdout or !!$internal_err->write($!) or die $!;
            open STDIN,  ">&", $stdin  or !!$internal_err->write($!) or die $!;

            $self->read_stream($stdin);
            $self->error_stream($stderr);
            $self->write_stream($stdout);

            $self->channel_in($channel_in->reader);
            $self->channel_out($channel_out->writer);
            $self->$_->autoflush($self->autoflush) for qw(read_stream error_stream write_stream channel_in channel_out);
        }

        my $rt;
        eval { $rt = $code->($self, @args); };
        $internal_err->write($@) if $@;
        $return->write($rt);
        exit 0;
    }
    $self->process_id($pid);

    my $return_reader       = $return_pipe->reader();
    my $internal_err_reader = $internal_err_pipe->reader();

    # Defered collect of return status
    $self->on(
        stop => sub {
            push(@{$self->error}, ['Cannot read from return code pipe']) unless IO::Select->new($return_reader)->can_read(10);
            push(@{$self->error}, ['Cannot read from errors pipe'])      unless IO::Select->new($internal_err_reader)->can_read(10);

            my @result_return = $return_reader->getlines();
            my @result_error  = $internal_err_reader->getlines();

            $self->exit_status(@result_return) if @result_return;
            push(@{$self->error}, @result_error) if @result_error;
        });

    push @{$self->backend->{children}}, $pid if ($self->backend);

    return $self unless $self->set_pipes();

    $self->read_stream($output_pipe->reader);
    $self->error_stream(($self->separate_err) ? $output_err_pipe->reader() : $self->read_stream());
    $self->write_stream($input_pipe->writer);
    $self->channel_in($channel_in->writer);
    $self->channel_out($channel_out->reader);
    $self->$_->autoflush($self->autoflush) for qw(read_stream error_stream write_stream channel_in channel_out);

    return $self;
}

# Convenience functions
sub _syswrite { my $stream = shift; return unless $stream; $stream->syswrite($_ . "\n") for @_; }
sub _getline { return unless IO::Select->new($_[0])->can_read(10); shift->getline; }
sub _getlines { return unless IO::Select->new($_[0])->can_read(10); wantarray ? shift->getlines : join '\n', @{[shift->getlines]}; }

# Write to the controlled-process STDIN
sub write_stdin {
    my ($self, @data) = @_;
    _syswrite($self->write_stream, @data);
    return $self;
}

# Write to the channel
sub write_channel {
    my ($self, @data) = @_;
    _syswrite($self->channel_in, @data);
    return $self;
}

# Get a line from the current process output stream
sub read_stdout { _getline(shift->read_stream) }

# Get a line from the process channel
sub read_channel { _getline(shift->channel_out) }

# Get a line from the current process output stream
sub read_stderr { return $_[0]->getline unless $_[0]->separate_err; _getline(shift->error_stream); }

# Get all lines from the current process output stream
sub read_all_stdout { _getlines(shift->read_stream) }

# Get all lines from the process channel
sub read_all_channel { _getlines(shift->channel_out); }

# Get all lines from the current process output stream
sub read_all_stderr { return $_[0]->getline unless $_[0]->separate_err; _getlines(shift->error_stream); }

# Start the process
sub start {
    my $self = shift;
    return $self if $self->is_running;
    die "Nothing to do" unless !!$self->execute || !!$self->code;

    $self->_fork($self->code) if !!$self->code;

    $self->_open($self->execute, (@{$self->args}) x !!($self->args && ref($self->args) eq "ARRAY")) if !!$self->execute;

    return $self;
}

# Stop the process and retrieve child status
sub stop {
    my $self = shift;
    return $self unless $self->is_running;

    my $ret;
    my $attempt = 0;
    do {
        sleep $self->sleeptime_during_kill if $self->sleeptime_during_kill;
        kill POSIX::SIGTERM => $self->process_id;
        $ret = waitpid($self->process_id, WNOHANG);
        $self->exit_status($? >> 8);
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

    $self->emit('stop');

    return $self;
}

# Restart process if running, otherwise starts it
sub restart { $_[0]->is_running ? $_[0]->stop->start : $_[0]->start; }

# Check if process is currently running
sub is_running { return $_[0]->process_id ? kill 0 => $_[0]->process_id : 0; }

# General alias
*pid           = \&process_id;
*return_status = \&exit_status;

# Aliases - write
*write         = \&write_stdin;
*stdin         = \&write_stdin;
*channel_write = \&write_channel;

# Aliases - read
*read             = \&read_stdout;
*stdout           = \&read_stdout;
*getline          = \&read_stdout;
*stderr           = \&read_stderr;
*err_getline      = \&read_stderr;
*channel_read     = \&read_channel;
*read_all         = \&read_all_stdout;
*getlines         = \&read_all_stdout;
*stderr_all       = \&read_all_stderr;
*err_getlines     = \&read_all_stderr;
*channel_read_all = \&read_all_channel;

# Aliases - IO::Handle
*stdin_handle        = \&write_stream;
*stdout_handle       = \&read_stream;
*stderr_handle       = \&error_stream;
*channe_write_handle = \&channel_in;
*channel_read_handle = \&channel_out;

1;
