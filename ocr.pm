# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package ocr;
use Mojo::Base -strict, -signatures;
use Mojo::File qw(path tempdir);
require IPC::System::Simple;

sub tesseract ($img, $area) {
    my $tempdir = tempdir();
    my $imgfn = $tempdir->child('ocr.png');
    my $txtfn = $tempdir->child('ocr');    # tesseract appends .txt automatically o_O
    my $txt;
    $img = $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}) if $area;
    $img->write($imgfn->to_string);
    # disable debug output, because new versions by default only reports errors and warnings
    system "tesseract $imgfn $txtfn quiet";
    $txtfn = $tempdir->child('ocr.txt');
    $txt = $txtfn->slurp('UTF-8');
    return $txt;
}

1;
