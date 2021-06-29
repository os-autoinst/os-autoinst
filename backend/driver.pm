# Copyright © 2009-2013 Bernhard M. Wiedemann
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

# this class is what presents $backend in isotovideo and its code runs
# in the main process. But its main task is to start a 2nd process and talk to it over
# a PIPE
# in that 2nd process runs the actual backend, derived from backend::baseclass

package backend::driver;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use Carp 'croak';
use Mojo::JSON 'to_json';
use File::Path 'remove_tree';
use POSIX '_exit';
require IPC::System::Simple;
use Mojo::IOLoop::ReadWriteProcess 'process';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';
use myjsonrpc;
use signalblocker;

sub new ($class, $name) {
    my $self = bless({class => $class}, $class);

    require "backend/$name.pm";
    $self->{backend}      = "backend::$name"->new();
    $self->{backend_name} = $name;

    session->on(
        collected_orphan => sub {
            my ($session, $p) = @_;
            bmwqemu::fctinfo("Driver backend collected unknown process with pid " . $p->pid . " and exit status: " . $p->exit_status);
        });

    $self->start();

    return $self;
}

sub start ($self) {
    open(my $STDOUTPARENT, '>&', *STDOUT);
    open(my $STDERRPARENT, '>&', *STDERR);

    my $backend_process = process(
        sleeptime_during_kill       => .1,
        total_sleeptime_during_kill => 30,
        max_kill_attempts           => 1,
        kill_sleeptime              => 0,
        blocking_stop               => 1,
        separate_err                => 0,
        subreaper                   => 1,
        code                        => sub {
            my $process = shift;
            $0 = "$0: backend";

            open STDOUT, ">&", $STDOUTPARENT;
            open STDERR, ">&", $STDERRPARENT;

            # initialize OpenCV
            my $signal_blocker = signalblocker->new;
            require cv;
            cv::init();
            require tinycv;
            tinycv::create_threads();
            undef $signal_blocker;

            $self->{backend}->run(fileno($process->channel_in), fileno($process->channel_out));
        })->start;

    $backend_process->on(collected => sub { bmwqemu::diag("backend process exited: " . shift->exit_status) });

    bmwqemu::diag("$$: channel_out " . fileno($backend_process->channel_out) . ', channel_in ' . fileno($backend_process->channel_in));
    $self->{backend_pid}     = $backend_process->pid;
    $self->{backend_process} = $backend_process;
}

sub extract_assets ($self) {
    $self->{backend}->do_extract_assets(@_);
}

sub stop ($self, $cmd) {
    return unless $self->{backend_process}->is_running;

    $self->stop_backend()                        if $self->{backend_process}->channel_out;
    close($self->{backend_process}->channel_out) if $self->{backend_process}->channel_out;
    close($self->{backend_process}->channel_in)  if $self->{backend_process}->channel_in;
    $self->{backend_process}->channel_in(undef);
    $self->{backend_process}->channel_out(undef);
    $self->{backend_process}->stop;
}

# new api

sub start_vm ($self) {
    my $json = to_json({backend => $self->{backend_name}});
    open(my $runf, ">", 'backend.run');
    print $runf "$json\n";
    close $runf;

    # remove old screenshots
    remove_tree($bmwqemu::screenshotpath);
    mkdir $bmwqemu::screenshotpath;

    $self->_send_json({cmd => 'start_vm'}) || die "failed to start VM";
    return 1;
}

sub stop_backend ($self) {
    $self->_send_json({cmd => 'stop_vm'});
    # remove if still existant
    unlink('backend.run') if -e 'backend.run';
    return;
}

# new api end

sub mouse_hide ($self, $border_offset) {
    $border_offset ||= 0;

    return $self->_send_json({cmd => 'mouse_hide', arguments => {border_offset => $border_offset}});
}

# virtual methods end

sub _send_json ($self, $cmd) {
    croak "no backend running" unless $self->{backend_process}->channel_in;
    my $token = myjsonrpc::send_json($self->{backend_process}->channel_in, $cmd);
    my $rsp   = myjsonrpc::read_json($self->{backend_process}->channel_out, $token);

    return $rsp->{rsp} if defined $rsp;
    # this might have been closed by signal handler
    no autodie 'close';
    close($self->{backend_process}->channel_out);
    $self->{backend_process}->channel_out(undef);
    $self->{backend_process}->stop;
    return;
}

1;
