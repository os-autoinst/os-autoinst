# wrapper around tinycv

package cv;
use strict;
use warnings;
use constant BPP=>3;
use ExtUtils::testlib;

use File::Basename;

BEGIN {
	my $libdir = dirname(__FILE__);
	my @s = stat("$libdir/ppmclibs/blib/lib/tinycv.pm");
	unless(@s && -e "$libdir/ppmclibs/tinycv.pm" && $s[7] == (stat(_))[7]) {
		$|=1;
		print STDERR "### Please build the tinycv bindings first:\n";
		print STDERR "cd $libdir/ppmclibs ; perl Makefile.PL\n" unless -e "$libdir/ppmclibs/Makefile";
		print STDERR "make -C $libdir/ppmclibs\n";
		die("tinycv outdated");
	}

	unshift(@INC, "$libdir/ppmclibs/blib/arch");
	unshift(@INC, "$libdir/ppmclibs/blib/lib");
}

require tinycv;

1;
