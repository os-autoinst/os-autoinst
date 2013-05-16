#!/usr/bin/perl -w

package bmwrpc;

use threads;
use bmwqemu ();

use base qw(JSON::RPC::Procedure);

sub stop_waitforneedle : Public {
	$bmwqemu::stop_waitforneedle = 1;
}

sub stop_vm : Public {
	printf "bmwrpc stop_vm %d\n", threads->tid();
	bmwqemu::stop_vm();
	print "<< done\n";
}

sub cont_vm : Public {
	bmwqemu::cont_vm();
}

sub freeze_vm : Public {
	bmwqemu::freeze_vm();
}

sub alive : Public {
	bmwqemu::alive();
}

sub quit : Public {
	alarm 1;
}

1;
