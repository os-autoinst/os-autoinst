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

# this class is what everyone else refers to as $bmwqemu::backend and its code runs
# in the main thread. But its main task is to start a 2nd thread and talk to it over
# a PIPE (thanks to perl's insane approach to threads).
# in that 2nd thread runs the actual backend, derived from backend::baseclass

package backend::driver;
use strict;
use threads;
use threads::shared;
use Carp qw(cluck carp croak confess);
use JSON qw( to_json );
use File::Path qw(remove_tree);
use IO::Select;
require IPC::System::Simple;
use autodie qw(:all);

# TODO: move the whole printing out of bmwqemu
sub diag {
    my ($text) = @_;

    print "$text\n";
}

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
    pipe($p1, $p2) or die "pipe: $!";
    $self->{from_parent} = $p1;
    $self->{to_child}    = $p2;

    $p1 = undef;
    $p2 = undef;
    pipe($p1, $p2) or die "pipe: $!";
    $self->{to_parent}  = $p2;
    $self->{from_child} = $p1;

    printf STDERR "$$: to_child %d, from_child %d\n", fileno($self->{to_child}), fileno($self->{from_child});

    my $tid = shared_clone(threads->create(\&_run, $self->{backend}, fileno($self->{from_parent}), fileno($self->{to_parent})));
    $self->{runthread} = $tid;
}

sub extract_assets {
    my $self = shift;
    $self->{backend}->do_extract_assets(@_);
}

# this is the backend thread
sub _run {
    my ($backend, $from_parent, $to_parent) = @_;

    $backend->run($from_parent, $to_parent);
}

sub stop {
    my $self = shift;
    my $cmd  = shift;

    return unless ($self->{runthread});

    $self->stop_thread() if $self->{from_child};
    close($self->{from_child}) if $self->{from_child};
    $self->{from_child} = undef;

    close($self->{to_child}) if ($self->{to_child});
    $self->{to_child} = undef;

    $self->{runthread}->join() if $self->{runthread};
    $self->{runthread} = undef;
}

# new api

sub start_vm {
    my $self = shift;
    my $json = to_json($self->get_info());
    open(my $runf, ">", 'backend.run');
    print $runf "$json\n";
    close $runf;

    # remove old screenshots
    print "remove_tree $bmwqemu::screenshotpath\n";
    remove_tree($bmwqemu::screenshotpath);
    mkdir $bmwqemu::screenshotpath;

    $self->_send_json({cmd => 'start_vm'}) || die "failed to start VM";
    # the backend thread might have added some defaults for the backend
    bmwqemu::load_vars();

    $self->post_start_hook();
    return 1;
}

sub stop_thread {
    my ($self) = @_;
    $self->stop_vm();
    # remove if still existant
    unlink('backend.run') if -e 'backend.run';
    return;
}

sub get_info {
    my ($self) = @_;
    $self->{infos} ||= {
        backend      => $self->{backend_name},
        backend_info => $self->get_backend_info()};
    return $self->{infos};
}

# new api end

sub send_key {
    my ($self, $key) = @_;
    return $self->_send_json({cmd => 'send_key', arguments => {key => $key}});
}

sub mouse_button {
    my ($self, $button, $bstate) = @_;
    return $self->_send_json({cmd => 'mouse_button', arguments => {button => $button, bstate => $bstate}});
}

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

sub AUTOLOAD {
    my ($self, $args) = @_;
    $args ||= {};    # default

    my $cmd = our $AUTOLOAD;
    $cmd =~ s,.*::,,;

    unless (ref($args) eq 'HASH') {
        carp "we require a hash as arguments for $cmd";
    }

    # allow symbolic references
    no strict 'refs';    ## no critic
    *$AUTOLOAD = sub { my ($self, $args) = @_; return $self->_send_json({cmd => $cmd, arguments => $args}); };
    goto &$AUTOLOAD;     # Restart the new routine.
}

# virtual methods end

sub _send_json {
    my $self = shift;
    my $cmd  = shift;
    # TODO: make this a class object
    # allow regular expressions to be automatically converted into
    # strings, using the Regex::TO_JSON function as defined at the end
    # of this file.
    my $JSON = JSON->new()->convert_blessed();
    my $json = $JSON->encode($cmd);

    croak "no backend running" unless ($self->{to_child});
    my $wb = syswrite($self->{to_child}, "$json");
    die "syswrite failed $!" unless ($wb == length($json));

    my $rsp = _read_json($self->{from_child});
    unless ($rsp) {
        close($self->{from_child});
        $self->{from_child} = undef;
        $self->stop();
        return;
    }
    return $rsp->{rsp};
}

# hash for keeping state
our $sockets;

# utility function
sub _read_json {
    my ($socket) = @_;

    my $fd = fileno($socket);
    if (!exists $sockets->{$fd}) {
        $sockets->{$fd} = JSON->new();
    }

    my $JSON = $sockets->{$fd};

    my $s = IO::Select->new();
    $s->add($socket);

    my $hash;

    # starting a IPMI host can take a while, so we need to be patient

    # the goal here is to find the end of the next valid JSON - and don't
    # add more data to it. As the backend sends things unasked, we might
    # run into the next message otherwise
    while (1) {
        $hash = $JSON->incr_parse();
        if ($hash) {
            if ($hash->{QUIT}) {
                print "received magic close\n";
                return;
            }
            return $hash;
        }

        # wait for next read
        my @res = $s->can_read;
        unless (@res) {
            my $E = $!;    # save the error
            backend::baseclass::write_crash_file();
            confess "ERROR: timeout reading JSON reply: $E\n";
        }

        my $qbuffer;
        my $bytes = sysread($socket, $qbuffer, 8000);
        if (!$bytes) { diag("sysread failed: $!"); return; }
        $JSON->incr_parse($qbuffer);
    }

    return $hash;
}

###################################################################
# enable _send_json to send regular expressions
#<<< perltidy off
# this has to be on two lines so other tools don't believe this file
# exports package Regexp
package
Regexp;
#>>> perltidy on
sub TO_JSON {
    my $regex = shift;
    $regex = "$regex";
    return $regex;
}

1;
# vim: set sw=4 et:
