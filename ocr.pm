# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package ocr;
use Mojo::Base -strict, -signatures;
require IPC::System::Simple;

sub tesseract ($img, $area) {
    my $imgfn = 'ocr.png';
    my $txtfn = 'ocr';    # tesseract appends .txt automatically o_O
    my $txt;

    if ($area) {
        $img = $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height});
    }

    $img->write($imgfn);
    # disable debug output, because new versions by default only reports errors and warnings
    system("tesseract $imgfn $txtfn quiet");
    $txtfn .= '.txt';
    open(my $fh, '<:encoding(UTF-8)', $txtfn);
    local $/;
    $txt = <$fh>;
    close $fh;
    unlink $imgfn;
    unlink $txtfn;
    return $txt;
}

1;
