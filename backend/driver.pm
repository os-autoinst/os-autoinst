# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

# this class is what presents $backend in isotovideo and its code runs
# in the main process. But its main task is to start a 2nd process and talk to it over
# a PIPE
# in that 2nd process runs the actual backend, derived from backend::baseclass

package backend::driver;
use strict;
use Carp qw(cluck carp croak confess);
use JSON 'to_json';
use File::Path 'remove_tree';
use IO::Select;
use POSIX '_exit';
require IPC::System::Simple;
use autodie ':all';
use Mojo::IOLoop::ReadWriteProcess 'process';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';
use myjsonrpc;
use bmwqemu;    # TODO: move the whole printing out of bmwqemu

sub new {
    my ($class, $name) = @_;
    my $self = bless({class => $class}, $class);

    require "backend/$name.pm";    ## no critic
    $self->{backend}      = "backend::$name"->new();
    $self->{backend_name} = $name;

    session->on(
        collected_orphan => sub {
            my ($session, $p) = @_;
            bmwqemu::diag("Driver backend collected unknown process with pid " . $p->pid . " and exit status: " . $p->exit_status);
        });

    $self->start();

    return $self;
}

sub start {
    my ($self) = @_;

    open(my $STDOUTPARENT, '>&', *STDOUT);
    open(my $STDERRPARENT, '>&', *STDERR);

    my $backend_process = process(sub {
            my $process = shift;
            $SIG{TERM} = 'DEFAULT';
            $SIG{INT}  = 'DEFAULT';
            $SIG{HUP}  = 'DEFAULT';
            #  $SIG{CHLD} = 'DEFAULT';
            $0 = "$0: backend";

            open STDOUT, ">&", $STDOUTPARENT;
            open STDERR, ">&", $STDERRPARENT;
            # now initialize opencv
            require cv;

            cv::init();
            require tinycv;

            $self->{backend}->run(fileno($process->channel_in), fileno($process->channel_out));
            _exit(0);
    })->blocking_stop(1)->separate_err(0)->subreaper(1)->start;

    $backend_process->on(collected => sub { bmwqemu::diag("backend process exited: " . shift->exit_status) });

    printf STDERR "$$: channel_out %d, channel_in %d\n", fileno($backend_process->channel_out), fileno($backend_process->channel_in);
    $self->{backend_pid}     = $backend_process->pid;
    $self->{backend_process} = $backend_process;
}

sub extract_assets {
    my $self = shift;
    $self->{backend}->do_extract_assets(@_);
}

sub stop {
    my ($self, $cmd) = @_;
    return unless $self->{backend_process}->is_running;

    $self->stop_backend()                        if $self->{backend_process}->channel_out;
    close($self->{backend_process}->channel_out) if $self->{backend_process}->channel_out;
    close($self->{backend_process}->channel_in)  if $self->{backend_process}->channel_in;
    $self->{backend_process}->channel_in(undef);
    $self->{backend_process}->channel_out(undef);
    $self->{backend_process}->stop;
}

# new api

sub start_vm {
    my $self = shift;
    my $json = to_json({backend => $self->{backend_name}});
    open(my $runf, ">", 'backend.run');
    print $runf "$json\n";
    close $runf;

    # remove old screenshots
    print "remove_tree $bmwqemu::screenshotpath\n";
    remove_tree($bmwqemu::screenshotpath);
    mkdir $bmwqemu::screenshotpath;

    $self->_send_json({cmd => 'start_vm'}) || die "failed to start VM";
    return 1;
}

sub stop_backend {
    my ($self) = @_;
    $self->_send_json({cmd => 'stop_vm'});
    # remove if still existant
    unlink('backend.run') if -e 'backend.run';
    return;
}

# new api end

sub mouse_hide {
    my ($self, $border_offset) = @_;
    $border_offset ||= 0;

    return $self->_send_json({cmd => 'mouse_hide', arguments => {border_offset => $border_offset}});
}

# virtual methods end

sub _send_json {
    my ($self, $cmd) = @_;
    croak "no backend running" unless $self->{backend_process}->channel_in;
    my $token = myjsonrpc::send_json($self->{backend_process}->channel_in, $cmd);
    my $rsp = myjsonrpc::read_json($self->{backend_process}->channel_out, $token);

    unless (defined $rsp) {
        # this might have been closed by signal handler
        no autodie 'close';
        close($self->{backend_process}->channel_out);
        $self->{backend_process}->channel_out(undef);
        $self->{backend_process}->stop;
        return;
    }
    return $rsp->{rsp};
}

1;
# vim: set sw=4 et:
