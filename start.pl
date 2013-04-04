#!/usr/bin/perl -w
#
# Start up the VM and start feeding it the distribution test script
# specified in the DISTRI environment variable.
#

use strict;
use bmwqemu;

# Sanity checks
die "DISTRI environment variable not set. unknown OS?" if !defined $ENV{DISTRI} && !defined $ENV{CASEDIR};
die "No scripts in $ENV{CASEDIR}" if ! -e "$ENV{CASEDIR}";
die "ISO environment variable not set" if !defined $ENV{ISO};

my $init=1;
alarm (7200+($ENV{UPGRADE}?3600:0)); # worst case timeout

# init part
$ENV{BACKEND}||="qemu";
init_backend($ENV{BACKEND});
if($init) {
	open(my $fd, ">os-autoinst.pid"); print $fd "$$\n"; close $fd;
	if(!bmwqemu::alive) {
		start_vm or die $@;
		sleep 3; # wait until BIOS is gone
	}
}
my $size=-s $ENV{ISO}; diag("iso_size=$size");
require "inst/screenshot.pm";

require Carp;
require Carp::Always;

# Load the main.pm from the casedir checked by the sanity checks above
require "$ENV{CASEDIR}/main.pm";

# this is only for still getting screenshots while
# all testscripts would have been already run
for(1..6000) { # time to let install work
	sleep 1;
}

