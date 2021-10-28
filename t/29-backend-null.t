#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(:all :report_warnings);

use bmwqemu;
use backend::null;

my $backend = backend::null->new;
is_deeply $backend->do_start_vm, {}, 'can call do_start_vm';
is $backend->do_stop_vm, undef, 'can call do_stop_vm';
is $backend->run_cmd, undef, 'can call run_cmd';
is $backend->can_handle, undef, 'can call can_handle';
is $backend->is_shutdown, 1, 'can call is_shutdown';
is $backend->stop_serial_grab, undef, 'can call stop_serial_grab';
done_testing;
