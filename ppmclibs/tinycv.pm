# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

use strict;
use warnings;

use bmwqemu qw(diag);

use File::Basename;

require Exporter;
require DynaLoader;

our @ISA    = qw(Exporter DynaLoader);
our @EXPORT = qw();

our $VERSION = '1.0';

bootstrap tinycv $VERSION;

package tinycv::Image;

sub mean_square_error {
    my ($areas) = @_;
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
sub search_ {
    my ($self, $needle, $threshold, $search_ratio) = @_;
    $threshold    ||= 0.0;
    $search_ratio ||= 0.0;
    my ($sim,     $xmatch, $ymatch);
    my (@exclude, @match,  @ocr);

    return unless $needle;

    my $img = $self;
    for my $a (@{$needle->{area}}) {
        push @exclude, $a if $a->{type} eq 'exclude';
        push @match,   $a if $a->{type} eq 'match';
        push @ocr,     $a if $a->{type} eq 'ocr';
    }

    if (@exclude) {
        $img = $self->copy;
        for my $a (@exclude) {
            $img->replacerect($a->{xpos}, $a->{ypos}, $a->{width}, $a->{height});
        }
    }

    my $ret = {ok => 1, needle => $needle, area => []};

    for my $area (@match) {
        my $margin = int($area->{margin} + $search_ratio * (1024 - $area->{margin}));
        ($sim, $xmatch, $ymatch) = $img->search_needle($needle->get_image, $area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}, $margin);

        my $ma = {
            similarity => $sim,
            x          => $xmatch,
            y          => $ymatch,
            w          => $area->{width},
            h          => $area->{height},
            result     => 'ok',
        };

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
    bmwqemu::diag(sprintf("MATCH(%s:%.2f)", $needle->{name}, 1 - $ret->{error}));

    if ($ret->{ok}) {
        for my $a (@ocr) {
            $ret->{ocr} ||= [];
            my $ocr = ocr::tesseract($img, $a);
            push @{$ret->{ocr}}, $ocr;
        }
    }

    return $ret;
}

# bigger OK is better (0/1)
# smaller error is better if not OK (0 perfect, 1 totally off)
# the name doesn't matter, but we prefer alphabetic order
sub cmp_by_error_ {
    my $okay = $b->{ok} <=> $a->{ok};
    return $okay if $okay;
    my $error = $a->{error} <=> $b->{error};
    return $error if $error;
    return $a->{needle}->{name} cmp $b->{needle}->{name};
}


# in scalar context return found info or undef
# in array context returns array with two elements. First element is best match
# or undefined, second element are candidates that did not match.
sub search {
    my ($self, $needle, $threshold, $search_ratio) = @_;
    return unless $needle;

    if (ref($needle) eq "ARRAY") {
        my @candidates;

        # try to match all needles and return the one with the highest similarity
        for my $n (@$needle) {
            my $found = $self->search_($n, $threshold, $search_ratio);
            push @candidates, $found if $found;
        }

        @candidates = sort cmp_by_error_ @candidates;
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
        my $found = $self->search_($needle, $threshold, $search_ratio);
        return unless $found;
        if (wantarray) {
            return ($found, undef) if ($found->{ok});
            return (undef, [$found]);
        }
        return unless $found->{ok};
        return $found;
    }
}

sub write_with_thumbnail {
    my ($self, $filename) = @_;

    $self->write($filename);

    my $thumb = $self->scale($self->xres() * 120 / $self->yres(), 120);
    my $dir   = File::Basename::dirname($filename) . "/.thumbs";
    my $base  = File::Basename::basename($filename);

    mkdir($dir);
    $thumb->write("$dir/$base");
}

1;

# vim: set sw=4 et:
