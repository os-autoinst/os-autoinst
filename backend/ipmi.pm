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

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
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
