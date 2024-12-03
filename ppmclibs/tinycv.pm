# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2023 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package tinycv;

=head1 tinycv

Package providing matching functionality.

=cut

use Mojo::Base -strict, -signatures;

use bmwqemu 'fctwarn';
use File::Basename;
use Math::Complex 'sqrt';
require Exporter;
require DynaLoader;

our @ISA = qw(Exporter DynaLoader);
our @EXPORT = qw();

our $VERSION = '1.0';

bootstrap tinycv $VERSION;

package tinycv::Image;

use bmwqemu 'fctwarn';
use Mojo::Base -strict, -signatures;
use ocr;
our $LEVENSHTEIN = eval {
    require Text::Levenshtein;
    Text::Levenshtein->import('distance');
    1;
} || 0;

sub mean_square_error ($areas) {
    my $mse = 0.0;
    my $err;

    for my $area (@$areas) {
        $err = 1 - $area->{similarity};
        $mse += $err * $err;
    }
    return $mse / scalar @$areas;
}

=head2 overlap_lvl

Returns the level of lap of area2 over area1.

=head3 Params

=over

=item *

area1 | A reference to a hash-like object representing an area

=item *

area2 | A reference to a hash-like object representing an area

=back

=head3 returns

=over

=item *

i in [0, 15] | i is level of overlap of area2 over area1 where:

=over

=item *

i:= 0 for: area2 does not overlap area1

=item *

i:= 1 for: area2 does overlap area1 completely

=item *

i:= 2 for: area2 does overlap the top edge of area1

=item *

i:= 3 for: area2 does overlap the bottom edge of area1

=item *

i:= 4 for: area2 does overlap the left edge of area1

=item *

i:= 5 for: area2 does overlap the right edge of area1

=item *

i:= 6 for: area2 splits area1 horizontally

=item *

i:= 7 for: area2 splits area1 vertically

=item *

i:= 8 for: area2 does overlap area1 on the top left corner

=item *

i:= 9 for: area2 does overlap area1 on the top right corner

=item *

i:= 10 for: area2 does overlap area1 on the bottom left corner

=item *

i:= 11 for: area2 does overlap area1 on the bottom right corner

=item *

i:= 12 for: area2 overlaps parts of area1's top edge

=item *

i:= 13 for: area2 overlaps parts of area1's bottom edge

=item *

i:= 14 for: area2 overlaps parts of area1's left edge

=item *

i:= 15 for: area2 overlaps parts of area1's right edge

=back

=back

=cut

sub overlap_lvl ($area1, $area2) {

    # y=0 at top of screen, x=0 on the left of the screen
    my $a1top = $area1->{ypos};
    my $a1bot = $area1->{ypos} + $area1->{height};
    my $a1left = $area1->{xpos};
    my $a1right = $area1->{xpos} + $area1->{width};
    my $a2top = $area2->{ypos};
    my $a2bot = $area2->{ypos} + $area2->{height};
    my $a2left = $area2->{xpos};
    my $a2right = $area2->{xpos} + $area2->{width};

    return 1 if ($a2bot >= $a1bot) && ($a2top <= $a1top)
      && ($a2left <= $a1left) && ($a2right >= $a1right);
    return 2 if ($a2bot < $a1bot) && ($a2top <= $a1top)
      && ($a2left <= $a1left) && ($a2right >= $a1right)
      && ($a2bot > $a1top);
    return 3 if ($a2bot >= $a1bot) && ($a2top > $a1top)
      && ($a2left <= $a1left) && ($a2right >= $a1right)
      && ($a2top < $a1bot);
    return 4 if ($a2bot >= $a1bot) && ($a2top <= $a1top)
      && ($a2left <= $a1left) && ($a2right < $a1right)
      && ($a2right > $a1left);
    return 5 if ($a2bot >= $a1bot) && ($a2top <= $a1top)
      && ($a2left > $a1left) && ($a2right >= $a1right)
      && ($a2left < $a1right);
    return 6 if ($a2bot < $a1bot) && ($a2top > $a1top)
      && ($a2left <= $a1left) && ($a2right >= $a1right);
    return 7 if ($a2bot >= $a1bot) && ($a2top <= $a1top)
      && ($a2left > $a1left) && ($a2right < $a1right);
    return 8 if ($a2bot < $a1bot) && ($a2top <= $a1top)
      && ($a2left <= $a1left) && ($a2right < $a1right)
      && ($a2right > $a1left) && ($a2bot > $a1top);
    return 9 if ($a2bot < $a1bot) && ($a2top <= $a1top)
      && ($a2left > $a1left) && ($a2right >= $a1right)
      && ($a2left < $a1right) && ($a2bot > $a1top);
    return 10 if ($a2bot >= $a1bot) && ($a2top > $a1top)
      && ($a2left <= $a1left) && ($a2right < $a1right)
      && ($a2right > $a1left) && ($a2top < $a1bot);
    return 11 if ($a2bot >= $a1bot) && ($a2top > $a1top)
      && ($a2left > $a1left) && ($a2right >= $a1right)
      && ($a2left < $a1right) && ($a2top < $a1bot);
    return 12 if ($a2bot < $a1bot) && ($a2top <= $a1top)
      && ($a2left > $a1left) && ($a2right < $a1right)
      && ($a2bot > $a1top);
    return 13 if ($a2bot >= $a1bot) && ($a2top > $a1top)
      && ($a2left > $a1left) && ($a2right < $a1right)
      && ($a2top < $a1bot);
    return 14 if ($a2bot < $a1bot) && ($a2top > $a1top)
      && ($a2left <= $a1left) && ($a2right < $a1right)
      && ($a2right > $a1left);
    return 15 if ($a2bot < $a1bot) && ($a2top > $a1top)
      && ($a2left > $a1left) && ($a2right >= $a1right)
      && ($a2left < $a1right);
    return 0;
}

=head2 search_

Function matching the image of this object with a given needle. The root
of the grid is placed on the left upper corner. The x-axis escalates to the
right. The y-axis escalates to the bottom.

=head3 Params

=over

=item *

self - A reference to an object of class tinycv::Image.

=item *

needle - A reference to an object of class needle.

=item *

threshold - f in [0.0, 1.0] | f is subtrahend to hardcoded default
minimum similarity asked for successful matches. Higher values reduce required
similarity. DEFAULT:= 0.0.

=item *

search_ratio - f in [0.0, INF) | A multiplier for the margin around the area
of interest to search for a needle image. Not applied to OCR areas
because the search ratio for text matching (OCR) is implicitly determined by
the corresponding OCR area defined in the needle. DEFAULT:= 0.0.

=item *

stopwatch - A reference to an object of class OpenQA::Benchmark::Stopwatch.
(Optional parameter for benchmarking)

=back

=head3 returns

A hash with following components:

=over

=item *

ok => b in {1, 0} | b:= 1 if the areas matched sufficiently; b:= 0 otherwise.

=item *

needle => needle object reference | Just the reference passed as parameter.

=item *

error => f in [0.0, 1.0] | Mean square error of matched areas.

=item *

area of object type ARRAY containing HASH objects with following components:

=over

=item *

x => i | i is position of upper left pixel of matched area on x-axis.

=item *

y => i | i is position of upper left pixel of matched area on y-axis.

=item *

w => i | i is width of the matched area in pixels.

=item *

h => i | i is height of the matched area in pixels.

=item *

similarity => f in [0.0, 1.0] | f is similarity of matched area.

=item *

result => s in {'ok', 'fail'}

=item *

(ocr_str => str | String which was found by OCR - only provided for OCR areas)

=back

=back

=cut

sub search_ ($self, $needle, $threshold, $search_ratio, $stopwatch = undef) {
    $threshold ||= 0.0;
    $search_ratio ||= 0.0;
    my ($sim, $xmatch, $ymatch, $need_ref_img);
    my (@exclude, @match, @ocr);

    unless ($needle) {
        fctwarn('Skipping due to missing needle.');
        return undef;
    }
    if (not $threshold =~ /^-?\d+\.?\d*$/ or $threshold < 0.0
        or $threshold > 1.0) {
        fctwarn('Skipping due to illegal threshold parameter value.');
        return undef;
    }
    if (not($search_ratio =~ /^-?\d+\.?\d*$/) or $search_ratio < 0.0) {
        fctwarn('Skipping due to illegal search_ratio parameter value.');
        return undef;
    }

    $need_ref_img = 0;
    for my $area (@{$needle->{area}}) {
        my $t = $area->{type};
        if ($t eq 'exclude') { push(@exclude, $area) }
        elsif ($t eq 'match') { push(@match, $area); $need_ref_img = 1 }
        elsif ($t eq 'ocr') {
            push(@ocr, $area);
        }
    }

    if (@ocr && !$LEVENSHTEIN && !ocr_installed()) {
        fctwarn("Skipping $needle->{name}: Perl Levenshtein module or OCR program are not installed.");
        return undef;
    }
    my $needle_image = $needle->get_image;
    $stopwatch->lap('**++ search__: get image') if $stopwatch;
    if (not $needle_image and $need_ref_img) {
        fctwarn("Skipping $needle->{name}: missing PNG");
        return undef;
    }

    my $img = $self;

    if (@exclude) {
        $img = $self->copy;
        for my $exclude_area (@exclude) {
            $img->replacerect(@{$exclude_area}{qw(xpos ypos width height)});
            $stopwatch->lap('**++-- search__: rectangle replacement') if $stopwatch;
        }
        $stopwatch->lap('**++ search__: areas exclusion') if $stopwatch;
    }

    my $ret = {ok => 1, needle => $needle, area => []};

    for my $area (@ocr) {

        my $refstr = $area->{refstr};

        if ($refstr =~ qr/§/) {
            fctwarn("Skipping $needle->{name}: Illegal placeholder character '\§' in refstr");
            return undef;
        }
        my $sim = 1;
        my @partareas = ({%$area});

        my $ma = {
            similarity => 1.0,
            x => $area->{xpos},
            y => $area->{ypos},
            w => $area->{width},
            h => $area->{height},
            refstr => $area->{refstr},
            result => 'ok',
        };

        if (my $click_point = $area->{click_point}) {
            $ma->{click_point} = $click_point;
        }

        for my $exclude_area (@exclude) {
            my $num_partareas = $#partareas;
            for (my $i = 0; $i <= $num_partareas; $i++) {
                my $partarea = shift @partareas;
                my $olvl = overlap_lvl($partarea, $exclude_area);

                # Not implemented: Cases >= 8 would require resynth of image bg
                if ($olvl == 0 or $olvl >= 8) {
                    push(@partareas, $partarea);
                    next;
                } elsif ($olvl == 1) {
                    # Discard area if excluded
                    next;
                }
                elsif ($olvl == 2) {
                    $partarea->{height} = ($partarea->{ypos} + $partarea->{height}) - ($exclude_area->{ypos} + $exclude_area->{height});
                    $partarea->{ypos} = $exclude_area->{ypos} + $exclude_area->{height};
                }
                elsif ($olvl == 3) {
                    $partarea->{height} = $exclude_area->{ypos} - $partarea->{ypos};
                }
                elsif ($olvl == 4) {
                    $partarea->{width} = ($partarea->{xpos} + $partarea->{width}) - ($exclude_area->{xpos} + $exclude_area->{width});
                    $partarea->{xpos} = $exclude_area->{xpos} + $exclude_area->{width};
                }
                elsif ($olvl == 5) {
                    $partarea->{width} = $exclude_area->{xpos} - $partarea->{xpos};
                }
                elsif ($olvl == 6) {
                    # Split in two areas horizontally
                    my %toparea = %$partarea;
                    $toparea{height} = $exclude_area->{ypos} - $toparea{ypos};
                    push(@partareas, \%toparea);
                    my %botarea = %$partarea;
                    $botarea{height} = ($botarea{ypos} + $botarea{height}) - ($exclude_area->{ypos} + $exclude_area->{height});
                    $botarea{ypos} = $exclude_area->{ypos} + $exclude_area->{height};
                    push(@partareas, \%botarea);
                    next;
                }
                elsif ($olvl == 7) {
                    # Split in two areas vertically
                    my %leftarea = %$partarea;
                    $leftarea{width} = $exclude_area->{xpos} - $leftarea{xpos};
                    push(@partareas, \%leftarea);
                    my %rightarea = %$partarea;
                    $rightarea{width} = ($rightarea{xpos} + $rightarea{width}) - ($exclude_area->{xpos} + $exclude_area->{width});
                    $rightarea{xpos} = $exclude_area->{xpos} + $exclude_area->{width};
                    push(@partareas, \%rightarea);
                    next;
                }
                push(@partareas, $partarea);
            }
        }
        my $ocr_str = "";
        for my $partarea (@partareas) {
            my $img_area = $img->copyrect(@{$partarea}{qw(xpos ypos width height)});
            $ocr_str .= $ocr_str eq '' ? img_to_str($img_area)
              : "\n" . img_to_str($img_area);
        }
        $stopwatch->lap('**++ ocr::img_to_str') if $stopwatch;
        $ma->{ocr_str} = $ocr_str;

        my $refstr_len = length($refstr);
        my $ocr_str_len = length($ocr_str);
        my $levenshtein_dist_div = $refstr_len >= $ocr_str_len ? $refstr_len : $ocr_str_len;
        if ($#partareas != -1 && $refstr ne $ocr_str) {
            $sim = 1 - distance($refstr, $ocr_str) / $levenshtein_dist_div;
            $ma->{similarity} = $sim;
            # If you change the percentage of 90%, please check if the
            # test 39-tinycv.t requires changes as well.
            my $m = ($area->{match} || 90) / 100;
            if ($sim < $m - $threshold) {
                $ma->{result} = 'fail';
                $ret->{ok} = 0;
            }
        }
        push(@{$ret->{area}}, $ma);
    }
    for my $area (@match) {
        my $margin = int($area->{margin} + $search_ratio * (1024 - $area->{margin}));

        ($sim, $xmatch, $ymatch) = $img->search_needle($needle_image, $area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}, $margin);

        $stopwatch->lap("**++ tinycv::search_needle $area->{width}x$area->{height} + $margin @ $area->{xpos}x$area->{ypos}") if $stopwatch;
        my $ma = {
            similarity => $sim,
            x => $xmatch,
            y => $ymatch,
            w => $area->{width},
            h => $area->{height},
            result => 'ok',
        };
        if (my $click_point = $area->{click_point}) {
            $ma->{click_point} = $click_point;
        }

        # A 96% match is ok for console tests. Please, if you
        # change this number consider change also the test
        # 01-test_needle and the console tests (for example, using
        # more smaller areas)
        my $m = ($area->{match} || 96) / 100;
        if ($sim < $m - $threshold) {
            $ma->{result} = 'fail';
            $ret->{ok} = 0;
        }
        push(@{$ret->{area}}, $ma);
    }

    $ret->{error} = mean_square_error($ret->{area});
    return $ret;
}

# bigger OK is better (0/1)
# smaller error is better if not OK (0 perfect, 1 totally off)
# if match is equal quality prefer workaround needle to non-workaround
# the name doesn't matter, but we prefer alphabetic order
sub cmp_by_error_type_ {    # no:style:signatures
    ## no critic ($a/$b outside of sort block)
    my $okay = $b->{ok} <=> $a->{ok};
    return $okay if $okay;
    my $error = $a->{error} <=> $b->{error};
    return $error if $error;
    return -1 if ($a->{needle}->has_property('workaround') && !$b->{needle}->has_property('workaround'));
    return 1 if ($b->{needle}->has_property('workaround') && !$a->{needle}->has_property('workaround'));
    return $a->{needle}->{name} cmp $b->{needle}->{name};

    ## use critic

}


# in scalar context return found info or undef
# in array context returns array with two elements. First element is best match
# or undefined, second element are candidates that did not match.
sub search ($self, $needle, $threshold = undef, $search_ratio = undef, $stopwatch = undef) {
    return unless $needle;

    $stopwatch->lap("Searching for needles") if $stopwatch;

    if (ref($needle) eq "ARRAY") {
        my @candidates;
        # try to match all needles and return the one with the highest similarity
        for my $n (@$needle) {
            my $found = $self->search_($n, $threshold, $search_ratio, $stopwatch);
            push @candidates, $found if $found;
            $stopwatch->lap("** search_: $n->{name}") if $stopwatch;
        }

        @candidates = sort cmp_by_error_type_ @candidates;
        my $best;

        if (@candidates && $candidates[0]->{ok}) {
            $best = shift @candidates;
        }
        if (wantarray) {
            return ($best, \@candidates);
        }
        else {
            return $best;
        }
    }

    else {
        my $found = $self->search_($needle, $threshold, $search_ratio, $stopwatch);
        $stopwatch->lap("** search_: single needle: $needle->{name}") if $stopwatch;
        return unless $found;
        if (wantarray) {
            return ($found, undef) if ($found->{ok});
            return (undef, [$found]);
        }
        return unless $found->{ok};
        return $found;
    }
}

sub write_with_thumbnail ($self, $filename) {
    $self->write($filename);

    my $thumb = $self->scale($self->xres() * 45 / $self->yres(), 45);
    my $dir = File::Basename::dirname($filename) . "/.thumbs";
    my $base = File::Basename::basename($filename);

    mkdir($dir);
    $thumb->write("$dir/$base");
}

1;
