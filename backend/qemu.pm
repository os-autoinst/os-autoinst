#!/usr/bin/perl -w

package backend::qemu;
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
my $iscrashedfile           = 'backend.crashed';

sub write_crash_file {
    if (open(my $fh, ">", $iscrashedfile )) {
        print $fh "qemu\n";
        close $fh;
    }
    else {
        warn "cannot write '$iscrashedfile'";
    }
}

sub init() {
    my $self = shift;
    $self->{'mousebutton'} = shared_clone( { 'left' => 0, 'right' => 0, 'middle' => 0 } );
    $self->{'pid'}         = undef;
    $self->{'pidfilename'} = 'qemu.pid';
    STDERR->autoflush(1);
    STDOUT->autoflush(1);
}

use Benchmark qw(:all);

# baseclass virt method overwrite

sub send_key($) {
    my ( $self, $key ) = @_;
    my $keys = [ map { { 'type' => 'qcode', 'data' => $_ } } split( '-', $key ) ];
    $self->send( { "execute" => "send-key", "arguments" => { 'keys' => $keys } } );
}

# warning: will not work due to https://bugs.launchpad.net/qemu/+bug/752476
sub mouse_set($$) {
    my $self = shift;
    my ( $x, $y ) = @_;

    # ... assuming size of screen is 800x600
    # (FIXME: size from last screenshot?)
    my ( $rx, $ry ) = ( 800, 600 );
    my $ax = int( $x / $rx * 0x7fff );
    my $ay = int( $y / $ry * 0x7fff );
    $self->send("mouse_move $ax $ay");
}

sub mouse_button($$$) {
    my ( $self, $button, $bstate ) = @_;
    $self->{'mousebutton'}->{$button} = $bstate;
    my $btn_bin = 0;
    $btn_bin |= 0b001 if ( $self->{'mousebutton'}->{'left'} );
    $btn_bin |= 0b010 if ( $self->{'mousebutton'}->{'right'} );
    $btn_bin |= 0b100 if ( $self->{'mousebutton'}->{'middle'} );
    $self->send("mouse_button $btn_bin");
}

sub mouse_hide(;$) {
    my $self = shift;
    my $border_offset = shift || 0;

    $self->send({ 'VNC' => "mouse_hide", 'arguments' => { 'border_offset' => $border_offset } } );
}

sub screendump() {
    my $self = shift;
    my ( $seconds, $microseconds ) = gettimeofday;

    my $tmp = "ppm.$seconds.$microseconds.ppm";
    my $rsp = $self->send( { 'execute' => 'screendump', 'arguments' => { 'filename' => "$tmp" } } );
    my $img = tinycv::read($tmp);
    unlink $tmp;

    # now just to test vnc
    $self->send( { 'VNC' => 'capture' } );
    return $img;
}

sub raw_alive($) {
    my $self = shift;
    return 0 unless $self->{'pid'};
    return kill( 0, $self->{'pid'} );
}

sub start_audiocapture($) {
    my ( $self, $filename ) = @_;
    $self->send("wavcapture $filename 44100 16 1");
    sleep(0.1);
}

sub stop_audiocapture($) {
    my ( $self, $index ) = @_;
    $self->send("stopcapture $index");
    sleep(0.1);
}

sub power($) {

    # parameters: acpi, reset, (on), off
    my ( $self, $action ) = @_;
    if ( $action eq 'acpi' ) {
        $self->send("system_powerdown");
    }
    elsif ( $action eq 'reset' ) {
        $self->send("system_reset");
    }
    elsif ( $action eq 'off' ) {
        $self->send("quit");
    }
}

sub eject_cd(;$) {
    my $self = shift;
    $self->send( { "execute" => "eject", "arguments" => { "device" => "ide1-cd0" } } );
}

sub cpu_stat($) {
    my $self = shift;
    my $stat = bmwqemu::fileContent( "/proc/" . $self->{'pid'} . "/stat" );
    my @a    = split( " ", $stat );
    return @a[ 13, 14 ];
}

sub do_start_vm($) {
    my $self = shift;
    require 'inst/startqemu.pm';
    startqemu::run($self, \%bmwqemu::vars);
    die "startqemu failed: $@" if $@;
    bmwqemu::save_vars(); # update variables

    # remove backend.crashed
    unlink($iscrashedfile) if -e $iscrashedfile;
    $self->open_management();
    my $cnt = bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw");
    if ($cnt) {
        $self->send($cnt);
    }

}

sub do_stop_vm($) {
    my $self = shift;
    $self->close_con();
    sleep(0.1);
    waitpid($self->{pid}, WNOHANG);
    my $n;
    for (my $i = 0; $i < 3; ++$i) {
        # dead meanwhile?
        $n = kill(0, $self->{'pid'});
        last if ($n == 0);
        printf STDERR "sending TERM to %d\n", $self->{'pid'};
        $n = kill( "TERM", $self->{'pid'} );
        last if ($n == 0); # we're done when qemu is gone
        sleep 1;
        waitpid($self->{pid}, WNOHANG);
    }
    if ($n != 0) {
        printf STDERR "sending KILL to %d\n", $self->{'pid'};
        $n = kill( "KILL", $self->{'pid'} );
        sleep 1;
        waitpid($self->{pid}, WNOHANG);
        $n = kill(0, $self->{'pid'});
        warn "ERROR: qemu still not dead. wtf?" if $n;
    }
    unlink( $self->{'pidfilename'} );
}

sub do_savevm($) {
    my ( $self, $vmname ) = @_;
    my $rsp = $self->send("savevm $vmname");
    print STDERR "SAVED $vmname $rsp\n";
    die unless ( $rsp eq "savevm $vmname" );
}

sub do_loadvm($) {
    my ( $self, $vmname ) = @_;
    my $rsp = $self->send("loadvm $vmname");
    print STDERR "LOAD $vmname '$rsp'\n";
    die unless ( $rsp eq "loadvm $vmname" );
    $rsp = $self->send("stop");
    print STDERR "stop $rsp\n";
    $rsp = $self->send("cont");
    print STDERR "cont $rsp\n";
}

sub do_delvm($) {
    my ( $self, $vmname ) = @_;
    $self->send("delvm $vmname");
}

# baseclass virt method overwrite end

# management console

sub open_management($) {
    my $self = shift;
    my $mgmtcon = $self->{mgmt} = backend::qemu::mgmt->new();
    $self->{mgmt}->start();
    $self->send("cont");    # start VM execution
}

sub close_con($) {
    my $self = shift;
    return unless ( $self->{mgmt} );
    $self->{mgmt}->stop();
    $self->{mgmt} = undef;
}

sub send($) {
    my $self   = shift;
    my $cmdstr = shift;

    #print STDERR "backend::send -> $cmdstr\n";
    my $rspt = $self->{mgmt}->send($cmdstr);
    write_crash_file unless $rspt;
    my $rsp  = JSON::decode_json($rspt);
    if ( $rsp->{rsp}->{error} ) {
        write_crash_file;
        Carp::carp "er";
        die JSON::to_json($rsp);
    }

    #print STDERR "backend::send $cmdstr -> $rspt\n";
    return $rsp->{rsp}->{return};
}

sub _read_json($) {
    my $socket = shift;

    my $rsp = '';
    my $s   = IO::Select->new();
    $s->add($socket);

    my $hash;

    # make sure we read the answer completely
    while ( !$hash ) {
        my @res = $s->can_read(60);
        unless (@res) {
            write_crash_file;
            die "ERROR: timeout reading JSON reply\n";
        }
        my $qbuffer;
        my $bytes = sysread( $socket, $qbuffer, 1 );
        if ( !$bytes ) { print STDERR "sysread failed: $!\n"; return undef; }
        $rsp .= $qbuffer;
        if ( $rsp !~ m/\n/ ) { next; }
        $hash = eval { JSON::decode_json($rsp); };
    }

    #print STDERR "read json " . JSON::to_json($hash) . "\n";
    return $hash;
}

# management console end

package backend::qemu::mgmt;

use threads;
use threads::shared;

my $qemu_lock : shared;

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

sub start {
    my $self = shift;

    my $p1, my $p2;
    pipe( $p1, $p2 ) or die "pipe: $!";
    $self->{from_parent} = $p1;
    $self->{to_child}    = $p2;

    $p1 = undef;
    $p2 = undef;
    pipe( $p1, $p2 ) or die "pipe: $!";
    $self->{to_parent}  = $p2;
    $self->{from_child} = $p1;

    printf STDERR "$$: to_child %d, from_child %d\n", fileno( $self->{to_child} ), fileno( $self->{from_child} );
    printf STDERR "$$: VNC %d\n", $bmwqemu::vars{VNC};

    my $tid = shared_clone( threads->create( \&_run, fileno( $self->{from_parent} ), fileno( $self->{to_parent} ), $bmwqemu::vars{VNC} ) );
    $self->{runthread} = $tid;
}

sub stop {
    my $self = shift;
    my $cmd  = shift;

    return unless ( $self->{runthread} );

    $self->send('quit');

    print STDERR " waiting for console read thread to quit...\n";
    $self->{runthread}->join();
    print STDERR "done\n";
    $self->{runthread} = undef;
    close( $self->{to_child} );
    $self->{to_child} = undef;
    close( $self->{from_child} );
    $self->{from_child} = undef;
}

sub translate_cmd($) {
    my $cmd = shift;
    for my $knowncmd (qw(quit stop cont)) {
        if ( $cmd eq $knowncmd ) {
            return { "execute" => $cmd };
        }
    }
    return { "hmp" => $cmd };
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
            print STDERR "got quit from management thread\n";
            return undef;
        }
        $rsp .= $buffer;
        my $hash = eval { JSON::decode_json($rsp); };
        if ($hash) {

            #		   print STDERR "RSP $rsp\n";
            last;
        }
    }

    # unfortunately when qemu prompts back after screendump the image is
    # not yet ready and while it isn't, we shouldn't send new commands to qemu
    if ( $cmd->{execute} && $cmd->{execute} eq "screendump" ) {
        wait_for_img( $cmd->{arguments}->{filename} );
    }
    return $rsp;
}

sub wait_for_img($) {
    my $tmp = shift;

    my $ret;
    while ( !defined $ret ) {
        sleep(0.1);
        my $fs = -s $tmp;

        # if qemu did not even start writing out
        # after 0.1s, it's most likely dead. In case
        # this is not true on slow machines, we may
        # need to scale this - because sleeping longer
        # doesn't make sense
        return unless ($fs);
        next if ( $fs < 70 );
        my $header;
        next if ( !open( PPM, $tmp ) );
        if ( read( PPM, $header, 70 ) < 70 ) {
            close(PPM);
            next;
        }
        close(PPM);
        my ( $xres, $yres ) = ( $header =~ m/\AP6\n(?:#.*\n)?(\d+) (\d+)\n255\n/ );
        next if ( !$xres );
        my $d = $xres * $yres * 3 + length($&);
        next if ( $fs != $d );
        return;
    }
}

sub _read_hmp($) {
    my $hmpsocket = shift;

    my $rsp = '';
    my $s   = IO::Select->new();
    $s->add($hmpsocket);

    while ( my @ready = $s->can_read(60) ) {
        my $buffer;
        my $bytes = sysread( $hmpsocket, $buffer, 1000 );
        last unless ($bytes);
        $rsp .= $buffer;
        my @rsp2 = unpack( "C*", $rsp );
        my $line = '';
        for my $c (@rsp2) {
            if ( $c == 13 ) {

                # skip
            }
            elsif ( $c == 10 ) {
                $line .= "\n";
            }
            elsif ( $c == 27 ) {
                $line .= "^";
            }
            elsif ( $c < 32 ) {
                $line .= "C$c ";
            }
            else {
                $line .= chr($c);
            }
        }

        # remove nop
        $line =~ s/\^\[K//g;

        # remove "cursor back"
        while ( $line =~ m/.\^\[D/ ) {
            $line =~ s/.\^\[D//;
        }
        if ( $line =~ m/\n\(qemu\) *$/ ) {
            $line =~ s/\n\(qemu\) *$//;
            return $line;
        }
    }

    backend::qemu::write_crash_file;
    die "ERROR: timeout reading hmp socket\n";
}

# only valid in management thread
our $vnc;

# runs in the thread to deserialize VNC commands
sub handle_vnc_command($) {

    my $cmd = shift;

    #print STDERR "VNC ". JSON::to_json($cmd) . "\n";

    $vnc->capture();

    # TODO: dummy
    return {};
}

our $qmpsocket;

# runs in the thread to bounce QMP
sub handle_qmp_command($) {

    my $cmd = shift;

    my $line = JSON::to_json($cmd);
    my $wb = syswrite( $qmpsocket, "$line\n" );
    die "syswrite failed $!" unless ( $wb == length($line) + 1 );

    #print STDERR "wrote $wb\n";
    my $hash;
    while ( !$hash ) {
        $hash = backend::qemu::_read_json($qmpsocket);
        if ( $hash->{event} ) {
            print STDERR "EVENT " . JSON::to_json($hash) . "\n";

            # ignore
            $hash = undef;
        }
    }

    return $hash;
}


sub _run {
    my $cmdpipe = shift;
    my $rsppipe = shift;
    my $vncport = shift;

    print STDERR "$$: cmdpipe $cmdpipe, rsppipe $rsppipe, VNC $vncport\n";

    $SIG{__DIE__} = sub { alarm 3 };

    $vnc = backend::VNC->new({hostname => 'localhost', port => 5900 + $vncport});
    $vnc->login;

    my $io = IO::Handle->new();
    $io->fdopen( $cmdpipe, "r" ) || die "r fdopen $!";
    $cmdpipe = $io;

    $io = IO::Handle->new();
    $io->fdopen( $rsppipe, "w" ) || die "w fdopen $!";
    $rsppipe = $io;
    $rsppipe->autoflush(1);

    my $hmpsocket = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "hmp_socket",
        Blocking => 0
    ) or die "can't open hmp";

    $hmpsocket->autoflush(1);
    binmode $hmpsocket;
    my $flags = fcntl( $hmpsocket, Fcntl::F_GETFL, 0 ) or die "can't getfl(): $!\n";
    $flags = fcntl( $hmpsocket, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK ) or die "can't setfl(): $!\n";

    $qmpsocket = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "qmp_socket",
        Blocking => 0
    ) or die "can't open qmp";

    $qmpsocket->autoflush(1);
    binmode $qmpsocket;
    $flags = fcntl( $qmpsocket, Fcntl::F_GETFL, 0 ) or die "can't getfl(): $!\n";
    $flags = fcntl( $qmpsocket, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK ) or die "can't setfl(): $!\n";

    printf STDERR "$$: hmpsocket %d, qmpsocket %d\n", fileno($hmpsocket), fileno($qmpsocket);

    # retrieve welcome
    my $line = _read_hmp($hmpsocket);
    print "WELCOME $line\n";

    my $init = backend::qemu::_read_json($qmpsocket);
    syswrite( $qmpsocket, "{'execute': 'qmp_capabilities'}\n" );
    my $hash = backend::qemu::_read_json($qmpsocket);
    if (0) {
        syswrite( $qmpsocket, "{'execute': 'query-commands'}\n" );
        $hash = backend::qemu::_read_json($qmpsocket);
        die "no commands!" unless ($hash);
        print "COMMANDS " . JSON::to_json( $hash, { pretty => 1 } ) . "\n";
    }

    bmwqemu::diag "started mgmt loop with thread id " . threads->tid();

    my $s = IO::Select->new();
    $s->add($qmpsocket);
    $s->add($hmpsocket);
    $s->add($cmdpipe);

  SELECT: while ( my @ready = $s->can_read ) {
        for my $fh (@ready) {
            my $buffer;

            if ( $fh == $qmpsocket ) {
                my $bytes = sysread( $fh, $buffer, 1000 );
                if ( !$bytes ) { print STDERR "read QMP failed: $!\n"; last SELECT; }

                #my $hash = backend::qemu::_read_json($qmpsocket);
                #if (!$hash) { print STDERR "read json failed: $!\n"; last SELECT; }
                #if ($hash->{event}) {
                #	print STDERR "EVENT " . JSON::to_json($hash) . "\n";
                #} else {
                print STDERR "WARNING: read qmp $bytes - $buffer\n";

                #}
                #syswrite($rsppipe, $buffer);

            }
            elsif ( $fh == $hmpsocket ) {
                my $bytes = sysread( $fh, $buffer, 1000 );
                if ( !$bytes ) { print STDERR "read HMP failed: $!\n"; last SELECT; }
                print STDERR "WARNING: read hmp $bytes - $buffer\n";

                #syswrite($rsppipe, $buffer);

            }
            elsif ( $fh == $cmdpipe ) {
                my $cmd = backend::qemu::_read_json($cmdpipe);

                #print STDERR "cmd ". JSON::to_json($cmd) . "\n";

                if ( $cmd->{hmp} ) {
                    my $wb = syswrite( $hmpsocket, "$cmd->{hmp}\n" );

                    #print STDERR "wrote HMP $wb $cmd->{hmp}\n";
                    die "syswrite failed $!" unless ( $wb == length( $cmd->{hmp} ) + 1 );

                    my $line = _read_hmp($hmpsocket);
                    print $rsppipe JSON::to_json(
                        {
                            "hmp" => $cmd->{hmp},
                            "rsp" => { "return" => $line }
                        }
                    );
                }
                elsif ( $cmd->{VNC} ) {
                    my $rsp = handle_vnc_command($cmd);
                    print $rsppipe JSON::to_json( { "VNC" => $cmd, "rsp" => $rsp } );
                }
                else { # qmp

                    my $hash = handle_qmp_command($cmd);
                    if ( !$hash ) {
                        print STDERR "no json from QMP: $!\n";
                        last SELECT;
                    }

                    print $rsppipe JSON::to_json( { "qmp" => $cmd, "rsp" => $hash } );
                }
            }
            else {
                print STDERR "huh!\n";
            }
        }
    }

    close($qmpsocket) || die "close $!\n";
    close($hmpsocket) || die "close $!\n";
    close($cmdpipe)   || die "close $!\n";

    # XXX: perl does not really close the fd here due to threads!?
    print $rsppipe $MAGIC_PIPE_CLOSE_STRING;
    close($rsppipe) || die "close $!\n";

    bmwqemu::diag( "management thread exit at " . POSIX::strftime( "%F %T", gmtime ) );
}

1;

# vim: set sw=4 et:
