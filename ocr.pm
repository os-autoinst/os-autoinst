# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2020 SUSE LLC
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
use Mojo::Base -strict;
require IPC::System::Simple;
use autodie ':all';

# input: image ref, area
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
