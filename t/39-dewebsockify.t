#!/usr/bin/perl
#
# Copyright 2019-2024 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base;
use Test::MockModule;
use Test::Warnings;
use Mojo::Log;
use Mojo::IOLoop::Server;

BEGIN {
    require OpenQA::Isotovideo::Dewebsockify;
}

my $accept_callback;

my $mock_server = Test::MockModule->new('Mojo::IOLoop::Server');
$mock_server->mock(
    new => sub {
        return bless {}, 'Mojo::IOLoop::Server';
    },
    on => sub {
        my ($self, $event, $cb) = @_;
        if ($event eq 'accept') {
            # saving callback for reusing later
            $accept_callback = $cb;
        }
    },
    listen => sub { },
    start => sub { },
);

my $mock_stream = Test::MockModule->new('Mojo::IOLoop::Stream');
$mock_stream->mock(new => sub { return bless {}, 'Mojo::IOLoop::Stream'; });
$mock_stream->mock(start => sub { });
$mock_stream->mock(on => sub { });
$mock_stream->mock(close_gracefully => sub { });

my $mock_ua = Test::MockModule->new('Mojo::UserAgent');
$mock_ua->mock(new => sub { bless {}, 'Mojo::UserAgent' });

$mock_ua->mock(build_websocket_tx => sub {
        my ($self, $url) = @_;
        return bless {}, 'MockTx';
});

$mock_ua->mock(start => sub {
        my ($self, $tx, $cb) = @_;
        $cb->($self, $tx);
});

# simulating failed handshake
{
    package MockTx;
    sub is_websocket { 0 }
    sub error { return undef }
    sub req { return bless {}, 'MockReq'; }
    sub res { return bless {}, 'MockRes'; }

    package MockReq;
    sub cookies { }
    sub headers { return bless {}, 'MockHeaders'; }

    package MockHeaders;
    sub add { }

    package MockRes;
    sub body { return 'dummy body'; }
}

my @log_messages;
my $mock_log = Test::MockModule->new('Mojo::Log');
$mock_log->mock(info => sub { push @log_messages, $_[1] });
$mock_log->mock(error => sub { push @log_messages, $_[1] });

my $args = {
    websocketurl => 'ws://example.com',
    listenport => 5900,
    cookie => undef,
    loglevel => 'info',
};

OpenQA::Isotovideo::Dewebsockify::main($args);

$accept_callback->(undef, 'dummy_socket_1');

ok(grep(/Unable to upgrade to WebSocket connection/, @log_messages),
    'WebSocket upgrade failed without HTTP code as expected.');

like($log_messages[-1], qr/Client accepted/i, 'first client accepted.');

$accept_callback->(undef, 'dummy_socket_2');
like($log_messages[-1], qr/Rejecting new client/i, 'second client rejected as expected.');

done_testing();

