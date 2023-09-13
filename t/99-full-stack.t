#!/usr/bin/perl
# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '450';
use Test::Warnings ':report_warnings';
use Try::Tiny;
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
}
EOV
# create screenshots
path('live_log')->touch;
system("cd $toplevel_dir && perl $toplevel_dir/isotovideo --workdir $pool_dir -d 2>&1 | tee $pool_dir/autoinst-log.txt");
my $log = path('autoinst-log.txt')->slurp;
my $version = -e "$toplevel_dir/.git" ? qr/[a-f0-9]+/ : 'UNKNOWN';
like $log, qr/Current version is $version [interface v[0-9]+]/, 'version read from git';
like $log, qr/\d*: EXIT 0/, 'test executed fine';
like $log, qr/\d* Snapshots are supported/, 'Snapshots are enabled';
unlike $log, qr/Tests died:/, 'Tests did not fail within modules' or diag "autoinst-log.txt: $log";
unlike $log, qr/script_run: DEPRECATED call of script_run.+die_on_timeout/, 'no deprecation warning for script_run';
like $log, qr/do not wait_still_screen/, 'test type string and do not wait';
like $log, qr/wait_still_screen: detected same image for 0.2 seconds/, 'test type string and wait for .2 seconds';
like $log, qr/wait_still_screen: detected same image for 1 seconds/, 'test type string and wait for 1 seconds';
like $log, qr/wait_still_screen: detected same image for 0\.1 seconds/, 'test type string and wait for .1 seconds';
like $log, qr/.*event.*STOP/, 'Machine properly paused';
like $log, qr/.*event.*RESUME/, 'Machine properly resumed';
like $log, qr/Saving storage devices \(current VM state is running\)/, 'save_storage started';
like $log, qr/Saving storage complete/, 'save_storage done';
like $log, qr/get_test_data returned expected file/, 'get_test_data test';
like $log, qr/save_tmp_file returned expected file/, 'save_tmp_file test';
unlike $log, qr/warn.*qemu-system.*terminating/, 'No warning about expected termination';

my $ignore_results_re = qr/fail/;
for my $result (grep { $_ !~ $ignore_results_re } glob("testresults/result*.json")) {
    my $json = decode_json(path($result)->slurp);
    is($json->{result}, 'ok', "Result in $result is ok");
}

for my $result (glob("testresults/result*fail*.json")) {
    my $json = decode_json(path($result)->slurp);
    is($json->{result}, 'fail', "Result in $result is fail");
}

subtest 'Assert screen failure' => sub {
    my $log = path('autoinst-log.txt')->slurp;
    my $count = () = $log =~ /(?<=no candidate needle with tag\(s\)) '(no_tag, no_tag2|no_tag3)'/g;
    is $count, 2, 'Assert screen failures';
    unlike $log, qr/post_fail_hook failed/, 'post_fail_hook could be invoked';
};

done_testing();
