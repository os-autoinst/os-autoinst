#!/usr/bin/perl
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
use 5.018;
use warnings;
use Carp 'confess';
use English -no_match_vars;
use POSIX qw( :sys_wait_h sigprocmask sigsuspend );
use Socket qw( PF_UNIX SOCK_STREAM sockaddr_un );
use Time::HiRes 'usleep';
use File::Temp 'tempfile';

use Test::More;
use Test::Warnings;

BEGIN {
    unshift @INC, '..';
}

use consoles::virtio_terminal;
use testapi ();
use bmwqemu ();

our $VERSION;

$testapi::password = 'd*97Jlk/.d';
my $socket_path       = './virtio_console';
my $login_prompt_data = <<'FIN.';


Welcome to SUSE Linux Enterprise Server 12 SP2 RC3 (x86_64) - Kernel 4.4.21-65-default (hvc0).

FIN.
$login_prompt_data .= 'linux-5rw7 login: ';
my $user_name_prompt_data = "login: ";
my $user_name_data        = "root\n";
my $password_prompt_data  = 'Password: ';
my $password_data         = "$testapi::password\n";
# Contains some ANSI/XTERM escape sequences
my $first_prompt_data      = "\e[1mlinux-5rw7:~ #\e[0m\e(B";
my $set_prompt_data        = qq/PS1="# "\n/;
my $normalised_prompt_data = '# ';
my $C0_EOT                 = "\cD";
my $C0_ETX                 = "\cC";
my $C1_control_code        = qq(\eQ\n);
my $US_keyboard_data       = <<'FIN.';
!@\#$%^&*()-_+={}[]|:;"'<>,.?/~`
abcdefghijklmnopqrstuwxyz
ABCDEFGHIJKLMNOPQRSTUWXYZ
0123456789
FIN.
my $stop_code_data        = "FIN.\n";
my $repeat_sequence_count = 1000;
my $next_test             = "GOTO NEXT\n";

# If test keeps timing out, this can be increased or you can add more calls to
# alarm in fake terminal
my $timeout = 10;

my ($logfd, $log_path) = tempfile('10-terminalXXXXX',       TMPDIR => 1, SUFFIX => '.log');
my ($errfd, $err_path) = tempfile('10-terminal-ERRORXXXXX', TMPDIR => 1, SUFFIX => '.log');

$bmwqemu::direct_output = 0;
$bmwqemu::logfd         = $errfd;
$bmwqemu::istty         = 0;

# Line buffer the error log (make it hot)
select((select($errfd), $| = 1)[0]);

# Either write $msg to the socket or die
sub try_write {
    my ($fd, $msg) = @_;

    print $logfd $msg;

    while (1) {
        my $written = syswrite $fd, $msg;
        unless (defined $written) {
            if ($ERRNO{EINTR}) {
                next;
            }
            confess "fake_terminal: Failed to write to socket $ERRNO";
        }
        if ($written < length($msg)) {
            confess "fake_terminal: Only wrote $written bytes of: $msg";
        }
        last;
    }
}

# Try to write $seq to the socket $repeat number of times with pauses between
# writes
sub try_write_sequence {
    my ($fd, $seq, $repeat, $stop_code) = @_;

    my @pauses = (10, 100, 200, 500, 1000);

    for my $i (1 .. $repeat) {
        try_write($fd, $seq);
        usleep(shift(@pauses) || 1);
    }

    try_write($fd, $stop_code);
}

# Try to read $expected data from the socket or die.
# Once we have read the data, echo it back like a real terminal, unless the
# message is $next_test which we just use for synchronisation.
sub try_read {
    my ($fd, $expected) = @_;
    my ($buf, $text);

    while (1) {
        my $read = sysread $fd, $buf, length($expected);
        unless (defined $read) {
            if ($ERRNO{EINTR}) {
                $text .= $buf;
                print $logfd $buf;
                next;
            }
            confess "fake_terminal: Could not read from socket: $ERRNO";
        }
        if ($read < length($expected)) {
            $text .= $buf;
            print $logfd $buf;
            usleep(100);
        }
        else {
            last;
        }
    }
    $text .= $buf;

    if ($expected ne $next_test) {
        try_write($fd, $text);
    }
    elsif ($text ne $next_test) {
        confess 'fake_terminal: Expecting special $next_test message, but got: ' . $text;
    }

    return $text eq $expected;
}

# A mock terminal which we can communicate with over a UNIX socket
sub fake_terminal {
    my ($sock_path) = @_;
    my ($fd, $listen_fd);

    $SIG{ALRM} = sub {
        fail('fake_terminal timed out while waiting for a connection');
        done_testing;
        exit(1);
    };

    alarm $timeout;

    socket($listen_fd, PF_UNIX, SOCK_STREAM, 0)
      || confess "fake_terminal: Could not create socket: $ERRNO";
    unlink($sock_path);
    bind($listen_fd, sockaddr_un($sock_path))
      || confess "fake_terminal: Could not bind socket to path $sock_path: $ERRNO";
    listen($listen_fd, 1)
      || confess "fake_terminal: Could not list on socket: $ERRNO";

    #Signal to parent that the socket is listening
    kill 'CONT', getppid;

  ACCEPT: {
        accept($fd, $listen_fd) || do {
            if ($ERRNO{EINTR}) {
                next ACCEPT;
            }
            confess "fake_terminal: Failed to accept connection: $ERRNO";
        };
    }

    $SIG{ALRM} = sub {
        fail('fake_terminal timed out while performing IO');
        done_testing;
        exit(1);
    };

    # Test::More does not support forking, but if these tests fail it should
    # cause the child to return a non zero exit code which will cause the
    # parent to fail as well
    my $tb = Test::More->builder;
    $tb->reset;

    try_write($fd, $login_prompt_data);
    ok(try_read($fd, $user_name_data), 'fake_terminal reads: Entered user name');

    try_write($fd, $password_prompt_data);
    ok(try_read($fd, $password_data), 'fake_terminal reads: Entered password');

    try_write($fd, $first_prompt_data);
    ok(try_read($fd, $set_prompt_data), 'fake_terminal reads: Normalised bash prompt');

    try_write($fd, $normalised_prompt_data);

    ok(try_read($fd, $C0_EOT), 'fake_terminal reads: C0 EOT control code');
    ok(try_read($fd, $C0_ETX), 'fake_terminal reads: C0 ETX control code');
    ok(try_read($fd, "\n"),    'fake_terminal reads: ret');
    try_write($fd, $login_prompt_data);

    alarm $timeout;

    # This for loop corresponds to the 'large amount of data tests'
    for (1 .. 2) {
        try_read($fd, $next_test);
        try_write_sequence($fd, $US_keyboard_data, $repeat_sequence_count, $stop_code_data);
    }

    #alarm $timeout * 2;
    #try_write($fd, ($US_keyboard_data x 100_000) . $stop_code_data);

    alarm $timeout;
    $SIG{ALRM} = sub {
        fail('fake_terminal timed out first');
        done_testing;
        exit(0);
    };

    try_read($fd, $next_test);
    try_write($fd, $US_keyboard_data);
    # Keep the socket open while we test the timeout
    try_read($fd, $next_test);

    alarm 0;
    pass('fake_terminal managed to get all the way to the end without timing out!');
    done_testing;
}

sub is_matched {
    my ($result, $expected, $name) = @_;
    is_deeply($result, {matched => 1, string => $expected}, $name);
}

sub test_terminal_directly {
    my $tb = Test::More->builder;
    $tb->reset;

    testapi::set_var('VIRTIO_CONSOLE', 1);

    my $term = consoles::virtio_terminal->new('unit-test-console', []);
    $term->activate;
    my $scrn = $term->screen;
    ok(defined($scrn), 'Create screen');

    local *type_string = sub {
        $scrn->type_string({text => shift});
    };

    is_matched($scrn->read_until(qr/$user_name_prompt_data$/, $timeout), $login_prompt_data, 'direct: find login prompt');
    type_string($user_name_data);

    is_matched($scrn->read_until(qr/$password_prompt_data$/, $timeout), $user_name_data . $password_prompt_data, 'direct: find password prompt');
    type_string($password_data);

    is_matched($scrn->read_until($first_prompt_data, $timeout, no_regex => 1), $password_data . $first_prompt_data, 'direct: find first command prompt');
    type_string($set_prompt_data);

    is_matched($scrn->read_until(qr/$normalised_prompt_data$/, $timeout), $set_prompt_data . $normalised_prompt_data, 'direct: find normalised prompt');

    $scrn->type_string({text => '', terminate_with => 'EOT'});
    $scrn->type_string({text => '', terminate_with => 'ETX'});
    $scrn->send_key({key => 'ret'});

    like($scrn->read_until([qr/.*\: /, qr/7/], $timeout)->{string}, qr/.*\Q$login_prompt_data\E/, 'direct: use array of regexs');

    # Note that a real terminal would echo this back to us causing the next test to fail
    # unless we suck up the echo.
    type_string($next_test);

    my $result = $scrn->read_until(
        $stop_code_data, $timeout,
        no_regex    => 1,
        buffer_size => 256
    );
    is(length($result->{string}), 256, 'direct: returned data is same length as buffer');
    like($result->{string}, qr/\Q$US_keyboard_data\E$stop_code_data$/, 'direct: read a large amount of data with small ring buffer');
    type_string($next_test);

    like(
        $scrn->read_until(qr/$stop_code_data$/, $timeout, record_output => 1)->{string},
        qr/^(\Q$US_keyboard_data\E){$repeat_sequence_count}$stop_code_data$/,
        'direct: record a large amount of data'
    );
    type_string($next_test);

    #ok($scrn->read_until(qr/$stop_code_data$/, $timeout, record_output => 1)->{matched},
    #   'direct: record a huge amount of data');

    is_deeply($scrn->read_until('we timeout', 1), {matched => 0, string => $US_keyboard_data}, 'direct: timeout');
    type_string($next_test);

    $term->reset;
    done_testing;
}

sub test_terminal_through_testapi {
    ...;
}

# Called after waitpid to check child's exit
sub check_child {
    my ($child)     = @_;
    my $exited      = WIFEXITED($CHILD_ERROR);
    my $exit_status = WEXITSTATUS($CHILD_ERROR);
    ok($exited, "$child process exits cleanly");
    if ($exited) {
        is($exit_status, 0, "$child process exit status is zero");
    }
}

# The virtio_terminal expects the socket to be ready by the time it is activated
# so wait for fake terminal to create socket and emit SIGCONT. Sigsuspend only
# returns if a signal is received which has a handler set. We must initially
# block the signal incase SIGCONT is emitted before we reach sigsuspend.
$SIG{CONT} = sub { };
my $blockmask = POSIX::SigSet->new(&POSIX::SIGCONT);
my $oldmask   = POSIX::SigSet->new();
sigprocmask(POSIX::SIG_BLOCK, $blockmask, $oldmask);

my $fpid = fork || do {
    fake_terminal($socket_path);
    exit 0;
};

sigsuspend($oldmask);
my $tpid = fork || do {
    test_terminal_directly;
    exit 0;
};

waitpid($fpid, 0);
check_child('Fake terminal');
waitpid($tpid, 0);
check_child('Direct test');

done_testing;
unlink $socket_path;
say "The IO log file is at $log_path and the error log is $err_path.";
