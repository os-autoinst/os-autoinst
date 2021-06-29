#!/usr/bin/perl
#
# Copyright (c) 2021 SUSE LLC
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

# This test covers the signalblocker module and tinycv's helper to create
# threads upfront.

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use File::Basename qw(dirname);
use Test::Warnings qw(warnings :report_warnings);
use Time::HiRes qw(sleep);
use POSIX ':signal_h';
use signalblocker;

no warnings 'redefine';
sub bmwqemu::diag { note $_[0] }

# make the number of threads to spawn configurable
my $fix_thread_count_for_testing = $ENV{OS_AUTOINST_TEST_THREAD_COUNT} // 8;

# make the usage of the signal blocker configurable
# note: The test will fail if this variable is set. This configuration is used to verify that the
#       test itself is actually able to show negative results.
my $no_signal_blocker = $ENV{OS_AUTOINST_TEST_NO_SIGNAL_BLOCKER};

# define a helper to find the number of threads spawned by this test
sub thread_count { scalar split("\n", `ps huH p $$`) }
is(my $last_thread_count = thread_count, 1, 'initially one thread');

# count SIGTERMs we receive; those handlers should work after creating/destroying the signal blocker
# Note that without these handlers, there won't be any crash in Perl's signal handler as it's never
# registered for those signals.
my $received_sigterm = 0;
$SIG{TERM} = sub { $received_sigterm += 1; note "received SIGTERM $received_sigterm"; };
my $received_sigchld = 0;
$SIG{CHLD} = sub { $received_sigchld += 1; note "received SIGCHLD $received_sigchld"; };

# initialize OpenCV via signalblocker and create_threads
{
    my $signal_blocker = $no_signal_blocker || signalblocker->new;
    require cv;
    cv::init();
    require tinycv;
    tinycv::create_threads($fix_thread_count_for_testing);
    $last_thread_count = thread_count;
    cmp_ok($last_thread_count, '>=', $fix_thread_count_for_testing, "at least $fix_thread_count_for_testing threads created");
}

# do some native calls; no further threads should be created
my $img = tinycv::read(dirname(__FILE__) . '/data/accept-ssh-host-key.png');
$img->search_needle($img, 0, 0, 50, 50, 0);
$img->similarity($img);
cmp_ok(thread_count, '<=', $last_thread_count, 'no new threads after searching for a needle');

# send a lot of SIGTERMs to ourselves; expect no crashes
# notes: Not simply using Perl's kill function here because using that I've never been able to actually observe
#        any crashes without the signal blocker in place (OS_AUTOINST_TEST_NO_SIGNAL_BLOCKER=1).
my $pid     = $$;
my $timeout = 5;
exec bash => '-e', '-c', "for i in {1..100}; do echo \"# sending SIGTERM \$i\" && kill $pid; done" unless my $fork = fork;
waitpid $fork, 0;
note 'waiting for at least one signal to be handled' and sleep .2 until $received_sigterm >= 1 || ($timeout -= .2) < 0;
note "handled $received_sigterm TERM signals";
ok($received_sigterm > 0, "received SIGTERM $received_sigterm times; no crashes after at least 200 ms idling time");

$received_sigchld = 0;
# 0 here means WIFEXITED and WEXITSTATUS == 0
cmp_ok(system("true"), '==', 0, 'system returns exit status');
is($received_sigchld, 1, 'got SIGCHLD after system');

cmp_ok(thread_count, '<=', $last_thread_count, 'still no new threads after sending signals');

done_testing;
