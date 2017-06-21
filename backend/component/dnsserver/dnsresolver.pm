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

package backend::component::dnsserver::dnsresolver;

use warnings;
use strict;
use base 'Net::DNS::Resolver';
use Net::DNS::Packet;
use Net::DNS;

use constant TRUE => 1;

sub new {
    my ($self, %options) = @_;

    $self = $self->SUPER::new(%options);
    $self->{records} = \%options;

    return $self;
}

sub send {
    my $self = shift;
    my ($domain, $class, $rr_type, $peerhost, $query, $conn) = @_;

    my $question = Net::DNS::Question->new($domain, $rr_type, $class);
    $domain  = lc($question->qname);
    $rr_type = $question->qtype;
    $class   = $question->qclass;

    $self->_reset_errorstring;

    my ($result, @answer_rrs);
    $result = 'NOERROR';

    if (defined(my $records = $self->{records})) {
        if (ref(my $rrs_for_domain = $records->{$domain}) eq 'ARRAY') {
            foreach my $rr (@$rrs_for_domain) {
                my $rr_obj = Net::DNS::RR->new($rr);
                push(@answer_rrs, $rr_obj)
                  if $rr_obj->name eq $domain
                  and $rr_obj->type eq $rr_type
                  and $rr_obj->class eq $class;
            }
        }
        ## no critic (HashKeyQuotes)
        elsif (my $sink = $records->{'*'}) {
            ## use critic
            my $rr_obj = Net::DNS::RR->new("$domain.     A   $sink");
            push(@answer_rrs, $rr_obj);
        }
    }

    return unless @answer_rrs > 0;

    my $packet = Net::DNS::Packet->new($domain, $rr_type, $class);
    $packet->header->qr(TRUE);
    $packet->header->rcode($result);
    $packet->header->aa(TRUE);
    $packet->push(answer => @answer_rrs);

    return $packet;
}

1;
