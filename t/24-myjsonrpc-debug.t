#!/usr/bin/perl
#
# Copyright (c) 2019-2020 SUSE LLC
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
use Socket;
BEGIN {
    $ENV{PERL_MYJSONRPC_DEBUG} = 1;
}
use myjsonrpc;

use Test::Warnings qw(warnings :report_warnings);

no warnings 'redefine';
sub bmwqemu::diag { warn $_[0] }


my ($child, $isotovideo);
socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC);

$child->autoflush(1);
$isotovideo->autoflush(1);

my $send1 = {a => 1};
my $send2 = {b => 12, json_cmd_token => 'dummy'};

$send1->{json_cmd_token} = 'dummy';

sub debug {
    myjsonrpc::send_json($child, $send1);
    my $read = myjsonrpc::read_json($isotovideo);
    is_deeply($read, $send1, "read_json returns what send_json sent");
}
subtest debug_json => sub {

    my @warnings = warnings { debug() };
    like($warnings[0], qr{send_json},                       "debug send_json");
    like($warnings[1], qr{read_json},                       "debug read_json");
    like($warnings[2], qr{read_json.*json_cmd_token=dummy}, "debug json_cmd_token");
    is(scalar @warnings, 3, "Correct number of warnings");
};

close $isotovideo;
close $child;

done_testing;
