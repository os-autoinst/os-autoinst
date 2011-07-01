use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitinststage("secondstage-register",500); # normally 144-400 sec for boot+automatic configuration
	sleep 3;
}

1;
