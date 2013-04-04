use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage("debian-popconconf", 140);
	$self->take_screenshot; sleep 1;
	sendkey "ret"; # no popcon
	sleep 5; waitidle;
}


1;
