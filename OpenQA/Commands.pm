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

use strict;
use Mojo::Base 'Mojolicious::Controller';
use commands;

use JSON qw(encode_json decode_json);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{clients} = {};
    return $self;
}

sub ws_message {
    my ($self, $msg) = @_;
    $self->app->log->debug("Message $msg");
    $msg = decode_json($msg);
    my $isotovideo = $self->app->stash('isotovideo');
    myjsonrpc::send_json($isotovideo, $msg);
    my $reply = myjsonrpc::read_json($isotovideo);
    app->log->debug("Message " . encode_json($reply));

    for (keys %{$self->{clients}}) {
        $self->{clients}->{$_}->send({json => $reply});
    }
}

sub ws_finish {
    my ($self, $id) = @_;
    $self->app->log->debug('Client disconnected');
    delete $self->{clients}->{$id};
}

sub start_ws {
    my ($self) = @_;

    $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx;
    $self->{clients}->{$id} = $self->tx;

    $self->on(message => \&ws_message);
    $self->on(finish => sub { ws_finish($self, $id) });
}

sub developer {
    my ($self) = @_;
    $self->stash(wsurl => $self->url_for('ws')->to_abs);
    return $self->render;
}

1;
