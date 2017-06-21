#!/usr/bin/perl

# Copyright (C) 2017 SUSE LLC
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

use 5.018;
use warnings;
use strict;
use Test::More;
use Mojo::UserAgent;
use POSIX;

BEGIN {
    unshift @INC, '..';
}

use backend::component::proxy;

my $ip   = "127.0.0.1";
my $port = "9991";
my $ua   = Mojo::UserAgent->new;

sub _request {
    my ($host, $path, $method) = @_;
    $method //= "get";
    return $ua->$method('http://' . $ip . ':' . $port . $path => {Host => $host})->result;
}

sub _start_proxy {
    my ($policy, $redirect_table) = @_;

    $redirect_table //= {};

    my $proxy = backend::component::proxy->new(
        listening_address => $ip,
        listening_port    => $port,
        policy            => $policy,
        redirect_table    => $redirect_table,
        verbose           => 0,
        kill_sleeptime    => 1
    );

    $proxy->prepare()->start();

    while (1) {
        last
          if $ua->get('http://'
              . ($bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_ADDRESS} || $ip) . ':'
              . ($bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} || $port))->connection;
    }
    *bmwqemu::vars = {};
    return $proxy;
}

subtest 'proxy forward' => sub {
    my $proxy = _start_proxy("FORWARD");

    # Test FORWARD policy functionality (just acting as a normal proxy)
    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP Request was correctly forwarded";

    $res = _request('openqa.opensuse.org', '/');
    ok $res->is_success;
    like $res->body, qr/openQA is licensed/, "HTTP Request was correctly forwarded";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok $res->is_success;
    like $res->body, qr/openQA web-frontend, scheduler and tools\./, "HTTP Request was correctly forwarded";

    $res = _request('openqa.opensuse.org', '/', "head");
    ok $res->is_success;

    $proxy->stop();
};

subtest 'proxy drop' => sub {
    my $proxy = _start_proxy("DROP");

    # All answers should be 404.
    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    $res = _request('openqa.opensuse.org', '/');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    $proxy->stop();
};

subtest 'proxy redirect' => sub {
    my $proxy = _start_proxy("REDIRECT", {'github.com' => ['download.opensuse.org']});

    # Test redirect functionality
    my $res = _request('github.com', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP request correctly redirected";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok !$res->is_success;
    is $res->code, "404", "Redirect is correct, leads to a 404";

    $proxy->stop();
};

subtest 'proxy urlrewrite' => sub {
    $port++;
    my $proxy = _start_proxy(
        "URLREWRITE",
        {
            'download.opensuse.org' => [
                'github.com',          "/tumbleweed/repo/oss/README",
                "FORWARD",             "/os-autoinst/os-autoinst\$",
                "/os-autoinst/openQA", "/os-autoinst/os-autoinst-distri-opensuse",
                "/os-autoinst/os-autoinst-needles-opensuse",
              ]

        });

    # Test if the specified domain in rules get forwarded correctly without url rewrites.
    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP Request with rewrite url";

    # Test url rewrites
    $res = _request('download.opensuse.org', '/os-autoinst/os-autoinst');
    ok $res->is_success;
    like $res->body, qr/openQA web-frontend, scheduler and tools/, "HTTP Request with rewrite url";

    $res = _request('download.opensuse.org', '/os-autoinst/os-autoinst-distri-opensuse');
    ok $res->is_success;
    like $res->body, qr/os-autoinst needles for openSUSE/, "HTTP Request with rewrite url";

    $proxy->stop();

    my $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        local *STDOUT = $handle;

        my $proxy = backend::component::proxy->new(
            listening_address => $ip,
            listening_port    => $port,
            policy            => "URLREWRITE",
            redirect_table    => {
                'download.opensuse.org' => ['github.com', "/tumbleweed/repo/oss/README", "FORWARD", "FOOBAR"]
            },
            verbose        => 1,
            kill_sleeptime => 1
        );
        $proxy->start();
        $proxy->stop();
    }

    like $buffer, qr/Odd number of rewrite rules given.*?Expecting even/;
};

subtest 'proxy options' => sub {
    use bmwqemu;
    use backend::component::proxy;

    {
        my $c = backend::component::proxy->new();

        can_ok($c, qw(inactivity_timeout max_redirects connect_timeout request_timeout));
        undef $c;
    }

    $bmwqemu::vars{VNC} = 50;
    my $proxy = _start_proxy(
        "URLREWRITE",
        {
            'download.opensuse.org' => [
                'github.com',          "/tumbleweed/repo/oss/README",
                "FORWARD",             "/os-autoinst/os-autoinst\$",
                "/os-autoinst/openQA", "/os-autoinst/os-autoinst-distri-opensuse",
                "/os-autoinst/os-autoinst-needles-opensuse",
              ]

        });
    $proxy->stop()->verbose(1)->prepare()->start();

    is $proxy->listening_port, "10042";
    is $proxy->is_running,     "1";
    is $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT}, "10042";
    $proxy->verbose(0)->stop();

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} = 10999;
    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY}      = "DROP";
    $proxy->prepare()->start();
    is $proxy->listening_port, "10999";
    is $proxy->is_running,     "1";
    is $proxy->policy,         "DROP";
    $proxy->stop();

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_ENTRY}  = "download.opensuse.org:test.com:/:/1";
    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} = "URLREWRITE";
    $proxy->prepare()->start();
    is $proxy->listening_port,        "10999";
    is $proxy->is_running,            "1";
    is $proxy->policy,                "URLREWRITE";
    is_deeply $proxy->redirect_table, {
        'download.opensuse.org' => ['test.com', "/", "/1"]

    };
    $proxy->stop();

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_ENTRY}  = "download.opensuse.org:test.com:/:/1";
    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} = "URLREWRITE";
    $proxy->prepare()->start();
    is $proxy->listening_port, "10999";
    is $proxy->is_running,     "1";
    is $proxy->policy,         "URLREWRITE";
    is_deeply $proxy->redirect_table, {'download.opensuse.org' => ['test.com', "/", "/1"]};
    $proxy->stop();
    is $proxy->is_running, "0";

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_ENTRY} = "blah.org:test.com:/:/1";
    $proxy->prepare()->start();
    is $proxy->listening_port, "10999";
    is $proxy->is_running,     "1";
    is $proxy->policy,         "URLREWRITE";
    is_deeply $proxy->redirect_table, {'blah.org' => ['test.com', "/", "/1"]};
    $proxy->stop();

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_ADDRESS} = "0.0.0.0";
    $proxy->prepare();
    is $proxy->listening_address, $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_ADDRESS}, "Correctly set listening address from vars";

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_TYPE} = "Daemon";
    $proxy->prepare();
    is $proxy->server_type, $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_TYPE}, "Correctly set server type from vars";

    # Expected failures.
    eval {
        my $proxy = backend::component::proxy->new(
            listening_address => $ip,
            listening_port    => $port,
            policy            => "FOO",
            verbose           => 0
        );
        $proxy->start();
        $proxy->stop();
    };
    ok $@;
    like $@, qr/Invalid policy/;

    eval {
        my $proxy = backend::component::proxy->new(
            listening_address => $ip,
            listening_port    => $port,
            server_type       => "FOO",
            verbose           => 0
        );
        $proxy->start();
        $proxy->stop();
    };
    ok $@;
    like $@, qr/Proxy server_type can be only of type/, "server type can be 'Prefork' or 'Daemon'";

};

done_testing;
