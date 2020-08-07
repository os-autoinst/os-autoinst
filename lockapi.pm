# Copyright (c) 2015-2021 SUSE LLC
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
use mmapi qw(api_call_2 get_job_info);
use testapi ();

use constant RETRY_COUNT    => $ENV{OS_AUTOINST_LOCKAPI_RETRY_COUNT}    // 7;
use constant RETRY_INTERVAL => $ENV{OS_AUTOINST_LOCKAPI_RETRY_INTERVAL} // 10;
use constant POLL_INTERVAL  => $ENV{OS_AUTOINST_LOCKAPI_POLL_INTERVAL}  // 5;

sub _try_lock {
    my ($type, $name, $param) = @_;

    my $log_ctx               = "acquiring $type '$name'";
    my %expected_return_codes = (200 => 1, 409 => 1, 410 => 1);
    my $actual_return_code;
    for (1 .. RETRY_COUNT) {
        my $tx = api_call_2(post => "$type/$name", $param, \%expected_return_codes);
        $actual_return_code = $tx->res->code;
        last unless mmapi::handle_api_error($tx, $log_ctx, \%expected_return_codes);
        last unless $actual_return_code == 410;
        bmwqemu::fctinfo("Retry $_ of " . RETRY_COUNT);    # uncoverable statement
        sleep RETRY_INTERVAL;                              # uncoverable statement
    }
    if ($actual_return_code) {
        return 1                                               if $actual_return_code == 200;
        bmwqemu::mydie "$log_ctx: lock owner already finished" if $actual_return_code == 410;
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
    my $job = $args{where} ? ((get_job_info($args{where}) // {})->{settings}->{TEST} // '?') . " #$args{where}" : 'parent job';
    my $msg = "Wait for $name (on $job)";
    $msg .= " - $args{info}" if $args{info};
    my $subject = 'Paused';
    if (defined $args{amend}) {
        # amend log info with wait duration
        $autotest::current_test->remove_last_result;
        $subject .= ' ' . int($args{amend} / 60) . 'm' . $args{amend} % 60 . 's';
    }
    testapi::record_info $subject, $msg;
}

sub _api_call_with_logging_and_error_handling {
    my ($log_ctx, $method, $action, $params, $expected_codes) = (@_);
    bmwqemu::diag($log_ctx);
    my $tx = api_call_2($method, $action, $params, $expected_codes);
    return 0 if mmapi::handle_api_error($tx, $log_ctx, $expected_codes);
    return $tx->res->code == 200 ? 1 : 0;
}

sub mutex_lock {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex lock '$name'");
    while (1) {
        my $res = _lock_action($name, $where);
        return 1 if $res;
        bmwqemu::diag("mutex lock '$name' unavailable, sleeping " . POLL_INTERVAL . ' seconds');    # uncoverable statement
        sleep POLL_INTERVAL;                                                                        # uncoverable statement
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
    bmwqemu::mydie('missing lock name') unless $name;
    my $param = {action => 'unlock'};
    $param->{where} = $where if $where;
    return _api_call_with_logging_and_error_handling("mutex unlock '$name'", post => "mutex/$name", $param);
}

sub mutex_create {
    my ($name) = @_;
    bmwqemu::mydie('missing lock name') unless $name;
    return _api_call_with_logging_and_error_handling("mutex create '$name'", post => "mutex", {name => $name});
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
    return _api_call_with_logging_and_error_handling("barrier create '$name' for $tasks tasks", post => 'barrier', {name => $name, tasks => $tasks});
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

        bmwqemu::diag("barrier '$name' not released, sleeping " . POLL_INTERVAL . ' seconds');    # uncoverable statement
        sleep POLL_INTERVAL;                                                                      # uncoverable statement
    }
}

sub barrier_destroy {
    my ($name, $where) = @_;
    bmwqemu::mydie('missing barrier name') unless $name;
    return _api_call_with_logging_and_error_handling("barrier destroy '$name'",
        delete => "barrier/$name", $where ? {where => $where} : undef, {200 => 1});
}

1;
