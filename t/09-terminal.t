#!/usr/bin/perl

use 5.018;
use warnings;
use Carp qw( confess );
use English qw( -no_match_vars );
use POSIX qw( :sys_wait_h pause );
use Socket qw( PF_UNIX SOCK_STREAM sockaddr_un );
use Time::HiRes qw( usleep );

use Test::More tests => 7;

BEGIN {
    unshift @INC, '..';
}

use consoles::virtio_terminal;
use testapi ();

our $VERSION;

$testapi::password = 'd*97Jlk/.d';
my $socket_path = './virtio_console';
my $login_prompt_data = <<'FIN.';


Welcome to SUSE Linux Enterprise Server 12 SP2 RC3 (x86_64) - Kernel 4.4.21-65-default (hvc0).

FIN.
$login_prompt_data .= 'linux-5rw7 login: ';
my $user_name_prompt_data = "login: ";
my $user_name_data = "root\n";
my $password_prompt_data = 'Password: ';
my $password_data = "$testapi::password\n";
# Contains some ANSI/XTERM escape sequences
my $first_prompt_data = "\e[1mlinux-5rw7:~ #\e[0m\e(B";
my $set_prompt_data = qq/PS1="# "\n/;
my $normalised_prompt_data = '# ';

# If test keeps timing out, this can be increased or you can add more calls to
# alarm in fake terminal
my $timeout = 5;

sub try_write {
    my ($fd, $msg) = @_;

  WRITE: {
        my $written = syswrite $fd, $msg;
        unless ( defined $written ) {
            if ( $ERRNO{EINTR} ) {
                next WRITE;
            }
            confess "fake_terminal: Failed to write to socket $ERRNO";
        }
        if ( $written < length($msg) ) {
            confess "fake_terminal: Only wrote $written bytes of: $msg";
        }
    }
}

sub try_read {
    my ($fd, $expected) = @_;
    my ($buf, $text);

  READ: {
        my $read = sysread $fd, $buf, length($expected);
        unless ( defined $read ) {
            if ($ERRNO{EINTR}) {
                $text .= $buf;
                next READ;
            }
            confess "fake_terminal: Could not read from socket: $ERRNO";
        }
        if ( $read < length($expected) ) {
            $text .= $buf;
            usleep(100);
            next READ;
        }
    }
    $text .= $buf;
    # Echo back what we just read like a real terminal
    try_write( $fd, $text );
    return $text eq $expected;
}

# A mock terminal which we can communicate with over a UNIX socket
sub fake_terminal {
    my ($sock_path) = @_;
    my ($fd, $listen_fd);

    $SIG{ALRM} = sub {
        fail('fake_terminal timed out while waiting for a connection');
        exit(1);
    };

    alarm $timeout;

    socket( $listen_fd, PF_UNIX, SOCK_STREAM, 0 )
      || confess "fake_terminal: Could not create socket: $ERRNO";
    unlink( $sock_path );
    bind( $listen_fd, sockaddr_un($sock_path) )
      || confess "fake_terminal: Could not bind socket to path $sock_path: $ERRNO";
    listen( $listen_fd, 1 )
      || confess "fake_terminal: Could not list on socket: $ERRNO";

    #Signal to parent that the socket is listening
    kill 'CONT', getppid;

  ACCEPT: {
        accept( $fd, $listen_fd ) || do {
            if ($ERRNO{EINTR}) {
                next ACCEPT;
            }
            confess "fake_terminal: Failed to accept connection: $ERRNO";
        };
    }

    $SIG{ALRM} = sub {
        fail('fake_terminal timed out while performing IO');
        exit(1);
    };

    # Test::More does not support forking, but if these tests fail it should
    # cause the child to return a non zero exit code which will cause the
    # parent to fail as well
    my $tb = Test::More->builder;
    $tb->reset;
    $tb->expected_tests(3)

    try_write( $fd, $login_prompt_data );
    ok( try_read($fd, $user_name_data), 'fake_terminal reads: Entered user name');

    try_write( $fd, $password_prompt_data );
    ok( try_read($fd, $password_data), 'fake_terminal reads: Entered password');

    try_write( $fd, $first_prompt_data );
    ok( try_read($fd, $set_prompt_data), 'fake_terminal reads: Normalised bash prompt');

    try_write( $fd, $normalised_prompt_data );

    #TODO:
    # - Send 4-8kb of data to test the ring buffer
    # - Send data in small chunks with pauses between them
    # - Test timeout
}

sub test_terminal_directly {
    my $term = consoles::virtio_terminal->new('unit-test-console', []);
    $term->activate;
    my $scrn = $term->screen;
    ok( defined($scrn), 'Create screen' );

    is( $scrn->read_until( qr/$user_name_prompt_data$/, $timeout ),
        $login_prompt_data, 'direct: find login prompt' );
    $scrn->type_string( $user_name_data );

    is( $scrn->read_until( qr/$password_prompt_data$/, $timeout ),
        $user_name_data . $password_prompt_data, 'direct: find password prompt' );
    $scrn->type_string( $password_data );

    is( $scrn->read_until( $first_prompt_data, $timeout, no_regex => 1 ),
        $password_data . $first_prompt_data, 'direct: find first command prompt' );
    $scrn->type_string( $set_prompt_data );

    is( $scrn->read_until( qr/$normalised_prompt_data$/, $timeout ),
        $set_prompt_data . $normalised_prompt_data, 'direct: find normalised prompt' );
}

sub test_terminal_through_testapi {
    ...
}

# Called after waitpid to check child's exit
sub report_on_fake_terminal {
    my $exited = WIFEXITED($CHILD_ERROR);
    my $exit_status = WEXITSTATUS($CHILD_ERROR);
    ok($exited, 'Fake terminal process exits cleanly');
    if ($exited) {
        is($exit_status, 0, 'Child exit status is zero');
    }
    if ($exited == 0 || $exit_status != 0) {
        return 0;
    }

    return 1;
}

# If child bails out early...
$SIG{CHLD} = sub {
    local ($ERRNO, $CHILD_ERROR);
    if ( waitpid(-1, WNOHANG) > 0 ) {
        report_on_fake_terminal || exit(1);
    }
};

my $pid = fork || do {
    fake_terminal( $socket_path );
    exit 0;
};

# The virtio_terminal expects the socket to be ready by the time it is activated
# so wait for fake terminal to create socket and emit SIGCONT. Pause only
# returns if a signal is received which has a handler set.
$SIG{CONT} = sub { };
pause;

test_terminal_directly;

$SIG{CHLD} = sub { };
waitpid($pid, 0);
report_on_fake_terminal;
