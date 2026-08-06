#!/usr/bin/perl
#
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::MockModule 'strict';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Socket;
use myjsonrpc;

use Test::Warnings qw(warnings :report_warnings);

no warnings 'redefine';
*bmwqemu::diag = sub ($msg) { warn $msg };

my ($child, $isotovideo);
socketpair $child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

$child->autoflush(1);
$isotovideo->autoflush(1);

my $send1 = {a => 1, umlaut => 'testä'};
my $send2 = {b => 12, json_cmd_token => 'dummy'};

subtest single_json => sub {
    myjsonrpc::send_json($child, $send1);
    my $read = myjsonrpc::read_json($isotovideo);
    ok exists $read->{json_cmd_token}, 'send_json/read_json json_cmd_token exists';
    delete $read->{json_cmd_token};

    is_deeply $read, $send1, 'read_json returns what send_json sent';
    $send1->{json_cmd_token} = 'dummy';

    myjsonrpc::send_json($child, $send1);
    myjsonrpc::send_json($child, $send2);
    my $read1 = myjsonrpc::read_json($isotovideo, undef, 0);
    my $read2 = myjsonrpc::read_json($isotovideo, undef, 0);
    is_deeply [$read1, $read2], [$send1, $send2], 'read_json twice works';
};

subtest multi_json => sub {
    myjsonrpc::send_json($child, $send1);
    myjsonrpc::send_json($child, $send2);
    my @read = myjsonrpc::read_json($isotovideo, undef, 1);
    is_deeply \@read, [$send1, $send2], 'read_json in list context works';
};

sub magic_close () {
    myjsonrpc::send_json($child, {QUIT => 1});
    my $quit = myjsonrpc::read_json($isotovideo);
    is $quit, undef, 'received magic close';
}

subtest magic_close => sub {
    my @warnings = warnings { magic_close() };
    like $warnings[0], qr{received magic close};
};

subtest 'send_json dies when buffer is empty and pipe is broken' => sub {
    my $myjsonrpc_mock = Test::MockModule->new('myjsonrpc');
    $myjsonrpc_mock->redefine(_syswrite => sub ($to_fd, $json, $len, $offset) { 0 });
    dies_ok { myjsonrpc::send_json($child, $send1) } 'myjsonrpc: remote end terminated connection, stopping';
};

subtest 'out-of-order message is stashed instead of dying' => sub {
    myjsonrpc::send_json($child, {postponed => 1, json_cmd_token => 'other-token'});
    myjsonrpc::send_json($child, {answer => 1, json_cmd_token => 'my-token'});
    my $read;
    my @w = warnings { $read = myjsonrpc::read_json($isotovideo, 'my-token') };
    like $w[0], qr/stashing out-of-order message/, 'out-of-order message logged';
    is $read->{answer}, 1, 'awaited response returned despite preceding foreign message';
    my $stashed = myjsonrpc::take_pending($isotovideo);
    is $stashed->{postponed}, 1, 'stashed message can be taken later';
    is myjsonrpc::take_pending($isotovideo), undef, 'queue is empty afterwards';
};

# Root cause (poo#205302): two messages written close together can be coalesced by
# the kernel into a single sysread. read_json only returns the first complete JSON
# value it finds and stashes the rest as raw text in its per-fd buffer; the bytes
# are already consumed from the pipe, so select()/can_read() will not report the
# fd readable again for that trailing message.
subtest 'select() is blind to a second message coalesced into one sysread' => sub {
    myjsonrpc::send_json($child, {msg => 1, json_cmd_token => 'A'});
    myjsonrpc::send_json($child, {msg => 2, json_cmd_token => 'B'});

    my $select = IO::Select->new($isotovideo);
    ok $select->can_read(0), 'fd is readable before the first read';
    ok !myjsonrpc::buffered($isotovideo), 'nothing buffered yet before the first read';

    my $first = myjsonrpc::read_json($isotovideo, 'A');
    is $first->{msg}, 1, 'first message read';

    ok !$select->can_read(0), 'select is blind to the second, already-consumed message';
    ok myjsonrpc::buffered($isotovideo), 'buffered() reports the second message is ready without another read';

    my $second = myjsonrpc::read_json($isotovideo, 'B');
    is $second->{msg}, 2, 'second message still recoverable via another read_json call';
    ok !myjsonrpc::buffered($isotovideo), 'nothing left buffered once drained';
};

# Martchus' hang: PR #3065's stash-and-continue makes read_json stop confessing on a
# foreign token, but nothing ever consults that stash for a *later* read_json call
# awaiting the token that was stashed earlier. That call then blocks in sysread
# forever, because the reply already arrived and was consumed off the fd -- it is
# sitting in Perl-space, not on the wire. Bounded by alarm() so a regression fails
# the test instead of hanging the suite.
subtest 'read_json recovers a token stashed by an earlier call instead of hanging' => sub {
    myjsonrpc::send_json($child, {msg => 'reload_needles reply', json_cmd_token => 'A'});
    myjsonrpc::send_json($child, {msg => 'set_tags_to_assert reply', json_cmd_token => 'B'});

    my @w = warnings {
        my $got_b = myjsonrpc::read_json($isotovideo, 'B');
        is $got_b->{msg}, 'set_tags_to_assert reply', 'awaited token B returned first';
    };
    like $w[0], qr/stashing out-of-order message/, 'token A stashed while waiting for B';

    my $got_a;
    eval {    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        local $SIG{ALRM} = sub { die "timed out waiting for stashed token A\n" };
        alarm 5;
        $got_a = myjsonrpc::read_json($isotovideo, 'A');
        alarm 0;
    };
    alarm 0;
    is $@, '', 'read_json(A) returns instead of blocking on a message already stashed';
    is $got_a->{msg}, 'reload_needles reply', 'previously stashed message for token A recovered';
};

# The stash lookup must fall through when it holds only tokens nobody is waiting
# on yet, otherwise a reply still on the wire would be shadowed by it.
subtest 'stashed foreign token does not shadow a reply still on the wire' => sub {
    myjsonrpc::send_json($child, {msg => 'foreign', json_cmd_token => 'X'});
    myjsonrpc::send_json($child, {msg => 'awaited', json_cmd_token => 'Y'});
    warnings { is myjsonrpc::read_json($isotovideo, 'Y')->{msg}, 'awaited', 'token Y returned, token X stashed' };

    myjsonrpc::send_json($child, {msg => 'later', json_cmd_token => 'Z'});
    is myjsonrpc::read_json($isotovideo, 'Z')->{msg}, 'later', 'token Z read from the fd although X is still stashed';
    is myjsonrpc::take_pending($isotovideo)->{msg}, 'foreign', 'stashed token X left untouched';
    is myjsonrpc::take_pending($isotovideo), undef, 'queue is empty afterwards';
};

# poo#205302 AC1: a wedge must never be silent again. If a genuinely unrecoverable
# run of foreign messages piles up, fail loudly with more information than the old
# unconditional confess ever had, instead of stashing forever.
subtest 'confesses with a clearer message after too many consecutive out-of-order messages' => sub {
    for my $i (1 .. 10) {
        myjsonrpc::send_json($child, {msg => "foreign-$i", json_cmd_token => "foreign-token-$i"});
    }
    warnings { throws_ok { myjsonrpc::read_json($isotovideo, 'never-arrives') } qr/token does not match/, 'confesses eventually' };
    my $error = $@;
    like $error, qr/never-arrives/, 'message names the awaited token';
    like $error, qr/foreign-token-1\b/, 'message names an early stashed token';
    like $error, qr/foreign-token-10\b/, 'message names the last stashed token';
    # drain the stash so it does not leak into later subtests
    1 while defined myjsonrpc::take_pending($isotovideo);
};

my $io_select_mock = Test::MockModule->new('IO::Select');
$io_select_mock->redefine(can_read => undef);
throws_ok { myjsonrpc::read_json($isotovideo) } qr/Illegal seek/, 'error exception raised when reading is aborted';

close $isotovideo;
close $child;

done_testing;
