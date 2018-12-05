# Copyright © 2018 SUSE LLC
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

package OpenQA::Commands;
use Mojo::Base 'Mojolicious::Controller';

use commands;
use Try::Tiny;
use Mojo::JSON 'decode_json';

sub pass_message_from_ws_client_to_isotovideo {
    my ($self, $id, $msg) = @_;

    my $isotovideo = $self->app->defaults('isotovideo');
    $self->app->log->debug("cmdsrv: passing command from client to isotovideo $isotovideo: " . $msg);
    try {
        $msg = decode_json($msg);
    }
    catch {
        $self->app->log->warning('cmdsrv: failed to decode message');
        return;
    };
    myjsonrpc::send_json($isotovideo, $msg);

    # note: no myjsonrpc::read_json() here - response is broadcasted to all clients in commands.pm
}

sub handle_ws_client_disconnects {
    my ($self, $id) = @_;
    $self->app->log->debug('cmdsrv: client disconnected: ' . $id);
    delete $self->app->defaults('clients')->{$id};
}

sub start_ws {
    my ($self) = @_;

    my $id = sprintf "%s", $self->tx;
    $self->app->log->debug('cmdsrv: client connected: ' . $id);
    $self->app->defaults('clients')->{$id} = $self->tx;

    $self->on(
        message => sub {
            my ($self, $msg) = @_;
            $self->pass_message_from_ws_client_to_isotovideo($id, $msg);
        });
    $self->on(finish => sub {
            $self->handle_ws_client_disconnects($id);
    });
}

1;
