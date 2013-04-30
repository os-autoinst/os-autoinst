package tinycv;

use strict;
use warnings;

use bmwqemu;

require Exporter;
require DynaLoader;

our @ISA = qw(Exporter DynaLoader);
our @EXPORT = qw();

our $VERSION = '1.0';

bootstrap tinycv $VERSION;

package tinycv::Image;

# returns area of last matched
sub search_($$;$) {
    my $self = shift;
    my $needle = shift;
    my $threshold = shift || 0.005;
    my ($sim, $xmatch, $ymatch, $d1, $d2);
    my (@exclude, @match, @ocr);

    return undef unless $needle;

    my $img = $self->copy;
    for my $a (@{$needle->{'area'}}) {
	    push @exclude, $a if $a->{'type'} eq 'exclude';
	    push @match, $a if $a->{'type'} eq 'match';
	    push @ocr, $a if $a->{'type'} eq 'ocr';
    }

    for my $a (@exclude) {
	    $img->replacerect($a->{'xpos'}, $a->{'ypos'},
			      $a->{'width'}, $a->{'height'});
    }
    my $area;

    my $lastarea;
    for my $area (@match) {
	    my $c = $needle->get_image($area);
	    ($sim, $xmatch, $ymatch, $d1, $d2) = $img->search_needle($c);
	    bmwqemu::diag(sprintf("MATCH(%s:%.2f): $xmatch $ymatch", $needle->{name}, $sim));
	    my $m = ($area->{match} || 100) / 100;
	    if ($sim < $m - $threshold) {
		    return undef;
	    }
	    $lastarea = $area;
    }

    my $ret = {
	    similarity => $sim, x => $xmatch, y => $ymatch,
	    w => $lastarea->{'width'},
	    h => $lastarea->{'height'},
	    needle => $needle
	  };

    for my $a (@ocr) {
	    $ret->{'ocr'} ||= [];
	    my $ocr = ocr::tesseract($img, $a);
	    push @{$ret->{'ocr'}}, $ocr;
    }

    return $ret;
}

sub search($;$) {
    my $self = shift;
    my $needle = shift;
    my $threshold = shift;
    return undef unless $needle;
    if (ref($needle) eq "ARRAY") {
	my $ret;
	# try to match all needles and return the one with the highest similarity
	for my $n (@$needle) {
	    my $found = $self->search_($n, $threshold);
	    next unless $found;
	    $ret = $found if !$ret || $ret->{'similarity'} < $found->{'similarity'};
	}
	return $ret;
    } else {
	return $self->search_($needle, $threshold);
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
