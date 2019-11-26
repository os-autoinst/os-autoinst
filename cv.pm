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

# wrapper around tinycv

package cv;
use strict;
use warnings;
use constant BPP => 3;
use ExtUtils::testlib;

use File::Basename;

sub init {
    use Config;
    my $vendorlib = $Config{installvendorlib};
    my $libdir    = dirname(__FILE__);
    # undef is substituted with $(pkglibexecdir) in
    # make install, in the following line. See Makefile.am
    my $sysdir = undef;
    return if ($sysdir && $libdir eq $sysdir);
    my @s = stat("$libdir/ppmclibs/blib/lib/tinycv.pm");
    unless (@s && -e "$libdir/ppmclibs/tinycv.pm" && $s[7] == (stat(_))[7]) {
        $| = 1;
        print STDERR "### Please build the tinycv bindings first:\n";
        print STDERR "cd $libdir/ppmclibs ; perl Makefile.PL\n" unless -e "$libdir/ppmclibs/Makefile";
        print STDERR "make -C $libdir/ppmclibs\n";
        die("tinycv outdated");
    }

    unshift(@INC, "$libdir/ppmclibs/blib/arch");
    unshift(@INC, "$libdir/ppmclibs/blib/lib");
}

1;
