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
use Devel::Cover;    # needed to collect coverage on spawned processes as well
use Mojo::File qw(path tempfile tempdir);
use File::Which;
use Data::Dumper;
use POSIX '_exit';

our $mojoport = Mojo::IOLoop::Server->generate_port;
my $base_url     = "http://localhost:$mojoport";
my $toplevel_dir = path(__FILE__)->dirname->realpath;
my $data_dir     = "$toplevel_dir/data/tests";

sub wait_for_server {
    my ($ua) = @_;
    for (my $counter = 0; $counter < 20; $counter++) {
        return if (($ua->get("$base_url/NEVEREVER")->res->code // 0) == 404);
        sleep .1;
    }
    return 1;
}

$bmwqemu::vars{JOBTOKEN} = 'Hallo';
$bmwqemu::vars{CASEDIR}  = $data_dir;

# now this is a game of luck
my ($cserver, $cfd) = commands::start_server($mojoport);

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

    subtest 'broadcast messages to websocket clients' => sub {
        my $t2 = Test::Mojo->new;
        $t2->post_ok("$base_url/Hallo/broadcast", json => {
                stopping_test_execution => 'foo',
        });
        $t2->status_is(200);
        $t->message_ok('message from broadcast route received');
        $t->json_message_is('/stopping_test_execution' => 'foo');
    };

    $t->finish_ok();
};

subtest 'data api' => sub {
    my $job = 'Hallo';

    # we need `cpio` for these tests
    ok(-x which 'cpio', 'cpio exists');

    $t->get_ok("$base_url/$job/data");
    $t->status_is(200);
    $t->content_type_is("application/x-cpio");
    my $tmpdir  = tempdir;
    my $outfile = path($tmpdir . '/data_full.cpio');
    $outfile->spurt($t->tx->res->body);
    ok(system("cd $tmpdir && cpio -id < data_full.cpio >/dev/null 2>&1") == 0, "Extract cpio archive");
    ok(-d $tmpdir . '/data/mod1',                                              'Recursive directory download 1.1');
    ok(-d $tmpdir . '/data/mod1/sub',                                          'Recursive directory download 1.2');
    ok(-f $tmpdir . '/data/mod1/test1.txt',                                    'Recursive directory download 1.3');
    ok(-f $tmpdir . '/data/mod1/sub/test2.txt',                                'Recursive directory download 1.4');
    ok(-f $tmpdir . '/data/autoinst.xml',                                      'Recursive directory download 1.5');
    ok(path($tmpdir . '/data/mod1/sub/test2.txt')->slurp eq 'TEST_FILE_2',     'Recursive directory download 1.6');
    ok(path($tmpdir . '/data/mod1/test1.txt')->slurp eq 'TEST_FILE_1',         'Recursive directory download 1.7');

    $t->get_ok("$base_url/$job/data/mod1");
    $t->status_is(200);
    $t->content_type_is("application/x-cpio");
    $tmpdir  = tempdir;
    $outfile = path($tmpdir . '/data_full.cpio');
    $outfile->spurt($t->tx->res->body);
    ok(system("cd $tmpdir && cpio -id < data_full.cpio >/dev/null 2>&1") == 0, "Extract cpio archive");
    ok(-d $tmpdir . '/data/sub',                                               'Recursive directory download 2.1');
    ok(-f $tmpdir . '/data/test1.txt',                                         'Recursive directory download 2.2');
    ok(-f $tmpdir . '/data/sub/test2.txt',                                     'Recursive directory download 2.3');
    ok(path($tmpdir . '/data/sub/test2.txt')->slurp eq 'TEST_FILE_2',          'Recursive directory download 2.4');
    ok(path($tmpdir . '/data/test1.txt')->slurp eq 'TEST_FILE_1',              'Recursive directory download 2.5');

    $t->get_ok("$base_url/$job/data/mod1/sub");
    $t->status_is(200);
    $t->content_type_is("application/x-cpio");

    $t->get_ok("$base_url/$job/data/mod1/test1.txt");
    $t->status_is(200);
    $t->content_type_like(qr/text/);
    $t->content_is("TEST_FILE_1");

    $t->get_ok("$base_url/$job/data/mod1/sub/test2.txt");
    $t->status_is(200);
    $t->content_type_like(qr/text/);
    $t->content_is("TEST_FILE_2");

    $t->get_ok("$base_url/$job/data/autoinst.xml");
    $t->status_is(200);
    $t->content_type_like(qr/xml/);

};

kill TERM => $spid;
waitpid($spid, 0);
eval { $cserver->stop() };

done_testing;
