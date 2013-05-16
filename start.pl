#!/usr/bin/perl -w
#
# Start up the VM and start feeding it the distribution test script
# specified in the DISTRI environment variable.
#

use strict;
use threads;

BEGIN {
  my ($wd) = $0 =~ m-(.*)/- ;
  $wd ||= '.';
  unshift @INC,  "$wd";
}

use bmwqemu;
use needle;
use autotest;
use bmwrpc;

# Sanity checks
die "DISTRI environment variable not set. unknown OS?" if !defined $ENV{DISTRI} && !defined $ENV{CASEDIR};
die "No scripts in $ENV{CASEDIR}" if ! -e "$ENV{CASEDIR}";
die "ISO environment variable not set" if !defined $ENV{ISO};

needle::init("$scriptdir/distri/$ENV{DISTRI}/needles") if ($scriptdir && $ENV{DISTRI});

my $init=1;
alarm (7200+($ENV{UPGRADE}?3600:0)); # worst case timeout

# init part
$ENV{BACKEND}||="qemu";
init_backend($ENV{BACKEND});

# all so ugly ...
$SIG{ALRM} = sub {
	print "got SIGALRM\n";
	if ($autotest::running) {
		$autotest::running->fail_if_running();
		$autotest::running = undef;
	}
	autotest::save_results();
	stop_vm();
	print STDERR "die due to SIGALARM\n";
	exit(1);
};

sub rpc()
{
	use JSON::RPC::Server::Daemon;
	print "start rpc\n";
	my $port = $ENV{'QEMUPORT'}+2;
	JSON::RPC::Server::Daemon->new(ReuseAddr => 1, LocalPort => $port)
		->dispatch({'/jsonrpc/API' => 'bmwrpc'})
		->handle();
}

my $rpcthr=threads->create(\&rpc);
$rpcthr->detach();

if($init) {
	open(my $fd, ">os-autoinst.pid"); print $fd "$$\n"; close $fd;
	if(!bmwqemu::alive) {
		start_vm or die $@;
		sleep 3; # wait until BIOS is gone
	}
}
my $size=-s $ENV{ISO}; diag("iso_size=$size");
our $screenshotthr = require "inst/screenshot.pm";

require Carp;
require Carp::Always;

my $r = 0;
eval {
	# Load the main.pm from the casedir checked by the sanity checks above
	require "$ENV{CASEDIR}/main.pm";
};
if ($@) {
	warn $@;
	$r = 1;
} else {
	# this is only for still getting screenshots while
	# all testscripts would have been already run
	sleep 10;
}

stop_vm();

$screenshotthr->join();

# Write JSON result
autotest::save_results();

diag "done" unless $r;
diag "FAIL" if $r;

exit $r;
