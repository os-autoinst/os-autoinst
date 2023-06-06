#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';

use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

sub check_qemu_oom () {
    system("$Bin/../check_qemu_oom 1");
    return $? >> 8;
}

$ENV{CHECK_QEMU_OOM_LOG_CMD} = 'true';
is check_qemu_oom(), 1, 'No OOM condition found on PID 1';
$ENV{CHECK_QEMU_OOM_LOG_CMD} = 'echo "Out of memory: Killed process 1"';
is check_qemu_oom(), 0, 'OOM condition found based on special message';

done_testing;
