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

package ocr;
use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

our $gocrbin = "/usr/bin/gocr";
if (!-x $gocrbin) { $gocrbin = undef }

# input: image ref
# TODO get_ocr is nowhere called, also not in opensuse tests or openQA, delete?
sub get_ocr {
    my $ppm        = shift;
    my $gocrparams = shift || "";
    my @ocrrect    = @{$_[0]};
    if (!$gocrbin || !@ocrrect) { return "" }
    if (@ocrrect != 4) { return " ocr: bad rect" }
    return unless $ppm;
    my $ppm2 = $ppm->copyrect(@ocrrect);
    if (!$ppm2) { return "" }
    my $tempname = "ocr.$$-" . time . rand(10000) . ".ppm";
    $ppm2->write($tempname) or return " ocr error writing $tempname";

    # init DB file:
    if (!-e "db/db.lst") {
        mkdir "db";
        open(my $fd, ">", "db/db.lst");
        close $fd;
    }

    open(my $pipe, '-|', "$gocrbin -l 128 -d 0 $gocrparams $tempname");
    local $/;
    my $ocr = <$pipe>;
    close($pipe);
    unlink $tempname;
    return $ocr;
}

# input: image ref, area
# FIXME: pass options
# FIXME: write C library bindings instead of system()
sub tesseract {
    my ($img, $area) = @_;
    my $imgfn = 'ocr.png';
    my $txtfn = 'ocr';       # tesseract appends .txt automatically o_O
    my $txt;

    if ($area) {
        $img = $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height});
    }

    $img->write($imgfn);
    system('tesseract', $imgfn, $txtfn);
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
# vim: set sw=4 et:
