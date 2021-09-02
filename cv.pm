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

# wrapper around tinycv

package cv;
use Mojo::Base -strict;
use constant BPP => 3;
use ExtUtils::testlib;

use File::Basename;

sub init {
    use Config;
    my $vendorlib = $Config{installvendorlib};
    my $libdir    = dirname(__FILE__);
    # undef is substituted at install time, see CMakeLists.txt
    my $sysdir = undef;
    return if ($sysdir && $libdir eq $sysdir);
    my @s = stat("$libdir/ppmclibs/blib/lib/tinycv.pm");
    unless (@s && -e "$libdir/ppmclibs/tinycv.pm" && $s[7] == (stat(_))[7]) {
        $| = 1;
        print STDERR "### Please build the tinycv bindings first (see os-autoinst's README)\n";
        die("tinycv outdated");
    }

    unshift(@INC, "$libdir/ppmclibs/blib/arch");
    unshift(@INC, "$libdir/ppmclibs/blib/lib");
}

1;
