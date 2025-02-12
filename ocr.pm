# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package ocr;
use Mojo::Base -strict, -signatures;
use Mojo::File 'path';
require IPC::System::Simple;

sub tesseract ($img, $area) {
    my $imgfn = 'ocr.png';
    my $txtfn = 'ocr';    # tesseract appends .txt automatically o_O
    my $txt;
    $img = $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}) if $area;
    $img->write($imgfn);
    # disable debug output, because new versions by default only reports errors and warnings
    system("tesseract $imgfn $txtfn quiet");
    $txtfn .= '.txt';
    $txt = path($txtfn)->slurp('UTF-8');
    unlink $imgfn;
    unlink $txtfn;
    return $txt;
}

1;
