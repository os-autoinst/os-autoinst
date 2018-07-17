#!/usr/bin/perl
#
# Copyright (c) 2016-2018 SUSE LLC
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


use strict;
use warnings;

use FindBin;
use File::Find;
require IPC::System::Simple;
use autodie ':all';


BEGIN {
    unshift @INC, '..';
}

use commands;
use Mojo::IOLoop::Server;
use Time::HiRes 'sleep';
use Test::More;
use Test::Warnings;
use Test::Mojo;
use Devel::Cover;
use POSIX '_exit';

our $mojoport = Mojo::IOLoop::Server->generate_port;
my $base_url = "http://localhost:$mojoport";

sub wait_for_server {
    my ($ua) = @_;
    for (my $counter = 0; $counter < 20; $counter++) {
        return if (($ua->get("$base_url/NEVEREVER")->res->code // 0) == 404);
        sleep .1;
    }
    return 1;
}

$bmwqemu::vars{JOBTOKEN} = 'Hallo';

# now this is a game of luck
my ($cpid, $cfd) = commands::start_server($mojoport);

my $spid = fork();
if ($spid == 0) {
    # we need to fake isotovideo here
    while (1) {
        my $json = myjsonrpc::read_json($cfd);
        my $cmd  = delete $json->{cmd};
        if ($cmd eq 'version') {
            myjsonrpc::send_json($cfd, {VERSION => 'COOL'});
        }
        elsif ($cmd) {
            myjsonrpc::send_json($cfd, {response_for => $cmd, %$json});
        }
    }
    _exit(0);
}

# create test user agent and wait for server
my $t = Test::Mojo->new;
if (wait_for_server($t->ua)) {
    exit(0);
}

subtest 'failure if jobtoken wrong' => sub {
    $t->get_ok("$base_url/NEVEREVER")->status_is(404);
    $t->get_ok("$base_url/isotovideo/version")->status_is(404);
};

subtest 'query isotovideo version' => sub {
    $t->get_ok("$base_url/Hallo/isotovideo/version");
    $t->status_is(200);
    # we only care whether 'json_cmd_token' exists
    $t->json_has('/json_cmd_token');
    delete $t->tx->res->json->{json_cmd_token};
    $t->json_is({VERSION => 'COOL'});
};

subtest 'web socket route' => sub {
    $t->websocket_ok("$base_url/Hallo/ws");
    $t->send_ok(
        {
            json => {
                cmd  => 'set_pause_at_test',
                name => 'installation-welcome',
              }
        },
        'command passed to isotovideo'
    );
    $t->message_ok('result from isotovideo is passed back');
    $t->json_message_is('/response_for' => 'set_pause_at_test');
    $t->json_message_is('/name'         => 'installation-welcome');
    $t->finish_ok();
};

done_testing;

END {
    return unless $spid;
    kill TERM => $spid;
    waitpid($spid, 0);
    kill TERM => $cpid;
    waitpid($cpid, 0);
    wait_for_server($t->ua);
}
