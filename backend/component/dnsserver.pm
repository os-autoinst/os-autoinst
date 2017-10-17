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

package backend::component::dnsserver;
use Mojo::Base "backend::component::process";
use Net::DNS::Nameserver;
use backend::component::dnsserver::dnsresolver;
use bmwqemu;
use Mojo::URL;
use osutils 'looks_like_ip';
use constant DNS_BASE_PORT => 9995;

has [qw(record_table _external_resolver)];
has forward_nameserver => sub { ['8.8.8.8'] };
has listening_address  => "127.0.0.1";
has policy             => 'SINK';
has listening_port     => DNS_BASE_PORT;
has load => sub { $bmwqemu::vars{CONNECTIONS_HIJACK_DNS} || $bmwqemu::vars{CONNECTIONS_HIJACK} };  #use autoload. so we keep the loading logic in the component.
has set_pipes => 0;

sub prepare {
    my ($self) = @_;
    my $dns_table = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_ENTRY};
    my $listening_port
      = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} || ($bmwqemu::vars{VNC} ? $bmwqemu::vars{VNC} + DNS_BASE_PORT : $self->listening_port());
    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} = $listening_port
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} || $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} ne $listening_port;
    my $listening_address = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} || $self->listening_address();
    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} = $listening_address
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} || $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} ne $listening_address;
    my $policy = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} || $self->policy;    # Can be SINK/FORWARD
    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} = $policy
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} || $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} ne $policy;

    # Be sure HIJACK_FAKEIP is present if necessary. Automatic handling of SUSEMIRROR depends on that.
    $bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP} = "10.0.2.254"
      if (
        (
               ($bmwqemu::vars{CONNECTIONS_HIJACK} || $bmwqemu::vars{CONNECTIONS_HIJACK_PROXY} || $bmwqemu::vars{CONNECTIONS_HIJACK_DNS})
            && $bmwqemu::vars{NICTYPE}
            && $bmwqemu::vars{NICTYPE} eq "user"
        )
        and !defined $bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP});

    my %record_table;

    if ($dns_table) {
        # Generate record table from configuration, translate them in DNS entries
        %record_table = map {
            my ($host, $ip) = split(/:/, $_);
            return () unless $host and $ip;
            $host => ($ip eq "FORWARD" or $ip eq "DROP") ? $ip : (looks_like_ip($ip)) ? ["$host.     A   $ip"] : ["$host.     CNAME   $ip"];
        } split(/,/, $dns_table);
    }

    $self->record_table(\%record_table)          if keys %record_table > 0;
    $self->listening_port($listening_port)       if $listening_port;
    $self->listening_address($listening_address) if $listening_address;
    $self->policy($policy)                       if $policy;
    $self->code(\&_start);

    return $self;
}

sub _forward_resolve {
    my $self = shift;
    return "SERVFAIL" unless @{$self->forward_nameserver()} > 0;

    my ($qname, $qtype, $qclass) = @_;
    my (@ans, $rcode);
    $self->_diag("Forwarding request to " . join(", ", @{$self->forward_nameserver()}));

    if (!$self->_external_resolver) {
        $self->_external_resolver(
            Net::DNS::Resolver->new(
                nameservers => $self->forward_nameserver(),
                recurse     => 1,
                debug       => 0
            ));
    }
    my $question = $self->_external_resolver->query($qname, $qtype, $qclass);

    if (defined $question) {
        @ans = $question->answer();
        $self->_diag("Answer(FWD) " . $_->string) for @ans;
        $rcode = "NOERROR";
    }
    else {
        $rcode = "NXDOMAIN";
    }

    return ($rcode, @ans);
}

sub _start {
    my $self = shift;

    die "Invalid policy supplied for DNS server. Policy can be 'SINK' or 'FORWARD'"
      unless ($self->policy eq "FORWARD" or $self->policy eq "SINK");

    $self->_diag("Global Policy is " . $self->policy());

    my $sinkhole = backend::component::dnsserver::dnsresolver->new(ref($self->record_table) eq 'HASH' ? %{$self->record_table} : ());
    my $ns = Net::DNS::Nameserver->new(
        LocalPort    => $self->listening_port,
        LocalAddr    => [$self->listening_address],
        ReplyHandler => sub {
            my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
            my ($rcode, @ans, @auth, @add);

            $self->_diag("Intercepting request for $qname");

            # If the specified domain needs to be forwarded (FORWARD in the record_table), handle it first
            if ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "FORWARD") {

                $self->_diag("Rule-based forward for $qname");

                ($rcode, @ans) = $self->_forward_resolve($qname, $qtype, $qclass);

                $rcode = "SERVFAIL" if $rcode eq "NXDOMAIN";    # fail softly, so client will try with next dns server instead of giving up.

                return ($rcode, \@ans);
            }
            # If the domain instead needs to be dropped, return NXDOMAIN with empty answers
            elsif ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "DROP") {
                $rcode = "NXDOMAIN";
                $self->_diag("Drop for $qname , returning $rcode");
                return ($rcode, []);
            }

            # Handle the internal name resolution with our (sinkhole) resolver
            my $question = $sinkhole->query($qname, $qtype, $qclass);

            if (defined $question) {
                @ans = $question->answer();
                $self->_diag("Answer " . $_->string) for @ans;
                $rcode = "NOERROR";
            }
            else {
                $rcode = "NXDOMAIN";
            }

            # If we had no answer from sinkhole and global policy is FORWARD, use external DNS to resolve the domain
            ($rcode, @ans) = $self->_forward_resolve($qname, $qtype, $qclass) if (@ans == 0 && $self->policy() eq "FORWARD");

            return ($rcode, \@ans,);
        },
        Verbose => 0,
    ) || die "couldn't create nameserver object\n";

    $self->_diag("Server started at " . $self->listening_address . ":" . $self->listening_port);

    if (ref($self->record_table) eq 'HASH') {
        my %record_table = %{$self->record_table};
        foreach my $k (keys %record_table) {
            $self->_diag("Table entry: $k => @{${record_table{$k}}}") if ref($record_table{$k}) eq "ARRAY";
            $self->_diag("Forward rule: $k => ${record_table{$k}}")   if ref($record_table{$k}) ne "ARRAY";
        }
    }

    $ns->main_loop;
    return $self;
}

sub start {
    my $self = shift;
    $self->code(\&_start) unless $self->code;    # Also if we do not call prepare() component will start.
    $self->backend::component::process::start;
}

1;
