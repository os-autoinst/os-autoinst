#!/usr/bin/perl

use 5.018;
use warnings;
use autodie;
use Carp qw( confess );
use English qw( -no_match_vars );
use POSIX qw( :sys_wait_h pause );
use Socket qw( PF_UNIX SOCK_STREAM sockaddr_un );

use Test::More tests => 9;

BEGIN {
    unshift @INC, '..';
}

use consoles::virtio_terminal;
use testapi ();

our $VERSION;

$testapi::password = 'd*97Jlk/.d';
my $socket_path = './virtio_console';
# Set this to an amount greater than any chunk of data sent in a unit test
my $largest_data_length = 8192;
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

my $timeout = 5;

sub try_write {
    my ($fd, $msg) = @_;

    syswrite($fd, $msg)
      || confess "fake_terminal: Failed to write to socket $ERRNO";
}

sub try_read {
    my ($fd, $expected) = shift;
    my ($buf, $text);

  READ: {
        sysread($fd, my $buf, length($expected)) || do {
            if ($ERRNO{EINTR}) {
                $text .= $buf;
                next READ;
            }
            confess "fake_terminal: Could not read from socket: $ERRNO";
        };
    }
    $text .= $buf;
    # Echo back what we just read like a real terminal
    try_write( $fd, $text );
    return $text eq $expected;
}

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

    try_write( $fd, $login_prompt_data );
    ok( try_read($fd, $user_name_data), 'fake_terminal reads: Entered user name');
    try_write( $fd, $password_prompt_data );
    ok( try_read($fd, $password_data), 'fake_terminal reads: Entered password');
    try_write( $fd, $first_prompt_data );
    ok( try_read($fd, $set_prompt_data), 'fake_terminal reads: Normalised bash prompt');
    try_write( $fd, $normalised_prompt_data );

    #TODO:
    # - Send 4-8kb of data to test the ring buffer
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
    is( $scrn->read_until( qr/$first_prompt_data$/, $timeout ),
        $password_data . $first_prompt_data, 'direct: find first command prompt' );
    $scrn->type_string( $set_prompt_data );
    is( $scrn->read_until( qr/$normalised_prompt_data$/, $timeout ),
        $set_prompt_data . $normalised_prompt_data, 'direct: find normalised prompt' );
}

sub test_terminal_through_testapi {
    ...
}

$SIG{CHLD} = sub {
    local ($ERRNO, $CHILD_ERROR);
    if ( waitpid(-1, WNOHANG) > 0 ) {
        my $exited = WIFEXITED($CHILD_ERROR);
        my $exit_status = WEXITSTATUS($CHILD_ERROR);
        ok($exited, 'Fake terminal process exits cleanly');
        if ($exited) {
            is($exit_status, 0, 'Child exit status is zero');
        }
        if ($exited == 0 || $exit_status != 0) {
            exit 0;
        }
    }
};

$SIG{CONT} = sub { };

my $pid = fork || do {
    fake_terminal( $socket_path );
    exit 0;
};

pause;

test_terminal_directly;
