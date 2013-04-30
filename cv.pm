# wrapper around tinycv

package cv;
use strict;
use warnings;
use constant BPP=>3;
use ExtUtils::testlib;

use File::Basename;

my $libdir = dirname(__FILE__);

unless(-e "$libdir/ppmclibs/Makefile") {
        $|=1;
        print "Building C-libraries...\n";
        system("cd $libdir/ppmclibs ; perl Makefile.PL");
}

# do not call make from make
if (!defined $ENV{MAKELEVEL}) {
  system("make", "-C", "$libdir/ppmclibs", "-s") == 0 || die 'make failed';
}

BEGIN {
  my $libdir = dirname(__FILE__);
  unshift(@INC, "$libdir/ppmclibs/blib/arch");
  unshift(@INC, "$libdir/ppmclibs/blib/lib");
}

require tinycv;
eval{ require tinycv; };

1;
