#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::File qw(tempdir);
use Mojo::IOLoop::ReadWriteProcess qw(process);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Output qw(combined_from);
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use log qw(logger);

use backend::driver;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my (@diag, @fctinfo);
my $mocklog = Test::MockModule->new('backend::driver');
$mocklog->redefine(diag => sub { push @diag, @_ });
$mocklog->redefine(fctinfo => sub { push @fctinfo, @_ });
sub reset_logs () { @diag = (); @fctinfo = () }

my $driver;
logger->handle->autoflush(1);
my $out = combined_from { $driver = backend::driver->new('null') };
like "@diag", qr/channel_out.+channel_in/, 'log output for backend driver creation';
reset_logs();

ok $driver, 'can create driver';
$out = combined_from { ok $driver->start, 'can start driver' };
like "@diag", qr/channel_out.+channel_in/, 'log content again';
reset_logs();

isnt $driver->{backend_process}, {}, 'backend process was started' or explain $driver->{backend_process};
is $driver->extract_assets, undef, 'extract_assets';
ok $driver->start_vm, 'start_vm';
is $driver->mouse_hide, 0, 'mouse_hide';
$out = combined_from { is $driver->stop_backend, undef, 'stop_backend' };
like "@diag", qr/backend.*exited/, 'exit logged';
reset_logs();
is $driver->stop, undef, 'stop';

my $process = process(process_id => 42, _status => (5 << 8));
reset_logs;
backend::driver::_collect_orphan(undef, $process);
like $fctinfo[0], qr/collected.*pid.*42.*exit status.*5/, 'message for collected orphan logged';

done_testing;

1;
