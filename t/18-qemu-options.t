#!/usr/bin/perl
# Copyright (C) 2018-2021 SUSE LLC
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
use Test::Warnings ':report_warnings';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '40';
use Try::Tiny;
use File::Basename;
use Cwd 'abs_path';
use Mojo::File qw(path tempdir);
use Mojo::JSON qw(encode_json);
use Benchmark ':hireswallclock';
use Mojo::Util qw(scope_guard);

my $dir          = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = "$Bin/..";
my $data_dir     = "$Bin/data";
my $pool_dir     = "$dir/pool";
mkdir $pool_dir;
chdir $pool_dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

# just save ourselves some time during testing
# note: The factor for coverage has been determined by comparing runtimes locally and was rounded up to the next integer.
$ENV{OSUTILS_WAIT_ATTEMPT_INTERVAL}           //= 1;
$ENV{QEMU_QMP_CONNECT_ATTEMPTS}               //= 1;
$ENV{EXPECTED_ISOTOVIDEO_RUNTIME_SCALE_COVER} //= Devel::Cover->can('report') ? 12 : 1;
$ENV{EXPECTED_ISOTOVIDEO_RUNTIME}             //= $ENV{EXPECTED_ISOTOVIDEO_RUNTIME_SCALE_COVER} * 4;

my @common_options = (
    ARCH            => 'i386',
    BACKEND         => 'qemu',
    QEMU            => 'i386',
    QEMU_NO_KVM     => 1,
    QEMU_NO_TABLET  => 1,
    QEMU_NO_FDC_SET => 1,
    CASEDIR         => "$data_dir/tests",
    ISO             => "$data_dir/Core-7.2.iso",
    CDMODEL         => 'ide-cd',
    HDDMODEL        => 'ide-hd',
    WORKER_INSTANCE => 3,
    VERSION         => 1,
    SCHEDULE        => 'tests/noop',
);
my $vars_json = path('vars.json');
my $log_file  = path('autoinst-log.txt');
my $log       = '';
sub run_isotovideo {
    $vars_json->spurt(encode_json({@common_options, @_}));
    system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
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
    like($log, qr/-version/,                                              '-version option added');
    like($log, qr/QEMU emulator version/,                                 'QEMU version printed');
    like($log, qr/Fabrice Bellard and the QEMU Project developers/,       'Copyright printed');
    like($log, qr/Not connecting to QEMU as requested by QEMU_ONLY_EXEC/, 'QEMU_ONLY_EXEC option has effect');
    unlike($log, qr/\: invalid option/, 'no invalid option detected');
    cmp_ok($time->[0], '<', $ENV{EXPECTED_ISOTOVIDEO_RUNTIME}, "execution time of isotovideo ($time->[0] s) within reasonable limits");

    # list machines: call isotovideo with QEMU_APPEND, to list machines
    # test whether QMP connection attempts are aborted when QEMU exists: unset QEMU_QMP_CONNECT_ATTEMPTS temporarily
    my $qmp_connect_attempts = delete $ENV{QEMU_QMP_CONNECT_ATTEMPTS};
    run_isotovideo(@common_options, QEMU_APPEND => 'M ?');
    like($log, qr/-M \?/,                    '-M ? option added');
    like($log, qr/Supported machines are\:/, 'Supported machines listed');
    unlike($log, qr/\: invalid option/, 'no invalid option detected');
    like($log, qr/QEMU terminated before QMP connection could be established/, 'connecting to QMP socket aborted');
    $ENV{QEMU_QMP_CONNECT_ATTEMPTS} = $qmp_connect_attempts;

    # multiple options: call isotovideo with QEMU_APPEND, with version
    run_isotovideo(QEMU_APPEND => 'M ? -version');
    like($log, qr/-version/,                                        '-version option added');
    like($log, qr/QEMU emulator version/,                           'QEMU version printed');
    like($log, qr/Fabrice Bellard and the QEMU Project developers/, 'Copyright printed');
    unlike($log, qr/\: invalid option/, 'no invalid option detected');

    # invalid option: call isotovideo with QEMU_APPEND, with a broken option
    run_isotovideo(QEMU_APPEND => 'broken option');
    like($log, qr/-broken option/,           '-broken option added');
    like($log, qr/-broken\: invalid option/, 'invalid option detected');
};

# test QEMU_HUGE_PAGES_PATH with different options
subtest qemu_huge_pages_option => sub {
    # print version: call isotovideo with QEMU_HUGE_PAGES_PATH
    run_isotovideo(QEMU_HUGE_PAGES_PATH => '/no/dev/hugepages/');
    like($log, qr/-mem-prealloc/,                                                                          '-mem-prealloc option added');
    like($log, qr|-mem-path /no/dev/hugepages/|,                                                           '-mem-path /no/dev/hugepages/');
    like($log, qr|can\'t open backing store /no/dev/hugepages/ for guest RAM\: No such file or directory|, 'expected failure as /no/dev/hugepages/ does not exist');
};

# test QEMUTPM with different options
# note: Since this test does not have any checks for the actual QEMU output it would be possible to mock the actual execution
#       of QEMU here.
subtest qemu_tpm_option => sub {
    # call isotovideo with QEMUTPM=instance
    run_isotovideo(QEMU_ONLY_EXEC => 1, QEMUTPM => 'instance');
    like($log, qr|-chardev socket,id=chrtpm,path=/tmp/mytpm3/swtpm-sock|, '-chardev socket option added (instance)');
    like($log, qr|-tpmdev emulator,id=tpm0,chardev=chrtpm|,               '-tpmdev emulator option added');
    like($log, qr|-device tpm-tis,tpmdev=tpm0|,                           '-device tpm-tis option added');

    # call isotovideo with QEMUTPM=2
    run_isotovideo(QEMU_ONLY_EXEC => 1, QEMUTPM => '2');
    like($log, qr|-chardev socket,id=chrtpm,path=/tmp/mytpm2/swtpm-sock|, '-chardev socket option added (2)');

    # call isotovideo with QEMUTPM=instance, ppc64le arch
    run_isotovideo(QEMU_ONLY_EXEC => 1, QEMUTPM => 'instance', ARCH => 'ppc64le');
    like($log, qr|-chardev socket,id=chrtpm,path=/tmp/mytpm3/swtpm-sock|, '-chardev socket option added (instance)');
    like($log, qr/-tpmdev emulator,id=tpm0,chardev=chrtpm/,               '-tpmdev emulator option added');
    like($log, qr/-device tpm-spapr,tpmdev=tpm0/,                         '-device tpm-spapr option added');
    like($log, qr/-device spapr-vscsi,id=scsi9,reg=0x00002000/,           '-device spapr-vscsi option added');

    # call isotovideo with QEMUTPM=instance, aarch64 arch
    run_isotovideo(QEMU_ONLY_EXEC => 1, QEMUTPM => 'instance', ARCH => 'aarch64');
    like($log, qr|-chardev socket,id=chrtpm,path=/tmp/mytpm3/swtpm-sock|, '-chardev socket option added (instance)');
    like($log, qr/-tpmdev emulator,id=tpm0,chardev=chrtpm/,               '-tpmdev emulator option added');
    like($log, qr/-device tpm-tis-device,tpmdev=tpm0/,                    '-device tpm-tis option added');
};

done_testing();
