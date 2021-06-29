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

## Multi-Machine API
package mmapi;

use Mojo::Base -strict, -signatures;

use base 'Exporter';
our @EXPORT = qw(get_children_by_state get_children get_parents
  get_job_info get_job_autoinst_url get_job_autoinst_vars
  wait_for_children wait_for_children_to_start api_call
  api_call_2 handle_api_error
);

require bmwqemu;

use Mojo::UserAgent;
use Mojo::URL;

use constant RETRY_COUNT   => $ENV{OS_AUTOINST_MMAPI_RETRY_COUNT}   // 3;
use constant POLL_INTERVAL => $ENV{OS_AUTOINST_MMAPI_POLL_INTERVAL} // 1;

# private ua
my $ua;
my $url;
my $app;

# define HTTP return codes which are not treated as errors by api_call/api_call_2/handle_api_error
my $CODES_EXPECTED_BY_DEFAULT = {200 => 1, 409 => 1};

# define HTTP return codes which are not treated as errors by functions of mmapi itself
my $CODES_EXPECTED_BY_MMAPI = {200 => 1};

sub _init {
    # init $ua and $url
    my $host   = $bmwqemu::vars{OPENQA_URL};
    my $secret = $bmwqemu::vars{JOBTOKEN};
    return unless $host && $secret;

    if ($host !~ '/') {
        $url = Mojo::URL->new();
        $url->host($host);
        $url->scheme('http');
    }
    else {
        $url = Mojo::URL->new($host);
    }

    # Relative paths are appended to the existing one
    $url->path('/api/v1/');

    $ua = Mojo::UserAgent->new;

    # add JOBTOKEN header secret
    $ua->on(
        start => sub {
            my ($ua, $tx) = @_;
            $tx->req->headers->add('X-API-JobToken' => $secret);
        });
}

sub set_app ($app_arg) {
    _init;
    $ua->server->app($app = $app_arg);
}

=head2 api_call_2

Queries openQA's multi-machine API and returns the resulting Mojo::Transaction::HTTP object.

=cut

sub api_call_2 ($method, $action, $params, $expected_codes) {
    _init                                       unless $ua;
    bmwqemu::mydie('Missing mandatory options') unless $method && $action && $ua;

    my $ua_url = $url->clone;
    $ua_url->path($action);
    $ua_url->query($params) if $params;

    my $tries = RETRY_COUNT;
    my ($tx, $res);
    while ($tries--) {
        $tx  = $ua->$method($ua_url);
        $res = $tx->res;
        last if $res->code && ($expected_codes // $CODES_EXPECTED_BY_DEFAULT)->{$res->code};
    }
    return $tx;
}

=head2 api_call

Queries openQA's multi-machine API and returns the result as Mojo::Message::Response object.

=cut

sub api_call { api_call_2(@_)->res }

=head2 handle_api_error

Returns a truthy value if the specified Mojo::Transaction::HTTP object has an error.
Logs the errors if a log context is specified.

=cut

sub handle_api_error ($tx, $log_ctx, $expected_codes) {
    my $err = $tx->error;
    return 0 unless $err;

    my $url  = $tx->req->url;
    my $code = $err->{code};
    return 0                            if $code && ($expected_codes // $CODES_EXPECTED_BY_DEFAULT)->{$code};
    $err->{message} .= "; URL was $url" if $url;
    bmwqemu::diag($code
        ? "$log_ctx: $code response: $err->{message}"
        : "$log_ctx: Connection error: $err->{message}") if $log_ctx;
    return 1;
}

=head2 get_children_by_state

    my $children = get_children_by_state('done');
    print $children->[0]

Returns an array ref conaining ids of children in given state.

=cut

sub get_children_by_state ($state) {
    my $tx = api_call_2(get => "mm/children/$state", undef, $CODES_EXPECTED_BY_MMAPI);
    return undef if handle_api_error($tx, 'get_children_by_state', $CODES_EXPECTED_BY_MMAPI);
    return $tx->res->json('/jobs');
}

=head2 get_children

    my $childern = get_children();
    print keys %$children;

Returns a hash ref conaining { id => state } pair for each child job.

=cut

sub get_children ($tx) {
    return undef if handle_api_error($tx, 'get_children', $CODES_EXPECTED_BY_MMAPI);
    return $tx->res->json('/jobs');
}

=head2 get_parents

    my $parents = get_parents
    print $parents->[0]

Returns an array ref conaining ids of parent jobs.

=cut

sub get_parents ($tx) {
    return undef if handle_api_error($tx, 'get_parents', $CODES_EXPECTED_BY_MMAPI);
    return $tx->res->json('/jobs');
}

=head2 get_job_info

    my $info = get_job_info($target_id);
    print $info->{settings}->{DESKTOP}

Returns a hash containin job information provided by openQA server.

=cut

sub get_job_info ($target_id) {
    my $tx = api_call_2(get => "jobs/$target_id", undef, $CODES_EXPECTED_BY_MMAPI);
    return undef if handle_api_error($tx, 'get_job_info', $CODES_EXPECTED_BY_MMAPI);
    return $tx->res->json('/job');
}

=head2 get_job_autoinst_url

    my $url = get_job_autoinst_url($target_id);

Returns url of os-autoinst webserver for job $target_id or C<undef> on failure.

=cut

sub get_job_autoinst_url ($target_id) {
    my $tx = api_call_2(get => 'workers', undef, $CODES_EXPECTED_BY_MMAPI);
    return undef if handle_api_error($tx, 'get_job_autoinst_url', $CODES_EXPECTED_BY_MMAPI);

    my $workers = $tx->res->json('/workers') // [];
    for my $worker (@$workers) {
        if ($worker->{jobid} && $target_id == $worker->{jobid} && $worker->{host} && $worker->{instance} && $worker->{properties}{JOBTOKEN}) {
            my $hostname   = $worker->{host};
            my $token      = $worker->{properties}{JOBTOKEN};
            my $workerport = $worker->{instance} * 10 + 20002 + 1;    # the same as in openqa/script/worker
            my $url        = "http://$hostname:$workerport/$token";
            return $url;
        }
    }
    bmwqemu::diag("get_job_autoinst_url: No worker info for job $target_id available.");
    return undef;
}

=head2 get_job_autoinst_vars

    my $vars = get_job_autoinst_vars($target_id);
    print $vars->{WORKER_ID};

Returns hash reference containing variables of job $target_id or C<undef> on failure. The variables
are taken from vars.json file of the corresponding worker.

=cut

sub get_job_autoinst_vars ($target_id) {
    my $url = get_job_autoinst_url($target_id);
    return undef unless $url;

    # query the os-autoinst webserver of the job specifed by $target_id
    $url .= '/vars';

    my $ua = Mojo::UserAgent->new;
    $ua->server->app($app) if $app;
    my $tx = $ua->get($url);
    return undef if handle_api_error($tx, 'get_job_autoinst_vars', $CODES_EXPECTED_BY_MMAPI);
    return $tx->res->json('/vars');
}

=head2 wait_for_children

    wait_for_children();

Wait while any running or scheduled children exist.

=cut

sub wait_for_children {
    while (1) {
        my $children = get_children() // {};
        my $n        = 0;
        for my $state (values %$children) {
            next if $state eq 'done' or $state eq 'cancelled';
            $n++;
        }

        bmwqemu::diag("Waiting for $n jobs to finish");
        last unless $n;
        sleep POLL_INTERVAL;
    }
}

=head2 wait_for_children_to_start

    wait_for_children_to_start();

Wait while any scheduled children exist.

=cut
sub wait_for_children_to_start {
    while (1) {
        my $children = get_children() // {};
        my $n        = 0;
        for my $state (values %$children) {
            next if $state eq 'done' or $state eq 'cancelled' or $state eq 'running';
            $n++;
        }

        bmwqemu::diag("Waiting for $n jobs to start");
        last unless $n;
        sleep POLL_INTERVAL;
    }
}

1;
