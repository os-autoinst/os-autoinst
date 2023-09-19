#!/usr/bin/perl
#
# Copyright 2016-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Mojo::Base -strict, -signatures;
use File::Find;
require IPC::System::Simple;
use autodie ':all';

use commands;
use OpenQA::Commands;
use Mojo::IOLoop::Server;
use Time::HiRes 'sleep';
use Test::Warnings ':report_warnings';
use Test::Output;
use Test::Mojo;
use Test::MockModule;
use Test::MockObject;
use Mojo::File qw(path tempfile tempdir);
use File::Which;
use Data::Dumper;
use POSIX '_exit';

our $mojoport = Mojo::IOLoop::Server->generate_port;
my $base_url = "http://localhost:$mojoport";
my $job = 'Hallo';
my $toplevel_dir = path(__FILE__)->dirname->realpath;
my $data_dir = $toplevel_dir->child('data');

sub wait_for_server ($ua) {
    for (my $counter = 0; $counter < 20; $counter++) {
        sleep .1;
        return if (($ua->get("$base_url/NEVEREVER")->res->code // 0) == 404);
    }
}

$bmwqemu::vars{JOBTOKEN} = $job;
$bmwqemu::vars{CASEDIR} = $data_dir->child('tests');
$bmwqemu::vars{ASSETDIR} = $data_dir->child('assets');
$bmwqemu::vars{UPLOAD_MAX_MESSAGE_SIZE_GB} = 0.0048828125;    # 5 MiB, less than our Tiny Core ISO

my @tempfiles;
# now this is a game of luck
my $pool_directory = $data_dir->child('pool');
ok(chdir $pool_directory, "change command server working directory to $pool_directory");
my ($cserver, $cfd);
ok(chdir $data_dir->child('pool'), 'change command server working directory');
combined_like { ($cserver, $cfd) = commands::start_server($mojoport); } qr//, 'command server started';

my $spid = fork();
if ($spid == 0) {
    # we need to fake isotovideo here
    while (1) {    # uncoverable statement
        my $json = myjsonrpc::read_json($cfd);    # uncoverable statement
        next unless my $cmd = delete $json->{cmd};    # uncoverable statement
        myjsonrpc::send_json($cfd, $cmd eq 'version' ? {VERSION => 'COOL'} : {response_for => $cmd, %$json});    # uncoverable statement
    }
    _exit(0);    # uncoverable statement
}

# create test user agent and wait for server
my $t = Test::Mojo->new;
wait_for_server($t->ua);

ok(chdir $toplevel_dir, "change overall test working directory back to $toplevel_dir");

subtest 'failure if jobtoken wrong' => sub {
    $t->get_ok("$base_url/NEVEREVER")->status_is(404);
    $t->get_ok("$base_url/isotovideo/version")->status_is(404);
};

subtest 'query isotovideo version' => sub {
    $t->get_ok("$base_url/$job/isotovideo/version");
    $t->status_is(200);
    # we only care whether 'json_cmd_token' exists
    $t->json_has('/json_cmd_token');
    delete $t->tx->res->json->{json_cmd_token};
    $t->json_is({VERSION => 'COOL'});
};

subtest 'web socket route' => sub {
    $t->websocket_ok("$base_url/$job/ws");
    $t->send_ok(
        {
            json => {
                cmd => 'set_pause_at_test',
                name => 'installation-welcome',
            }
        },
        'command passed to isotovideo'
    );
    $t->message_ok('result from isotovideo is passed back');
    $t->json_message_is('/response_for' => 'set_pause_at_test');
    $t->json_message_is('/name' => 'installation-welcome');

    subtest 'broadcast messages to websocket clients' => sub {
        my $t2 = Test::Mojo->new;
        $t2->post_ok("$base_url/$job/broadcast", json => {
                stopping_test_execution => 'foo',
        });
        $t2->status_is(200);
        $t->message_ok('message from broadcast route received');
        $t->json_message_is('/stopping_test_execution' => 'foo');
    };

    $t->finish_ok();
};

subtest 'data api (directory download)' => sub {
    die "'cpio' is needed for these tests" unless which 'cpio';

    $t->get_ok("$base_url/$job/data")->status_is(200)->content_type_is('application/x-cpio');
    my $tmpdir = tempdir;
    my $outfile = path($tmpdir . '/data_full.cpio');
    $outfile->spew($t->tx->res->body);
    ok(system("cd $tmpdir && cpio -id < data_full.cpio >/dev/null 2>&1") == 0, 'Extract cpio archive');
    ok(-d $tmpdir . '/data/mod1', 'Recursive directory download 1.1');
    ok(-d $tmpdir . '/data/mod1/sub', 'Recursive directory download 1.2');
    ok(-f $tmpdir . '/data/mod1/test1.txt', 'Recursive directory download 1.3');
    ok(-f $tmpdir . '/data/mod1/sub/test2.txt', 'Recursive directory download 1.4');
    ok(-f $tmpdir . '/data/autoinst.xml', 'Recursive directory download 1.5');
    ok(path($tmpdir . '/data/mod1/sub/test2.txt')->slurp eq 'TEST_FILE_2', 'Recursive directory download 1.6');
    ok(path($tmpdir . '/data/mod1/test1.txt')->slurp eq 'TEST_FILE_1', 'Recursive directory download 1.7');

    $t->get_ok("$base_url/$job/data/mod1");
    $t->status_is(200);
    $t->content_type_is("application/x-cpio");
    $tmpdir = tempdir;
    $outfile = path($tmpdir . '/data_full.cpio');
    $outfile->spew($t->tx->res->body);
    ok(system("cd $tmpdir && cpio -id < data_full.cpio >/dev/null 2>&1") == 0, 'Extract cpio archive');
    ok(-d $tmpdir . '/data/sub', 'Recursive directory download 2.1');
    ok(-f $tmpdir . '/data/test1.txt', 'Recursive directory download 2.2');
    ok(-f $tmpdir . '/data/sub/test2.txt', 'Recursive directory download 2.3');
    ok(path($tmpdir . '/data/sub/test2.txt')->slurp eq 'TEST_FILE_2', 'Recursive directory download 2.4');
    ok(path($tmpdir . '/data/test1.txt')->slurp eq 'TEST_FILE_1', 'Recursive directory download 2.5');

    $t->get_ok("$base_url/$job/data/mod1/sub")->status_is(200)->content_type_is('application/x-cpio');
};

subtest 'data api (single file download)' => sub {
    $t->get_ok("$base_url/$job/data/mod1/not/present")->status_is(404);

    $t->get_ok("$base_url/$job/data/mod1/test1.txt")->status_is(200);
    $t->content_type_like(qr/text/)->content_is('TEST_FILE_1');

    $t->get_ok("$base_url/$job/data/mod1/sub/test2.txt")->status_is(200);
    $t->content_type_like(qr/text/)->content_is('TEST_FILE_2');

    $t->get_ok("$base_url/$job/data/autoinst.xml")->status_is(200)->content_type_like(qr/xml/);
};

subtest 'asset api' => sub {
    subtest 'asset served from working directory (pool directory)' => sub {
        $t->get_ok("$base_url/$job/assets/other/01377524-autoinst.xml")->status_is(200);
        $t->content_type_is('application/xml')->content_like(qr/fake profile within pool dir/);
    };
    subtest 'asset served from ASSETDIR' => sub {
        $t->get_ok("$base_url/$job/assets/other/01377523-autoinst.xml")->status_is(200);
        $t->content_type_is('application/xml')->content_like(qr/fake profile within assets dir/);
    };
    subtest 'asset not present' => sub {
        $t->get_ok("$base_url/$job/assets/other/01377522-autoinst.xml")->status_is(404);
    };
    subtest 'file from parent directory not served' => sub {
        $t->get_ok("$base_url/$job/assets/../accept-ssh-host-key.png")->status_is(404);
        $t->get_ok("$base_url/$job/assets/other/../../accept-ssh-host-key.png")->status_is(404);
    };
};

subtest 'upload api' => sub {
    subtest 'file content missing' => sub {
        $t->post_ok("$base_url/$job/upload_asset/foo")->status_is(400)->content_is('Upload file content missing');
    };
    subtest 'target directory cannot be created' => sub {
        push @tempfiles, $pool_directory->child('a-file');
        $pool_directory->child('a-file')->touch;
        $t->post_ok("$base_url/$job/upload_asset/foo", form => {upload => {content => 'foo'}, target => 'a-file'});
        $t->status_is(500)->content_like(qr/Unable to create directory for upload.*File exists/);
    };
    subtest 'file exceeds limit' => sub {
        $t->post_ok("$base_url/$job/upload_asset/foo", form => {upload => {file => "$Bin/data/Core-7.2.iso"}});
        $t->status_is(400)->content_is('Maximum message size exceeded');
    };
    subtest 'successful upload' => sub {
        $t->post_ok("$base_url/$job/upload_asset/private-asset", form => {upload => {content => 'private-content'}});
        $t->status_is(200)->content_is("OK: private-asset\n");
        push @tempfiles, $pool_directory->child('assets_private/private-asset');
        is $pool_directory->child('assets_private/private-asset')->slurp, 'private-content', 'private asset created';

        $t->post_ok("$base_url/$job/upload_asset/public-asset", form => {upload => {content => 'public-content'}, target => 'assets_public'});
        $t->status_is(200)->content_is("OK: public-asset\n");
        push @tempfiles, $pool_directory->child('assets_public/public-asset');
        is $pool_directory->child('assets_public/public-asset')->slurp, 'public-content', 'public asset created';
    };
};

kill TERM => $spid;
waitpid($spid, 0);
combined_like { eval { $cserver->stop() } } qr/commands process exited/, 'commands server stopped';

subtest 'decode failure' => sub {
    my $jsonrpc = Test::MockModule->new('myjsonrpc');
    # uncoverable statement count:2
    # uncoverable statement count:3
    $jsonrpc->redefine(send_json => sub ($iso, $data) { 1 });

    my $oc = Test::MockModule->new('OpenQA::Commands');
    $oc->redefine(decode_json => sub ($json) { die 23 });

    my $mock_log = Test::MockObject->new({});
    my (@debug, @warn);
    $mock_log->mock(debug => sub ($self, $msg) { push @debug, $msg });
    $mock_log->mock(warn => sub ($self, $msg) { push @warn, $msg });

    my $mock_app = Test::MockObject->new({});
    $mock_app->mock(log => sub ($self) { $mock_log });
    $mock_app->mock(defaults => sub ($self, $type) { 1 });

    my $mock = Test::MockObject->new({});
    $mock->mock(app => sub ($self) { $mock_app });

    my $json = '{"foo":"bar"}';
    my $ret = OpenQA::Commands::pass_message_from_ws_client_to_isotovideo($mock, 23, $json);
    is $debug[0], "cmdsrv: passing command from client to isotovideo 1: $json",
      'debug output like expected';
    is $warn[0], 'cmdsrv: failed to decode message', 'warn output like expected';
    is $ret, undef, 'pass_message_from_ws_client_to_isotovideo returns undef';
};

done_testing;

END {
    unlink @tempfiles;
}
