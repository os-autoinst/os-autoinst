# Copyright 2018-2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Commands;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use commands;
use Try::Tiny;
use Mojo::JSON qw(decode_json to_json);

sub pass_message_from_ws_client_to_isotovideo ($self, $id, $msg) {
    my $app = $self->app;
    my $isotovideo = $app->defaults('isotovideo');
    return $app->log->debug('cmdsrv: not passing command from client to isotovideo; connection to isotovideo has already been stopped')
      unless defined $isotovideo;

    $app->log->debug("cmdsrv: passing command from client to isotovideo $isotovideo: $msg");

    my $decoded_message;
    try {
        $decoded_message = decode_json($msg);
    }
    catch {
        $app->log->warn('cmdsrv: failed to decode message');
        return undef;
    };
    return undef unless defined $decoded_message;

    myjsonrpc::send_json($isotovideo, $decoded_message);

    # note: no myjsonrpc::read_json() here - response is broadcasted to all clients in commands.pm
}

sub handle_ws_client_disconnects ($self, $id) {
    $self->app->log->debug('cmdsrv: client disconnected: ' . $id);
    delete $self->app->defaults('clients')->{$id};
}

sub start_ws ($self) {
    my $id = sprintf "%s", $self->tx;
    $self->app->log->debug('cmdsrv: client connected: ' . $id);
    $self->app->defaults('clients')->{$id} = $self->tx;

    $self->on(
        message => sub ($self, $msg) {
            $self->pass_message_from_ws_client_to_isotovideo($id, $msg);
        });
    $self->on(finish => sub {
            $self->handle_ws_client_disconnects($id);
    });
}

sub broadcast_message_to_websocket_clients ($self) {
    my $app = $self->app;
    my $clients = $app->defaults('clients');
    my $message = $self->req->json;

    $app->log->debug('cmdsrv: broadcasting message from API call to all ws clients');
    return $self->render(
        json => {
            error => 'JSON message to be boradcasted missing or invalid',
            status => 'boradcast failed',
        },
        status => 400,
    ) unless ($message);

    $app->log->debug('cmdsrv: broadcasting message from API call to all ws clients: ' . to_json($message));

    my $outstanding_transactions = scalar keys %$clients;
    return $self->render(json => {status => 'boradcast done'}) unless $outstanding_transactions;

    for (keys %$clients) {
        $clients->{$_}->send({json => $message}, sub {
                return undef if (($outstanding_transactions -= 1) > 0);
                return $self->render(json => {status => 'boradcast done'});
        });
    }

    return $self;
}

1;
