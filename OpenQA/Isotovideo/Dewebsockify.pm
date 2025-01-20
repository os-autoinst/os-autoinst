# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Dewebsockify;

use Mojo::Base -strict, -signatures;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::Log;
use Mojo::UserAgent;

sub establish_websocket_connection ($log, $ws_url, $tosend, $ua, $ws_connection, $stream, $cookie = undef) {
    $log->info("Establishing WebSocket connection to $ws_url");
    @$tosend = ();
    my $tx = $ua->build_websocket_tx($ws_url);
    my $req = $tx->req;
    my $headers = $tx->req->headers;
    $req->cookies($cookie) if $cookie;
    $headers->add(Pragma => 'no-cache');
    $headers->add('Sec-WebSocket-Protocol' => 'binary, vmware-vvc');
    $ua->start($tx => sub ($ua, $tx) {
            # handle errors
            if (!$tx->is_websocket) {
                if (my $err = $tx->error) {
                    $log->error($err->{code} ? "WebSocket $err->{code} response: $err->{message}"
                        : "WebSocket connection error: $err->{message}");
                } else {
                    $log->error('Unable to upgrade to WebSocket connection');
                }
                my $body = $tx->res->body;
                $log->trace($body) if $body;
                $$ws_connection = undef;
                $stream->close_gracefully if $stream;
                return undef;
            }
            $log->info('WebSocket connection established');
            $tx->max_websocket_size(1024**3);    # required to avoid 1009 error, at least when using raw encoding
            $$ws_connection = $tx;

            # pass data from websocket to raw socket
            $tx->on(text => sub ($tx, $text) {
                    $log->trace("WebSocket text message: $text");
            });
            $tx->on(binary => sub ($tx, $bytes) {
                    $log->trace("WebSocket binary message:\n" . sprintf("%v02X", $bytes));
                    $stream->write($bytes) if $stream;
            });

            # pass pending data from raw socket to websocket
            $tx->send($_) for @$tosend;
            @$tosend = ();

            # handle websocket connection finish
            # note: Terminating here because at least for VMWare one needed a new URL/ticket anyways.
            $tx->on(finish => sub ($tx, $code, $reason) {
                    $log->info("WebSocket closed with status $code.");
                    $$ws_connection = undef;
                    $stream->close_gracefully if $stream;
                    Mojo::IOLoop->stop_gracefully;
            });
    });
}

sub main ($args) {
    die "Arguments must be a hash reference!" unless defined $args && ref($args) eq 'HASH';

    my $ws_url = $args->{websocketurl} or die "websocket URL missing\n";
    my $port = $args->{listenport} // 5900;
    my $cookie = $args->{cookie} // undef;
    my $log = Mojo::Log->new(level => $args->{loglevel} // 'info');

    $log->debug("websocket url: $ws_url");
    $log->debug("listen port: $port");
    $log->debug("cookie: " . $cookie) if $cookie;

    # create listen socket
    my $ua = Mojo::UserAgent->new;
    my $server = Mojo::IOLoop::Server->new;
    my $ws_connection;
    my $stream;
    my @tosend;
    $ua->insecure($args->{insecure} // 0);

    # accept new connections
    $server->on(accept => sub ($server, $handle) {
            if ($stream) {
                $log->info('Rejecting new client; already one client connected');
                return undef;
            }
            $stream = Mojo::IOLoop::Stream->new($handle);
            $stream->start;
            $stream->reactor->start unless $stream->reactor->is_running;
            establish_websocket_connection($log, $ws_url, \@tosend, $ua, \$ws_connection, $stream, $cookie) unless $ws_connection;
            # pass data from raw socket to websocket
            $stream->on(read => sub ($s, $bytes) {
                    if ($ws_connection) {
                        $log->debug("Raw socket message:\n" . sprintf("%v02X", $bytes));
                        $ws_connection->send({binary => $bytes});
                    } else {
                        $log->debug("Raw socket message (forwarding later):\n" . sprintf("%v02X", $bytes));
                        push @tosend, $bytes;
                    }
            });

            # handle raw socket close/error
            $stream->on(close => sub ($s) {
                    $log->info('Client closed connection');
                    $stream = undef;
                    $ws_connection ? $ws_connection->finish : Mojo::IOLoop->stop_gracefully;
            });
            $stream->on(error => sub ($stream, $err) {
                    $log->error("Client error: $err");
            });

            $log->info('Client accepted');
    });
    $server->listen(port => $port);
    $server->start;
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

1;

