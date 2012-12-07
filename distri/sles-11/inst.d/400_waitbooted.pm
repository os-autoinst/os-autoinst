use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitinststage("config-rootpw|networktest",190);
	waitidle(60); # especially for upgrade case
	waitstillimage(25, 260);
	mouse_hide;
}

1;
