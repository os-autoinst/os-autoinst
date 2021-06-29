#!/usr/bin/perl
# Copyright (C) 2017-2020 SUSE LLC
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
use OpenQA::Test::TimeLimit '360';
use Test::Warnings ':report_warnings';
use Try::Tiny;
use File::Basename;
use Cwd 'abs_path';
use Mojo::JSON 'decode_json';
use Mojo::File 'tempdir';
use Mojo::Util qw(scope_guard);

my $dir          = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = "$Bin/..";
my $data_dir     = "$Bin/data/";
my $pool_dir     = "$dir/pool/";
mkdir $pool_dir;

note("data dir: $data_dir");
note("pool dir: $pool_dir");

chdir($pool_dir);
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

open(my $var, '>', 'vars.json');
print $var <<EOV;
{
   "ARCH" : "i386",
   "BACKEND" : "qemu",
   "QEMU" : "i386",
   "QEMU_NO_KVM" : "1",
   "QEMU_NO_TABLET" : "1",
   "QEMU_NO_FDC_SET" : "1",
   "CASEDIR" : "$data_dir/tests",
   "ISO" : "$data_dir/Core-7.2.iso",
   "CDMODEL" : "ide-cd",
   "HDDMODEL" : "ide-hd",
   "VERSION" : "1",
   "SSH_CONNECT_RETRY"  : "2",
   "SSH_CONNECT_RETRY_INTERVAL"  : ".001",
}
EOV
close($var);
# create screenshots
open($var, '>', 'live_log');
close($var);
system("perl $toplevel_dir/isotovideo -d 2>&1 | tee autoinst-log.txt");
is(system('grep -q "\d*: EXIT 0" autoinst-log.txt'),                                            0, 'test executed fine');
is(system('grep -q "\d* Snapshots are supported" autoinst-log.txt'),                            0, 'Snapshots are enabled');
is(system('grep -q "do not wait_still_screen" autoinst-log.txt'),                               0, 'test type string and do not wait');
is(system('grep -q "wait_still_screen: detected same image for 0.2 seconds" autoinst-log.txt'), 0, 'test type string and wait for .2 seconds');
is(system('grep -q "wait_still_screen: detected same image for 1 seconds" autoinst-log.txt'),   0, 'test type string and wait for 1 seconds');
is(system('grep -q "wait_still_screen: detected same image for 0.1 seconds" autoinst-log.txt'), 0, 'test type string and wait for .1 seconds');
is(system('grep -q ".*event.*STOP" autoinst-log.txt'),                                          0, 'Machine properly paused');
is(system('grep -q ".*event.*RESUME" autoinst-log.txt'),                                        0, 'Machine properly resumed');

is(system('grep -q "get_test_data returned expected file" autoinst-log.txt'), 0, 'get_test_data test');
is(system('grep -q "save_tmp_file returned expected file" autoinst-log.txt'), 0, 'save_tmp_file test');

my $ignore_results_re = qr/fail/;
for my $result (grep { $_ !~ $ignore_results_re } glob("testresults/result*.json")) {
    my $json = decode_json(Mojo::File->new($result)->slurp);
    is($json->{result}, 'ok', "Result in $result is ok") or BAIL_OUT("$result failed");
}

for my $result (glob("testresults/result*fail*.json")) {
    my $json = decode_json(Mojo::File->new($result)->slurp);
    is($json->{result}, 'fail', "Result in $result is fail") or BAIL_OUT("$result failed");
}

subtest 'Assert screen failure' => sub {
    plan tests => 1;
    open my $ifh, '<', 'autoinst-log.txt';
    my $regexp = qr /(?<=no candidate needle with tag\(s\)) '(no_tag, no_tag2|no_tag3)'/;
    my $count  = 0;
    for my $line (<$ifh>) {
        $count++ if $line =~ $regexp;
    }
    close $ifh;

    is($count, 2, 'Assert screen failures');
};

open($var, '>', 'vars.json');
print $var <<EOV;
{
   "ARCH" : "i386",
   "BACKEND" : "qemu",
   "QEMU" : "i386",
   "QEMU_NO_KVM" : "1",
   "QEMU_NO_TABLET" : "1",
   "QEMU_NO_FDC_SET" : "1",
   "CASEDIR" : "$data_dir/tests",
   "ISO" : "$data_dir/Core-7.2.iso",
   "CDMODEL" : "ide-cd",
   "HDDMODEL" : "ide-hd",
   "INTEGRATION_TESTS" : "1",
   "VERSION" : "1"
}
EOV

# call isotovideo with additional test parameters provided by command line
system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
isnt(system('grep -q "assert_screen_fail_test" autoinst-log.txt'), 0, 'assert screen test not scheduled');
is(system('grep -q "\d* Snapshots are not supported" autoinst-log.txt'), 0, 'Snapshots are not supported');
is(system('grep -q "isotovideo done" autoinst-log.txt'),                 0, 'isotovideo is done');
is(system('grep -q "EXIT 0" autoinst-log.txt'),                          0, 'Test finished as expected');

done_testing();
