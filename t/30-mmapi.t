#!/usr/bin/perl
#
# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# This test covers the signalblocker module and tinycv's helper to create
# threads upfront.

use Test::Most;
use Test::Mock::Time;
use Mojo::Base -strict, -signatures;

BEGIN {
    $ENV{OS_AUTOINST_LOCKAPI_RETRY_COUNT} = 1;
    $ENV{OS_AUTOINST_LOCKAPI_RETRY_INTERVAL} = 0;
    $ENV{OS_AUTOINST_MMAPI_RETRY_COUNT} = 1;
    $ENV{OS_AUTOINST_MMAPI_RETRY_INTERVAL} = 0;
    $ENV{OS_AUTOINST_MMAPI_POLL_INTERVAL} = 0;
    $ENV{MOJO_CONNECT_TIMEOUT} = 0.01;
}

use FindBin;
use lib "$FindBin::Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Fatal;
use Test::Output;
use Test::MockModule;
use Test::Warnings qw(:report_warnings);
use Mojolicious;
use mmapi;
use lockapi;

# mock testapi
my $testapi_mock = Test::MockModule->new('testapi');
my @recorded_info;
$testapi_mock->redefine(record_info => sub { push @recorded_info, [@_] });
my $basetest_mock = Test::MockModule->new('basetest');
$basetest_mock->redefine(remove_last_result => sub { pop @recorded_info });
$autotest::current_test = basetest->new;

# init mmapi/lockapi
$bmwqemu::vars{OPENQA_URL} = 'http://not/relevant';
$bmwqemu::vars{JOBTOKEN} = 'fake-jobtoken';

# define helper to call a function by its name
sub call ($function_name, @args) {
    __PACKAGE__->can($function_name)->(@args);
}

# test without a server
subtest 'mmapi: server not reachable' => sub {
    combined_like { is_deeply call($_), undef, "undef returned ($_)" } qr/Connection error/, "error logged ($_)" for (qw(mmapi::get_children));
    is_deeply(\@recorded_info, [], 'no info recorded') or diag explain \@recorded_info;
};
subtest 'lockapi: server not reachable' => sub {
    combined_like { is call($_, qw(name where info)), 0, "zero returned $_" } qr/Connection error/, "error logged ($_)"
      for (qw(lockapi::mutex_create lockapi::mutex_try_lock lockapi::barrier_create lockapi::barrier_try_wait));
    is_deeply(\@recorded_info, [], 'no info recorded') or diag explain \@recorded_info;
};

# setup a fake server
my $mock_srv = Mojolicious->new;
$mock_srv->log->unsubscribe('message')->on(
    message => sub {
        my ($log, $level, @lines) = @_;
        note "[$level] " . join "\n", @lines, '';
    });
$mock_srv->helper(render_mutex => sub {
        my ($self, %args) = @_;
        my $name = $self->param('name') // '';
        return $self->render(status => 200, text => 'ok') if $name eq 'lucky_lock';
        return $self->render(status => 404, text => 'error') if $name eq 'prone_lock';
        return $self->render(status => 410, text => 'owner finished') if $name eq 'finished_lock';
        return $self->render(status => 409, text => 'conflict');
});
my $routes = $mock_srv->routes;
my $fake_api = $routes->any('/api/v1');
my $wait_for_children_state;
$fake_api->get('/mm/children' => sub {
        my ($self) = @_;
        if ($wait_for_children_state) {
            return $self->render(json => {jobs => {1 => 'scheduled'}}) if $wait_for_children_state->{interations_left}--;
            return $self->render(json => {jobs => {1 => $wait_for_children_state->{state}}});
        }
        return $self->render(status => 403, text => 'not authorized') if ($self->tx->req->headers->header('X-API-JobToken') || '') ne 'fake-jobtoken';
        return $self->render(json => {jobs => [1, 2, 3]});
});
$fake_api->get('/mm/children/#state' => sub {
        my ($self) = @_;
        return $self->render(status => 404, json => {jobs => []}) if $self->stash('state') ne 'some-state';
        return $self->render(json => {jobs => [1]});
});
$fake_api->get('/mm/parents' => sub { shift->render(json => {jobs => [4, 5, 6]}) });
$fake_api->get('/jobs/100' => sub { shift->render(json => {job => {the => 'job info'}}) });
$fake_api->get('/workers' => sub {
        shift->render(json => {workers => [{
                        jobid => '100',
                        host => 'fake-host',
                        instance => 42,
                        properties => {JOBTOKEN => 'fake-jobtoken'},
        }]});
});
$fake_api->post('/mutex' => sub { shift->render_mutex });
$fake_api->post('/mutex/foo' => sub { shift->render(json => {some => 'mutex'}) });
$fake_api->post('/mutex/#name' => sub {
        my ($self) = @_;
        my $name = $self->param('name') // '';
        my $action = $self->param('action') // '';
        return $self->render(status => 200, text => 'ok') if ($name eq 'lockable' && $action eq 'lock') || ($name eq 'unlockable' && $action eq 'unlock');
        return $self->render_mutex;
});
$fake_api->post('/barrier' => sub {
        my ($self) = @_;
        my $name = $self->param('name') // '';
        my $tasks = $self->param('tasks') // '';
        return $self->render(status => 200, text => 'ok') if $name eq 'lucky_barrier' && $tasks eq '41';
        return $self->render_mutex;
});
$fake_api->post('/barrier/#name' => sub {
        my ($self) = @_;
        state $counter = 0;
        my $name = $self->param('name') // '';
        return $self->render(status => (++$counter % 3 == 0) == 0 ? 200 : 409, text => 'ok') if $name eq 'unblocked_next';
        return $self->render(status => 200, text => 'ok') if $name eq 'unblocked';
        return $self->render(status => 409, text => 'ok') if $name eq 'blocked';
        return $self->render(status => 410, text => 'ok') if $name eq 'not-exists';
        return $self->render(status => 200, text => 'ok') if $name eq 'check_dead_job_barrier' && ($self->param('check_dead_job') // '' eq '1');
        return $self->render_mutex;
});
$fake_api->delete('/barrier/#name' => sub {
        my ($self) = @_;
        my $name = $self->param('name') // '';
        return $self->render(status => 200, text => 'ok') if $name eq 'deletable';
        return $self->render_mutex;
});
$routes->get('/autoinst/vars' => sub { shift->render(json => {vars => {foo => 'bar'}}) });

# make mmapi/lockapi connect to the fake server
$bmwqemu::vars{OPENQA_URL} = '/not/relevant';
mmapi::set_app($mock_srv);

subtest 'mmapi: general usage' => sub {
    is(api_call(post => 'mutex/foo', {action => 'unlock'})->code, 200, 'api_call returns result');

    # test mmapi's `get_` functions
    is_deeply(mmapi::get_children(), [1, 2, 3], 'query children');
    is_deeply(mmapi::get_children_by_state('some-state'), [1], 'query children by state');
    combined_like {
        is_deeply(mmapi::get_children_by_state('another-state'), undef, 'query children by state (no results)');
    } qr|get_children_by_state: 404 response.*URL was.*/mm/children/another-state|, 'query children by state error logged';
    is_deeply(mmapi::get_parents(), [4, 5, 6], 'query parents');
    is_deeply(mmapi::get_job_info(100), {the => 'job info'}, 'query job info');
    combined_like {
        is_deeply(mmapi::get_job_info(101), undef, 'query job info (no result)');
    } qr/get_job_info: 404 response.*URL was.*101/, 'query job info error logged';
    is_deeply(mmapi::get_job_autoinst_url(100), "http://fake-host:20423/fake-jobtoken", 'get autoinst URL');
    combined_like {
        is_deeply(mmapi::get_job_autoinst_vars(101), undef, 'get autoinst vars (no result)');
    } qr/get_job_autoinst_url: .*/, 'error to get autoinst URL logged';

    # test with mocked get_job_autoinst_url
    my $mmapi_mock = Test::MockModule->new('mmapi');
    $mmapi_mock->redefine(get_job_autoinst_url => sub { '/autoinst' });
    is_deeply(mmapi::get_job_autoinst_vars(100), {foo => 'bar'}, 'get autoinst vars');

    is_deeply(\@recorded_info, [], 'no info recorded') or diag explain \@recorded_info;
};

subtest 'lockapi: misuse' => sub {
    combined_like { throws_ok { call($_, '') } qr/mydie/, "no name throws ($_)" } qr/missing lock name/, "no name logged ($_)"
      for (qw(lockapi::mutex_create lockapi::mutex_try_lock lockapi::mutex_lock lockapi::mutex_unlock));
    combined_like { throws_ok { call($_, '') } qr/mydie/, "no name throws ($_)" } qr/missing barrier name/, "no name logged ($_)"
      for (qw(lockapi::barrier_create lockapi::barrier_wait lockapi::barrier_destroy));
    combined_like { throws_ok { call($_, 'foo', '') } qr/mydie/, "no task throws ($_)" } qr/missing.*task/, "no task logged ($_)"
      for (qw(lockapi::barrier_create));
    is_deeply(\@recorded_info, [], 'no info recorded') or diag explain \@recorded_info;
};

subtest 'lockapi: server returns error' => sub {
    combined_like { is call($_, 'prone_lock'), 0, "0 returned ($_)" } qr/prone_lock.*404 response/, "error logged ($_)"
      for (qw(lockapi::mutex_create lockapi::mutex_try_lock lockapi::mutex_unlock));
    combined_like { is call($_, 'prone_lock', 7), 0, "0 returned ($_)" } qr/prone_lock.*404 response/, "error logged ($_)"
      for (qw(lockapi::barrier_create lockapi::barrier_try_wait lockapi::barrier_destroy));
    combined_unlike { is call($_, 'some_lock'), 0, "0 returned ($_)" } qr/(.*response|Connection error)/, "no error logged for blocked mutex ($_)"
      for (qw(lockapi::mutex_try_lock lockapi::mutex_unlock lockapi::barrier_try_wait));
    combined_like { throws_ok { call($_, 'finished_lock') } qr/mydie/, "owner finished throws ($_)" } qr/owner already finished/, "finished logged ($_)"
      for (qw(lockapi::mutex_try_lock));
    is_deeply(\@recorded_info, [], 'no info recorded') or diag explain \@recorded_info;
    # note: Omitting lockapi::mutex_lock and lockapi::barrier_wait here to avoid being blocked infinitely.
};

subtest 'lockapi: successful use' => sub {
    combined_like {
        is lockapi::mutex_create('lucky_lock'), 1, 'mutex created';
        is lockapi::mutex_lock('lockable'), 1, 'mutex locked';
        is lockapi::mutex_try_lock('lockable'), 1, 'mutex locked (try)';
        is lockapi::mutex_unlock('unlockable'), 1, 'mutex unlocked';
        is lockapi::barrier_create('lucky_barrier', 41), 1, 'barrier created';
        is lockapi::barrier_wait('unblocked_next'), 1, 'waited for barrier';
        is $recorded_info[0]->[1], 'Wait for unblocked_next (on parent job)', 'info recorded by waited for barrier';
        is lockapi::barrier_wait({name => 'check_dead_job_barrier', check_dead_job => 1}), 1, 'waited for barrier with check_dead_job flag';
        is $recorded_info[1]->[1], 'Wait for check_dead_job_barrier (on parent job)', 'different info recorded with check_dead_job flag';
        is lockapi::barrier_try_wait('unblocked'), 1, 'tried waiting for barrier';
        is lockapi::barrier_destroy('deletable'), 1, 'barrier destroyed';
    } qr/mutex create.*mutex lock.*mutex try lock.*mutex unlock.*barrier create.*barrier wait.*barrier try wait.*barrier destroy/s, 'logging';
    is scalar @recorded_info, 2, 'record info called expected number of times' or diag explain \@recorded_info;
};

subtest 'lockapi::barrier_wait() failures' => sub {
    combined_like { throws_ok { lockapi::barrier_wait({name => 'not-exists'}) } qr/mydie/, "die() on not-exists" } qr/lock owner already finished/, "Throw exception if lock doesn't exists or already finished";
    my $start = time;
    my $timeout = lockapi::POLL_INTERVAL - 1;
    combined_like { throws_ok { lockapi::barrier_wait({name => 'blocked', timeout => $timeout}) } qr/mydie/, "die() on timeout" } qr/barrier 'blocked' timeout after/, "barrier_wait() die on timeout specified";
    is(time - $start, $timeout, "Wait $timeout seconds, for timeout < POLL_INTERVAL");
    $start = time;
    $timeout = lockapi::POLL_INTERVAL + 1;
    combined_like { throws_ok { lockapi::barrier_wait({name => 'blocked', timeout => $timeout}) } qr/mydie/, "die() on timeout" } qr/barrier 'blocked' timeout after/, "barrier_wait() die on timeout specified";
    is(time - $start, $timeout, "Wait $timeout seconds, for timeout > POLL_INTERVAL");
    $start = time;
    combined_like { throws_ok { lockapi::barrier_wait({name => 'blocked', timeout => 0}) } qr/mydie/, "die() on timeout" } qr/barrier 'blocked' timeout after/, "barrier_wait() die on timeout specified";
    is(time - $start, 0, "Don't wait for timeout == 0");
};

subtest 'mmapi: wait functions' => sub {
    $wait_for_children_state = {interations_left => 1, state => 'done'};
    combined_like { mmapi::wait_for_children } qr/Waiting for 1 jobs to finish/, 'wait for children to be done';
    $wait_for_children_state = {interations_left => 1, state => 'running'};
    combined_like { mmapi::wait_for_children_to_start } qr/Waiting for 1 jobs to start/, 'wait for children to be runnning';
    my $mmapi_mock = Test::MockModule->new('mmapi');
    $mmapi_mock->redefine(get_children => undef);
    like exception { mmapi::wait_for_children }, qr/Failed to wait/, 'wait for children dies on error';
};

subtest 'mmapi: get_current_job_id function' => sub {
    my $do_error = 0;
    $fake_api->get('/whoami' => sub { return $do_error ? shift->render(status => 404, text => 'error') : shift->render(json => {id => 23}) });

    is(get_current_job_id(), 23, 'Retrieve jobid');
    $do_error = 1;
    combined_like {
        is(get_current_job_id(), undef, 'Retrieve undef on error');
    } qr /404 response/, 'Error message has 404';
};

done_testing;
