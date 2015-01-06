#!/usr/bin/perl -w

package backend::ipmi;
use strict;
use base ('backend::baseclass');
use threads;
use threads::shared;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use Data::Dump qw/pp/;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use backend::VNC;

my $MAGIC_PIPE_CLOSE_STRING = 'xxxQUITxxx';

sub init() {
    my $self = shift;
}

# baseclass virt method overwrite

sub send_key($) {
    my ( $self, $key ) = @_;
    $self->send({ 'cmd' => "send_key", 'arguments' => { 'key' => $key } });
}

sub type_string($$) {
    my ( $self, $text, $max_interval ) = @_;
    return unless ($text);
    $self->send({ 'cmd' => "type_string", 'arguments' => { 'text' => $text, 'max_interval' => $max_interval } });
}

sub mouse_set($$) {
    my $self = shift;
    my ( $x, $y ) = @_;

    $self->send({ 'cmd' => "mouse_set", 'arguments' => { 'x' => $x, 'y' => $y } } );
    %backend::baseclass::last_mouse_coords = ( 'x' => $x, 'y' => $y );
}

sub mouse_button($$$) {
    my ( $self, $button, $bstate ) = @_;
    $self->send({ 'cmd' => "mouse_button", 'arguments' => { 'button' => $button, 'bstate' => $bstate } } );
}

sub mouse_hide(;$);
sub mouse_hide(;$) {
    my $self = shift;
    my $border_offset = shift || 0;

    my $counter = 0;
    while ( $counter < 10 ) {
        my $rsp = $self->send({ 'cmd' => "mouse_hide", 'arguments' => { 'border_offset' => $border_offset } } );
        last if $rsp->{absolute} ne '0';
        sleep 1;
        $counter++;
    }
}

sub do_start_vm($) {
    my $self = shift;
    #$self->start_qemu(\%bmwqemu::vars);
    die "startqemu failed: $@" if $@;
    bmwqemu::save_vars(); # update variables
    my $mgmtcon = $self->{mgmt} = backend::ipmi::mgmt->new();
    $self->{mgmt}->start($self);
}

# baseclass virt method overwrite end

sub send($) {
    my $self   = shift;
    my $cmdstr = shift;

    #bmwqemu::diag "backend::send -> $cmdstr";
    my $rspt = $self->{mgmt}->send($cmdstr);
    if (!$rspt) {
        write_crash_file();
        Carp::confess "no answer from mgmt thread";
    }
    #bmwqemu::diag "backend::send -> $cmdstr -> '$rspt'";
    my $rsp  = JSON::decode_json($rspt);
    if ( $rsp->{rsp}->{error} ) {
        write_crash_file();
        Carp::croak JSON::to_json($rsp);
    }

    bmwqemu::diag "backend::send $cmdstr -> $rspt";
    return $rsp->{rsp};
}

# management console end

package backend::ipmi::mgmt;

use threads;
use threads::shared;

my $qemu_lock : shared;

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

sub start($) {
    my $self = shift;
    my $backend = shift;

    my $p1, my $p2;
    pipe( $p1, $p2 ) or die "pipe: $!";
    $self->{from_parent} = $p1;
    $self->{to_child}    = $p2;

    $p1 = undef;
    $p2 = undef;
    pipe( $p1, $p2 ) or die "pipe: $!";
    $self->{to_parent}  = $p2;
    $self->{from_child} = $p1;

    #printf STDERR "$$: to_child %d, from_child %d\n", fileno( $self->{to_child} ), fileno( $self->{from_child} );
    #printf STDERR "$$: VNC %d\n", $bmwqemu::vars{VNC};

    my $tid = shared_clone( threads->create( \&_run, fileno( $self->{from_parent} ), fileno( $self->{to_parent} ),$bmwqemu::vars{VNC} ) );
    $self->{runthread} = $tid;
}

sub send {
    my $self = shift;
    my $cmd  = shift;

    if ( !ref($cmd) ) {
        $cmd = translate_cmd($cmd);
    }
    my $json = JSON::encode_json($cmd);

    #print STDERR "locking QEMU: $json\n";
    lock($qemu_lock);

    #print STDERR "SENT to child $json " . threads->tid() . "\n";
    my $wb = syswrite( $self->{to_child}, "$json\n" );
    die "syswrite failed $!" unless ( $wb == length($json) + 1 );
    my $rsp = '';

    my $s = IO::Select->new();
    $s->add( $self->{from_child} );

    while (1) {
        my $buffer;

        #print STDERR "before read from_child\n";
        unless ( $s->can_read(60) ) {
            bmwqemu::diag "ERROR: 60 seconds no reply to send '" . Data::Dump::pp($cmd) . "'";
            return undef;
        }
        my $bytes = sysread( $self->{from_child}, $buffer, 1000 );

        #print STDERR "from_child got $bytes\n";
        return undef unless ($bytes);
        if ( !$rsp && $buffer eq $MAGIC_PIPE_CLOSE_STRING ) {
            bmwqemu::diag "got quit from management thread";
            return undef;
        }
        $rsp .= $buffer;
        my $hash = eval { JSON::decode_json($rsp); };
        if ($hash) {

            #		   print STDERR "RSP $rsp\n";
            last;
        }
    }

    return $rsp;
}

# only valid in management thread
our $vnc;
my $mouse_xpos = 0;
my $mouse_ypos = 0;
my ( $screenshot_sec, $screenshot_usec );
my $qemupipe;
my $cmdpipe;
my $rsppipe;
my $vncport;


use Time::HiRes qw(gettimeofday);

sub wait_for_screen_stall($) {
    my $s = shift;
    $vnc->send_update_request;
    my ( $s1, $ms1 ) = gettimeofday;
    while (1) {
        my @ready = $s->can_read(.1);
        last unless @ready;
        for my $fh (@ready) {
            if ($fh == $qemupipe) {
                read_qemupipe();
            }
            else {
                $vnc->receive_message();
                enqueue_screenshot();
                $vnc->send_update_request;
            }
        }
        my ( $s2, $usec2 ) = gettimeofday;
        my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
        #bmwqemu::diag "diff $diff";
        # we can't wait longer - in password prompts there is no screen update
        last if ($diff > .8);
    }
    #my ( $s2, $usec2 ) = gettimeofday;
    #my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
    #bmwqemu::diag "done $diff";
    enqueue_screenshot();
}

sub type_string($$) {
    my ($text) = @_;
    my @letters = split( "", $text );
    my $s = IO::Select->new();
    $s->add($vnc->socket);
    $s->add($qemupipe);

    for my $letter (@letters) {
        $letter = map_letter($letter);
        $vnc->send_mapped_key($letter);
        wait_for_screen_stall($s);
    }
}

# runs in the thread to deserialize VNC commands
sub handle_vnc_command($) {

    my $cmd = shift;

    bmwqemu::diag "VNC ". JSON::to_json($cmd);

    if ($cmd->{cmd} eq 'capture') {
        my $img = $vnc->capture();
        my ( $seconds, $microseconds ) = gettimeofday;
        my $filename = "vnc.$seconds.$microseconds.png";

        $img->write($filename);
        return {'filename' => $filename};
    }

    if ($cmd->{cmd} eq 'mouse_hide') {
        $mouse_xpos = $vnc->width - 1;
        $mouse_ypos = $vnc->height - 1;

        my $border_offset = int($cmd->{arguments}->{border_offset});
        $mouse_xpos -= $border_offset;
        $mouse_ypos -= $border_offset;

        bmwqemu::diag "mouse_move $mouse_xpos, $mouse_ypos";
        $vnc->mouse_move_to($mouse_xpos, $mouse_ypos);
        return { 'absolute' => $vnc->absolute };
    }

    if ($cmd->{cmd} eq 'mouse_set') {
        # TODO: for framebuffers larger than 1024x768, we need to upscale
        $mouse_xpos = int($cmd->{arguments}->{x});
        $mouse_ypos = int($cmd->{arguments}->{y});

        bmwqemu::diag "mouse_set $mouse_xpos, $mouse_ypos";
        $vnc->mouse_move_to($mouse_xpos, $mouse_ypos);
        return {};
    }

    if ($cmd->{cmd} eq 'mouse_button') {
        my $button = $cmd->{arguments}->{button};
        my $bstate = $cmd->{arguments}->{bstate};

        my $mask = 0;
        if ($button eq 'left') {
            $mask = $bstate;
        }
        elsif ($button eq 'right') {
            $mask = $bstate << 2;
        }
        elsif ($button eq 'middle') {
            $mask = $bstate << 1;
        }
        bmwqemu::diag "pointer_event $mask $mouse_xpos, $mouse_ypos";
        $vnc->send_pointer_event( $mask, $mouse_xpos, $mouse_ypos );
        return {};
    }

    if ($cmd->{cmd} eq 'send_key') {
        bmwqemu::diag "send_mapped_key '" . $cmd->{arguments}->{key} . "'";
        $vnc->send_mapped_key($cmd->{arguments}->{key});
        my $s = IO::Select->new();
        $s->add($vnc->socket);
        wait_for_screen_stall($s);
        return {};
    }

    if ($cmd->{cmd} eq 'type_string') {
        type_string($cmd->{arguments}->{text}, $cmd->{arguments}->{max_interval});
        return {};
    }

    die "unsupported command " . $cmd->{cmd};
}

sub screenshot_interval() {
    return $bmwqemu::vars{SCREENSHOTINTERVAL} || .5;
}

sub enqueue_screenshot() {
    return unless $vnc->_framebuffer;
    my ( $s2, $usec2 ) = gettimeofday();
    my $rest = screenshot_interval() - ( $s2 - $screenshot_sec ) - ( $usec2 - $screenshot_usec ) / 1e6;

    # don't overdo it
    return unless $rest < 0.05;
    bmwqemu::enqueue_screenshot($vnc->_framebuffer->scale( 1024, 768 ));
    ( $screenshot_sec, $screenshot_usec ) = gettimeofday();
    #bmwqemu::diag "enqueue_screenshot $screenshot_sec, $screenshot_usec";
    $vnc->send_update_request();
}

sub close_pipes() {
    Carp::carp "hallo";
    close($vnc->socket) if ($vnc->socket);

    if ($cmdpipe) {
        close($cmdpipe)   || die "close $!\n";
        $cmdpipe = undef;
    }

    return unless $rsppipe;

    # XXX: perl does not really close the fd here due to threads!?
    print $rsppipe $MAGIC_PIPE_CLOSE_STRING;
    close($rsppipe) || die "close $!\n";
}

sub _run {
    $cmdpipe = shift;
    $rsppipe = shift;

    print STDERR "$$: cmdpipe $cmdpipe, rsppipe $rsppipe\n";

    $SIG{__DIE__} = sub { alarm 3 };

    $vnc = backend::VNC->new({hostname => 'obs-admin.suse.de', port => 5900, username => 'ADMIN', password => 'ADMIN', ikvm => 1});
    eval { $vnc->login; };
    if ($@) {
        close_pipes();
        die $@;
    }

    my $io = IO::Handle->new();
    $io->fdopen( $cmdpipe, "r" ) || die "r fdopen $!";
    $cmdpipe = $io;

    $io = IO::Handle->new();
    $io->fdopen( $rsppipe, "w" ) || die "w fdopen $!";
    $rsppipe = $io;
    $rsppipe->autoflush(1);

    bmwqemu::diag "started mgmt loop with thread id " . threads->tid();

    my $s = IO::Select->new();
    $s->add($cmdpipe);
    $s->add($vnc->socket);

    $vnc->send_update_request;
    ( $screenshot_sec, $screenshot_usec ) = gettimeofday();
    my $interval = screenshot_interval();

  SELECT: while (1) {
        my ( $s2, $usec2 ) = gettimeofday();
        my $rest = $interval - ( $s2 - $screenshot_sec ) - ( $usec2 - $screenshot_usec ) / 1e6;

        my @ready = $s->can_read($rest);
        # vnc is non-blocking so just try
        eval { $vnc->receive_message(); };
        if ($@) {
            bmwqemu::diag "VNC failed $@";
            last SELECT;
        }
        enqueue_screenshot();

        for my $fh (@ready) {
            my $buffer;

            if ( $fh == $cmdpipe ) {
                my $cmd = backend::baseclass::_read_json($cmdpipe);

                #print STDERR "cmd ". JSON::to_json($cmd) . "\n";

                my $rsp = handle_vnc_command($cmd);
                print $rsppipe JSON::to_json( { "cmd" => $cmd, "rsp" => $rsp } );
            }
            elsif ( $fh == $vnc->socket) {
                # already checked
            }
            elsif ( $fh == $qemupipe) {
                last SELECT unless read_qemupipe();
            }
            else {
                print STDERR "huh!\n";
            }
        }
    }

    close_pipes();

    bmwqemu::diag( "management thread exit at " . POSIX::strftime( "%F %T", gmtime ) );
}

1;

# vim: set sw=4 et:
