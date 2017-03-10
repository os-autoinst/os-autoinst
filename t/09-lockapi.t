#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Warnings;

BEGIN {
    unshift @INC, '..';
}

use lockapi;

# mock api_call return value
my $api_call_return;
my %locks;
my %action = (
    method => undef,
    action => undef,
    params => undef,
);

package ua_return;

sub new { my $t = shift; return bless {res => @_}, $t; }
sub code { return shift->{res} }
1;

package main;
# simulate responses from openQA WebUI or overridden by $api_call_return
sub fake_api_call {
    my ($method, $action, $params, $expected_codes) = @_;
    %action = (
        method => $method,
        action => $action,
        params => $params
    );
    return ua_return->new($api_call_return);
}

# monkey-patch mmap::api_call
my $mod = new Test::MockModule('lockapi');
$mod->mock(api_call => \&fake_api_call);

sub check_action {
    my ($method, $action, $params) = @_;
    my $res = 0;
    $res++ if ($method eq $action{method});
    $res++ if ($action eq $action{action});
    #     return unless($params

    %action = (
        method => undef,
        action => undef,
        params => undef,
    );
    return $res;
}

eval { mutex_create; };
ok($@, 'missing create name catched');
eval { mutex_try_lock; };
ok($@, 'missing try lock name catched');
eval { mutex_lock; };
ok($@, 'missing lock name catched');
eval { mutex_unlock; };
ok($@, 'missing unlock name catched');

# check successful ops
$api_call_return = 200;
ok(mutex_create('lock1'), 'mutex created');
ok(check_action('POST', 'mutex', {name => 'lock1'}), 'mutex_create request valid');

ok(mutex_lock('lock1'), 'mutex locked');
ok(check_action('POST', 'mutex/lock1', {action => 'lock'}), 'mutex_lock request valid');

ok(mutex_try_lock('lock1'), 'mutex locked');
ok(check_action('POST', 'mutex/lock1', {action => 'lock'}), 'mutex_lock request valid');

ok(mutex_unlock('lock1'), 'lock unlocked');
ok(check_action('POST', 'mutex/lock1', {action => 'unlock'}), 'mutex_unlock request valid');

# check unsuccessful ops
$api_call_return = 409;
ok(!mutex_create('lock1'), 'mutex not created');
ok(check_action('POST', 'mutex', {name => 'lock1'}), 'mutex_create request valid');

# instead of mutex_lock test mutex_try_lock to avoid block
ok(!mutex_try_lock('lock1'), 'mutex not locked');
ok(check_action('POST', 'mutex/lock1', {action => 'lock'}), 'mutex_lock request valid');

ok(!mutex_unlock('lock1'), 'lock not unlocked');
ok(check_action('POST', 'mutex/lock1', {action => 'unlock'}), 'mutex_unlock request valid');



# barriers testing
$api_call_return = 200;
eval { barrier_create; };
ok($@, 'missing create name catched');
eval { barrier_create('barrier1'); };
ok($@, 'missing create tasks catched');
eval { barrier_wait; };
ok($@, 'missing wait name catched');
eval { barrier_destroy; };
ok($@, 'missing destroy name catched');

ok(barrier_create('barrier1', 3), 'barrier created');
ok(check_action('POST', 'barrier', {name => 'barrier1', tasks => 3}), 'barrier create request valid');

ok(barrier_wait('barrier1'), 'registered for waiting and released immideately');
ok(check_action('POST', 'barrier/barrier1', undef), 'barrier wait request valid');

ok(barrier_destroy('barrier1'), 'barrier destroyed');
ok(check_action('DELETE', 'barrier/barrier1', undef), 'barrier destroy request valid');

$api_call_return = 409;
ok(!barrier_create('barrier1', 3), 'barrier not created');
ok(check_action('POST', 'barrier', {name => 'barrier1', tasks => 3}), 'barrier create request valid');

# instead of barrier_wait test barrier_try_wait to avoid block
ok(!barrier_try_wait('barrier1'), 'registered for waiting and waiting');
ok(check_action('POST', 'barrier/barrier1', undef), 'barrier wait request valid');

ok(!barrier_destroy('barrier1'), 'barrier not destroyed');
ok(check_action('DELETE', 'barrier/barrier1', undef), 'barrier destroy request valid');

done_testing;
