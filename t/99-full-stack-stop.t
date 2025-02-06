#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '450';
use Test::Warnings ':report_warnings';
use File::Basename;
use Cwd 'abs_path';
use Mojo::JSON 'decode_json';
use Mojo::File qw(path tempdir);
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = "$Bin/..";
my $data_dir = "$Bin/data/";
my $pool_dir = "$dir/pool/";
mkdir $pool_dir;

note("data dir: $data_dir");
note("pool dir: $pool_dir");

chdir($pool_dir);
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $casedir = path($data_dir, 'tests');
path('vars.json')->spew(<<EOV);
{
   "ARCH" : "i386",
   "BACKEND" : "qemu",
   "QEMU" : "i386",
   "QEMU_NO_TABLET" : "1",
   "QEMU_NO_FDC_SET" : "1",
   "CASEDIR" : "$casedir",
   "ISO" : "$data_dir/Core-7.2.iso",
   "CDMODEL" : "ide-cd",
   "HDDMODEL" : "ide-hd",
   "VERSION" : "1",
   "SSH_CONNECT_RETRY"  : "2",
   "SSH_CONNECT_RETRY_INTERVAL"  : ".001",
   "NAME" : "00001-1-i386@32bit",
   "INTEGRATION_TESTS" : "1",
   "CMD_AFTER_STOP" : "1",
}
EOV
# create screenshots
path('live_log')->touch;
system("cd $toplevel_dir && perl $toplevel_dir/isotovideo --workdir $pool_dir -d 2>&1 | tee $pool_dir/autoinst-log.txt");
my $log = path('autoinst-log.txt')->slurp;
my $version = -e "$toplevel_dir/.git" ? qr/[a-f0-9]+/ : 'UNKNOWN';
like $log, qr/Current version is $version [interface v[0-9]+]/, 'version read from git';
like $log, qr/\d*: EXIT 1/, 'test execution failed';
unlike $log, qr/Tests died:/, 'Tests did not fail within modules' or diag "autoinst-log.txt: $log";
unlike $log, qr/warn.*qemu-system.*terminating/, 'No warning about expected termination';
like $log, qr/qemu was explicitly stopped from test code.*system_reset/s, 'Warning about QMP cmd after qemu stopped';

done_testing();
