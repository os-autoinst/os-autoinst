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

use base qw/Exporter/;
our @EXPORT = qw/mutex_create mutex_lock mutex_unlock mutex_try_lock barrier_create barrier_wait barrier_try_wait barrier_destroy/;

require bmwqemu;
use mmapi qw/api_call/;
use log;

sub _lock_action {
    my ($name, $where) = @_;
    my $param = {action => 'lock'};
    $param->{where} = $where if $where;
    my $res = api_call('post', "mutex/$name", $param)->code;
    return 1 if ($res == 200);

    log::mydie "mutex lock '$name': lock owner already finished" if $res == 410;

    if ($res != 409) {
        log::fctwarn("Unknown return code $res for lock api");
    }
    return 0;
}

sub mutex_lock {
    my ($name, $where) = @_;
    log::mydie('missing lock name') unless $name;
    log::diag("mutex lock '$name'");
    while (1) {
        my $res = _lock_action($name, $where);
        return 1 if $res;
        log::diag("mutex lock '$name' unavailable, sleeping 5s");
        sleep(5);
    }
}

sub mutex_try_lock {
    my ($name, $where) = @_;
    log::mydie('missing lock name') unless $name;
    log::diag("mutex try lock '$name'");
    return _lock_action($name, $where);
}

sub mutex_unlock {
    my ($name) = @_;
    log::mydie('missing lock name') unless $name;
    log::diag("mutex unlock '$name'");
    my $res = api_call('post', "mutex/$name", {action => 'unlock'})->code;
    return 1 if ($res == 200);
    log::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

sub mutex_create {
    my ($name) = @_;
    log::mydie('missing lock name') unless $name;
    log::diag("mutex create '$name'");
    my $res = api_call('post', "mutex", {name => $name})->code;
    return 1 if ($res == 200);
    log::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

## Barriers
sub barrier_create {
    my ($name, $tasks) = @_;
    log::mydie('missing barrier name')           unless $name;
    log::mydie('missing number of barrier task') unless $tasks;
    log::diag("barrier create '$name' for $tasks tasks");
    my $res = api_call('post', 'barrier', {name => $name, tasks => $tasks})->code;
    return 1 if ($res == 200);
    log::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

sub _wait_action {
    my ($name, $where) = @_;
    my $param;
    $param->{where} = $where if $where;
    my $res = api_call('post', "barrier/$name", $param)->code;
    return 1 if ($res == 200);

    log::mydie "barrier_wait '$name': barrier owner already finished" if $res == 410;

    if ($res != 409) {
        log::fctwarn("Unknown return code $res for lock api");
        return 0;
    }
}

# Reason to include this is to be able to unit test _wait_action without blocking
sub barrier_try_wait {
    my ($name, $where) = @_;
    log::mydie('missing barrier name') unless $name;
    log::diag("barrier try wait '$name'");
    return _wait_action($name, $where);
}

sub barrier_wait {
    my ($name, $where) = @_;
    log::mydie('missing barrier name') unless $name;
    log::diag("barrier wait '$name'");
    while (1) {
        my $res = _wait_action($name, $where);
        return 1 if $res;

        log::diag("barrier '$name' not released, sleeping 5s");
        sleep(5);
    }
}

sub barrier_destroy {
    my ($name, $where) = @_;
    log::mydie('missing barrier name') unless $name;
    log::diag("barrier destroy '$name'");
    my $param;
    $param->{where} = $where if $where;
    my $res = api_call('delete', "barrier/$name", $param)->code;
    return 1 if ($res == 200);
    log::fctwarn("Unknown return code $res for lock api");
}

1;
