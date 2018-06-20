# Copyright (c) 2015 SUSE LINUX GmbH, Nuernberg, Germany.
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

## synchronization API
package lockapi;

use strict;
use warnings;
use Scalar::Util 'looks_like_number';
use base 'Exporter';
our @EXPORT = qw(mutex_create mutex_lock mutex_unlock mutex_try_lock mutex_wait
  barrier_create barrier_wait barrier_try_wait barrier_destroy);

require bmwqemu;
use mmapi qw(api_call get_job_info);
use testapi 'record_info';

sub _try_lock {
    my ($type, $name, $param) = @_;
    # try up to 7 times
    my $res = '';
    for (1 .. 7) {
        $res = api_call('post', "$type/$name", $param)->code;
        return 1 if ($res == 200);
        last unless $res == 410;
        bmwqemu::fctinfo("Retry $_ of 7...");
        sleep 10;
    }
    bmwqemu::mydie "$type '$name': lock owner already finished" if $res == 410;
    if ($res != 409) {
        bmwqemu::fctwarn("Unknown return code $res for lock api");
    }
    return 0;
}

sub _lock_action {
    my ($name, $where) = @_;
    my $param = {action => 'lock'};
    $param->{where} = $where if $where;
    return _try_lock('mutex', $name, $param);
}

# Log info about event and it's location
sub _log {
    my ($name, %args) = @_;

    # Generate log message
    my $job = $args{where} ? get_job_info($args{where})->{settings}->{TEST} . " #$args{where}" : 'parent job';
    my $msg = "Wait for $name (on $job)";
    $msg .= " - $args{info}" if $args{info};

    if (defined $args{amend}) {
        # amend log info with wait duration
        $autotest::current_test->remove_last_result;
        record_info 'Paused ' . int($args{amend} / 60) . 'm' . $args{amend} % 60 . 's', $msg;
    }
    else {
        record_info 'Paused', $msg;
    }
}

sub mutex_lock {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex lock '$name'");
    while (1) {
        my $res = _lock_action($name, $where);
        return 1 if $res;
        bmwqemu::diag("mutex lock '$name' unavailable, sleeping 5s");
        sleep(5);
    }
}

sub mutex_try_lock {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex try lock '$name'");
    return _lock_action($name, $where);
}

sub mutex_unlock {
    my ($name, $where) = @_;
    my $param = {action => 'unlock'};
    $param->{where} = $where if $where;

    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex unlock '$name'");
    my $res = api_call('post', "mutex/$name", $param)->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

sub mutex_create {
    my ($name) = @_;
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex create '$name'");
    my $res = api_call('post', "mutex", {name => $name})->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

# Wrapper for mutex_lock & mutex_unlock
sub mutex_wait {
    my ($name, $where, $info) = @_;
    _log $name, where => $where, info => $info;
    my $start = time;
    mutex_lock $name,   $where;
    mutex_unlock $name, $where;
    _log $name,         where => $where, info => $info, amend => time - $start;
}

## Barriers
sub barrier_create {
    my ($name, $tasks) = @_;
    bmwqemu::mydie('missing barrier name')           unless $name;
    bmwqemu::mydie('missing number of barrier task') unless $tasks;
    bmwqemu::diag("barrier create '$name' for $tasks tasks");
    my $res = api_call('post', 'barrier', {name => $name, tasks => $tasks})->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

sub _wait_action {
    my ($name, $where, $check_dead_job) = @_;
    my $param;
    $param->{where}          = $where          if $where;
    $param->{check_dead_job} = $check_dead_job if defined $check_dead_job;

    return _try_lock('barrier', $name, $param);
}

# Reason to include this is to be able to unit test _wait_action without blocking
sub barrier_try_wait {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing barrier name') unless $name;
    bmwqemu::diag("barrier try wait '$name'");
    return _wait_action($name, $where);
}

sub barrier_wait {
    my ($name, $where, $check_dead_job) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(name where check_dead_job)}) : @_;

    $check_dead_job = looks_like_number($check_dead_job) && $check_dead_job ? 1 : 0;

    bmwqemu::mydie('missing barrier name') unless $name;
    bmwqemu::diag("barrier wait '$name'");

    _log $name, where => $where;
    my $start = time;
    while (1) {
        my $res = _wait_action($name, $where, $check_dead_job);
        if ($res) {
            _log $name, where => $where, amend => time - $start;
            return 1;
        }

        bmwqemu::diag("barrier '$name' not released, sleeping 5s");
        sleep(5);
    }
}

sub barrier_destroy {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing barrier name') unless $name;
    bmwqemu::diag("barrier destroy '$name'");
    my $param;
    $param->{where} = $where if $where;
    my $res = api_call('delete', "barrier/$name", $param)->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api");
}

1;
