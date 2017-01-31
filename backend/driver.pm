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
use myjsonrpc;


sub new {
    my ($class, $name) = @_;
    my $self = bless({class => $class}, $class);

    require "backend/$name.pm";    ## no critic
    $self->{backend}      = "backend::$name"->new();
    $self->{backend_name} = $name;

    $self->start();

    return $self;
}

sub start {
    my ($self) = @_;

    my $p1, my $p2;
    pipe($p1, $p2) or OpenQA::Log::die("pipe: $!");
    $self->{from_parent} = $p1;
    $self->{to_child}    = $p2;

    $p1 = undef;
    $p2 = undef;
    pipe($p1, $p2) or OpenQA::Log::die("pipe: $!");
    $self->{to_parent}  = $p2;
    $self->{from_child} = $p1;

    OpenQA::Log::warn sprintf "$$: to_child %d, from_child %d\n", fileno($self->{to_child}), fileno($self->{from_child});

    my $pid = fork();
    OpenQA::Log::die "fork failed" unless defined $pid;

    if ($pid == 0) {
        $SIG{TERM} = 'DEFAULT';
        $SIG{INT}  = 'DEFAULT';
        $SIG{HUP}  = 'DEFAULT';
        $SIG{CHLD} = 'DEFAULT';
        $0         = "$0: backend";

        # now initialize opencv
        require cv;

        cv::init();
        require tinycv;

        $self->{backend}->run(fileno($self->{from_parent}), fileno($self->{to_parent}));
        _exit(0);
    }
    else {
        $self->{backend_pid} = $pid;
    }
}

sub extract_assets {
    my $self = shift;
    $self->{backend}->do_extract_assets(@_);
}

sub stop {
    my ($self, $cmd) = @_;

    return unless ($self->{backend_pid});

    $self->stop_backend() if $self->{from_child};
    close($self->{from_child}) if $self->{from_child};
    $self->{from_child} = undef;

    close($self->{to_child}) if ($self->{to_child});
    $self->{to_child} = undef;

    waitpid($self->{backend_pid}, 0) if $self->{backend_pid};
    $self->{backend_pid} = undef;
}

# new api

sub start_vm {
    my $self = shift;
    my $json = to_json({backend => $self->{backend_name}});
    open(my $runf, ">", 'backend.run');
    print $runf "$json\n";
    close $runf;

    # remove old screenshots
    OpenQA::Log::debug "remove_tree $bmwqemu::screenshotpath\n";
    remove_tree($bmwqemu::screenshotpath);
    mkdir $bmwqemu::screenshotpath;

    $self->_send_json({cmd => 'start_vm'}) || OpenQA::Log::die "failed to start VM";
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

    # TODO: come up with a better solution - this is qemu specific.
    my $counter = 0;
    my $rsp;
    while ($counter < 10) {
        $rsp = $self->_send_json({cmd => 'mouse_hide', arguments => {border_offset => $border_offset}});
        last if $rsp->{absolute} ne '0';
        sleep 1;
        $counter++;
    }
    return $rsp;
}

# virtual methods end

sub _send_json {
    my ($self, $cmd) = @_;

    croak "no backend running" unless $self->{to_child};
    my $token = myjsonrpc::send_json($self->{to_child}, $cmd);
    my $rsp = myjsonrpc::read_json($self->{from_child}, $token);
    unless (defined $rsp) {
        # this might have been closed by signal handler
        no autodie 'close';
        close($self->{from_child});
        $self->{from_child} = undef;
        $self->stop();
        return;
    }
    return $rsp->{rsp};
}

1;
# vim: set sw=4 et:
