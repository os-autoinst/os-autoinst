# Copyright 2015-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

## synchronization API
package lockapi;

use Mojo::Base 'Exporter', -signatures;
use Scalar::Util 'looks_like_number';
use Time::Seconds;
our @EXPORT = qw(mutex_create mutex_lock mutex_unlock mutex_try_lock mutex_wait
  barrier_create barrier_wait barrier_try_wait barrier_destroy);

require bmwqemu;
use mmapi qw(api_call_2 get_job_info);
use testapi ();

use constant RETRY_COUNT => $ENV{OS_AUTOINST_LOCKAPI_RETRY_COUNT} // 7;
use constant RETRY_INTERVAL => $ENV{OS_AUTOINST_LOCKAPI_RETRY_INTERVAL} // 10;
use constant POLL_INTERVAL => $ENV{OS_AUTOINST_LOCKAPI_POLL_INTERVAL} // 5;

sub _try_lock ($type, $name, $param) {
    my $log_ctx = "acquiring $type '$name'";
    my %expected_return_codes = (200 => 1, 409 => 1, 410 => 1);
    my $actual_return_code;
    for (1 .. RETRY_COUNT) {
        my $tx = api_call_2(post => "$type/$name", $param, \%expected_return_codes);
        $actual_return_code = $tx->res->code;
        last unless mmapi::handle_api_error($tx, $log_ctx, \%expected_return_codes);
        last unless ($actual_return_code // 0) == 410;
        bmwqemu::fctinfo("Retry $_ of " . RETRY_COUNT);    # uncoverable statement
        sleep RETRY_INTERVAL;    # uncoverable statement
    }
    if ($actual_return_code) {
        return 1 if $actual_return_code == 200;
        bmwqemu::mydie "$log_ctx: lock owner already finished" if $actual_return_code == 410;
    }
    return 0;
}

sub _lock_action ($name, $where = undef) {
    my $param = {action => 'lock'};
    $param->{where} = $where if $where;
    return _try_lock('mutex', $name, $param);
}

# Log info about event and it's location
sub _log ($name, %args) {
    # Generate log message
    my $job
      = $args{where}
      ? ((get_job_info($args{where}) // {})->{settings}->{TEST} // '?') . " #$args{where}"
      : 'parent job';
    my $msg = "Wait for $name (on $job)";
    $msg .= " - $args{info}" if $args{info};
    my $subject = 'Paused';
    if (defined $args{amend}) {
        # amend log info with wait duration
        $autotest::current_test->remove_last_result;
        $subject .= ' ' . int($args{amend} / ONE_MINUTE) . 'm' . $args{amend} % ONE_MINUTE . 's';
    }
    testapi::record_info $subject, $msg;
}

sub _api_call_with_logging_and_error_handling ($log_ctx, $method, $action, $params, $expected_codes = undef) {
    bmwqemu::diag($log_ctx);
    my $tx = api_call_2($method, $action, $params, $expected_codes);
    return 0 if mmapi::handle_api_error($tx, $log_ctx, $expected_codes);
    return $tx->res->code == 200 ? 1 : 0;
}

sub mutex_lock ($name, $where = undef) {
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex lock '$name'");
    while (1) {
        my $res = _lock_action($name, $where);
        return 1 if $res;
        bmwqemu::diag("mutex lock '$name' unavailable, sleeping " . POLL_INTERVAL . ' seconds'); # uncoverable statement
        sleep POLL_INTERVAL;    # uncoverable statement
    }
}

sub mutex_try_lock ($name, $where = undef, @) {
    bmwqemu::mydie('missing lock name') unless $name;
    bmwqemu::diag("mutex try lock '$name'");
    return _lock_action($name, $where);
}

sub mutex_unlock ($name, $where = undef) {
    bmwqemu::mydie('missing lock name') unless $name;
    my $param = {action => 'unlock'};
    $param->{where} = $where if $where;
    return _api_call_with_logging_and_error_handling("mutex unlock '$name'", post => "mutex/$name", $param);
}

sub mutex_create ($name, @) {
    bmwqemu::mydie('missing lock name') unless $name;
    return _api_call_with_logging_and_error_handling("mutex create '$name'", post => "mutex", {name => $name});
}

# Wrapper for mutex_lock & mutex_unlock
sub mutex_wait ($name, $where = undef, $info = undef) {
    _log $name, where => $where, info => $info;
    my $start = time;
    mutex_lock $name, $where;
    mutex_unlock $name, $where;
    _log $name, where => $where, info => $info, amend => time - $start;
}

## Barriers
sub barrier_create ($name, $tasks = undef, @) {
    bmwqemu::mydie('missing barrier name') unless $name;
    bmwqemu::mydie('missing number of barrier task') unless $tasks;
    return _api_call_with_logging_and_error_handling(
        "barrier create '$name' for $tasks tasks",
        post => 'barrier',
        {name => $name, tasks => $tasks});
}

sub _wait_action ($name, $where = undef, $check_dead_job = undef) {
    my $param;
    $param->{where} = $where if $where;
    $param->{check_dead_job} = $check_dead_job if defined $check_dead_job;

    return _try_lock('barrier', $name, $param);
}

# Reason to include this is to be able to unit test _wait_action without blocking
sub barrier_try_wait ($name, $where = undef, @) {
    bmwqemu::mydie('missing barrier name') unless $name;
    bmwqemu::diag("barrier try wait '$name'");
    return _wait_action($name, $where);
}

sub barrier_wait (@args) {
    my ($name, $where, $check_dead_job) = ref $args[0] eq 'HASH' ? (@{$args[0]}{qw(name where check_dead_job)}) : @args;
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

        bmwqemu::diag("barrier '$name' not released, sleeping " . POLL_INTERVAL . ' seconds');   # uncoverable statement
        sleep POLL_INTERVAL;    # uncoverable statement
    }
}

sub barrier_destroy ($name, $where = undef) {
    bmwqemu::mydie('missing barrier name') unless $name;
    return _api_call_with_logging_and_error_handling(
        "barrier destroy '$name'",
        delete => "barrier/$name",
        $where ? {where => $where} : undef, {200 => 1});
}

1;
