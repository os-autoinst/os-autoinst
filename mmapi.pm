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

use base qw/Exporter/;
our @EXPORT = qw/get_children_by_state get_children get_parents get_job_info wait_for_children wait_for_children_to_start api_call/;

require bmwqemu;

use Mojo::UserAgent;
use Mojo::URL;
use JSON qw/decode_json/;

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

sub get_children_by_state {
    my ($state) = @_;
    my $res = api_call('get', 'mm/children/' . $state);
    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

sub get_children {
    my $res = api_call('get', 'mm/children');

    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

sub get_parents {
    my $res = api_call('get', 'mm/parents');

    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

sub get_job_info {
    my ($target_id) = @_;
    my $res = api_call('get', "jobs/$target_id");

    if ($res->code == 200) {
        return $res->json('/job');
    }
    return;
}

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
