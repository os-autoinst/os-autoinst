use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitforneedle("splashscreen", 12);
	sendkey "esc";
}

1;
