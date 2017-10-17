# Copyright (C) 2017 SUSE LLC
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

package backend::component::proxy;
use base 'Mojolicious';
use Mojo::Base 'backend::component::process';

use Mojo::Server::Prefork;
use Mojo::Server::Daemon;

use Mojo::Transaction::HTTP;
use bmwqemu;
use constant PROXY_BASE_PORT => 9992;
has listening_address        => "127.0.0.1";
has listening_port           => PROXY_BASE_PORT;
has redirect_table => sub { {} };
has policy         => "FORWARD";
has server_type    => "Prefork";
has load => sub { $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY} || $bmwqemu::vars{CONNECTIONS_HIJACK} };
has silent_daemon      => 1;
has log_level          => "error";
has inactivity_timeout => 20;
has max_redirects      => 5;
has connect_timeout    => 20;
has request_timeout    => 10;
has set_pipes          => 0;

sub prepare {
    my ($self) = @_;
    my @entry;

    my $hosts = $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_ENTRY};
    my $policy = $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} || $self->policy;    # Can be REDIRECT, DROP, FORWARD

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} = $policy
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} || $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_POLICY} ne $policy;

    my $proxy_server_port
      = $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} || ($bmwqemu::vars{VNC} ? $bmwqemu::vars{VNC} + PROXY_BASE_PORT : $self->listening_port);
    my $proxy_server_address = $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_ADDRESS} || $self->listening_address;

    $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} = $proxy_server_port
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} || $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_PORT} ne $proxy_server_port;

    my $server_type = $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY_SERVER_TYPE};

    @entry = split(/,/, $hosts) if $hosts;

    # Generate record table from configuration
    my $redirect_table = {
        map {
            my ($host, @redirect) = split(/:/, $_);
            $host => [@redirect] if ($host and @redirect)
        } @entry
    };

    $policy = "REDIRECT" if (!$policy && $hosts);

    $self->redirect_table($redirect_table)          if keys %{$redirect_table} > 0;
    $self->listening_port($proxy_server_port)       if $proxy_server_port;
    $self->listening_address($proxy_server_address) if $proxy_server_address;
    $self->policy($policy)                          if $policy;
    $self->server_type($server_type)                if $server_type;
    $self->code(\&_start);

    return $self;
}

sub _build_tx {
    my ($self, $from, $r_host, $r_urlpath, $r_method) = @_;
    my $host_entry = $self->redirect_table;

    #Start forging - FORWARD by default
    my $tx = Mojo::Transaction::HTTP->new();
    $tx->req($from);    #this is better, we keep also the same request
    $tx->req->method($r_method);

    if ($self->policy eq "FORWARD" or (($self->policy eq "REDIRECT" && !exists $host_entry->{$r_host})))
    {                   # If policy is REDIRECT and no entry in the host table, fallback to FORWARD
        $tx->req->url->parse("http://" . $r_host);
        $tx->req->url->path($r_urlpath);

        $self->_diag("No redirect rules for the host, forwarding to: " . $r_host);
        return $tx;
    }

    return unless exists $host_entry->{$r_host};
    my @rules       = @{$host_entry->{$r_host}};
    my $redirect_to = shift @rules;

    # URLREWRITE policy lets you define rules to rewrite URL paths. Otherwise fallback is just redirect
    if ($self->policy eq "URLREWRITE") {
        for (my $i = 0; $i <= $#rules; $i += 2) {
            my $redirect_replace      = $rules[$i];
            my $redirect_replace_with = $rules[$i + 1];
            next unless $redirect_replace && $redirect_replace_with;
            if ($redirect_replace_with eq "FORWARD" and $r_urlpath =~ /$redirect_replace/i) {
                $tx->req->url->parse("http://" . $r_host);
                $tx->req->url->path($r_urlpath);
                $self->_diag("Forwarding request directly to: " . $tx->req->url->to_abs);
                return $tx;
            }
            $r_urlpath =~ s/$redirect_replace/$redirect_replace_with/g;
        }
    }

    $redirect_to =~ s/^http(s)?:\/\///g;
    # Now we can generate the url path of the proxied transaction
    my $url = Mojo::URL->new("http://" . $redirect_to);

    if ($url) {    #needed since tx is built from clone()
        $tx->req->url->parse("http://" . $url->host);
        $tx->req->url->base->host($url->host);
        $tx->req->content->headers->host($url->host);
    }

    $tx->req->url->path(($url and $url->path ne "/") ? $url->path . $r_urlpath : $r_urlpath);

    $self->_diag("Redirecting to: " . $tx->req->url->to_string);
    return $tx;
}


sub _handle_request {
    my ($self, $controller) = @_;
    $controller->render_later;

    my $r_url     = $controller->tx->req->url;
    my $r_urlpath = $controller->tx->req->url->path;

    my $r_host         = $controller->tx->req->url->base->host() || $controller->tx->req->content->headers->host();
    my $r_method       = $controller->tx->req->method();
    my $client_address = $controller->tx->remote_address;

    if (!$r_host) {
        $self->_diag("Request from: " . $client_address . " could not be processed - cannot retrieve requested host");
        $controller->reply->not_found;
        return;
    }

    if ($self->policy eq "DROP") {
        $self->_diag("Answering with 404");
        $controller->reply->not_found;
        return;
    }

    $self->_diag("Request from: " . $client_address . " method: " . $r_method . " to host: " . $r_host);
    $self->_diag("Requested url is: " . $controller->tx->req->url->to_abs);

    my $tx = $self->_build_tx($controller->tx->req->clone(), $r_host, $r_urlpath, $r_method);
    unless ($tx) {
        $self->_diag("Proxy was unable to build the request");
        $controller->reply->not_found;
        return;
    }
    $tx->req->url->query($controller->tx->req->params);
    my $req_tx = $self->ua->start($tx);

    unless ($req_tx->result->is_success) {
        $self->_diag("!! Request error: Something went wrong when processing the request, return code from request is: " . $req_tx->result->code);
        if ($req_tx->result->code eq "404") {
            $self->_diag("!! Returning 404");
            $controller->reply->not_found;
            return;
        }
        $self->_diag("!! Forwarding to client anyway");
    }

    $controller->tx->res($req_tx->res);
    $controller->rendered;
}

sub startup {
    my $self = shift;
    $self->log->level($self->log_level);

    $self->routes->any('*' => sub { $self->_handle_request(shift) });    ## no critic
    $self->routes->any('/' => sub { $self->_handle_request(shift) });
}

sub _start {
    my $self = shift;

    die "Invalid policy supplied for Proxy"
      unless ($self->policy eq "FORWARD" or $self->policy eq "DROP" or $self->policy eq "REDIRECT" or $self->policy eq "URLREWRITE");

    $self->_diag("Server starting at: " . $self->listening_address . ":" . $self->listening_port);
    $self->_diag("Server type is: " . $self->server_type);
    $self->_diag("Policy is: " . $self->policy);
    $self->_diag("Redirect table: ") if ref($self->redirect_table) eq "HASH" && !!keys %{$self->redirect_table};

    die "Proxy server_type can be only of type 'Daemon' or 'Prefork'" unless ($self->server_type eq "Daemon" or $self->server_type eq "Prefork");

    foreach my $k (keys %{$self->redirect_table}) {
        $self->_diag("\t $k => " . join(", ", @{$self->redirect_table->{$k}}));
    }

    if ($self->policy eq "URLREWRITE" and ref($self->redirect_table) eq "HASH") {
        for my $r_host (keys %{$self->redirect_table}) {
            $self->_diag("!! Odd number of rewrite rules given for '$r_host'. Expecting even")
              unless (scalar(@{$self->redirect_table->{$r_host}}) - 1) % 2 == 0;
        }
    }

    for my $attrs (qw(inactivity_timeout max_redirects connect_timeout request_timeout)) {
        if ($self->ua->$attrs() != $self->$attrs()) {
            $self->ua->$attrs($self->$attrs());
            $self->_diag("$attrs is : " . $self->ua->$attrs);
        }
    }

    my $server_type = join("::", "Mojo", "Server", $self->server_type);
    $server_type->new(listen => ['http://' . $self->listening_address . ':' . $self->listening_port], app => $self)->silent($self->silent_daemon)->run;

}

# We need to override the Mojolicious one with the backend::component::process start()
sub start {
    my $self = shift;
    $self->code(\&_start) unless $self->code;
    $self->backend::component::process::start;
}

1;
