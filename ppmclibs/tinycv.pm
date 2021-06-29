# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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

package tinycv;

use Mojo::Base -strict, -signatures;

use bmwqemu 'fctwarn';
use File::Basename;
use Math::Complex 'sqrt';
require Exporter;
require DynaLoader;

our @ISA    = qw(Exporter DynaLoader);
our @EXPORT = qw();

our $VERSION = '1.0';

bootstrap tinycv $VERSION;

package tinycv::Image;

use Mojo::Base -strict, -signatures;

sub mean_square_error ($areas) {
    my $mse = 0.0;
    my $err;

    for my $area (@$areas) {
        $err = 1 - $area->{similarity};
        $mse += $err * $err;
    }
    return $mse / scalar @$areas;
}

# returns hash with match hinformation
# {
#   ok => INT(1,0), # 1 if all areas matched
#   area = [
#     { x => INT, y => INT, w => INT, h => INT,
#       similarity => FLOAT,
#       result = STRING('ok', 'fail'),
#     }
#   ]
# }
sub search_ ($self, $needle, $threshold, $search_ratio, $stopwatch) {
    $threshold    ||= 0.0;
    $search_ratio ||= 0.0;
    my ($sim,     $xmatch, $ymatch);
    my (@exclude, @match,  @ocr);

    return unless $needle;

    my $needle_image = $needle->get_image;
    unless ($needle_image) {
        bmwqemu::fctwarn("skipping $needle->{name}: missing PNG");
        return undef;
    }
    $stopwatch->lap("**++ search__: get image") if $stopwatch;

    my $img = $self;
    for my $area (@{$needle->{area}}) {
        push @exclude, $area if $area->{type} eq 'exclude';
        push @match,   $area if $area->{type} eq 'match';
        push @ocr,     $area if $area->{type} eq 'ocr';
    }

    if (@exclude) {
        $img = $self->copy;
        for my $exclude_area (@exclude) {
            $img->replacerect(@{$exclude_area}{qw(xpos ypos width height)});
            $stopwatch->lap("**++-- search__: rectangle replacement") if $stopwatch;
        }
        $stopwatch->lap("**++ search__: areas exclusion") if $stopwatch;
    }
    my $ret = {ok => 1, needle => $needle, area => []};
    for my $area (@match) {
        my $margin = int($area->{margin} + $search_ratio * (1024 - $area->{margin}));

        ($sim, $xmatch, $ymatch) = $img->search_needle($needle_image, $area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}, $margin);

        $stopwatch->lap("**++ tinycv::search_needle $area->{width}x$area->{height} + $margin @ $area->{xpos}x$area->{ypos}") if $stopwatch;
        my $ma = {
            similarity => $sim,
            x          => $xmatch,
            y          => $ymatch,
            w          => $area->{width},
            h          => $area->{height},
            result     => 'ok',
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
            $ret->{ok}    = 0;
        }
        push @{$ret->{area}}, $ma;
    }

    $ret->{error} = mean_square_error($ret->{area});
    if ($ret->{ok}) {
        for my $ocr_area (@ocr) {
            $ret->{ocr} ||= [];
            my $ocr = ocr::tesseract($img, $ocr_area);
            push @{$ret->{ocr}}, $ocr;
        }
        $stopwatch->lap("**++ ocr::tesseract: $needle->{name}") if $stopwatch;
    }
    return $ret;
}

# bigger OK is better (0/1)
# smaller error is better if not OK (0 perfect, 1 totally off)
# if match is equal quality prefer workaround needle to non-workaround
# the name doesn't matter, but we prefer alphabetic order
sub cmp_by_error_type_ {
    ## no critic ($a/$b outside of sort block)
    my $okay = $b->{ok} <=> $a->{ok};
    return $okay if $okay;
    my $error = $a->{error} <=> $b->{error};
    return $error if $error;
    return -1     if ($a->{needle}->has_property('workaround') && !$b->{needle}->has_property('workaround'));
    return 1      if ($b->{needle}->has_property('workaround') && !$a->{needle}->has_property('workaround'));
    return $a->{needle}->{name} cmp $b->{needle}->{name};

    ## use critic

}


# in scalar context return found info or undef
# in array context returns array with two elements. First element is best match
# or undefined, second element are candidates that did not match.
sub search ($self, $needle, $threshold, $search_ratio, $stopwatch) {
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
            return (undef,  [$found]);
        }
        return unless $found->{ok};
        return $found;
    }
}

sub write_with_thumbnail ($self, $filename) {
    $self->write($filename);

    my $thumb = $self->scale($self->xres() * 45 / $self->yres(), 45);
    my $dir   = File::Basename::dirname($filename) . "/.thumbs";
    my $base  = File::Basename::basename($filename);

    mkdir($dir);
    $thumb->write("$dir/$base");
}

1;
