#!/usr/bin/perl

# Copyright (C) 2016-2021 SUSE LLC
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
use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Carp 'confess';
use English -no_match_vars;
use POSIX qw( :sys_wait_h sigprocmask sigsuspend mkfifo);
use Fcntl qw( :flock :seek );
use Socket qw( PF_UNIX SOCK_STREAM sockaddr_un );
use Time::HiRes 'usleep';
use File::Temp 'tempfile';
use Mojo::Log;
use Mojo::JSON qw( encode_json decode_json );

use Test::Warnings ':report_warnings';
my $main_pid = $$;

use consoles::virtio_terminal;
use testapi ();
use bmwqemu ();

our $VERSION;

$testapi::password = 'd*97Jlk/.d';
my $socket_path       = './virtio_console';
my $sharefile         = "$Bin/fork-share.txt";
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
abcdefghijklmnopqrstuvwxyz
ABCDEFGHIJKLMNOPQRSTUVWXYZ
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
$bmwqemu::logger        = Mojo::Log->new(path => $err_path);

# Either write $msg to the socket or die
sub try_write ($fd, $msg) {
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
sub try_write_sequence ($fd, $seq, $repeat, $stop_code) {
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
sub try_read ($fd, $fd_w, $expected) {
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
        try_write($fd_w, $text);
    }
    elsif ($text ne $next_test) {
        confess 'fake_terminal: Expecting special $next_test message, but got: ' . $text;
    }

    return $text eq $expected;
}

# A mock terminal which we can communicate with over a UNIX socket
sub fake_terminal ($pipe_in, $pipe_out) {
    my ($fd, $listen_fd);

    $SIG{ALRM} = sub {
        report_child_test(fail => 'fake_terminal timed out while waiting for a connection');
        exit(1);
    };

    alarm $timeout;

    open(my $fd_r, "<", $pipe_in)
      or die "Can't open in pipe for writing $!";
    open(my $fd_w, ">", $pipe_out)
      or die "Can't open out pipe for reading $!";

    $SIG{ALRM} = sub {
        report_child_test(fail => 'fake_terminal timed out while performing IO');
        exit(1);
    };

    # Test::Most does not support forking, but if these tests fail it should
    # cause the child to return a non zero exit code which will cause the
    # parent to fail as well
    my $tb = Test::Most->builder;
    $tb->reset;

    try_write($fd_w, $login_prompt_data);
    report_child_test(ok => (scalar try_read($fd_r, $fd_w, $user_name_data)), 'fake_terminal reads: Entered user name');

    try_write($fd_w, $password_prompt_data);
    report_child_test(ok => try_read($fd_r, $fd_w, $password_data), 'fake_terminal reads: Entered password');

    try_write($fd_w, $first_prompt_data);
    report_child_test(ok => try_read($fd_r, $fd_w, $set_prompt_data), 'fake_terminal reads: Normalised bash prompt');

    try_write($fd_w, $normalised_prompt_data);

    report_child_test(ok => try_read($fd_r, $fd_w, $C0_EOT), 'fake_terminal reads: C0 EOT control code');
    report_child_test(ok => try_read($fd_r, $fd_w, $C0_ETX), 'fake_terminal reads: C0 ETX control code');
    report_child_test(ok => try_read($fd_r, $fd_w, "\n"),    'fake_terminal reads: ret');
    try_write($fd_w, $login_prompt_data);

    alarm $timeout;

    # This for loop corresponds to the 'large amount of data tests'
    for (1 .. 2) {
        try_read($fd_r, $fd_w, $next_test);
        try_write_sequence($fd_w, $US_keyboard_data, $repeat_sequence_count, $stop_code_data);
    }

    # Trailing data/carry buffer tests
    for (1 .. 2) {
        try_read($fd_r, $fd_w, $next_test);
        try_write($fd_w, $US_keyboard_data . $stop_code_data . $stop_code_data);
    }

    #alarm $timeout * 2;
    #try_write($fd, ($US_keyboard_data x 100_000) . $stop_code_data);

    try_write($fd_w, $first_prompt_data);
    try_read($fd_r, $fd_w, $next_test);

    alarm $timeout;
    $SIG{ALRM} = sub {
        report_child_test(fail => 'fake_terminal timed out first');
        exit(0);
    };

    try_read($fd_r, $fd_w, $next_test);
    try_write($fd_w, $US_keyboard_data);
    # Keep the socket open while we test the timeout
    try_read($fd_r, $fd_w, $next_test);

    alarm 0;
    report_child_test(pass => 'fake_terminal managed to get all the way to the end without timing out!');
}

sub is_matched ($result, $expected, $name) {
    report_child_test(is_deeply => $result, {matched => 1, string => $expected}, $name);
}

sub test_terminal_directly ($tb) {
    $tb->reset;

    my $term = consoles::virtio_terminal->new('unit-test-console', {tty => 3});
    report_child_test(ok => $term->console_key eq "ctrl-alt-f3", 'console_key set correct');

    $term->activate;
    my $scrn = $term->screen;
    report_child_test(ok => defined($scrn), 'Create screen');

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

    report_child_test(like => $scrn->read_until([qr/.*\: /, qr/7/], $timeout)->{string}, qr/.*\Q$login_prompt_data\E/, 'direct: use array of regexs');

    # Note that a real terminal would echo this back to us causing the next test to fail
    # unless we suck up the echo.
    type_string($next_test);

    my $result = $scrn->read_until(
        $stop_code_data, $timeout,
        no_regex    => 1,
        buffer_size => 256
    );
    report_child_test(is   => length($result->{string}), 256,                               'direct: returned data is same length as buffer');
    report_child_test(like => $result->{string}, qr/\Q$US_keyboard_data\E$stop_code_data$/, 'direct: read a large amount of data with small ring buffer');
    type_string($next_test);

    report_child_test(like =>
          $scrn->read_until(qr/$stop_code_data$/, $timeout, record_output => 1)->{string},
        qr/^(\Q$US_keyboard_data\E){$repeat_sequence_count}$stop_code_data$/,
        'direct: record a large amount of data'
    );
    type_string($next_test);

    # In theory, even if the carry buffer is not implemented, this may succeed
    # if the kernel is preempted in, and/or a kernel buffer ends in just the
    # right place.
    report_child_test(is => $scrn->read_until($US_keyboard_data, $timeout, no_regex => 1)->{matched}, 1, 'direct: read including trailing data with no_regex');
    report_child_test(is => $scrn->read_until(qr/$stop_code_data$/, $timeout)->{matched}, 1, 'direct: trailing data is carried over to next read');
    type_string($next_test);

    report_child_test(is => $scrn->read_until(qr/\Q$US_keyboard_data\E/, $timeout)->{matched}, 1, 'direct: read including trailing data');
    report_child_test(is => $scrn->read_until(qr/$stop_code_data$stop_code_data/, $timeout)->{matched}, 1,
        'direct: trailing data is carried over to next read');
    type_string($next_test);

    my $res;
    do {
        $res = $scrn->peak();
    } while (length($res) < 1);
    report_child_test(ok => $res, 'direct: peaked');
    report_child_test(is => $scrn->read_until($first_prompt_data, $timeout, no_regex => 1)->{matched}, 1,
        'direct: read after peak');
    type_string($next_test);

    report_child_test(is_deeply => $scrn->read_until('we timeout', 1), {matched => 0, string => $US_keyboard_data}, 'direct: timeout');
    type_string($next_test);

    $term->reset;
}

sub test_terminal_disabled ($tb) {
    $tb->reset;

    testapi::set_var('VIRTIO_CONSOLE', 0);

    my $term = consoles::virtio_terminal->new('unit-test-console', {});
    eval { $term->activate };
    die "Expected message about unavailable terminal" unless $@ =~ /no virtio-serial.*available/;
}

# Called after waitpid to check child's exit
sub check_child ($child, $expected_exit_status = 0) {
    my $exited      = WIFEXITED($CHILD_ERROR);
    my $exit_status = WEXITSTATUS($CHILD_ERROR);

    ok($exited, "$child process exits cleanly");
    if ($exited) {
        is($exit_status, $expected_exit_status, "$child process exit status is $expected_exit_status");
    }
}

# The virtio_terminal expects the socket to be ready by the time it is activated
# so wait for fake terminal to create socket and emit SIGCONT. Sigsuspend only
# returns if a signal is received which has a handler set. We must initially
# block the signal incase SIGCONT is emitted before we reach sigsuspend.
my $pipe_in  = $socket_path . ".in";
my $pipe_out = $socket_path . ".out";

for (($pipe_in, $pipe_out)) {
    unlink($_) if (-p $_);
    mkfifo($_, 0666) or die("Cannot create fifo pipe $_");
}

my $fpid = fork || do {
    fake_terminal($pipe_in, $pipe_out);
    exit 0;
};

my $tpid = fork || do {
    test_terminal_directly;
    exit 0;
};

my $tpid2 = fork || do {
    test_terminal_disabled;
    exit 0;
};

waitpid($fpid, 0);
check_child('Fake terminal');
waitpid($tpid, 0);
check_child('Direct test VIRTIO_CONSOLE not set');
waitpid($tpid2, 0);
check_child('Direct test with VIRTIO_CONSOLE=0', 0);
my $child_tests = retrieve_child_tests();
for my $pid (sort keys %$child_tests) {
    my $tests = $child_tests->{$pid};
    for my $test (@$tests) {
        my ($method, @args) = @$test;
        if (my $sub = Test::Most->can($method)) {
            if ($method eq 'like') {
                $args[1] = qr{$args[1]};
            }
            $args[-1] = "[Child $pid] " . $args[-1];
            $sub->(@args);
        }
    }
}

done_testing;
unlink $socket_path . ".in";
unlink $socket_path . ".out";
say "The IO log file is at $log_path and the error log is $err_path.";

# We need this because the test numbers need to be in the right order
# so that prove doesn't complain
# Otherwise the childs will output test numbers in arbitrary order,
# so we temporarily save the tests in a JSON file and output them when
# all childs have finished
# Test::SharedFork is usually used to share test numbers between forks,
# but it doesn't work with this test
sub report_child_test ($method, @args) {
    my $json = encode_json([$$, [$method => @args]]);
    open my $fh, '>>', $sharefile or die $!;
    flock $fh, LOCK_EX;
    seek $fh, 0, SEEK_END;
    print $fh "$json\n";
    close $fh;
}

sub retrieve_child_tests {
    return unless -e $sharefile;
    open my $fh, '<', $sharefile or die $!;
    flock $fh, LOCK_SH;
    my %tests;
    while (my $json = <$fh>) {
        my $data = eval { decode_json($json) };
        if (my $error = $@) {
            diag("Error decoding '$json': $error");
            ok(0, "Valid JSON");
            next;
        }
        my ($pid, $test) = @$data;
        push @{$tests{$pid}}, $test;
    }
    close $fh;
    return \%tests;
}

END {
    unlink $sharefile if $$ == $main_pid;
}
