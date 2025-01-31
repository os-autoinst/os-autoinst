#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Test::MockModule;
use Test::Output qw(stderr_like);
use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';

require "$Bin/../script/vnctest";

subtest 'Ensure that main gets args' => sub {
    local @ARGV = qw(--verbose --hostname open.qa);
    my $options = main::parse_args();
    is_deeply $options, {verbose => 1, hostname => 'open.qa'}, 'parse_args() returns options';
};

subtest 'Run vnctest script' => sub {
    $ENV{TEST_ENV} = 1;
    my $vnc = Test::MockModule->new('consoles::VNC');
    $vnc->redefine('login', 1);
    $vnc->redefine('send_update_request', 1);
    $vnc->redefine('update_framebuffer', 1);
    stderr_like { main::main({hostname => 'nohost', 'update-delay' => 0, verbose => 1}) } qr/Update received/, 'Captured output from main::main';
};

done_testing;
