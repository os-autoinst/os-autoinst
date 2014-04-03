package ocr;
use strict;
use warnings;

our $gocrbin = "/usr/bin/gocr";
if ( !-x $gocrbin ) { $gocrbin = undef }

# input: image ref
sub get_ocr($$@) {
    my $ppm        = shift;
    my $gocrparams = shift || "";
    my @ocrrect    = @{ $_[0] };
    if ( !$gocrbin || !@ocrrect ) { return "" }
    if ( @ocrrect != 4 ) { return " ocr: bad rect" }
    return unless $ppm;
    my $ppm2 = $ppm->copyrect(@ocrrect);
    if ( !$ppm2 ) { return "" }
    my $tempname = "ocr.$$-" . time . rand(10000) . ".ppm";
    $ppm2->write($tempname) or return " ocr error writing $tempname";

    # init DB file:
    if ( !-e "db/db.lst" ) {
        mkdir "db";
        open( my $fd, ">db/db.lst" );
        close $fd;
    }

    open( my $pipe, "$gocrbin -l 128 -d 0 $gocrparams $tempname |" ) or return "failed to exec $gocrbin: $!";
    local $/;
    my $ocr = <$pipe>;
    close($pipe);
    unlink $tempname;
    return $ocr;
}

# input: image ref, area
# FIXME: pass options
# FIXME: write C library bindings instead of system()
sub tesseract($;$$) {
    my $img   = shift;
    my $area  = shift;
    my $imgfn = 'ocr.png';
    my $txtfn = 'ocr';       # tesseract appends .txt automatically o_O
    my $txt;

    if ($area) {
        $img = $img->copyrect( $area->{'xpos'}, $area->{'ypos'}, $area->{'width'}, $area->{'height'} );
    }

    $img->write($imgfn);
    if ( system( 'tesseract', $imgfn, $txtfn ) == 0 ) {
        $txtfn .= '.txt';
        if ( open( my $fh, '<:encoding(UTF-8)', $txtfn ) ) {
            local $/;
            $txt = <$fh>;
            close $fh;
        }
    }
    unlink $imgfn;
    unlink $txtfn;
    return $txt;
}

1;
# vim: set sw=4 et:
