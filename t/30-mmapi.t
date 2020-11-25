#!/usr/bin/perl
#
# Copyright (c) 2020 SUSE LLC
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

use OpenQA::Test::TimeLimit '5';
use Test::Output;
use Test::MockModule;
use Mojolicious;
use mmapi;

# setup a fake server
my $mock_srv = Mojolicious->new;
$mock_srv->log->unsubscribe('message')->on(
    message => sub {
        my ($log, $level, @lines) = @_;
        note "[$level] " . join "\n", @lines, '';
    });
my $routes   = $mock_srv->routes;
my $fake_api = $routes->any('/api/v1');
$fake_api->get('/mm/children' => sub {
        my ($self) = @_;
        return $self->render(status => 403, text => 'not authorized') if ($self->tx->req->headers->header('X-API-JobToken') || '') ne 'fake-jobtoken';
        return $self->render(json   => {jobs => [1, 2, 3]});
});
$fake_api->get('/mm/children/#state' => sub {
        my ($self) = @_;
        return $self->render(status => 404, json => {jobs => []}) if $self->stash('state') ne 'some-state';
        return $self->render(json => {jobs => [1]});
});
$fake_api->get('/mm/parents' => sub { shift->render(json => {jobs => [4, 5, 6]}) });
$fake_api->get('/jobs/100'   => sub { shift->render(json => {job  => {the => 'job info'}}) });
$fake_api->get('/workers' => sub {
        shift->render(json => {workers => [{
                        jobid      => '100',
                        host       => 'fake-host',
                        instance   => 42,
                        properties => {JOBTOKEN => 'fake-jobtoken'},
        }]});
});
$routes->get('/autoinst/vars' => sub { shift->render(json => {vars => {foo => 'bar'}}) });

# make mmapi connect to the fake server
$bmwqemu::vars{OPENQA_URL} = '/not/relevant';
$bmwqemu::vars{JOBTOKEN}   = 'fake-jobtoken';
mmapi::set_app($mock_srv);

# test mmapi's `get_` functions
is_deeply(mmapi::get_children(),                      [1, 2, 3], 'query children');
is_deeply(mmapi::get_children_by_state('some-state'), [1],       'query children by state');
combined_like {
    is_deeply(mmapi::get_children_by_state('another-state'), undef, 'query children by state (no results)');
} qr|get_children_by_state: 404 response.*URL was.*/mm/children/another-state|, 'query children by state error logged';
is_deeply(mmapi::get_parents(),     [4, 5, 6],           'query parents');
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

done_testing;
