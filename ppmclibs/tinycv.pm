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

sub mean_square_error($) {
    my $areas = shift;
    my $mse   = 0.0;
    my $err;

    for my $area (@$areas) {
        $err = 1 - $area->{"similarity"};
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
sub search_($;$$) {
    my $self         = shift;
    my $needle       = shift;
    my $threshold    = shift || 0.0;
    my $search_ratio = shift || 0.0;
    my ( $sim, $xmatch, $ymatch );
    my ( @exclude, @match, @ocr );

    return undef unless $needle;

    my $img = $self->copy;
    for my $a ( @{ $needle->{'area'} } ) {
        push @exclude, $a if $a->{'type'} eq 'exclude';
        push @match,   $a if $a->{'type'} eq 'match';
        push @ocr,     $a if $a->{'type'} eq 'ocr';
    }

    for my $a (@exclude) {
        $img->replacerect( $a->{'xpos'}, $a->{'ypos'}, $a->{'width'}, $a->{'height'} );
    }

    my $ret = { ok => 1, needle => $needle, area => [] };

    for my $area (@match) {
        my $margin = int($area->{'margin'} + $search_ratio * (1024 - $area->{'margin'}));
        ( $sim, $xmatch, $ymatch ) = $img->search_needle( $needle->get_image, $area->{'xpos'}, $area->{'ypos'}, $area->{'width'}, $area->{'height'}, $margin );
        bmwqemu::diag( sprintf( "MATCH(%s:%.2f): $xmatch $ymatch [m:$margin]", $needle->{name}, $sim ) );

        my $ma = {
            similarity => $sim,
            x          => $xmatch,
            y          => $ymatch,
            w          => $area->{'width'},
            h          => $area->{'height'},
            result     => 'ok',
        };

        # A 96% match is ok for console tests. Please, if you
        # change this number consider change also the test
        # 01-test_needle and the console tests (for example, using
        # more smaller areas)

        my $m = ( $area->{'match'} || 96 ) / 100;
        #if ( $sim < 1 ) {
        #    my $needle_img = $needle->get_image($area);
        #    if ($needle_img) {
        #        my $area_img = $img->copyrect( $xmatch, $ymatch, $area->{'width'}, $area->{'height'} );
        #        $ma->{'diff'} = $area_img->absdiff($needle_img);
        #    }
        #}

        if ( $sim < $m - $threshold ) {
            $ma->{'result'} = 'fail';
            $ret->{'ok'}    = 0;
        }
        push @{ $ret->{'area'} }, $ma;
    }

    $ret->{'error'} = mean_square_error( $ret->{'area'} );

    if ( $ret->{'ok'} ) {
        for my $a (@ocr) {
            $ret->{'ocr'} ||= [];
            my $ocr = ocr::tesseract( $img, $a );
            push @{ $ret->{'ocr'} }, $ocr;
        }
    }

    return $ret;
}

# in scalar context return found info or undef
# in array context returns array with two elements. First element is best match
# or undefined, second element are candidates that did not match.
sub search($;$$) {
    my $self         = shift;
    my $needle       = shift;
    my $threshold    = shift;
    my $search_ratio = shift;
    return undef unless $needle;

    if ( ref($needle) eq "ARRAY" ) {
        my $candidates;
        my $best;

        # try to match all needles and return the one with the highest similarity
        for my $n (@$needle) {
            my $found = $self->search_( $n, $threshold, $search_ratio );
            next unless $found;
            if ( $found->{'ok'} ) {
                if ( !$best ) {
                    $best = $found;
                }
                elsif ( $best->{'error'} > $found->{'error'} ) {
                    push @$candidates, $best;
                    $best = $found;
                }
            }
            else {
                push @$candidates, $found;
            }
        }
        if (wantarray) {
            return ( $best, $candidates );
        }
        else {
            return $best;
        }
    }
    else {
        my $found = $self->search_( $needle, $threshold, $search_ratio );
        return undef unless $found;
        if (wantarray) {
            return ( $found, undef ) if ( $found->{'ok'} );
            return ( undef, [$found] );
        }
        return undef unless $found->{'ok'};
        return $found;
    }
}

sub write_with_thumbnail($$) {
    my $self     = shift;
    my $filename = shift;

    $self->write($filename);

    my $thumb = $self->scale( $self->xres() * 120 / $self->yres(), 120 );
    my $dir = File::Basename::dirname($filename) . "/.thumbs";
    my $base = File::Basename::basename($filename);

    mkdir($dir);
    $thumb->write("$dir/$base");
}

1;

# vim: set sw=4 et:
