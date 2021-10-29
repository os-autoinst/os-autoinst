#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use bmwqemu;
use distribution;
use backend::spvm;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
my $backend = backend::spvm->new;
$bmwqemu::vars{NOVALINK_HOSTNAME} = 'novalink';
$bmwqemu::vars{NOVALINK_PASSWORD} = 'novalink';
my $distri = $testapi::distri = distribution->new;
is_deeply $backend->do_start_vm, {}, 'can call do_start_vm';
is_deeply $backend->do_stop_vm, {}, 'can call do_stop_vm';
my $baseclass = Test::MockModule->new('backend::baseclass');
$baseclass->redefine(run_ssh_cmd => undef);
is $backend->run_cmd('foo'), undef, 'can call run_cmd';
is $backend->can_handle, undef, 'can call can_handle';
$bmwqemu::vars{NOVALINK_LPAR_ID} = 1;
is $backend->is_shutdown, undef, 'can call is_shutdown';
is $backend->stop_serial_grab, undef, 'can call stop_serial_grab';
is $backend->check_socket(undef), 0, 'can call check_socket';
is $backend->power({action => 'off'}), undef, 'can call power';
done_testing;
