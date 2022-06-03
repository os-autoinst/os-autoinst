# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# wrapper around tinycv

package cv;
use Mojo::Base -strict, -signatures;
use constant BPP => 3;
use ExtUtils::testlib;

use File::Basename;
use Cwd qw(realpath);

sub init () {
    use Config;
    my $vendorlib = $Config{installvendorlib};
    my $libdir = realpath(dirname(__FILE__));
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
