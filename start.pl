#!/usr/bin/perl -w
#
# Start up the VM and start feeding it the distribution test script
# specified in the DISTRI environment variable.
#

use strict;
use threads;

BEGIN {
    my ($wd) = $0 =~ m-(.*)/-;
    $wd ||= '.';
    unshift @INC, "$wd";
}

use bmwqemu;
use needle;
use autotest;
use Data::Dumper;

bmwqemu::init();

my $envs = bmwqemu::load_envs();

# Sanity checks
die "DISTRI environment variable not set. unknown OS?" if !defined $envs->{DISTRI} && !defined $envs->{CASEDIR};
die "No scripts in $envs->{CASEDIR}"                      if !-e "$envs->{CASEDIR}";

bmwqemu::clean_control_files();

bmwqemu::save_results();

my $init = 1;
alarm( 7200 + ( $envs->{UPGRADE} ? 3600 : 0 ) );    # worst case timeout

# all so ugly ...
sub signalhandler {

    # do not start a race about the results between the threads

    my $sig = shift;
    diag("signalhandler $$: got $sig");
    if ($autotest::running) {
        $autotest::running->fail_if_running();
        $autotest::running = undef;
    }
    if ( threads->tid() == 0 ) {
        bmwqemu::save_results();
        stop_vm();
    }
    else {
        print STDERR "bug!? signal not received in main thread\n";
    }
    exit(1);
}

$SIG{ALRM} = \&signalhandler;
$SIG{TERM} = \&signalhandler;
$SIG{HUP}  = \&signalhandler;

# init part
$envs->{BACKEND} ||= "qemu";
bmwqemu::save_envs($envs);
init_backend( $envs->{BACKEND} );

if ($init) {
    open( my $fd, ">os-autoinst.pid" );
    print $fd "$$\n";
    close $fd;
    if ( !bmwqemu::alive ) {
        start_vm or die $@;
        sleep 3;    # wait until BIOS is gone
    }
}

our $screenshotthr = require "inst/screenshot.pm";

require Carp;
require Carp::Always;

my $r = 0;
eval {
    # Load the main.pm from the casedir checked by the sanity checks above
    require "$envs->{CASEDIR}/main.pm";

    needle::init();

    autotest::runalltests();
};
if ($@) {
    warn $@;
    $r = 1;
}
else {
    # this is only for still getting screenshots while
    # all testscripts would have been already run
    sleep 10;
}

diag "done" unless $r;
diag "FAIL" if $r;

$SIG{ALRM} = 'IGNORE';    # ignore ALRM so the readthread doesn't kill us here

stop_vm();

$screenshotthr->join();

# mark it as no longer working
delete $ENV{WORKERID};

# Write JSON result
bmwqemu::save_results();

exit $r;
# vim: set sw=4 et:
