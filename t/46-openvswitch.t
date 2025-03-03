#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';

use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

sub check_openvswitch () {
    system("$Bin/../script/os-autoinst-openvswitch");
    return $? >> 8;
}

is check_openvswitch(), 2, 'test';

done_testing;
