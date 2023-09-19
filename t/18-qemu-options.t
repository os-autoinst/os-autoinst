#!/usr/bin/perl
# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use Try::Tiny;
use File::Basename;
use Cwd 'abs_path';
use Mojo::File qw(path tempdir);
use Mojo::JSON qw(encode_json);
use Benchmark ':hireswallclock';
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = "$Bin/..";
my $data_dir = "$Bin/data";
my $pool_dir = "$dir/pool";
mkdir $pool_dir;
chdir $pool_dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

# just save ourselves some time during testing
# note: The factor for coverage has been determined by comparing runtimes locally and was rounded up to the next integer.
$ENV{OSUTILS_WAIT_ATTEMPT_INTERVAL} //= 1;
$ENV{QEMU_QMP_CONNECT_ATTEMPTS} //= 1;
$ENV{EXPECTED_ISOTOVIDEO_RUNTIME_SCALE_COVER} //= Devel::Cover->can('report') ? 12 : 1;
$ENV{EXPECTED_ISOTOVIDEO_RUNTIME} //= $ENV{EXPECTED_ISOTOVIDEO_RUNTIME_SCALE_COVER} * 4;

my @common_options = (
    ARCH => 'i386',
    BACKEND => 'qemu',
    QEMU => 'i386',
    CASEDIR => "$data_dir/tests",
    WORKER_INSTANCE => 3,
    SCHEDULE => 'tests/noop',
);
my $vars_json = path('vars.json');
my $log_file = path('autoinst-log.txt');
my $log = '';
sub run_isotovideo (@args) {
    $vars_json->spew(encode_json({@common_options, @args}));
    ok system("cd $toplevel_dir && perl $toplevel_dir/isotovideo --workdir $pool_dir -d qemu_disable_snapshots=1 2>&1 | tee $pool_dir/autoinst-log.txt") == 0, 'zero exit status';
    $log = $log_file->slurp;
}

# notes regarding SCHEDULE, QEMU_ONLY_EXEC and QEMU_WAIT_FINISH used by this test
# - SCHEDULE is set to a test which will do nothing to mock any actual test execution.
# - QEMU_ONLY_EXEC skips any further setup/handling of QEMU after launching it. That means autoinst-log.txt will contain
#   the QEMU start parameter.
# - It will not necessarily contain the output of QEMU itself because we do not wait for QEMU to do anything after launching
#   it and therefore already terminate the test execution before QEMU can do something.
# - That is where QEMU_WAIT_FINISH comes into play. It causes the backend to wait until QEMU terminates on its own (in this test
#   case after printing the version).

# test QEMU_APPEND with different options
subtest qemu_append_option => sub {
    # print version and also measure time of startup and shutdown: call isotovideo with QEMU_APPEND
    my $time = timeit(1, sub { run_isotovideo(QEMU_ONLY_EXEC => 1, QEMU_WAIT_FINISH => 1, QEMU_APPEND => 'version') });
    like($log, qr/-version/, '-version option added');
    like($log, qr/QEMU emulator version/, 'QEMU version printed');
    like($log, qr/Fabrice Bellard and the QEMU Project developers/, 'Copyright printed');
    like($log, qr/Not connecting to QEMU as requested by QEMU_ONLY_EXEC/, 'QEMU_ONLY_EXEC option has effect');
    unlike($log, qr/\: invalid option/, 'no invalid option detected');
    cmp_ok($time->[0], '<', $ENV{EXPECTED_ISOTOVIDEO_RUNTIME}, "execution time of isotovideo ($time->[0] s) within reasonable limits");

    # multiple options added, only version will be effective
    # test whether QMP connection attempts are aborted when QEMU exists: unset QEMU_QMP_CONNECT_ATTEMPTS temporarily
    my $qmp_connect_attempts = delete $ENV{QEMU_QMP_CONNECT_ATTEMPTS};
    run_isotovideo(@common_options, QEMU_APPEND => 'version -M ?');
    like($log, qr/-M \?/, '-M ? option added');
    like($log, qr/-version/, '-version option added');
    like($log, qr/QEMU emulator version/, 'QEMU version printed');
    unlike($log, qr/Supported machines are\:/, 'Supported machines not listed');
    unlike($log, qr/\: invalid option/, 'no invalid option detected');
    like($log, qr/QEMU terminated before QMP connection could be established/, 'connecting to QMP socket aborted');
    $ENV{QEMU_QMP_CONNECT_ATTEMPTS} = $qmp_connect_attempts;
};

done_testing();
