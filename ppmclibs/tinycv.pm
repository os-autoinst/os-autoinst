package tinycv;

use strict;
use warnings;

require Exporter;
require DynaLoader;

our @ISA = qw(Exporter DynaLoader);
our @EXPORT = qw();

our $VERSION = '1.0';

bootstrap tinycv $VERSION;

package tinycv::Image;

sub search_($$) {
    my $self = shift;
    my $needle = shift;

    my ($sim, $xmatch, $ymatch, $d1, $d2) = $self->search_needle($needle->glob());
    printf "MATCH(%.2f): $xmatch $ymatch\n", $sim;
    if ($sim >= $needle->{match} - 0.05) {
	return 1;
    }
    return 0;
}

sub search($) {
    my $self = shift;
    my $needle = shift;
    if (ref($needle) eq "ARRAY") {
	for my $n (@$needle) {
	    return 1 if ($self->search_($n));
	}
    } else {
	return $self->search_($needle);
    }
}

1;
