#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);


use backend::driver;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $driver;
combined_like { $driver = backend::driver->new('null') } qr/(Blocking SIGCHLD|channel_out)/, 'log output for backend driver creation';
ok $driver, 'can create driver';
combined_like { ok $driver->start, 'can start driver' } qr/(Blocking SIGCHLD|channel_out)/, 'log content again';
isnt $driver->{backend_process}, {}, 'backend process was started' or explain $driver->{backend_process};
is $driver->extract_assets, undef, 'extract_assets';
ok $driver->start_vm, 'start_vm';
is $driver->mouse_hide, 0, 'mouse_hide';
combined_like { is $driver->stop_backend, undef, 'stop_backend' } qr/backend.*exited/, 'exit logged';
is $driver->stop, undef, 'stop';
done_testing;

1;
