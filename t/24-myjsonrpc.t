#!/usr/bin/perl
#
# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Exception;
use Test::MockModule 'strict';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Socket;
use myjsonrpc;

use Test::Warnings qw(warnings :report_warnings);

no warnings 'redefine';
sub bmwqemu::diag ($msg) { warn $msg }

my ($child, $isotovideo);
socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC);

$child->autoflush(1);
$isotovideo->autoflush(1);

my $send1 = {a => 1, umlaut => "testä"};
my $send2 = {b => 12, json_cmd_token => 'dummy'};

subtest single_json => sub {
    myjsonrpc::send_json($child, $send1);
    my $read = myjsonrpc::read_json($isotovideo);
    ok(exists $read->{json_cmd_token}, "send_json/read_json json_cmd_token exists");
    delete $read->{json_cmd_token};

    is_deeply($read, $send1, "read_json returns what send_json sent");
    $send1->{json_cmd_token} = 'dummy';

    myjsonrpc::send_json($child, $send1);
    myjsonrpc::send_json($child, $send2);
    my $read1 = myjsonrpc::read_json($isotovideo, undef, 0);
    my $read2 = myjsonrpc::read_json($isotovideo, undef, 0);
    is_deeply([$read1, $read2], [$send1, $send2], "read_json twice works");
};

subtest multi_json => sub {
    myjsonrpc::send_json($child, $send1);
    myjsonrpc::send_json($child, $send2);
    my @read = myjsonrpc::read_json($isotovideo, undef, 1);
    is_deeply(\@read, [$send1, $send2], "read_json in list context works");
};

sub magic_close () {
    myjsonrpc::send_json($child, {QUIT => 1});
    my $quit = myjsonrpc::read_json($isotovideo);
    is($quit, undef, "received magic close");
}
subtest magic_close => sub {
    my @warnings = warnings { magic_close() };
    like($warnings[0], qr{received magic close});
};

my $io_select_mock = Test::MockModule->new('IO::Select');
$io_select_mock->redefine(can_read => undef);
throws_ok { myjsonrpc::read_json($isotovideo) } qr/Illegal seek/, 'error exception raised when reading is aborted';

close $isotovideo;
close $child;

done_testing;
