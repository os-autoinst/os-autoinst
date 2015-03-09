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
our @EXPORT = qw/get_children_by_state api_call/;

require bmwqemu;

use Mojo::UserAgent;
use Mojo::URL;
use JSON qw/decode_json/;

# private ua
my $ua;
my $url;

sub _init {
    # init $ua and $url
    my $host = $bmwqemu::vars{'OPENQA_URL'};
    my $secret = $bmwqemu::vars{'JOBTOKEN'};
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
        }
    );
}

sub api_call {
    my ($method, $action) = @_;
    _init unless $ua;
    bmwqemu::mydie('Missing mandatory options') unless $method && $action && $ua;

    bmwqemu::fctinfo("Trying mm action $action");
    my $ua_url = $url->clone;
    $ua_url->path($action);
    return $ua->$method($ua_url)->res;
}

sub get_children_by_state {
    my ($state) = @_;
    my $res = api_call('get', 'mm/children/' . $state);
    if ($res->code == 200) {
        return $res->json('/jobs');
    }
    return;
}

1;
