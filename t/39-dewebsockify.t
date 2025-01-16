#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use Test::Most;
use Test::MockModule;
use Test::Warnings;
use Mojo::Log;
use Mojo::IOLoop::Server;

BEGIN {
    require OpenQA::Isotovideo::Dewebsockify;
}

my $args_common = {
    websocketurl => 'ws://example.com',
    listenport => 5900,
    cookie => undef,
    loglevel => 'info',
};

my ($accept_callback, @log_messages);
our ($ws_on_text, $ws_on_binary, $ws_on_finish);

my $mock_log = Test::MockModule->new('Mojo::Log');
$mock_log->redefine(info => sub ($self, $msg) { push @log_messages, $msg });
$mock_log->redefine(error => sub ($self, $msg) { push @log_messages, $msg });
$mock_log->redefine(trace => sub ($self, $msg) { push @log_messages, $msg });

my $mock_server = Test::MockModule->new('Mojo::IOLoop::Server');
$mock_server->redefine(
    new => sub { bless {}, 'Mojo::IOLoop::Server' },
    on => sub ($self, $event, $cb) {
        $accept_callback = $cb if $event eq 'accept';
    },
    listen => sub { },
    start => sub { },
);

my $mock_stream = Test::MockModule->new('Mojo::IOLoop::Stream');
$mock_stream->redefine(
    new => sub { bless {}, 'Mojo::IOLoop::Stream' },
    start => sub { },
    on => sub { },    # selectively overridden in subtests
    write => sub { },
    close_gracefully => sub { },
);

my $mock_ua = Test::MockModule->new('Mojo::UserAgent');
$mock_ua->mock(new => sub { bless {}, 'Mojo::UserAgent' });
$mock_ua->mock(start => sub ($ua, $tx, $cb) {
        $cb->($ua, $tx);
});

{
    package MockTxGeneric;    # uncoverable statement
    use Test::Most;

    sub is_websocket { 1 }
    sub max_websocket_size { }
    sub error { }
    sub req { bless {}, 'MockTxGenericReq' }
    sub on ($self, $event, $cb) {
        if ($event eq 'text') { $main::ws_on_text = $cb }
        elsif ($event eq 'binary') { $main::ws_on_binary = $cb }
        elsif ($event eq 'finish') { $main::ws_on_finish = $cb }
    }
    sub send { }
    sub finish { }

    package MockTxGenericReq;
    sub cookies { }
    sub headers { bless {}, 'MockTxGenericHeaders' }

    package MockTxGenericHeaders;
    sub add { }

    package MockTxFailNoCode;
    sub is_websocket { 0 }
    sub error { undef }    # No code, no message
    sub req { bless {}, 'MockTxFailNoCodeReq' }
    sub res { bless {}, 'MockTxFailNoCodeRes' }

    package MockTxFailNoCodeReq;
    sub cookies { }
    sub headers { bless {}, 'MockTxFailNoCodeHeaders' }

    package MockTxFailNoCodeHeaders;
    sub add { }

    package MockTxFailNoCodeRes;
    sub body { 'dummy body' }

    package MockTxFailWithCode;
    sub is_websocket { 0 }
    sub error {
        return {code => 403, message => 'Forbidden'};
    }
    sub req { bless {}, 'MockTxFailWithCodeReq' }
    sub res { bless {}, 'MockTxFailWithCodeRes' }

    package MockTxFailWithCodeReq;
    sub cookies { }
    sub headers { bless {}, 'MockTxFailWithCodeHeaders' }

    package MockTxFailWithCodeHeaders;
    sub add { }

    package MockTxFailWithCodeRes;
    sub body { 'dummy body' }
}

sub mock_build_ws_tx ($mock_ua, $tx_class) {
    $mock_ua->mock(build_websocket_tx => sub { return bless {}, $tx_class; });
}

sub reset_log_messages () {
    @log_messages = ();
}

sub start_dewebsockify () {
    OpenQA::Isotovideo::Dewebsockify::main($args_common);
}

sub accept_client ($socket_name) {
    $accept_callback->(undef, $socket_name);
}

subtest 'WebSocket handshake fails (no HTTP code)' => sub {
    reset_log_messages();

    mock_build_ws_tx($mock_ua, 'MockTxFailNoCode');
    start_dewebsockify();
    accept_client('dummy_socket_1');
    ok(grep(/Unable to upgrade to WebSocket connection/, @log_messages),
        'WebSocket upgrade failed without HTTP code');
    like($log_messages[-1], qr/Client accepted/,
        'First client accepted before failing handshake');
    accept_client('dummy_socket_2');    # Second client must be rejected
    like($log_messages[-1], qr/Rejecting new client/,
        'Second client rejected as expected');
};

subtest 'WebSocket handshake succeeds' => sub {
    reset_log_messages();
    mock_build_ws_tx($mock_ua, 'MockTxGeneric');    # reset tx

    $mock_stream->redefine(on => sub ($self, $event, $cb) {
            if ($event eq 'read') {
                $cb->($self, "dummy raw data");
            }
    });
    $mock_stream->redefine(write => sub ($self, $bytes) {
            pass("Data written to raw socket: $bytes");
    });

    start_dewebsockify();
    accept_client('dummy_socket_1');
    ok(grep(/WebSocket connection established/, @log_messages),
        'WebSocket connection established');

    $ws_on_text->(undef, "dummy text message");
    pass("Text message received via WebSocket");
    $ws_on_binary->(undef, "dummy binary data");
    pass("Binary message received via WebSocket");
    $ws_on_finish->(undef, 1000, "Normal closure");
    ok(grep(/WebSocket closed with status 1000/, @log_messages),
        'WebSocket closed as expected');
};

subtest 'WebSocket handshake fails with error code' => sub {
    reset_log_messages();

    mock_build_ws_tx($mock_ua, 'MockTxFailWithCode');
    start_dewebsockify();
    accept_client('dummy_socket_1');
    ok(grep(/WebSocket 403 response: Forbidden/, @log_messages),
        'WebSocket upgrade failed with error code');
};

subtest 'Client connection closure' => sub {
    reset_log_messages();
    mock_build_ws_tx($mock_ua, 'MockTxGeneric');

    my $stream_close_cb;
    $mock_stream->redefine(on => sub ($self, $event, $cb) {
            $stream_close_cb = $cb if $event eq 'close';
    });

    start_dewebsockify();
    accept_client('dummy_socket_1');
    ok(grep(/WebSocket connection established/, @log_messages),
        'WebSocket connection established');
    $stream_close_cb->('dummy_stream') if $stream_close_cb;
    ok(grep(/Client closed connection/, @log_messages),
        'Client connection closure logged');
};

subtest 'Client connection error' => sub {
    reset_log_messages();
    mock_build_ws_tx($mock_ua, 'MockTxGeneric');

    my $stream_error_cb;
    # Capture error callback
    $mock_stream->redefine(on => sub ($self, $event, $cb) {
            if ($event eq 'error') {
                $stream_error_cb = $cb;
            }
    });

    start_dewebsockify();
    accept_client('dummy_socket_1');
    ok(grep(/WebSocket connection established/, @log_messages),
        'WebSocket connection established');
    $stream_error_cb->('dummy_stream', 'Something went wrong') if $stream_error_cb;
    ok(grep(/Client error: Something went wrong/, @log_messages),
        'Client error was logged');
};

done_testing();
