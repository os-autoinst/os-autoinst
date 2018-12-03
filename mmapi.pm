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

## Multi-Machine API
package mmapi;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(get_children_by_state get_children get_parents
  get_job_info get_job_autoinst_url get_job_autoinst_vars
  wait_for_children wait_for_children_to_start api_call
);

require bmwqemu;

use Mojo::UserAgent;
use Mojo::URL;

# private ua
my $ua;
my $url;

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

sub api_call {
    my ($method, $action, $params, $expected_codes) = @_;
    _init unless $ua;
    bmwqemu::mydie('Missing mandatory options') unless $method && $action && $ua;

    my $ua_url = $url->clone;
    $ua_url->path($action);
    $ua_url->query($params) if $params;

    my $tries = 3;
    $expected_codes //= {
        200 => 1,
        409 => 1,
    };

    my $res;
    while ($tries--) {
        $res = $ua->$method($ua_url)->res;
        last if $expected_codes->{$res->code};
    }
    return $res;
}

=head2 get_children_by_state

    my $children = get_children_by_state('done');
    print $children->[0]

Returns an array ref conaining ids of children in given state.

=cut

sub get_children_by_state {
    my ($state) = @_;
    my $res = api_call('get', 'mm/children/' . $state);
    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

=head2 get_children

    my $childern = get_children();
    print keys %$children;

Returns a hash ref conaining { id => state } pair for each child job.

=cut

sub get_children {
    my $res = api_call('get', 'mm/children');

    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

=head2 get_parents

    my $parents = get_parents
    print $parents->[0]

Returns an array ref conaining ids of parent jobs.

=cut

sub get_parents {
    my $res = api_call('get', 'mm/parents');

    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

=head2 get_job_info

    my $info = get_job_info($target_id);
    print $info->{settings}->{DESKTOP}

Returns a hash containin job information provided by openQA server.

=cut

sub get_job_info {
    my ($target_id) = @_;
    my $res = api_call('get', "jobs/$target_id");

    if ($res->code == 200) {
        return $res->json('/job');
    }
    return;
}

=head2 get_job_autoinst_url

    my $url = get_job_autoinst_url($target_id);

Returns url of os-autoinst webserver for job $target_id or C<undef> on failure.

=cut

sub get_job_autoinst_url {
    my ($target_id) = @_;
    my $res = api_call('get', "workers");

    if ($res->code == 200) {
        my $workers = $res->json('/workers');
        for my $worker (@$workers) {
            if ($worker->{jobid} && $target_id == $worker->{jobid} && $worker->{host} && $worker->{instance} && $worker->{properties}{JOBTOKEN}) {
                my $hostname   = $worker->{host};
                my $token      = $worker->{properties}{JOBTOKEN};
                my $workerport = $worker->{instance} * 10 + 20002 + 1;    # the same as in openqa/script/worker
                my $url        = "http://$hostname:$workerport/$token";
                return $url;
            }
        }
    }
    else {
        bmwqemu::diag("get_job_autoinst_url: code: " . $res->code);
    }
    return;
}

=head2 get_job_autoinst_vars

    my $vars = get_job_autoinst_vars($target_id);
    print $vars->{WORKER_ID};

Returns hash reference containing variables of job $target_id or C<undef> on failure. The variables
are taken from vars.json file of the corresponding worker.

=cut

sub get_job_autoinst_vars {
    my ($target_id) = @_;

    my $url = get_job_autoinst_url($target_id);
    return unless $url;

    # query the os-autoinst webserver of the job specifed by $target_id
    $url .= '/vars';

    my $ua  = Mojo::UserAgent->new;
    my $res = $ua->get($url)->res;
    if ($res->code == 200) {
        return $res->json('/vars');
    }
    else {
        bmwqemu::diag("get_job_autoinst_vars: code: " . $res->code);
    }
    return;
}

=head2 wait_for_children

    wait_for_children();

Wait while any running or scheduled children exist.

=cut

sub wait_for_children {
    while (1) {
        my $children = get_children();
        my $n        = 0;
        for my $state (values %$children) {
            next if $state eq 'done' or $state eq 'cancelled';
            $n++;
        }

        bmwqemu::diag("Waiting for $n jobs to finish");
        last unless $n;
        sleep 1;
    }
}

=head2 wait_for_children_to_start

    wait_for_children_to_start();

Wait while any scheduled children exist.

=cut
sub wait_for_children_to_start {
    while (1) {
        my $children = get_children();
        my $n        = 0;
        for my $state (values %$children) {
            next if $state eq 'done' or $state eq 'cancelled' or $state eq 'running';
            $n++;
        }

        bmwqemu::diag("Waiting for $n jobs to start");
        last unless $n;
        sleep 1;
    }
}

1;
