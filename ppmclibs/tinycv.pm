package tinycv;

use strict;
use warnings;

use bmwqemu qw(diag);

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
sub search_($$) {
    my $self      = shift;
    my $needle    = shift;
    my $threshold = shift || 0.005;
    my ( $sim, $xmatch, $ymatch, $d1, $d2 );
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
        ( $sim, $xmatch, $ymatch, $d1, $d2 ) = $img->search_needle( $needle->get_image, $area->{'xpos'}, $area->{'ypos'}, $area->{'width'}, $area->{'height'} );
        bmwqemu::diag( sprintf( "MATCH(%s:%.2f): $xmatch $ymatch", $needle->{name}, $sim ) );

        my $ma = {
            similarity => $sim,
            x          => $xmatch,
            y          => $ymatch,
            w          => $area->{'width'},
            h          => $area->{'height'},
            result     => 'ok',
        };

        # A 96.9% match is ok for console tests. Please, if you
        # change this number consider change also the test
        # 01-test_needle and the console tests (for example, using
        # more smaller areas)

        my $m = ( $area->{match} || 96.6 ) / 100;
        if ( $sim < 1 ) {
            my $needle_img = $needle->get_image($area);
            if ($needle_img) {
                my $area_img = $img->copyrect( $xmatch, $ymatch, $area->{'width'}, $area->{'height'} );
                $ma->{'diff'} = $area_img->absdiff($needle_img);
            }
        }

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
sub search($;$) {
    my $self      = shift;
    my $needle    = shift;
    my $threshold = shift;
    return undef unless $needle;
    if ( ref($needle) eq "ARRAY" ) {
        my $candidates;
        my $best;

        # try to match all needles and return the one with the highest similarity
        for my $n (@$needle) {
            my $found = $self->search_( $n, $threshold );
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
        my $found = $self->search_( $needle, $threshold );
        return undef unless $found;
        if (wantarray) {
            return ( $found, undef ) if ( $found->{'ok'} );
            return ( undef, [$found] );
        }
        return undef unless $found->{'ok'};
        return $found;
    }
}

sub write_optimized($$) {
    my $self     = shift;
    my $filename = shift;
    $self->write($filename);

    # TODO make a thread for running optipng one after the other (Thread::Queue)
    system( "optipng", "-quiet", $filename );
}

1;

# Local Variables:
# tab-width: 8
# cperl-indent-level: 8
# End:
# vim: set sw=4 et:
