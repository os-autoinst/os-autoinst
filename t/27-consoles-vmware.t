#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings;
use Mojo::Base -signatures;
use utf8;

# disable time limit when testing against real VMWare instance
BEGIN {
    $ENV{OPENQA_TEST_TIMEOUT_DISABLE} = 1 if $ENV{OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE};
}

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib", "$Bin/../tools/lib";
use OpenQA::Test::Isolation qw(setup_isolated_workdir);
use OpenQA::Test::TimeLimit '60';

use Test::MockObject;
use Test::MockModule;
use Test::Mojo;
use Test::Output qw(combined_like);
use Mojo::Transaction::HTTP;
use Mojo::Message::Request;
use Mojo::Message::Response;
use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Scalar::Util qw(blessed);
use POSIX qw(WNOHANG);

use consoles::VMWare;

$bmwqemu::topdir = "$Bin/..";
$bmwqemu::vars{VMWARE_VNC_OVER_WS_INSECURE} = 1;

sub mk_res ($code, @text) { map { Mojo::Message::Response->new->code($code)->body($_) } @text }

subtest 'test configuration with fake URL' => sub {
    my $vmware_mock = Test::MockModule->new('consoles::VMWare');
    my (@get_vmware_wss_url_args, @dewebsockify_args);
    $vmware_mock->redefine(get_vmware_wss_url => sub ($self) { ('wss://foo', 'session') });
    $vmware_mock->redefine(_start_dewebsockify_process => sub ($self, @args) { @dewebsockify_args = @args });

    my $fake_vnc = Test::MockObject->new;
    $fake_vnc->set_always(vmware_vnc_over_ws_url => undef);
    is consoles::VMWare::setup_for_vnc_console($fake_vnc), undef, 'noop if URL not set';

    $fake_vnc->set_always(vmware_vnc_over_ws_url => 'https://root:secret%23@foo.bar');
    $fake_vnc->set_always(hostname => 'original-hostname');
    $fake_vnc->set_always(original_hostname => undef);
    $fake_vnc->set_always(port => 12345);
    $fake_vnc->set_true(qw(description));
    $fake_vnc->clear;

    my $vmware;
    combined_like { $vmware = consoles::VMWare::setup_for_vnc_console($fake_vnc) }
    qr{Establishing VNC connection over WebSockets via https://foo\.bar}, 'log message present without secrets';
    ok $vmware, 'VMWare "console" returned if URL is set' or return undef;
    $fake_vnc->called_pos_ok(4, 'original_hostname', 'hostname saved as original hostname');
    $fake_vnc->called_args_pos_is(4, 2, 'original-hostname', 'original hostname set to hostname');
    $fake_vnc->called_pos_ok(5, 'hostname', 'hostname assigned');
    $fake_vnc->called_args_pos_is(5, 2, '127.0.0.1', 'hostname set to localhost');
    $fake_vnc->called_pos_ok(6, 'description', 'description assigned');
    $fake_vnc->called_args_pos_is(6, 2, 'VNC over WebSockets server provided by VMWare', 'description set accordingly');
    is_deeply \@dewebsockify_args, [12345, 'wss://foo', 'session'], 'dewebsockify called with expected args'
      or always_explain \@dewebsockify_args;
    is $vmware->host, 'foo.bar', 'hostname set';
    is $vmware->vm_id, undef, 'no VM-ID set (as our URL did not include one)';
    is $vmware->username, 'root', 'username set';
    is $vmware->password, 'secret#', 'password set (with URL-encoded character)';

    $vmware->configure_from_url('https://not-root:123@another-host/42');
    is $vmware->protocol, 'https', 'protocol configured from URL';
    is $vmware->host, 'another-host', 'host configured from URL';
    is $vmware->vm_id, '42', 'specific VM-ID configured from URL';
};

subtest 'request WebSockets URL' => sub {
    # mock ua
    my $user_agent_mock = Test::MockModule->new('Mojo::UserAgent');
    my $http = Test::MockModule->new('Mojo::Transaction::HTTP');
    my $req_mock = Test::MockModule->new('Mojo::Message::Request');
    my @fake_res = mk_res 200, '<faultstring>some error</faultstring>';
    $user_agent_mock->redefine(start => sub ($ua, $tx) { });
    # uncoverable statement count:2
    $user_agent_mock->redefine(get => sub { Mojo::Transaction::HTTP->new });
    $http->redefine(result => sub { shift @fake_res });

    my $vmware = consoles::VMWare->new(vm_id => 42, host => 'mocked');
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare auth request failed: some error/, 'auth error handled';

    @fake_res = mk_res 200, '', '<faultstring>another error</faultstring>';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare web socket URL request failed: another error/, 'ws request error handled';

    @fake_res = mk_res 200, '', 'foo';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare did not return a web socket URL, it responsed:\nfoo/, 'no ws URL handled';

    @fake_res = mk_res 200, '', '<url>wss://</url>';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare did not return a session cookie/, 'no cookie handled';

    @fake_res = mk_res 200, '', '<url>wss://foo.bar</url>';
    $req_mock->redefine(cookies => ['the cookie']);
    my ($url, $cookie) = $vmware->get_vmware_wss_url;
    is $url, 'wss://foo.bar', 'URL found';
    is $cookie, 'the cookie', 'cookie returned';
};

subtest 'deducing VNC over WebSockets URL from vars' => sub {
    my $vnc_console = Test::MockObject->new;
    is consoles::VMWare::deduce_url_from_vars($vnc_console), undef, 'no URL if VMWARE_VNC_OVER_WS not set';

    $bmwqemu::vars{VMWARE_VNC_OVER_WS} = 1;
    $vnc_console->set_always(original_hostname => undef)->set_always(hostname => 'foo');
    is consoles::VMWare::deduce_url_from_vars($vnc_console), undef, 'no URL if VIRSH_GUEST not matching';

    $vnc_console->set_always(hostname => $bmwqemu::vars{VIRSH_GUEST} = 'virsh-guest-host');
    throws_ok { consoles::VMWare::deduce_url_from_vars($vnc_console) } qr/VMWARE_VNC_OVER_WS set but not VMWARE_HOST/, 'error if vars specified inconsistently';

    $bmwqemu::vars{VMWARE_HOST} = 'the-host';
    throws_ok { consoles::VMWare::deduce_url_from_vars($vnc_console) } qr/VMWARE_VNC_OVER_WS set but not VMWARE_PASSWORD/, 'error if password missing';

    $bmwqemu::vars{VMWARE_USERNAME} = 'foo';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'bar';
    is consoles::VMWare::deduce_url_from_vars($vnc_console), 'https://foo:bar@the-host', 'URL deduced from vars';

    $vnc_console->set_always(original_hostname => $bmwqemu::vars{VIRSH_GUEST})->set_always(hostname => '127.0.0.1');
    is consoles::VMWare::deduce_url_from_vars($vnc_console), 'https://foo:bar@the-host', 'original hostname used to check if VIRSH_GUEST matching';
};

subtest 'turning WebSocket into normal socket via dewebsockify' => sub {
    # define simple WebSocket server for testing
    package TestWebSocketApp {
        use Mojo::Base 'Mojolicious', -signatures;
        has received_data => '';

        sub startup ($self) {
            $self->routes->websocket('/test')->to('test#start_ws');
            $self->routes->any('*')->to('test#fallback');
        }
        sub received_everything ($self) { length $self->received_data >= length 'message sent from raw socket' }
    }    # uncoverable statement

    package TestWebSocketApp::Controller::Test {
        use Mojo::Base 'Mojolicious::Controller', -signatures;

        sub start_ws ($self) {
            my $sent_everything;
            $self->send({binary => 'binary sent from WebSocket'}, sub {
                    $self->send({text => 'text message sent from WebSocket'}, sub {
                            $sent_everything = 1;
                            $self->finish if $self->app->received_everything;
                    });
            });
            $self->on(
                message => sub ($self, $msg) {
                    $self->app->received_data($self->app->received_data . $msg);
                    $self->finish if $sent_everything && $self->app->received_everything;
                });

            $self->on(finish => sub ($ws, $code, $reason) { $self->ua->ioloop->stop });
        }

        sub fallback ($self) {
            Test::Most::note 'start replying HTTP response';
            $self->render(text => 'fallback', status => 404);
            $self->tx->on(finish => sub ($ws, $code, $reason) {
                    Test::Most::note 'finished replying HTTP response';
                    $self->ua->ioloop->stop;
            });
        }
    }    # uncoverable statement

    # start test WebSocket server
    local $ENV{MOJO_CONNECT_TIMEOUT} = OpenQA::Test::TimeLimit::scale_timeout(60);
    local $ENV{MOJO_INACTIVITY_TIMEOUT} = OpenQA::Test::TimeLimit::scale_timeout(60);
    my $log_level = $ENV{OS_AUTOINST_TEST_DEWEBSOCKIFY_VERBOSE} ? 'trace' : 'error';
    my $t = Test::Mojo->new('TestWebSocketApp');
    my $app = $t->app;
    $app->log->level($log_level);
    $app->ua->ioloop($t->ua->ioloop); # ensure the app providing the HTTP/websocket server and its transactions use the same event loop we use in subsequent code
    note 'Using reactor ' . blessed $t->ua->ioloop->reactor;
    my $daemon = Mojo::Server::Daemon->new(listen => ['http://127.0.0.1:0'], ioloop => $t->ua->ioloop, app => $app);
    combined_like { $daemon->start } qr/Web application available at/, 'could start test WebSocket server' or BAIL_OUT 'cannot proceed without test server';
    my $ws_port = $daemon->ports->[0];

    my $_start_dewebsockify_robustly = sub ($ws_url, $capture_log, $vmware_instance = undef, $log_level = undef) {
        for my $attempt (1 .. 10) {
            my $tcp_port = Mojo::IOLoop::Server->generate_port;
            my ($pid, $pipe);
            if ($capture_log) {
                $pid = open $pipe, "$bmwqemu::topdir/script/dewebsockify --listenport $tcp_port --websocketurl $ws_url 2>&1 |" or die "Unable to start dewebsockify: $!";
            } else {
                $vmware_instance->_start_dewebsockify_process($tcp_port, $ws_url, 'session', $log_level);
                $pid = $vmware_instance->dewebsockify_pid;
            }
            select undef, undef, undef, 0.1;
            my $res = waitpid $pid, WNOHANG;
            if ($res == 0) {
                return ($pid, $tcp_port, $pipe);
            }
            if ($pipe) {
                close $pipe;
            }
            $vmware_instance->dewebsockify_pid(undef) if $vmware_instance;
            note "dewebsockify died immediately on port $tcp_port (res=$res, pid=$pid, err=$!), retrying ($attempt/10).";
        }
        die 'Failed to start dewebsockify after 10 attempts';
    };

    # start dewebsockify
    my $vmware = consoles::VMWare->new;
    my ($tcp_pid, $tcp_port) = $_start_dewebsockify_robustly->("ws://127.0.0.1:$ws_port/test", 0, $vmware, $log_level);
    ok $vmware->dewebsockify_pid, 'dewebsockify PID tracked: ' . ($vmware->dewebsockify_pid // '?');

    # connect to dewebsockify and let everything run
    my $data_received_via_raw_socket = '';
    my $configured_connect_attempts = OpenQA::Test::TimeLimit::scale_timeout($ENV{OS_AUTOINST_TEST_DEWEBSOCKIFY_CONNECT_ATTEMPTS} // 100);
    my ($close_immediately, $connect_attempts, $connect_to_dewebsockify, $current_tcp_port, $current_wait_pid, $stop_on_close);
    $connect_to_dewebsockify = sub ($loop) {
        if ($current_wait_pid && waitpid($current_wait_pid, WNOHANG) > 0) {
            fail "dewebsockify process $current_wait_pid died prematurely, aborting connection attempts";
            return $loop->stop;
        }
        note "connecting to dewebsockify on port $current_tcp_port";
        $loop->client({port => $current_tcp_port} => sub ($loop, $err, $stream) {
                if ($err) {
                    if (--$connect_attempts) {
                        note "unable to connect to dewebsockify on port $current_tcp_port: $err (will try again $connect_attempts times)";
                        return $loop->timer(0.05 => $connect_to_dewebsockify);
                    }
                    fail "unable to connect to dewebsockify on port $current_tcp_port: $err";    # uncoverable statement
                    return $loop->stop;    # uncoverable statement
                }
                note "connection to dewebsockify established via port $current_tcp_port";
                if ($close_immediately) {
                    note 'closing connection to dewebsockify immediately';
                    $stream->close;
                    return $loop->stop;
                }
                $stream->on(read => sub ($stream, $bytes) {
                        $data_received_via_raw_socket .= $bytes;
                        $stream->write('message sent from raw socket') if length $data_received_via_raw_socket >= length 'binary sent from WebSocket';
                });
                $stream->on(close => sub {
                        return unless $stop_on_close;
                        note 'dewebsockify closed connection';
                        $loop->stop;
                });
                $stream->on(error => sub ($stream, $err) {
                        fail "dewebsockify connection error: $err";
                        $loop->stop;
                });
        });
    };
    my $connect_to_dewebsockify_with_multiple_attempts = sub (%args) {
        $current_tcp_port = $args{port} // $tcp_port;
        $current_wait_pid = $args{wait_pid};
        $connect_attempts = $configured_connect_attempts;
        $close_immediately = $args{close_immediately} // 0;
        $stop_on_close = $args{stop_on_close} // 0;
        my $watchdog = $t->ua->ioloop->timer(OpenQA::Test::TimeLimit::scale_timeout(15) => sub {
                my $loop = shift;
                fail "Subtest 'turning WebSocket into normal socket via dewebsockify' timed out (watchdog)";
                $loop->stop;
        });
        $t->ua->ioloop->next_tick($connect_to_dewebsockify);
        $t->ua->ioloop->start;
        $t->ua->ioloop->remove($watchdog);
        if (my $pid = $args{wait_pid}) {
            note "waiting for dewebsockify process to terminate, pid: $pid";
            waitpid $pid, 0;    # dewebsockify is supposed to exit on its own
        }
    };
    $connect_to_dewebsockify_with_multiple_attempts->();

    # check whether all messages have been passed as expected
    is $data_received_via_raw_socket, 'binary sent from WebSocket', 'expected data received via raw socket';
    is $app->received_data, 'message sent from raw socket', 'expected data received via WebSocket';
    note 'waiting for dewebsockify process to terminate, pid: ' . ($vmware->dewebsockify_pid // '?');
    $vmware->_cleanup_previous_dewebsockify_process;

    my $assert_log = sub ($dewebsockify_pipe, $expected) {
        my $dewebsockify_log;
        read $dewebsockify_pipe, $dewebsockify_log, 1000 or die "Unable read dewebsockify pipe: $!";
        like $dewebsockify_log, $expected, 'error logged';
        close $dewebsockify_pipe;    # might fail because dewebsockify has already exited but that's ok
    };

    subtest 'handle error when WebSocket server is not reachable' => sub {
        my ($dewebsockify_pid, $tcp_port_for_errors1, $dewebsockify_pipe) = $_start_dewebsockify_robustly->('ws://127.0.0.:4', 1);
        $connect_to_dewebsockify_with_multiple_attempts->(close_immediately => 1, wait_pid => $dewebsockify_pid, port => $tcp_port_for_errors1);
        $assert_log->($dewebsockify_pipe, qr/WebSocket connection error:/);
    };
    subtest 'handle error when HTTP server is not upgrading to WebSockets' => sub {
        my ($dewebsockify_pid, $tcp_port_for_errors2, $dewebsockify_pipe) = $_start_dewebsockify_robustly->("ws://127.0.0.1:$ws_port/foo", 1);
        $connect_to_dewebsockify_with_multiple_attempts->(close_immediately => 0, wait_pid => $dewebsockify_pid, port => $tcp_port_for_errors2, stop_on_close => 1);
        $assert_log->($dewebsockify_pipe, qr/WebSocket 404 response: Not Found/);
    };
};

subtest 'multiple attempts to launch VNC server' => sub {
    my $vmware_mock = Test::MockModule->new('consoles::VMWare');
    $vmware_mock->redefine(get_vmware_wss_url => sub { die "test error handling\n" });
    $bmwqemu::vars{VMWARE_VNC_OVER_WS_REQUEST_DELAY} = 0;

    my $vmware = consoles::VMWare->new;
    combined_like {
        throws_ok { $vmware->launch_vnc_server(1234) } qr/test error handling/, 'exception re-thrown'
    } qr/test error handling, trying 11 more times.*trying 1 more times/s, 'attempts logged';
};

subtest 'test against real VMWare instance' => sub {
    my $vmware = consoles::VMWare->new;
    my $instance_url = $ENV{OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE};
    unless ($instance_url) {
        plan skip_all => 'Set OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE to run this test.';
    }
    $vmware->configure_from_url($instance_url);    # uncoverable statement
    note 'host: ' . $vmware->host // '?';    # uncoverable statement
    note 'username: ' . $vmware->username // '?';    # uncoverable statement
    note 'password: ' . $vmware->password // '?';    # uncoverable statement
    note 'instance: ' . $vmware->vm_id // '?';    # uncoverable statement

    # request wss URL and session cookie
    my ($wss_url, $session) = $vmware->get_vmware_wss_url;    # uncoverable statement
    like $wss_url, qr{wss://.+/ticket/.+}, 'wss URL returned for VMWare host';    # uncoverable statement
    like $session, qr{vmware_soap_session=.+}, 'session cookie returned';    # uncoverable statement
    note "wss url: $wss_url\n";    # uncoverable statement
    note "session: $session\n";    # uncoverable statement

    # spawn test instance of dewebsockify for manually testing with vncviewer
    if (my $port = $ENV{OS_AUTOINST_DEWEBSOCKIFY_PORT}) {    # uncoverable statement
        system "'$bmwqemu::topdir/script/dewebsockify' --listenport '$port' --websocketurl '$wss_url' --cookie 'vmware_client=VMware; $session' --insecure"; # uncoverable statement

    }
};

done_testing;
