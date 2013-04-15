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

# returns area of last matched
sub search_($$) {
    my $self = shift;
    my $needle = shift;
    my ($sim, $xmatch, $ymatch, $d1, $d2);

    for my $area (@{$needle->{'include'}}) {
	($sim, $xmatch, $ymatch, $d1, $d2) = $self->search_needle($needle->get_image($area));
	printf "MATCH(%s:%.2f): $xmatch $ymatch\n", $needle->{name}, $sim;
	if ($sim < $area->{match} - 0.005) {
	    return undef
	}
    }
    return { similarity => $sim, x => $xmatch, y => $ymatch,
	    w => $needle->{'include'}->[-1]->{'width'},
	    h => $needle->{'include'}->[-1]->{'height'},
	    needle => $needle };
}

sub search($) {
    my $self = shift;
    my $needle = shift;
    return undef unless $needle;
    if (ref($needle) eq "ARRAY") {
	for my $n (@$needle) {
	    my $ret = $self->search_($n);
	    return $ret if $ret;
	}
    } else {
	return $self->search_($needle);
    }
}

sub write_optimized($$) {
	my $self = shift;
	my $filename = shift;
	$self->write($filename);
	# TODO make a thread for running optipng one after the other (Thread::Queue)
	system("optipng", "-quiet", $filename);
}

1;

# Local Variables:
# tab-width: 8
# cperl-indent-level: 8
# End:
